import SwiftUI
import AppKit
import Combine

// MARK: - Permission Alert (mimo 방식 그대로)

enum PermissionAlert {
    static func showIfNeeded() {
        _ = GlobalEventMonitor.requestPermission()
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
    private var cancellables = Set<AnyCancellable>()

    let serverURL = URL(string: "wss://catch.hannah-log.site")!

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
        PermissionAlert.showIfNeeded()
    }

    // MARK: - Event monitor

    private func setupEventMonitor() {
        eventMonitor.onKeyboardActiveChanged = { [weak self] isActive in
            guard let self, isActive else { return }  // keyDown만 반응, keyUp 무시
            localCat.isActive ? localCat.deactivate() : localCat.activate()
            sendStateThrottled()
        }
        eventMonitor.onMouseActiveChanged = { [weak self] isActive in
            guard let self, isActive else { return }  // mouseDown만 반응, mouseUp 무시
            localCat.isActive ? localCat.deactivate() : localCat.activate()
            sendStateThrottled()
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
