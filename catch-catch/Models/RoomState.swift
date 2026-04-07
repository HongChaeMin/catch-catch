import Foundation
import Combine

struct PeerCat: Identifiable {
    let id: String  // userId
    var name: String
    var x: Double
    var y: Double
    var isActive: Bool
}

class RoomState: ObservableObject {
    @Published var roomCode: String? = nil
    @Published var isConnected: Bool = false
    @Published var peers: [PeerCat] = []
    @Published var connectionError: String? = nil
    @Published var displayName: String = {
        return UserDefaults.standard.string(forKey: "displayName") ?? NSFullUserName()
    }()

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

    func removePeer(userId: String) {
        peers.removeAll { $0.id == userId }
    }

    func reset() {
        roomCode = nil
        isConnected = false
        peers = []
        connectionError = nil
    }
}
