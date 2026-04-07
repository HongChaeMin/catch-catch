import AppKit
import Combine
import IOKit.hid

class GlobalEventMonitor: ObservableObject {
    @Published private(set) var hasInputMonitoringPermission: Bool = false
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var mouseDownMonitor: Any?
    private var mouseUpMonitor: Any?

    // Drag tracking for move mode
    private var dragMouseDownMonitor: Any?
    private var dragMoveMonitor: Any?
    private var dragMouseUpMonitor: Any?
    private var isDragging = false

    var onActivate: (() -> Void)?
    var onDeactivate: (() -> Void)?

    var isRunning: Bool = false

    // MARK: - Permission check

    func checkAndRequestPermission() {
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        if access == kIOHIDAccessTypeGranted {
            hasInputMonitoringPermission = true
        } else {
            hasInputMonitoringPermission = false
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    }

    static func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Start / stop

    func start() {
        checkAndRequestPermission()
        guard !isRunning else { return }
        isRunning = true

        // Keyboard events require Input Monitoring permission.
        // Mouse events work without it — so the cat reacts to clicks even without permission.
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            DispatchQueue.main.async { self?.onActivate?() }
        }

        keyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] _ in
            DispatchQueue.main.async { self?.onDeactivate?() }
        }

        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.onActivate?() }
        }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] _ in
            DispatchQueue.main.async { self?.onDeactivate?() }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        [keyDownMonitor, keyUpMonitor, mouseDownMonitor, mouseUpMonitor]
            .compactMap { $0 }
            .forEach { NSEvent.removeMonitor($0) }

        keyDownMonitor = nil
        keyUpMonitor = nil
        mouseDownMonitor = nil
        mouseUpMonitor = nil
    }

    // MARK: - Drag tracking (move mode)

    /// Start tracking mouse drag to move the cat.
    /// The window stays ignoresMouseEvents=true so global monitors work correctly.
    /// onDrag fires with the cursor's absolute macOS position (bottom-left origin).
    func startDragTracking(onDrag: @escaping (CGPoint) -> Void, onEnd: @escaping () -> Void) {
        stopDragTracking()

        dragMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.isDragging = true
        }

        dragMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            guard self?.isDragging == true else { return }
            let loc = NSEvent.mouseLocation  // absolute macOS coords, bottom-left origin
            DispatchQueue.main.async { onDrag(loc) }
        }

        dragMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            guard self?.isDragging == true else { return }
            self?.isDragging = false
            DispatchQueue.main.async { onEnd() }
        }
    }

    func stopDragTracking() {
        [dragMouseDownMonitor, dragMoveMonitor, dragMouseUpMonitor]
            .compactMap { $0 }
            .forEach { NSEvent.removeMonitor($0) }
        dragMouseDownMonitor = nil
        dragMoveMonitor = nil
        dragMouseUpMonitor = nil
        isDragging = false
    }
}
