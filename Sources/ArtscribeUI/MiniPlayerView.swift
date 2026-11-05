#if os(macOS)
import AppKit
import SwiftUI

/// What the Mac's mini player shows: the picture, and on hover the two things
/// you reach for from another app — play/pause, and the way back.
struct MiniPlayerView: View {
    let model: ViewerModel
    let playPause: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
            if let presenter = model.video?.presenter {
                VideoSurfaceRepresentable(presenter: presenter)
            }
            controls
                .opacity(hovering ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: hovering)
        }
        .onHover { hovering = $0 }
        .ignoresSafeArea()
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Button(action: playPause) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .help(model.isPlaying ? "Pause" : "Play")
            Button {
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "arrow.up.backward.and.arrow.down.forward")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .help("Show Artscripture")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
        .padding(.bottom, 12)
    }
}
#endif
