import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @ObservedObject var roomState: RoomState
    @ObservedObject var localCat: CatState
    let onToggleMove: () -> Void
    let onJoinRoom: (String) -> Void
    let onLeaveRoom: () -> Void
    var isMoving: Bool

    @State private var roomCodeInput: String = ""
    @State private var isEditingName = false

    var body: some View {
        VStack(spacing: 0) {
            catHeader
            Divider()
            roomSection
            Divider()
            bottomBar
        }
        .frame(width: 260)
    }

    // MARK: - Cat header (name + move button)

    private var catHeader: some View {
        HStack(spacing: 10) {
            // Cat preview
            Image(localCat.isActive ? "cat_active" : "cat_idle")
                .resizable()
                .interpolation(.none)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Name field
            VStack(alignment: .leading, spacing: 2) {
                Text("내 이름")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                TextField("이름", text: $roomState.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .textFieldStyle(.plain)
                    .onSubmit {
                        localCat.name = roomState.displayName
                        UserDefaults.standard.set(roomState.displayName, forKey: "displayName")
                    }
            }

            Spacer()

            // Move mode toggle
            Button(action: onToggleMove) {
                Image(systemName: isMoving ? "lock.fill" : "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 13))
                    .frame(width: 28, height: 28)
                    .background(isMoving ? Color.orange.opacity(0.2) : Color.secondary.opacity(0.1))
                    .foregroundColor(isMoving ? .orange : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .help(isMoving ? "위치 고정" : "고양이 이동")
        }
        .padding(14)
    }

    // MARK: - Room section

    @ViewBuilder
    private var roomSection: some View {
        if let code = roomState.roomCode {
            connectedRoomView(code: code)
        } else {
            joinRoomView
        }
    }

    private func connectedRoomView(code: String) -> some View {
        VStack(spacing: 10) {
            // Room code + copy
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("룸 코드")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(code)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentColor)
                        .tracking(2)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 13))
                        .frame(width: 28, height: 28)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("코드 복사")
            }

            // Connection status + peers
            HStack(spacing: 6) {
                Circle()
                    .fill(roomState.isConnected ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(roomState.isConnected ? "연결됨" : "연결 중...")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                if !roomState.peers.isEmpty {
                    Text("\(roomState.peers.count + 1)명")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            // Peer list
            if !roomState.peers.isEmpty {
                VStack(spacing: 4) {
                    ForEach(roomState.peers) { peer in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(peer.isActive ? Color.green : Color.gray.opacity(0.3))
                                .frame(width: 6, height: 6)
                            Text(peer.name)
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(6)
                    }
                }
            }

            // Leave button
            Button(action: onLeaveRoom) {
                Text("나가기")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .foregroundColor(.red)
        }
        .padding(14)
    }

    private var joinRoomView: some View {
        VStack(spacing: 10) {
            // Code input
            HStack(spacing: 6) {
                TextField("코드 입력 (예: ABC123)", text: $roomCodeInput)
                    .font(.system(size: 13, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .textCase(.uppercase)
                    .onSubmit { joinIfValid() }

                Button("참가", action: joinIfValid)
                    .buttonStyle(.borderedProminent)
                    .disabled(roomCodeInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let error = roomState.connectionError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                let code = randomRoomCode()
                roomCodeInput = code
                onJoinRoom(code)
            } label: {
                Label("새 룸 만들기", systemImage: "plus.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            Text("catch-catch")
                .font(.system(size: 10))
                .foregroundColor(Color.secondary.opacity(0.5))
            Spacer()
            Button("종료") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func joinIfValid() {
        let code = roomCodeInput.trimmingCharacters(in: .whitespaces).uppercased()
        guard !code.isEmpty else { return }
        onJoinRoom(code)
    }

    private func randomRoomCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in chars.randomElement()! })
    }
}
