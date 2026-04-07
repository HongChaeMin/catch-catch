import SwiftUI
import AppKit
import IOKit.hid

// MARK: - Permission Window

class PermissionWindowController: NSWindowController, NSWindowDelegate {
    static var shared: PermissionWindowController?

    convenience init() {
        let view = PermissionView {
            PermissionWindowController.shared?.close()
        }
        let hosting = NSHostingController(rootView: view)
        // Borderless window — SwiftUI view provides the card background
        let win = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = true
        win.level = .floating
        win.isMovableByWindowBackground = true
        // Explicitly size the hosting view to match window
        hosting.view.frame = NSRect(x: 0, y: 0, width: 380, height: 400)
        win.contentViewController = hosting
        self.init(window: win)
        win.delegate = self
        win.center()
    }

    func windowWillClose(_ notification: Notification) {
        PermissionWindowController.shared = nil
    }

    static func showIfNeeded() {
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        guard access != kIOHIDAccessTypeGranted else { return }
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { show() }
    }

    static func show() {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
        } else {
            let ctrl = PermissionWindowController()
            shared = ctrl
            ctrl.showWindow(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct PermissionView: View {
    let onLater: () -> Void
    // After tapping "Open Settings", switch to restart-prompt state
    @State private var didOpenSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // App icon
            Image("cat_idle")
                .resizable()
                .interpolation(.none)
                .frame(width: 80, height: 80)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                .padding(.top, 28)
                .padding(.bottom, 18)

            if didOpenSettings {
                // --- After opening settings: prompt restart ---
                Text("권한 설정 완료 후\n앱을 재시작해주세요")
                    .font(.system(size: 16, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 10)

                Text("System Settings에서 catch-catch를\n활성화했다면 아래 버튼으로 재시작하세요.\n재시작 후 타자를 치면 고양이가 반응해요.")
                    .font(.system(size: 13))
                    .foregroundColor(.primary.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineSpacing(1.5)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 22)

                primaryButton(title: "앱 재시작") { restartApp() }
                secondaryButton(title: "나중에") { onLater() }
            } else {
                // --- Initial state: explain & open settings ---
                Text("Input Monitoring\nPermission Required")
                    .font(.system(size: 16, weight: .bold))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 10)

                Text("catch-catch needs Input Monitoring permission to animate the cat when you type.\n\nPlease enable catch-catch in:\nSystem Settings → Privacy & Security\n→ Input Monitoring")
                    .font(.system(size: 13))
                    .foregroundColor(.primary.opacity(0.75))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(1.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 22)

                primaryButton(title: "Open System Settings") {
                    GlobalEventMonitor.openInputMonitoringSettings()
                    didOpenSettings = true  // switch to restart state
                }
                secondaryButton(title: "Later") { onLater() }
            }
        }
        .frame(width: 380)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func primaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Color.accentColor)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 26)
        .padding(.bottom, 8)
    }

    private func secondaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Color(NSColor.controlColor))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 26)
        .padding(.bottom, 26)
    }

    private func restartApp() {
        guard let url = Bundle.main.bundleURL as URL? else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
    }
}

// MARK: - Overlay Window (one per screen)

class CatWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    let screen: NSScreen
    let localCat: CatState
    let roomState: RoomState

    init(screen: NSScreen, localCat: CatState, roomState: RoomState) {
        self.screen = screen
        self.localCat = localCat
        self.roomState = roomState
    }

    func show() {
        guard window == nil else { return }

        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        win.level = .statusBar
        win.isOpaque = false
        win.backgroundColor = .clear
        win.ignoresMouseEvents = true
        win.hidesOnDeactivate = false
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let isPrimary = screen == NSScreen.main
        let view = CatOverlayView(
            localCat: localCat,
            roomState: roomState,
            screen: screen,
            isPrimary: isPrimary
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: screen.frame.size)
        win.contentView = hostingView
        win.delegate = self
        self.window = win
        win.setFrame(screen.frame, display: true)
        win.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
    }
}

// MARK: - Multi-screen controller

class MultiScreenCatController {
    private var controllers: [CatWindowController] = []
    let localCat: CatState
    let roomState: RoomState

    init(localCat: CatState, roomState: RoomState) {
        self.localCat = localCat
        self.roomState = roomState
    }

