import AppKit
import Combine

class GlobalEventMonitor: ObservableObject {
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var mouseDownMonitor: Any?
    private var mouseUpMonitor: Any?

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
}
