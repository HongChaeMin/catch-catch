import AppKit
import Combine

final class GlobalEventMonitor: ObservableObject {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pressedKeyCodes = Set<UInt16>()

    private var mouseDownMonitor: Any?
    private var mouseUpMonitor: Any?
    private var pressedMouseButtons = Set<Int>()

    private var dragMouseDownMonitor: Any?
    private var dragMoveMonitor: Any?
    private var dragMouseUpMonitor: Any?
    private var dragLocalMouseDownMonitor: Any?
    private var dragLocalMoveMonitor: Any?
    private var dragLocalMouseUpMonitor: Any?
    private var isDragging = false

    private var permissionPollTimer: Timer?

    var onKeyboardActiveChanged: ((Bool) -> Void)?
    var onMouseActiveChanged: ((Bool) -> Void)?

    var isRunning = false

    static func hasPermission() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleMouseDown(event)
        }
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] event in
            self?.handleMouseUp(event)
        }

        let trusted = Self.requestPermission()
        if trusted {
            startKeyboardMonitoring()
        } else {
            startPermissionPolling()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        stopPermissionPolling()
        stopKeyboardMonitoring()

        [mouseDownMonitor, mouseUpMonitor].compactMap { $0 }.forEach { NSEvent.removeMonitor($0) }
        mouseDownMonitor = nil
        mouseUpMonitor = nil

        pressedKeyCodes.removeAll()
        pressedMouseButtons.removeAll()
        DispatchQueue.main.async { [weak self] in
            self?.onKeyboardActiveChanged?(false)
        }
    }

    private func startKeyboardMonitoring() {
        guard eventTap == nil else { return }

        let eventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            stopKeyboardMonitoring()
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func stopKeyboardMonitoring() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        pressedKeyCodes.removeAll()
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<GlobalEventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        return monitor.handleEventTap(type: type, event: event)
    }

    private func handleEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        case .keyDown:
            handleKeyDown(UInt16(event.getIntegerValueField(.keyboardEventKeycode)))
        case .keyUp:
            handleKeyUp(UInt16(event.getIntegerValueField(.keyboardEventKeycode)))
        case .flagsChanged:
            handleFlagsChanged(UInt16(event.getIntegerValueField(.keyboardEventKeycode)))
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func startPermissionPolling() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if Self.hasPermission() {
                stopPermissionPolling()
                startKeyboardMonitoring()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionPollTimer = timer
    }

    private func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    private func handleKeyDown(_ keyCode: UInt16) {
        pressedKeyCodes.insert(keyCode)
        DispatchQueue.main.async { [weak self] in
            self?.onKeyboardActiveChanged?(true)
        }
    }

    private func handleKeyUp(_ keyCode: UInt16) {
        pressedKeyCodes.remove(keyCode)
        DispatchQueue.main.async { [weak self] in
            self?.onKeyboardActiveChanged?(false)
        }
    }

    private func handleFlagsChanged(_ keyCode: UInt16) {
        let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        guard modifierKeyCodes.contains(keyCode) else { return }

        if pressedKeyCodes.contains(keyCode) {
            handleKeyUp(keyCode)
        } else {
            handleKeyDown(keyCode)
        }
    }

    private func handleMouseDown(_ event: NSEvent) {
        pressedMouseButtons.insert(event.buttonNumber)
        DispatchQueue.main.async { [weak self] in
            self?.onMouseActiveChanged?(true)
        }
    }

    private func handleMouseUp(_ event: NSEvent) {
        guard pressedMouseButtons.remove(event.buttonNumber) != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onMouseActiveChanged?(false)
        }
    }

    func startDragTracking(onDown: @escaping (CGPoint) -> Void, onDrag: @escaping (CGPoint) -> Void, onEnd: @escaping () -> Void) {
        stopDragTracking()

        // Global monitors: catch events targeting other apps
        dragMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.isDragging = true
            let loc = NSEvent.mouseLocation
            DispatchQueue.main.async { onDown(loc) }
        }
        dragMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            guard self?.isDragging == true else { return }
            let loc = NSEvent.mouseLocation
            DispatchQueue.main.async { onDrag(loc) }
        }
        dragMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            guard self?.isDragging == true else { return }
            self?.isDragging = false
            DispatchQueue.main.async { onEnd() }
        }

        // Local monitors: catch events captured by our own overlay windows
        // (when ignoresMouseEvents = false during move mode)
        dragLocalMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.isDragging = true
            let loc = NSEvent.mouseLocation
            DispatchQueue.main.async { onDown(loc) }
            return event
        }
        dragLocalMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            guard self?.isDragging == true else { return event }
            let loc = NSEvent.mouseLocation
            DispatchQueue.main.async { onDrag(loc) }
            return event
        }
        dragLocalMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard self?.isDragging == true else { return event }
            self?.isDragging = false
            DispatchQueue.main.async { onEnd() }
            return event
        }
    }

    func stopDragTracking() {
        [dragMouseDownMonitor, dragMoveMonitor, dragMouseUpMonitor,
         dragLocalMouseDownMonitor, dragLocalMoveMonitor, dragLocalMouseUpMonitor]
            .compactMap { $0 }
            .forEach { NSEvent.removeMonitor($0) }
        dragMouseDownMonitor = nil
        dragMoveMonitor = nil
        dragMouseUpMonitor = nil
        dragLocalMouseDownMonitor = nil
        dragLocalMoveMonitor = nil
        dragLocalMouseUpMonitor = nil
        isDragging = false
    }


}
