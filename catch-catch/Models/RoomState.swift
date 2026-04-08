import Foundation
import Combine

struct BubbleMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

struct PeerCat: Identifiable {
    let id: String  // userId
    var name: String
    var x: Double
    var y: Double
    var isActive: Bool
    var bubbleMessages: [BubbleMessage] = []
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

    var idleImage: String { "\(rawValue)_idle" }
    var activeImage: String { "\(rawValue)_active" }

    var displayName: String {
        switch self {
        case .gray: return "회색 고양이"
        case .gray2: return "흰색 고양이"
        case .calico: return "삼색 고양이"
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

    func upsertPeer(userId: String, name: String, x: Double, y: Double, isActive: Bool) {
        if let idx = peers.firstIndex(where: { $0.id == userId }) {
            peers[idx].x = x
            peers[idx].y = y
            peers[idx].isActive = isActive
            peers[idx].name = name
        } else {
            peers.append(PeerCat(id: userId, name: name, x: x, y: y, isActive: isActive))
        }
    }

    func updatePeerState(userId: String, x: Double, y: Double, isActive: Bool) {
        if let idx = peers.firstIndex(where: { $0.id == userId }) {
            peers[idx].x = x
            peers[idx].y = y
            peers[idx].isActive = isActive
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
