import Foundation
import AppKit
import Combine

class CatState: ObservableObject {
    // Absolute macOS screen coordinates (origin: bottom-left of primary screen)
    @Published var absX: Double
    @Published var absY: Double
    @Published var isActive: Bool = false

    let userId: String
    var name: String

    private var idleTimer: Timer?

    init(userId: String = UUID().uuidString, name: String = "me") {
        self.userId = userId
        self.name = name
        // Default: bottom-right of main screen
        let screen = NSScreen.main ?? NSScreen.screens[0]
        absX = Double(screen.frame.maxX) - 80
        absY = Double(screen.frame.minY) + 80
    }

    func activate() {
        isActive = true
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.isActive = false }
        }
    }

    func setAbsPosition(_ point: CGPoint) {
        absX = Double(point.x)
        absY = Double(point.y)
    }

    /// Normalized (0–1) position relative to the screen the cat is on. Used for network sync.
    var networkPosition: (x: Double, y: Double) {
        let screen = containingScreen ?? NSScreen.main ?? NSScreen.screens[0]
        let normX = (absX - Double(screen.frame.minX)) / Double(screen.frame.width)
        // Flip Y: macOS is bottom-left, network protocol uses top-left
        let normY = 1.0 - (absY - Double(screen.frame.minY)) / Double(screen.frame.height)
        return (
            x: max(0, min(1, normX)),
            y: max(0, min(1, normY))
        )
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
        // 0,0 means never saved — keep default
        if x != 0 || y != 0 {
            absX = x
            absY = y
        }
    }
}
