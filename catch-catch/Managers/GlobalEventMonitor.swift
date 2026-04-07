import AppKit
import Combine

class GlobalEventMonitor: ObservableObject {
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

    func start() {
        guard !isRunning else { return }
        isRunning = true

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
    /// onDrag fires with the cursor position in normalized screen coordinates (0–1).
    func startDragTracking(onDrag: @escaping (Double, Double) -> Void, onEnd: @escaping () -> Void) {
        stopDragTracking()

        dragMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.isDragging = true
        }

        dragMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            guard self?.isDragging == true, let screen = NSScreen.main else { return }
            let loc = NSEvent.mouseLocation
            let x = loc.x / screen.frame.width
            let y = 1.0 - (loc.y / screen.frame.height)  // flip Y: macOS is bottom-left, SwiftUI is top-left
            DispatchQueue.main.async { onDrag(x, y) }
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
