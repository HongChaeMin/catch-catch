import SwiftUI
import AppKit
import IOKit.hid

// MARK: - Permission Window

class PermissionWindowController: NSWindowController, NSWindowDelegate {
    static var shared: PermissionWindowController?

    convenience init() {
        let view = PermissionView(onOpenSettings: {
            GlobalEventMonitor.openInputMonitoringSettings()
        })
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "catch-catch — 권한 필요"
        win.contentViewController = hosting
        win.level = .floating
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
        DispatchQueue.main.async { show() }
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
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "keyboard.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            VStack(spacing: 6) {
                Text("입력 모니터링 권한 필요")
                    .font(.headline)
                Text("타자 칠 때 고양이가 반응하려면\n시스템 설정에서 권한을 허용해야 해요.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("시스템 설정 열기") {
                onOpenSettings()
            }
            .buttonStyle(.borderedProminent)

            Text("설정 후 앱을 재시작해주세요.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(30)
        .frame(width: 360, height: 220)
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
        // Explicitly set frame like mimo does — required for correct rendering
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

// MARK: - App Coordinator (owns all state, initializes at launch)

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

        // Show overlay immediately at launch — don't wait for menu bar click
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
        wsClient.onConnected = { [weak self] in
            self?.roomState.isConnected = true
        }
        wsClient.onDisconnected = { [weak self] in
            self?.roomState.isConnected = false
        }
        wsClient.onMessage = { [weak self] message in
            self?.handleServerMessage(message)
        }
    }

    private func handleServerMessage(_ message: ServerMessage) {
        switch message {
        case .joined(let users):
            for user in users {
                roomState.upsertPeer(userId: user.userId, name: user.name,
                                     x: user.x, y: user.y, isActive: user.isActive)
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
