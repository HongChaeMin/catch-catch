import SwiftUI
import AppKit

struct SpeechBubble: View {
    let text: String
    var showTail: Bool = true

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .lineLimit(3)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: 200)
            .fixedSize(horizontal: true, vertical: true)
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

// MARK: - Power mode particles

struct ParticleView: View {
    let particles: [CatParticle]

    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date
            Canvas { context, size in
                let centerX = size.width / 2
                let bottomY = size.height * 0.75  // 고양이 하단 근처에서 시작
                for p in particles {
                    let age = now.timeIntervalSince(p.created)
                    let life: Double = 0.8
                    guard age < life else { continue }
                    let progress = age / life
                    let x = centerX + p.startX + p.dx * progress
                    let y = bottomY + p.dy * progress
                    let opacity = 1.0 - progress * progress  // 부드러운 페이드
                    let radius = 3.5 * (1.0 - progress * 0.4)

                    // 글로우
                    context.opacity = opacity * 0.35
                    let glowR = radius * 2.5
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - glowR, y: y - glowR, width: glowR * 2, height: glowR * 2)),
                        with: .color(p.color.swiftUIColor)
                    )

                    // 코어
                    context.opacity = opacity
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                        with: .color(p.color.swiftUIColor)
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct ComboLabel: View {
    let count: Int
    let color: CatParticleColor

    var body: some View {
        if count >= 2 {
            Text("x\(count)")
                .font(.system(size: comboFontSize, weight: .heavy, design: .rounded))
                .foregroundColor(color.swiftUIColor)
                .shadow(color: color.swiftUIColor.opacity(0.6), radius: 4)
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: count)
        }
    }

    private var comboFontSize: CGFloat {
        switch count {
        case 0..<30: return 14
        case 30..<60: return 16
        case 60..<100: return 18
        case 100..<150: return 20
        default: return 24
        }
    }
}

extension CatParticleColor {
    var swiftUIColor: Color {
        switch self {
        case .cyan: return Color(red: 0.3, green: 0.9, blue: 1.0)
        case .blue: return Color(red: 0.4, green: 0.6, blue: 1.0)
        case .green: return Color(red: 0.3, green: 1.0, blue: 0.5)
        case .yellow: return Color(red: 1.0, green: 0.95, blue: 0.3)
        case .orange: return Color(red: 1.0, green: 0.6, blue: 0.2)
        case .red: return Color(red: 1.0, green: 0.2, blue: 0.2)
        case .pink: return Color(red: 1.0, green: 0.3, blue: 0.7)
        case .white: return .white
        }
    }
}

struct SleepIndicator: View {
    @State private var opacity: Double = 0.4

    var body: some View {
        Text("\u{1F4A4}")
            .font(.system(size: 18))
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    opacity = 1.0
                }
            }
    }
}

struct CatWidget: View {
    let isActive: Bool
    let name: String
    let isLocal: Bool
    let theme: CatTheme
    let messages: [BubbleMessage]
    var isChatOpen: Bool = false
    var showName: Bool = true
    var isSleeping: Bool = false
    var comboCount: Int = 0
    var comboColor: CatParticleColor = .white
    var particles: [CatParticle] = []

    var body: some View {
        Image(isActive ? theme.activeImage : theme.idleImage)
            .resizable()
            .interpolation(.none)
            .frame(width: 80, height: 80)
            // 수면 표시: 고양이 머리 위 왼쪽
            .overlay(alignment: .topLeading) {
                if isSleeping {
                    SleepIndicator()
                        .offset(x: -16, y: -24)
                }
            }
            // 말풍선: 고양이 위로 쌓임
            .overlay(alignment: .top) {
                VStack(spacing: 4) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
                        SpeechBubble(text: msg.text, showTail: index == messages.count - 1)
                    }
                }
                .fixedSize()
                .alignmentGuide(.top) { d in d[.bottom] + 6 }
                .animation(.easeOut(duration: 0.18), value: messages)
            }
            // 파워모드: 파티클 + 콤보
            .overlay {
                ParticleView(particles: particles)
                    .frame(width: 160, height: 160)
            }
            .overlay(alignment: .topTrailing) {
                ComboLabel(count: comboCount, color: comboColor)
                    .offset(x: 10, y: -10)
            }
            // 이름: 고양이 바로 밑 (채팅 인풋 열리면 더 밑으로)
            .overlay(alignment: .bottom) {
                if showName {
                    Text(name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(6)
                        .fixedSize()
                        .alignmentGuide(.bottom) { d in d[.top] - 2 }
                        .offset(y: isChatOpen ? 58 : 0)
                        .animation(.easeOut(duration: 0.15), value: isChatOpen)
                }
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
                messages: localCat.bubbleMessages,
                isChatOpen: localCat.isChatOpen,
                showName: localCat.showName,
                isSleeping: localCat.isSleeping,
                comboCount: localCat.comboCount,
                comboColor: localCat.comboColor,
                particles: localCat.particles
            )
            widget.position(x: localX, y: localY)
        }
    }

    private var peerCatsView: some View {
        ForEach(roomState.peers) { peer in
            let peerComboColor: CatParticleColor = {
                switch peer.comboCount {
                case 0..<30: return .cyan
                case 30..<60: return .green
                case 60..<100: return .orange
                case 100..<150: return .red
                default: return .pink
                }
            }()
            CatWidget(
                isActive: peer.isActive,
                name: peer.name,
                isLocal: false,
                theme: peer.theme,
                messages: peer.bubbleMessages,
                isSleeping: peer.isSleeping,
                comboCount: peer.comboCount,
                comboColor: peerComboColor,
                particles: peer.particles
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
