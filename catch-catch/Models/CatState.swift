import Foundation
import AppKit
import Combine

class CatState: ObservableObject {
    @Published var absX: Double
    @Published var absY: Double
    @Published var isActive: Bool = false
    @Published var isSleeping: Bool = false
    @Published var bubbleMessages: [BubbleMessage] = []
    @Published var isChatOpen: Bool = false
    @Published var showName: Bool = UserDefaults.standard.object(forKey: "showName") as? Bool ?? true
    @Published var syncPosition: Bool = UserDefaults.standard.object(forKey: "syncPosition") as? Bool ?? true
    @Published var powerMode: Bool = UserDefaults.standard.object(forKey: "powerMode") as? Bool ?? true
    @Published var keystrokeCount: Int = UserDefaults.standard.integer(forKey: "keystrokeCount")
    @Published var keystrokeDate: String = UserDefaults.standard.string(forKey: "keystrokeDate") ?? ""

    // Power mode
    @Published var comboCount: Int = 0
    @Published var particles: [CatParticle] = []
    private var comboResetTimer: Timer?
    var onComboReset: (() -> Void)?

    func incrementKeystroke() {
        let today = Self.todayString()
        if keystrokeDate != today {
            keystrokeCount = 0
            keystrokeDate = today
        }
        keystrokeCount += 1
        bumpCombo()
    }

    private func bumpCombo() {
        guard powerMode else { return }
        comboCount += 1
        spawnParticles()
        comboResetTimer?.invalidate()
        comboResetTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.comboCount = 0
            self?.onComboReset?()
        }
    }

    private func spawnParticles() {
        let count = min(3 + comboCount / 10, 8)
        for _ in 0..<count {
            let p = CatParticle(
                startX: Double.random(in: -30...30),
                dx: Double.random(in: -15...15),
                dy: Double.random(in: -50...(-15)),
                color: .randomForTier(comboCount)
            )
            particles.append(p)
        }
        // 오래된 파티클 정리
        let cutoff = Date().addingTimeInterval(-0.8)
        particles.removeAll { $0.created < cutoff }
    }

    var comboColor: CatParticleColor {
        switch comboCount {
        case 0..<30: return .cyan
        case 30..<60: return .green
        case 60..<100: return .orange
        case 100..<150: return .red
        default: return .pink
        }
    }

    func saveKeystrokeCount() {
        UserDefaults.standard.set(keystrokeCount, forKey: "keystrokeCount")
        UserDefaults.standard.set(keystrokeDate, forKey: "keystrokeDate")
    }

    private static func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

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
        let screen = NSScreen.screens[0]
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
        let screen = NSScreen.screens[0]  // 항상 주 모니터 기준 정규화
        let normX = (absX - Double(screen.frame.minX)) / Double(screen.frame.width)
        let normY = 1.0 - (absY - Double(screen.frame.minY)) / Double(screen.frame.height)
        return (x: normX, y: normY)  // 클램핑 없음 — 멀티모니터 좌표 보존
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
        guard x != 0 || y != 0 else { return }
        let point = CGPoint(x: x, y: y)
        let onScreen = NSScreen.screens.contains { $0.frame.contains(point) }
        if onScreen {
            absX = x; absY = y
        }
        // 화면 밖이면 init 기본 위치 유지
    }
}
