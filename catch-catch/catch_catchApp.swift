import SwiftUI
import AppKit

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
        win.contentView = NSHostingView(rootView: view)
        win.delegate = self
        self.window = win
        win.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
    }

    func setIgnoresMouseEvents(_ ignore: Bool) {
        window?.ignoresMouseEvents = ignore
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

    @StateObject private var localCat = CatState()
    @StateObject private var roomState = RoomState()

    @State private var multiScreen: MultiScreenCatController?
    @State private var isMoving = false
    @State private var stateThrottleTimer: Timer?

    // Managers
    private let eventMonitor = GlobalEventMonitor()
    private let wsClient = WebSocketClient()

    // Server URL — update after deploying server
    private let serverURL = URL(string: "wss://catch-catch-server.up.railway.app")!

    var body: some Scene {
        MenuBarExtra("catch-catch", systemImage: "cat") {
            MenuBarContentView(
                roomState: roomState,
                localCat: localCat,
                eventMonitor: eventMonitor,
                onToggleMove: toggleMoveMode,
                onJoinRoom: joinRoom,
                onLeaveRoom: leaveRoom,
                isMoving: isMoving
            )
            .onAppear { setup() }
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: - Setup

    private func setup() {
        localCat.loadPosition()
        localCat.name = roomState.displayName

        if multiScreen == nil {
            let ctrl = MultiScreenCatController(localCat: localCat, roomState: roomState)
            multiScreen = ctrl
            ctrl.show()
        }

        setupEventMonitor()
        setupWebSocketHandlers()
    }

    private func setupEventMonitor() {
        eventMonitor.onActivate = {
            localCat.activate()
            sendStateThrottled()
        }
        eventMonitor.onDeactivate = {
            sendStateThrottled()
        }
        eventMonitor.start()
    }

    // MARK: - Move mode (drag cat position)

    private func toggleMoveMode() {
        isMoving.toggle()

        if isMoving {
            eventMonitor.startDragTracking { [localCat, wsClient] absPoint in
                // absPoint = NSEvent.mouseLocation (macOS absolute, bottom-left origin)
                localCat.setAbsPosition(absPoint)
                if wsClient.isConnected {
                    let net = localCat.networkPosition
                    wsClient.sendState(x: net.x, y: net.y, isActive: localCat.isActive)
                }
            } onEnd: { [localCat] in
                localCat.savePosition()
            }
        } else {
            eventMonitor.stopDragTracking()
            localCat.savePosition()
        }
    }

    // MARK: - Room management

    private func joinRoom(_ code: String) {
        roomState.connectionError = nil
        roomState.roomCode = code

        wsClient.onConnected = {
            roomState.isConnected = true
        }
        wsClient.onDisconnected = {
            roomState.isConnected = false
        }
        wsClient.onMessage = { message in
            handleServerMessage(message)
        }

        wsClient.connect(
            to: serverURL,
            roomCode: code,
            userId: localCat.userId,
            name: localCat.name
        )
    }

    private func leaveRoom() {
        wsClient.disconnect()
        roomState.reset()
    }

    // MARK: - WebSocket handlers

    private func setupWebSocketHandlers() {
        wsClient.onMessage = { message in
            handleServerMessage(message)
        }
        wsClient.onConnected = {
            roomState.isConnected = true
        }
        wsClient.onDisconnected = {
            roomState.isConnected = false
        }
    }

    private func handleServerMessage(_ message: ServerMessage) {
        switch message {
        case .joined(let users):
            for user in users {
                roomState.upsertPeer(
                    userId: user.userId, name: user.name,
                    x: user.x, y: user.y, isActive: user.isActive
                )
            }

        case .userJoined(let userId, let name):
            roomState.upsertPeer(userId: userId, name: name, x: 0.85, y: 0.85, isActive: false)

        case .userLeft(let userId):
            roomState.removePeer(userId: userId)

        case .stateUpdate(let userId, let x, let y, let isActive):
            roomState.updatePeerState(userId: userId, x: x, y: y, isActive: isActive)

        case .error(let message):
            roomState.connectionError = message
            roomState.roomCode = nil
        }
    }

    // MARK: - State throttle (100ms)

    private func sendStateThrottled() {
        stateThrottleTimer?.invalidate()
        stateThrottleTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
            guard roomState.isConnected else { return }
            let net = localCat.networkPosition
            wsClient.sendState(x: net.x, y: net.y, isActive: localCat.isActive)
        }
    }
}
