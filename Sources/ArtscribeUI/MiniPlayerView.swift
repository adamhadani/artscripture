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

    /// The hover controls' sizes: a pointer target over a small window.
    private static let button: CGFloat = 36
    private static let playGlyph: CGFloat = 18
    private static let backGlyph: CGFloat = 15
    private static let gap: CGFloat = 18

    private var controls: some View {
        HStack(spacing: Self.gap) {
            Button(action: playPause) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: Self.playGlyph, weight: .semibold))
                    .frame(width: Self.button, height: Self.button)
            }
            .help(model.isPlaying ? "Pause" : "Play")
            Button {
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "arrow.up.backward.and.arrow.down.forward")
                    .font(.system(size: Self.backGlyph, weight: .semibold))
                    .frame(width: Self.button, height: Self.button)
            }
            .help("Show Artscripture")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, Metrics.xxl)
        .padding(.vertical, Metrics.sm)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
        .padding(.bottom, Metrics.xl)
    }
}
#endif
