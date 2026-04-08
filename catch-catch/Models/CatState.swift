import Foundation
import AppKit
import Combine

class CatState: ObservableObject {
    @Published var absX: Double
    @Published var absY: Double
    @Published var isActive: Bool = false
    @Published var bubbleMessages: [BubbleMessage] = []
    @Published var isChatOpen: Bool = false

    let userId: String
    var name: String

    func showMessage(_ text: String, duration: TimeInterval = 5) {
        let msg = BubbleMessage(text: text)
        bubbleMessages.append(msg)
        if bubbleMessages.count > 5 {
            bubbleMessages.removeFirst(bubbleMessages.count - 5)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.bubbleMessages.removeAll { $0.id == msg.id }
        }
    }

    init(userId: String = UUID().uuidString, name: String = "me") {
        self.userId = userId
        self.name = name
        let screen = NSScreen.main ?? NSScreen.screens[0]
        absX = Double(screen.frame.maxX) - 80
        absY = Double(screen.frame.minY) + 80
    }

    func activate() { isActive = true }
    func deactivate() { isActive = false }
    func toggleActive() { isActive.toggle() }

    func setAbsPosition(_ point: CGPoint) {
        absX = Double(point.x)
        absY = Double(point.y)
    }

    var networkPosition: (x: Double, y: Double) {
        let screen = containingScreen ?? NSScreen.main ?? NSScreen.screens[0]
        let normX = (absX - Double(screen.frame.minX)) / Double(screen.frame.width)
        let normY = 1.0 - (absY - Double(screen.frame.minY)) / Double(screen.frame.height)
        return (x: max(0, min(1, normX)), y: max(0, min(1, normY)))
    }

    var containingScreen: NSScreen? {
        NSScreen.screens.first { $0.frame.contains(CGPoint(x: absX, y: absY)) }
    }

    func savePosition() {
        UserDefaults.standard.set(absX, forKey: "catAbsX")
        UserDefaults.standard.set(absY, forKey: "catAbsY")
    }

    func loadPosition() {
        let x = UserDefaults.standard.double(forKey: "catAbsX")
        let y = UserDefaults.standard.double(forKey: "catAbsY")
        if x != 0 || y != 0 { absX = x; absY = y }
    }
}
