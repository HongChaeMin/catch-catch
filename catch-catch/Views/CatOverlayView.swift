import SwiftUI
import AppKit

// MARK: - Single cat widget

struct CatWidget: View {
    let isActive: Bool
    let name: String
    let isLocal: Bool

    var body: some View {
        VStack(spacing: 2) {
            if !isLocal {
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(6)
            }
            Image(isActive ? "cat_active" : "cat_idle")
                .resizable()
                .interpolation(.none)  // pixel-perfect scaling
                .frame(width: 80, height: 80)
        }
    }
}

// MARK: - Per-screen overlay

/// Renders cats for one specific screen.
/// - Local cat: shown only on the screen its absolute position falls within.
/// - Peer cats: shown only on the primary (main) screen to avoid duplicates.
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

    // Local cat: only if its absolute position is within this screen
    @ViewBuilder
    private var localCatView: some View {
        let absPoint = CGPoint(x: localCat.absX, y: localCat.absY)
        if screen.frame.contains(absPoint) {
            // Convert absolute → local SwiftUI coords (flip Y: macOS BL → SwiftUI TL)
            let localX = localCat.absX - Double(screen.frame.minX)
            let localY = Double(screen.frame.height) - (localCat.absY - Double(screen.frame.minY))
            CatWidget(isActive: localCat.isActive, name: localCat.name, isLocal: true)
                .position(x: localX, y: localY)
        }
    }

    // Peer cats: normalized (0–1) → local SwiftUI coords on primary screen
    private var peerCatsView: some View {
        ForEach(roomState.peers) { peer in
            CatWidget(isActive: peer.isActive, name: peer.name, isLocal: false)
                .position(
                    x: peer.x * Double(screen.frame.width),
                    y: peer.y * Double(screen.frame.height)
                )
        }
    }
}
