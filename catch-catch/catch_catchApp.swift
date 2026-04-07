import SwiftUI
import AppKit
import IOKit.hid

// MARK: - Permission Window

class PermissionWindowController: NSWindowController, NSWindowDelegate {
    static var shared: PermissionWindowController?

    convenience init() {
        let view = PermissionView()
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "catch-catch"
        win.contentViewController = hosting
        win.level = .floating
        win.isMovableByWindowBackground = true
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
        // Request so the app appears in System Settings list
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
    @State private var step: Int = 1

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: "keyboard")
                        .font(.system(size: 26))
                        .foregroundColor(.orange)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("입력 모니터링 권한 필요")
                        .font(.system(size: 15, weight: .semibold))
                    Text("타자 칠 때 고양이를 움직이려면\n아래 순서대로 설정해주세요.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                }
                Spacer()
            }
            .padding(20)

            Divider()

            // Steps
            VStack(alignment: .leading, spacing: 10) {
                stepRow(num: 1, text: "아래 버튼으로 시스템 설정 열기")
                stepRow(num: 2, text: "개인 정보 보호 → 입력 모니터링 선택")
                stepRow(num: 3, text: "catch-catch 항목 토글 ON")
                stepRow(num: 4, text: "앱 재시작 (아래 버튼)")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // Buttons
            HStack(spacing: 10) {
                Button("시스템 설정 열기") {
                    GlobalEventMonitor.openInputMonitoringSettings()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("재시작") {
                    restartApp()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 420)
    }

    private func stepRow(num: Int, text: String) -> some View {
        HStack(spacing: 10) {
            Text("\(num)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor)
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.primary)
            Spacer()
        }
    }

    private func restartApp() {
        guard let url = Bundle.main.bundleURL as URL? else { return }
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
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
