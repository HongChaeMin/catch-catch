import SwiftUI
import AppKit

struct SpeechBubble: View {
    let text: String
    var showTail: Bool = true

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .lineLimit(4)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: 220)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.78))
            )
            .overlay(alignment: .bottom) {
                if showTail {
                    Triangle()
                        .fill(Color.black.opacity(0.78))
                        .frame(width: 10, height: 6)
                        .offset(y: 6)
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

struct CatWidget: View {
    let isActive: Bool
    let name: String
    let isLocal: Bool
    let theme: CatTheme
    let messages: [BubbleMessage]

    var body: some View {
        Image(isActive ? theme.activeImage : theme.idleImage)
            .resizable()
            .interpolation(.none)
            .frame(width: 80, height: 80)
            .overlay(alignment: .top) {
                // 말풍선/이름을 cat 위에 띄움. alignmentGuide로 child의 bottom을
                // parent의 top에 붙여서 메시지가 늘어도 cat은 제자리, 말풍선만 위로 쌓임.
                VStack(spacing: 4) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
                        SpeechBubble(text: msg.text, showTail: index == messages.count - 1)
                    }
                    if !isLocal {
                        Text(name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(6)
                    }
                }
                .fixedSize()
                .alignmentGuide(.top) { d in d[.bottom] + 6 }
                .animation(.easeOut(duration: 0.18), value: messages)
            }
    }
}

struct CatOverlayView: View {
    @ObservedObject var localCat: CatState
    @ObservedObject var roomState: RoomState
    let screen: NSScreen
    let isPrimary: Bool

    var body: some View {
        ZStack {
            localCatView
            if isPrimary { peerCatsView }
        }
        .frame(width: screen.frame.width, height: screen.frame.height)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var localCatView: some View {
        let absPoint = CGPoint(x: localCat.absX, y: localCat.absY)
        if screen.frame.contains(absPoint) {
            let localX: CGFloat = CGFloat(localCat.absX) - screen.frame.minX
            let localY: CGFloat = screen.frame.height - (CGFloat(localCat.absY) - screen.frame.minY)
            let widget = CatWidget(
                isActive: localCat.isActive,
                name: localCat.name,
                isLocal: true,
                theme: roomState.selectedTheme,
                messages: localCat.bubbleMessages
            )
            widget.position(x: localX, y: localY)
        }
    }

    private var peerCatsView: some View {
        ForEach(roomState.peers) { peer in
            CatWidget(
                isActive: peer.isActive,
                name: peer.name,
                isLocal: false,
                theme: roomState.selectedTheme,
                messages: peer.bubbleMessages
            )
            .position(
                x: peer.x * Double(screen.frame.width),
                y: peer.y * Double(screen.frame.height)
            )
        }
    }
}

// MARK: - Chat input panel (floating)

struct ChatInputView: View {
    static let width: CGFloat = 240
    static let height: CGFloat = 38

    @State private var text = ""
    @FocusState private var focused: Bool
    let onSend: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            TextField("메시지...", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .focused($focused)
                .onSubmit { submit() }

            Button(action: submit) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderedProminent)
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(width: Self.width, height: Self.height)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                focused = true
            }
        }
        .onExitCommand { onDismiss() }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onSend(trimmed)
        text = ""
    }
}
