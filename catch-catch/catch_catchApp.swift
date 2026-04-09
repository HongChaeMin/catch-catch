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

    func setIgnoresMouseEvents(_ ignores: Bool) {
        window?.ignoresMouseEvents = ignores
    }
}

// MARK: - Floating chat panel

/// Borderless NSPanel must override canBecomeKey to accept keyboard input
/// (e.g. TextField focus). Default NSPanel returns false for borderless.
final class KeyableChatPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

class ChatPanel {
    private var panel: NSPanel?
    var onSendChat: ((String) -> Void)?
    var onVisibilityChanged: ((Bool) -> Void)?

    var isVisible: Bool { panel != nil }

    func toggle(near catAbsPoint: CGPoint) {
        if panel != nil {
            hide()
        } else {
            show(near: catAbsPoint)
        }
    }

    func show(near catAbsPoint: CGPoint) {
        hide()

        let width = ChatInputView.width
        let height = ChatInputView.height
        let size = CGSize(width: width, height: height)

        // catAbsPoint는 고양이 중심(absX, absY + 40), 이미지 80×80
        // 이름 라벨이 고양이 밑에 ~20px, 인풋은 그 밑에 배치
        let catRect = CGRect(
            x: catAbsPoint.x - 40, y: catAbsPoint.y - 40,
            width: 80, height: 80
        )

        let screen = NSScreen.screens.first { $0.frame.contains(catAbsPoint) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? .zero
        let gap: CGFloat = 2

        // catRect.minY는 고양이 중심(catAbsPoint이 고양이 상단이므로), 실제 하단은 -40 더
        let catBottomScreen = catRect.minY - 40
        let belowCatY = catBottomScreen - gap - height
        let candidates: [NSPoint] = [
            NSPoint(x: catAbsPoint.x - width / 2, y: belowCatY),
            NSPoint(x: catAbsPoint.x - width / 2, y: catRect.maxY + gap),
            NSPoint(x: catRect.maxX + gap, y: catAbsPoint.y - height / 2),
        ]
        let picked = candidates.first { origin in
            let r = CGRect(origin: origin, size: size)
            return vf.contains(r)
        } ?? candidates[0]

        // 최종 안전망: visibleFrame 내로 클램프
        let origin = NSPoint(
            x: min(max(vf.minX + 8, picked.x), vf.maxX - width - 8),
            y: min(max(vf.minY + 8, picked.y), vf.maxY - height - 8)
        )

        let p = KeyableChatPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .statusBar + 1
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let hostingView = NSHostingView(rootView: ChatInputView(
            onSend: { [weak self] text in
                // 전송 후에도 입력창은 열어둠 (Esc 또는 외부 클릭으로만 닫힘)
                self?.onSendChat?(text)
            },
            onDismiss: { [weak self] in
                self?.hide()
            }
        ))
        hostingView.frame = NSRect(origin: .zero, size: p.frame.size)
        p.contentView = hostingView

        self.panel = p
        p.orderFrontRegardless()
        p.makeKey()
        onVisibilityChanged?(true)
    }

    func hide() {
        guard panel != nil else { return }
        panel?.orderOut(nil)
        panel = nil
        onVisibilityChanged?(false)
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

    func setIgnoresMouseEvents(_ ignores: Bool) {
        controllers.forEach { $0.setIgnoresMouseEvents(ignores) }
    }
}

// MARK: - App Coordinator

class AppCoordinator: ObservableObject {
    let localCat = CatState()
    let roomState = RoomState()
    let eventMonitor = GlobalEventMonitor()
    let wsClient = WebSocketClient()
    let updateChecker = UpdateChecker()

    private var isMoving = false

    private var multiScreen: MultiScreenCatController?
    private let chatPanel = ChatPanel()
    private var stateThrottleTimer: Timer?
    private var sleepTimer: Timer?
    private var lastActivityDate = Date()
    private static let sleepTimeout: TimeInterval = 30
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
        setupAlwaysDrag()
        startSleepTimer()
        PermissionAlert.showIfNeeded()
        updateChecker.check()
    }

    // MARK: - Event monitor

    private func setupEventMonitor() {
        eventMonitor.onKeyboardActiveChanged = { [weak self] isActive in
            guard let self, isActive else { return }  // keyDown만 반응, keyUp 무시
            recordActivity()
            localCat.incrementKeystroke()
            localCat.isActive ? localCat.deactivate() : localCat.activate()
            sendStateThrottled()
        }
        eventMonitor.onMouseActiveChanged = { [weak self] isActive in
            guard let self, isActive else { return }  // mouseDown만 반응, mouseUp 무시
            recordActivity()
            localCat.isActive ? localCat.deactivate() : localCat.activate()
            sendStateThrottled()
        }
        eventMonitor.start()
    }

    // MARK: - Always-drag (click near cat to drag, click to chat)

    private var alwaysDragMonitor: Any?
    private var draggingPeerIndex: Int? = nil
    private var dragStartPoint: CGPoint? = nil
    private static let dragThreshold: CGFloat = 5

    /// Set up a permanent global mouseDown monitor. When the click lands near a cat,
    /// enter drag mode. On mouseUp: if movement < threshold → treat as click (toggle chat).
    private func setupAlwaysDrag() {
        chatPanel.onSendChat = { [weak self] text in
            self?.sendChat(text)
        }
        chatPanel.onVisibilityChanged = { [weak self] visible in
            self?.localCat.isChatOpen = visible
        }

        alwaysDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self else { return }
            let clickPoint = NSEvent.mouseLocation

            // Check if click is near any cat (local or peer)
            let isNearCat = isClickNearAnyCat(clickPoint)
            guard isNearCat else {
                // Click not near any cat — dismiss chat if open
                DispatchQueue.main.async { [weak self] in
                    guard let self, chatPanel.isVisible else { return }
                    chatPanel.hide()
                }
                return
            }

            // Click is near a cat — start drag tracking
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.beginCatDrag(from: clickPoint)
            }
        }
    }

    /// Returns true if the click point is within range of any cat (local or peer).
    /// Reuses findClosestPeer distance logic — local cat is always checked there too.
    private func isClickNearAnyCat(_ point: CGPoint) -> Bool {
        let localCenter = CGPoint(x: localCat.absX, y: localCat.absY + 40)
        if hypot(point.x - localCenter.x, point.y - localCenter.y) < 40 { return true }
        // findClosestPeer returns non-nil only if a peer is within 60px AND closer than local
        // So also check peers directly with the same 40px threshold
        return findClosestPeer(to: point) != nil
    }

    /// Enter drag mode: enable overlay mouse events, record start point, install drag monitors.
    private func beginCatDrag(from clickPoint: CGPoint) {
        isMoving = true
        dragStartPoint = clickPoint
        draggingPeerIndex = findClosestPeer(to: clickPoint)
        multiScreen?.setIgnoresMouseEvents(false)

        eventMonitor.startDragTracking(
            onDown: { _ in },  // already handled above
            onDrag: { [weak self] absPoint in
                guard let self else { return }
                if let idx = draggingPeerIndex {
                    let screen = NSScreen.main ?? NSScreen.screens[0]
                    let normX = (Double(absPoint.x) - Double(screen.frame.minX)) / Double(screen.frame.width)
                    let normY = (Double(absPoint.y) - Double(screen.frame.minY)) / Double(screen.frame.height)
                    roomState.peers[idx].x = max(0, min(1, normX))
                    roomState.peers[idx].y = max(0, min(1, 1.0 - normY))
                } else {
                    localCat.setAbsPosition(absPoint)
                    if wsClient.isConnected, localCat.syncPosition {
                        let net = localCat.networkPosition
                        wsClient.sendState(x: net.x, y: net.y, isActive: localCat.isActive, combo: localCat.comboCount, sleeping: localCat.isSleeping)
                    }
                }
            },
            onEnd: { [weak self] in
                guard let self else { return }
                let endPoint = NSEvent.mouseLocation
                let startPoint = dragStartPoint ?? endPoint
                let distance = hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y)

                if distance < Self.dragThreshold {
                    // Click (not drag) → toggle chat if connected
                    if roomState.isConnected {
                        chatPanel.toggle(near: CGPoint(x: localCat.absX, y: localCat.absY + 40))
                    }
                } else {
                    // Drag completed → save position
                    if draggingPeerIndex == nil {
                        localCat.savePosition()
                    }
                }

                // Restore overlay passthrough
                multiScreen?.setIgnoresMouseEvents(true)
                eventMonitor.stopDragTracking()
                isMoving = false
                draggingPeerIndex = nil
                dragStartPoint = nil
            }
        )
    }

    private func findClosestPeer(to point: CGPoint) -> Int? {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        // 로컬 고양이 중심
        let localCenter = CGPoint(x: localCat.absX, y: localCat.absY + 40)
        let localDist = hypot(point.x - localCenter.x, point.y - localCenter.y)

        var closestIdx: Int? = nil
        var closestDist = localDist // 로컬이 더 가까우면 nil 리턴 (로컬 드래그)

        for (i, peer) in roomState.peers.enumerated() {
            let px = Double(screen.frame.minX) + peer.x * Double(screen.frame.width)
            let py = Double(screen.frame.minY) + (1.0 - peer.y) * Double(screen.frame.height)
            let peerCenter = CGPoint(x: px, y: py + 40)
            let dist = hypot(point.x - peerCenter.x, point.y - peerCenter.y)
            if dist < closestDist && dist < 60 {
                closestDist = dist
                closestIdx = i
            }
        }

        return closestIdx
    }

    // MARK: - Room management

    func joinRoom(_ code: String) {
        roomState.connectionError = nil
        roomState.roomCode = code
        wsClient.currentTheme = roomState.selectedTheme.rawValue
        wsClient.connect(to: serverURL, roomCode: code, userId: localCat.userId, name: localCat.name)
    }

    func changeTheme(_ theme: CatTheme) {
        roomState.selectedTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: "catTheme")
        if wsClient.isConnected {
            wsClient.sendTheme(theme: theme.rawValue)
        }
    }

    func leaveRoom() {
        wsClient.disconnect()
        roomState.reset()
    }

    func sendChat(_ text: String) {
        guard wsClient.isConnected else { return }
        wsClient.sendChat(text: text)
    }

    func renameInRoom(_ name: String) {
        localCat.name = name
        UserDefaults.standard.set(name, forKey: "displayName")
        if wsClient.isConnected {
            wsClient.sendRename(name: name)
        }
    }

    func setShowName(_ show: Bool) {
        localCat.showName = show
        UserDefaults.standard.set(show, forKey: "showName")
    }

    func setSyncPosition(_ sync: Bool) {
        localCat.syncPosition = sync
        UserDefaults.standard.set(sync, forKey: "syncPosition")
    }

    // MARK: - WebSocket

    private func setupWebSocketHandlers() {
        wsClient.onConnected = { [weak self] in self?.roomState.isConnected = true }
        wsClient.onDisconnected = { [weak self] in self?.roomState.isConnected = false }
        wsClient.onConnectionFailed = { [weak self] in
            guard let self else { return }
            roomState.isConnected = false
            roomState.connectionError = "연결이 끊겼습니다"
            roomState.roomCode = nil
            roomState.peers = []
        }
        wsClient.onMessage = { [weak self] msg in self?.handleServerMessage(msg) }
    }

    private func handleServerMessage(_ message: ServerMessage) {
        switch message {
        case .joined(let users):
            for u in users {
                let theme = CatTheme(rawValue: u.theme) ?? .gray
                roomState.upsertPeer(userId: u.userId, name: u.name, x: u.x, y: u.y, isActive: u.isActive, theme: theme)
            }
        case .userJoined(let userId, let name, let theme):
            let catTheme = CatTheme(rawValue: theme) ?? .gray
            roomState.upsertPeer(userId: userId, name: name, x: 0.85, y: 0.85, isActive: false, theme: catTheme)
        case .userLeft(let userId):
            roomState.removePeer(userId: userId)
        case .stateUpdate(let userId, let x, let y, let isActive, let combo, let sleeping):
            if localCat.syncPosition {
                roomState.updatePeerState(userId: userId, x: x, y: y, isActive: isActive)
            } else {
                // 위치 동기화 OFF: 위치 무시, active 상태만 반영
                roomState.updatePeerActive(userId: userId, isActive: isActive)
            }
            roomState.updatePeerCombo(userId: userId, combo: combo)
            roomState.updatePeerSleeping(userId: userId, isSleeping: sleeping)
        case .renamed(let userId, let name):
            roomState.updatePeerName(userId: userId, name: name)
        case .themeChanged(let userId, let theme):
            let catTheme = CatTheme(rawValue: theme) ?? .gray
            roomState.updatePeerTheme(userId: userId, theme: catTheme)
        case .chat(let userId, let name, let text):
            roomState.addMessage(userId: userId, name: name, text: text)
            if userId == localCat.userId {
                localCat.showMessage(text)
            } else {
                roomState.showPeerMessage(userId: userId, text: text)
            }
        case .error(let msg):
            roomState.connectionError = msg
            roomState.roomCode = nil
        }
    }

    // MARK: - Sleep detection

    private func startSleepTimer() {
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let elapsed = Date().timeIntervalSince(lastActivityDate)
            if elapsed >= Self.sleepTimeout, !localCat.isSleeping {
                localCat.isSleeping = true
                sendSleepState()
            }
        }
    }

    private func recordActivity() {
        lastActivityDate = Date()
        if localCat.isSleeping {
            localCat.isSleeping = false
            sendSleepState()
        }
    }

    private func sendSleepState() {
        guard wsClient.isConnected, localCat.syncPosition else { return }
        let net = localCat.networkPosition
        wsClient.sendState(x: net.x, y: net.y, isActive: localCat.isActive, combo: localCat.comboCount, sleeping: localCat.isSleeping)
    }

    private func sendStateThrottled() {
        stateThrottleTimer?.invalidate()
        stateThrottleTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            guard let self else { return }
            localCat.saveKeystrokeCount()
            guard wsClient.isConnected, localCat.syncPosition else { return }
            let net = localCat.networkPosition
            wsClient.sendState(x: net.x, y: net.y, isActive: localCat.isActive, combo: localCat.comboCount, sleeping: localCat.isSleeping)
        }
    }

    func setPowerMode(_ on: Bool) {
        localCat.powerMode = on
        UserDefaults.standard.set(on, forKey: "powerMode")
        if !on {
            localCat.comboCount = 0
            localCat.particles.removeAll()
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
                updateChecker: coordinator.updateChecker,
                onJoinRoom: coordinator.joinRoom,
                onLeaveRoom: coordinator.leaveRoom,
                onNameChanged: coordinator.renameInRoom,
                onThemeChanged: coordinator.changeTheme,
                onShowNameChanged: coordinator.setShowName,
                onSyncPositionChanged: coordinator.setSyncPosition,
                onPowerModeChanged: coordinator.setPowerMode
            )
        }
        .menuBarExtraStyle(.window)
    }
}