    func show() {
        guard controllers.isEmpty else { return }
        for screen in NSScreen.screens {
            let ctrl = CatWindowController(screen: screen, localCat: localCat, roomState: roomState)
            controllers.append(ctrl)
            ctrl.show()
        }
    }

    func hide() {
        controllers.forEach { $0.hide() }
        controllers.removeAll()
    }
}

// MARK: - App Coordinator

class AppCoordinator: ObservableObject {
    let localCat = CatState()
    let roomState = RoomState()
    let eventMonitor = GlobalEventMonitor()
    let wsClient = WebSocketClient()

    @Published var isMoving = false

    private var multiScreen: MultiScreenCatController?
    private var stateThrottleTimer: Timer?

    let serverURL = URL(string: "wss://catch-catch-server.up.railway.app")!

    init() {
        localCat.loadPosition()
        localCat.name = roomState.displayName

        // Defer overlay + monitor setup until after app finishes launching
        DispatchQueue.main.async { [weak self] in
            self?.lateSetup()
        }
    }

    private func lateSetup() {
        let ctrl = MultiScreenCatController(localCat: localCat, roomState: roomState)
        multiScreen = ctrl
        ctrl.show()

        setupEventMonitor()
        setupWebSocketHandlers()
        PermissionWindowController.showIfNeeded()
    }

    // MARK: - Event monitor

    private func setupEventMonitor() {
        eventMonitor.onActivate = { [weak self] in
            self?.localCat.activate()
            self?.sendStateThrottled()
        }
        eventMonitor.onDeactivate = { [weak self] in
            self?.sendStateThrottled()
        }
        eventMonitor.start()
    }

    // MARK: - Move mode

    func toggleMoveMode() {
        isMoving.toggle()
        if isMoving {
            eventMonitor.startDragTracking { [weak self] absPoint in
                guard let self else { return }
                localCat.setAbsPosition(absPoint)
                if wsClient.isConnected {
                    let net = localCat.networkPosition
                    wsClient.sendState(x: net.x, y: net.y, isActive: localCat.isActive)
                }
            } onEnd: { [weak self] in
                self?.localCat.savePosition()
            }
        } else {
            eventMonitor.stopDragTracking()
            localCat.savePosition()
        }
    }

    // MARK: - Room management

    func joinRoom(_ code: String) {
        roomState.connectionError = nil
        roomState.roomCode = code
        wsClient.connect(to: serverURL, roomCode: code, userId: localCat.userId, name: localCat.name)
    }

    func leaveRoom() {
        wsClient.disconnect()
        roomState.reset()
    }

    // MARK: - WebSocket

    private func setupWebSocketHandlers() {
        wsClient.onConnected = { [weak self] in self?.roomState.isConnected = true }
        wsClient.onDisconnected = { [weak self] in self?.roomState.isConnected = false }
        wsClient.onMessage = { [weak self] msg in self?.handleServerMessage(msg) }
    }

    private func handleServerMessage(_ message: ServerMessage) {
        switch message {
        case .joined(let users):
            for u in users {
                roomState.upsertPeer(userId: u.userId, name: u.name, x: u.x, y: u.y, isActive: u.isActive)
            }
        case .userJoined(let userId, let name):
            roomState.upsertPeer(userId: userId, name: name, x: 0.85, y: 0.85, isActive: false)
        case .userLeft(let userId):
            roomState.removePeer(userId: userId)
        case .stateUpdate(let userId, let x, let y, let isActive):
            roomState.updatePeerState(userId: userId, x: x, y: y, isActive: isActive)
        case .error(let msg):
            roomState.connectionError = msg
            roomState.roomCode = nil
        }
    }

    private func sendStateThrottled() {
        stateThrottleTimer?.invalidate()
        stateThrottleTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            guard let self, wsClient.isConnected else { return }
            let net = localCat.networkPosition
            wsClient.sendState(x: net.x, y: net.y, isActive: localCat.isActive)
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - Main App

@main
struct CatchCatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("catch-catch", systemImage: "cat") {
            MenuBarContentView(
                roomState: coordinator.roomState,
                localCat: coordinator.localCat,
                onToggleMove: coordinator.toggleMoveMode,
                onJoinRoom: coordinator.joinRoom,
                onLeaveRoom: coordinator.leaveRoom,
                isMoving: coordinator.isMoving
            )
        }
        .menuBarExtraStyle(.window)
    }
}
