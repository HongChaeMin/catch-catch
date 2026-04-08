import Foundation

// MARK: - Message types

enum ServerMessage {
    case joined(users: [JoinedUser])
    case userJoined(userId: String, name: String, theme: String)
    case userLeft(userId: String)
    case stateUpdate(userId: String, x: Double, y: Double, isActive: Bool)
    case renamed(userId: String, name: String)
    case themeChanged(userId: String, theme: String)
    case chat(userId: String, name: String, text: String)
    case error(message: String)
}

struct JoinedUser {
    let userId: String
    let name: String
    let x: Double
    let y: Double
    let isActive: Bool
    let theme: String
}

// MARK: - Client

class WebSocketClient: NSObject, URLSessionWebSocketDelegate {
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var retryCount = 0
    private let maxRetries = 3
    private var pendingJoin: (url: URL, roomCode: String, userId: String, name: String)?

    private(set) var isConnected: Bool = false

    var onMessage: ((ServerMessage) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    var onConnectionFailed: (() -> Void)?

    var currentTheme: String = "cat"

    func connect(to url: URL, roomCode: String, userId: String, name: String) {
        pendingJoin = (url, roomCode, userId, name)
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        task = session?.webSocketTask(with: url)
        task?.resume()
        receive()
    }

    func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        pendingJoin = nil
        retryCount = 0
        isConnected = false
    }

    func sendState(x: Double, y: Double, isActive: Bool) {
        let msg: [String: Any] = ["type": "state", "x": x, "y": y, "active": isActive]
        send(msg)
    }

    func sendChat(text: String) {
        send(["type": "chat", "text": text])
    }

    func sendRename(name: String) {
        send(["type": "rename", "name": name])
    }

    func sendTheme(theme: String) {
        send(["type": "theme", "theme": theme])
    }

    private func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self.handleMessage(text)
                }
                self.receive()
            case .failure:
                self.handleDisconnect()
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "joined":
            let users = (json["users"] as? [[String: Any]] ?? []).compactMap { u -> JoinedUser? in
                guard let id = u["userId"] as? String,
                      let name = u["name"] as? String else { return nil }
                return JoinedUser(
                    userId: id, name: name,
                    x: u["x"] as? Double ?? 0.85,
                    y: u["y"] as? Double ?? 0.85,
                    isActive: u["active"] as? Bool ?? false,
                    theme: u["theme"] as? String ?? "cat"
                )
            }
            onMessage?(.joined(users: users))

        case "user_joined":
            if let userId = json["userId"] as? String, let name = json["name"] as? String {
                let theme = json["theme"] as? String ?? "cat"
                onMessage?(.userJoined(userId: userId, name: name, theme: theme))
            }

        case "user_left":
            if let userId = json["userId"] as? String {
                onMessage?(.userLeft(userId: userId))
            }

        case "state":
            if let userId = json["userId"] as? String {
                onMessage?(.stateUpdate(
                    userId: userId,
                    x: json["x"] as? Double ?? 0.5,
                    y: json["y"] as? Double ?? 0.5,
                    isActive: json["active"] as? Bool ?? false
                ))
            }

        case "renamed":
            if let userId = json["userId"] as? String, let name = json["name"] as? String {
                onMessage?(.renamed(userId: userId, name: name))
            }

        case "theme":
            if let userId = json["userId"] as? String, let theme = json["theme"] as? String {
                onMessage?(.themeChanged(userId: userId, theme: theme))
            }

        case "chat":
            if let userId = json["userId"] as? String,
               let name = json["name"] as? String,
               let text = json["text"] as? String {
                onMessage?(.chat(userId: userId, name: name, text: text))
            }

        case "error":
            onMessage?(.error(message: json["message"] as? String ?? "Unknown error"))

        default:
            break
        }
    }

    private func handleDisconnect() {
        isConnected = false
        onDisconnected?()

        guard retryCount < maxRetries, pendingJoin != nil else {
            if pendingJoin != nil { onConnectionFailed?() }
            return
        }

        retryCount += 1
        let delay = pow(2.0, Double(retryCount))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let pending = self.pendingJoin else { return }
            self.connect(to: pending.url, roomCode: pending.roomCode, userId: pending.userId, name: pending.name)
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        retryCount = 0
        isConnected = true
        onConnected?()
        if let pending = pendingJoin {
            let msg: [String: Any] = [
                "type": "join",
                "roomCode": pending.roomCode,
                "userId": pending.userId,
                "name": pending.name,
                "theme": currentTheme
            ]
            send(msg)
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        handleDisconnect()
    }
}
