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

// MARK: - Full overlay view (all cats)

struct CatOverlayView: View {
    @ObservedObject var localCat: CatState
    @ObservedObject var roomState: RoomState
    let screenSize: CGSize

    var body: some View {
        ZStack {
            // Local cat
            CatWidget(isActive: localCat.isActive, name: localCat.name, isLocal: true)
                .position(
                    x: localCat.x * screenSize.width,
                    y: localCat.y * screenSize.height
                )

            // Peer cats
            ForEach(roomState.peers) { peer in
                CatWidget(isActive: peer.isActive, name: peer.name, isLocal: false)
                    .position(
                        x: peer.x * screenSize.width,
                        y: peer.y * screenSize.height
                    )
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .ignoresSafeArea()
    }
}
