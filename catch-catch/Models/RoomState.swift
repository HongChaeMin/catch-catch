import Foundation
import Combine

struct BubbleMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

enum CatParticleColor: CaseIterable {
    case cyan, blue, green, yellow, orange, red, pink, white

    static func randomForTier(_ combo: Int) -> CatParticleColor {
        let pool: [CatParticleColor] = switch combo {
        case 0..<30: [.cyan, .blue, .white]
        case 30..<60: [.green, .cyan, .yellow]
        case 60..<100: [.yellow, .orange, .pink]
        case 100..<150: [.orange, .red, .pink]
        default: [.red, .pink, .orange]
        }
        return pool.randomElement()!
    }
}

struct CatParticle: Identifiable {
    let id = UUID()
    let startX: Double  // 시작 x 오프셋 (고양이 너비 범위)
    let dx: Double      // 수평 드리프트
    let dy: Double      // 수직 이동 (음수 = 위)
    let color: CatParticleColor
    let created = Date()
}

struct PeerCat: Identifiable {
    let id: String  // userId
    var name: String
    var x: Double
    var y: Double
    var isActive: Bool
    var theme: CatTheme = .gray
    var bubbleMessages: [BubbleMessage] = []
    var isSleeping: Bool = false
    var comboCount: Int = 0
    var particles: [CatParticle] = []
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let userId: String
    let name: String
    let text: String
}

enum CatTheme: String, CaseIterable {
    case gray = "cat"
    case gray2 = "cat2"
    case calico = "cat3"
    case calico2 = "cat4"

    var idleImage: String { "\(rawValue)_idle" }
    var activeImage: String { "\(rawValue)_active" }

    var displayName: String {
        switch self {
        case .gray: return "회색 고양이"
        case .gray2: return "흰색 고양이"
        case .calico: return "삼색 고양이"
        case .calico2: return "삼색 고양이 2"
        }
    }
}

class RoomState: ObservableObject {
    @Published var roomCode: String? = nil
    @Published var isConnected: Bool = false
    @Published var peers: [PeerCat] = []
    @Published var connectionError: String? = nil
    @Published var messages: [ChatMessage] = []
    @Published var selectedTheme: CatTheme = {
        let saved = UserDefaults.standard.string(forKey: "catTheme") ?? ""
        return CatTheme(rawValue: saved) ?? .gray
    }()
    @Published var displayName: String = {
        return UserDefaults.standard.string(forKey: "displayName") ?? NSFullUserName()
    }()

    func showPeerMessage(userId: String, text: String, duration: TimeInterval = 5) {
        guard let idx = peers.firstIndex(where: { $0.id == userId }) else { return }
        let msg = BubbleMessage(text: text)
        peers[idx].bubbleMessages.append(msg)
        if peers[idx].bubbleMessages.count > 5 {
            peers[idx].bubbleMessages.removeFirst(peers[idx].bubbleMessages.count - 5)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, let i = self.peers.firstIndex(where: { $0.id == userId }) else { return }
            self.peers[i].bubbleMessages.removeAll { $0.id == msg.id }
        }
    }

    func upsertPeer(userId: String, name: String, x: Double, y: Double, isActive: Bool, theme: CatTheme = .gray) {
        if let idx = peers.firstIndex(where: { $0.id == userId }) {
            peers[idx].x = x
            peers[idx].y = y
            peers[idx].isActive = isActive
            peers[idx].name = name
            peers[idx].theme = theme
        } else {
            peers.append(PeerCat(id: userId, name: name, x: x, y: y, isActive: isActive, theme: theme))
        }
    }

    func updatePeerTheme(userId: String, theme: CatTheme) {
        if let idx = peers.firstIndex(where: { $0.id == userId }) {
            peers[idx].theme = theme
        }
    }

    func updatePeerState(userId: String, x: Double, y: Double, isActive: Bool) {
        if let idx = peers.firstIndex(where: { $0.id == userId }) {
            peers[idx].x = x
            peers[idx].y = y
            peers[idx].isActive = isActive
        }
    }

    func updatePeerActive(userId: String, isActive: Bool) {
        if let idx = peers.firstIndex(where: { $0.id == userId }) {
            peers[idx].isActive = isActive
        }
    }

    func updatePeerSleeping(userId: String, isSleeping: Bool) {
        if let idx = peers.firstIndex(where: { $0.id == userId }) {
            peers[idx].isSleeping = isSleeping
        }
    }

    func updatePeerCombo(userId: String, combo: Int) {
        guard let idx = peers.firstIndex(where: { $0.id == userId }) else { return }
        let oldCombo = peers[idx].comboCount
        peers[idx].comboCount = combo
        // 콤보가 증가하면 파티클 스폰
        if combo > oldCombo {
            let count = min(3 + combo / 10, 8)
            for _ in 0..<count {
                peers[idx].particles.append(CatParticle(
                    startX: Double.random(in: -30...30),
                    dx: Double.random(in: -15...15),
                    dy: Double.random(in: -50...(-15)),
                    color: .randomForTier(combo)
                ))
            }
            let cutoff = Date().addingTimeInterval(-0.8)
            peers[idx].particles.removeAll { $0.created < cutoff }
        } else if combo == 0 {
            peers[idx].particles.removeAll()
        }
    }

    func updatePeerName(userId: String, name: String) {
        if let idx = peers.firstIndex(where: { $0.id == userId }) {
            peers[idx].name = name
        }
    }

    func addMessage(userId: String, name: String, text: String) {
        messages.append(ChatMessage(userId: userId, name: name, text: text))
        if messages.count > 100 { messages.removeFirst() }
    }

    func removePeer(userId: String) {
        peers.removeAll { $0.id == userId }
    }

    func reset() {
        roomCode = nil
        isConnected = false
        peers = []
        connectionError = nil
        messages = []
    }
}
