import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @ObservedObject var roomState: RoomState
    @ObservedObject var localCat: CatState
    @ObservedObject var eventMonitor: GlobalEventMonitor
    let onToggleMove: () -> Void
    let onJoinRoom: (String) -> Void
    let onLeaveRoom: () -> Void
    var isMoving: Bool

    @State private var roomCodeInput: String = ""

    var body: some View {
        VStack(spacing: 12) {
            // Input Monitoring permission warning
            if !eventMonitor.hasInputMonitoringPermission {
                permissionBanner
                Divider()
            }

            // Display name
            nameSection

            Divider()

            // Room section
            roomSection

            Divider()

            // Move cat button
            Button(action: onToggleMove) {
                HStack {
                    Image(systemName: isMoving ? "lock.fill" : "arrow.up.and.down.and.arrow.left.and.right")
                    Text(isMoving ? "위치 고정" : "고양이 이동")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isMoving ? Color.orange.opacity(0.15) : Color.gray.opacity(0.1))
                .foregroundColor(isMoving ? .orange : .primary)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Divider()

            Button("종료") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
        }
        .padding(14)
        .frame(width: 240)
    }

    private var permissionBanner: some View {
        Button(action: GlobalEventMonitor.openInputMonitoringSettings) {
            HStack(spacing: 8) {
                Image(systemName: "keyboard.badge.exclamationmark")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("타자 감지 권한 필요")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text("설정 열기 →")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
                Spacer()
            }
            .padding(8)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("내 이름")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("이름 입력", text: $roomState.displayName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    localCat.name = roomState.displayName
                    UserDefaults.standard.set(roomState.displayName, forKey: "displayName")
                }
        }
    }

    @ViewBuilder
    private var roomSection: some View {
        if let code = roomState.roomCode {
            // Connected to a room
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("룸 코드")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(code)
                            .font(.system(.title3, design: .monospaced, weight: .bold))
                            .foregroundColor(.blue)
                    }
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }

                // Connection status
                HStack(spacing: 6) {
                    Circle()
                        .fill(roomState.isConnected ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(roomState.isConnected ? "\(roomState.peers.count + 1)명 접속 중" : "연결 중...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }

                // Peer list
                if !roomState.peers.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(roomState.peers) { peer in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(peer.isActive ? Color.green : Color.gray.opacity(0.4))
                                    .frame(width: 6, height: 6)
                                Text(peer.name)
                                    .font(.caption)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button("나가기", action: onLeaveRoom)
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                    .font(.subheadline)
            }
        } else {
            // Not in a room
            VStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("룸 코드로 참가")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        TextField("ABC123", text: $roomCodeInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .textCase(.uppercase)
                            .onSubmit { joinIfValid() }
                        Button("참가") { joinIfValid() }
                            .disabled(roomCodeInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                if let error = roomState.connectionError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Button("새 룸 만들기") {
                    let code = randomRoomCode()
                    roomCodeInput = code
                    onJoinRoom(code)
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
            }
        }
    }

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
