import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @ObservedObject var roomState: RoomState
    @ObservedObject var localCat: CatState
    @ObservedObject var updateChecker: UpdateChecker
    let onJoinRoom: (String) -> Void
    let onLeaveRoom: () -> Void
    let onNameChanged: (String) -> Void
    let onThemeChanged: (CatTheme) -> Void
    let onShowNameChanged: (Bool) -> Void
    let onSyncPositionChanged: (Bool) -> Void
    let onPowerModeChanged: (Bool) -> Void

    @State private var roomCodeInput: String = ""

    var body: some View {
        VStack(spacing: 0) {
            catHeader
            Divider()
            optionsSection
            Divider()
            themeSection
            Divider()
            roomSection
            Divider()
            bottomBar
        }
        .frame(width: 260)
    }

    // MARK: - Cat header

    private var catHeader: some View {
        HStack(spacing: 10) {
            Image(localCat.isActive ? roomState.selectedTheme.activeImage : roomState.selectedTheme.idleImage)
                .resizable()
                .interpolation(.none)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text("내 이름")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                TextField("이름", text: $roomState.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .textFieldStyle(.plain)
                    .onSubmit {
                        onNameChanged(roomState.displayName)
                    }
            }

            Spacer()
        }
        .padding(14)
    }

    // MARK: - Options section

    private var optionsSection: some View {
        VStack(spacing: 6) {
            Toggle("이름 표시", isOn: Binding(
                get: { localCat.showName },
                set: { onShowNameChanged($0) }
            ))
            .font(.system(size: 12))
            .toggleStyle(.checkbox)

            Toggle("위치 동기화", isOn: Binding(
                get: { localCat.syncPosition },
                set: { onSyncPositionChanged($0) }
            ))
            .font(.system(size: 12))
            .toggleStyle(.checkbox)

            Toggle("파워 모드", isOn: Binding(
                get: { localCat.powerMode },
                set: { onPowerModeChanged($0) }
            ))
            .font(.system(size: 12))
            .toggleStyle(.checkbox)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Theme section

    private var themeSection: some View {
        HStack(spacing: 8) {
            Text("테마")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 28, alignment: .leading)

            HStack(spacing: 6) {
                ForEach(CatTheme.allCases, id: \.self) { theme in
                    Button {
                        onThemeChanged(theme)
                    } label: {
                        Image(theme.idleImage)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: 32, height: 32)
                            .padding(3)
                            .background(roomState.selectedTheme == theme
                                ? Color.accentColor.opacity(0.2)
                                : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(roomState.selectedTheme == theme
                                        ? Color.accentColor
                                        : Color.clear, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(theme.displayName)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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

            // Connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(roomState.isConnected ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(roomState.isConnected ? "연결됨" : "재연결 중...")
                    .font(.system(size: 11))
                    .foregroundColor(roomState.isConnected ? .secondary : .orange)
                Spacer()
                if !roomState.peers.isEmpty {
                    Text("\(roomState.peers.count + 1)명")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            // Peer list
            if !roomState.peers.isEmpty {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(roomState.peers) { peer in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(peer.isActive ? Color.green : Color.gray.opacity(0.3))
                                    .frame(width: 6, height: 6)
                                Text(peer.name)
                                    .font(.system(size: 12))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, 6)
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(6)
                        }
                    }
                }
                .frame(maxHeight: 120)
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

    // MARK: - Join room

    private var joinRoomView: some View {
        VStack(spacing: 10) {
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
        VStack(spacing: 6) {
            Button {
                updateChecker.checkForUpdates()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 10))
                    Text("업데이트 확인")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            HStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("오늘 \(localCat.keystrokeCount.formatted())타")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
            }

            HStack {
                Text("catch-catch v\(updateChecker.currentVersion)")
                    .font(.system(size: 10))
                    .foregroundColor(Color.secondary.opacity(0.5))
                Spacer()
                Button("종료") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
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
