import Foundation
import Combine

class CatState: ObservableObject {
    // Position in normalized coordinates (0.0 - 1.0)
    @Published var x: Double = 0.85
    @Published var y: Double = 0.85
    @Published var isActive: Bool = false

    let userId: String
    var name: String

    private var idleTimer: Timer?

    init(userId: String = UUID().uuidString, name: String = "me") {
        self.userId = userId
        self.name = name
    }

    func activate() {
        isActive = true
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.isActive = false
            }
        }
    }

    func setPosition(x: Double, y: Double) {
        self.x = max(0.0, min(1.0, x))
        self.y = max(0.0, min(1.0, y))
    }

    func savePosition() {
        UserDefaults.standard.set(x, forKey: "catPositionX")
        UserDefaults.standard.set(y, forKey: "catPositionY")
    }

    func loadPosition() {
        let savedX = UserDefaults.standard.double(forKey: "catPositionX")
        let savedY = UserDefaults.standard.double(forKey: "catPositionY")
        if savedX > 0 || savedY > 0 {
            x = savedX
            y = savedY
        }
    }
}
