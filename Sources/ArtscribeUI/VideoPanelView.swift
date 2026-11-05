import SwiftUI
import Video

/// The picture of the open video file: black, aspect-fit, and saying why when
/// there is nothing to show.
struct VideoPanelView: View {
    let video: VideoState
    /// The corner button's target — and, on iOS, the owner of the system
    /// Picture in Picture that takes its picture from this panel's layer.
    let miniPlayer: MiniPlayerController
    @State private var hovering = false

    var body: some View {
        ZStack {
            Color.black
            if let presenter = video.presenter {
                // Kept while floating, not removed: on iOS this very layer is
                // what Picture in Picture shows, and dismantling it would end it.
                VideoSurfaceRepresentable(presenter: presenter, pictureInPicture: miniPlayer)
            }
            if video.isFloating {
                // Like every Apple player: say where the picture went, rather
                // than draw it twice.
                ZStack {
                    Color.black
                    Label("Playing in the mini player", systemImage: "pip")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            if let failure = video.failure {
                Text("This video's picture can't be shown. \(failure)")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(Metrics.lg)
            }
        }
        .overlay(alignment: .topTrailing) { pictureInPictureButton }
        .onHover { hovering = $0 }
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Video")
    }

    /// Shown on hover with a pointer, always on touch — where there is no
    /// hover to reveal it.
    @ViewBuilder
    private var pictureInPictureButton: some View {
        if MiniPlayerSupport.isAvailable, video.presenter != nil {
            let touch = ControlMetrics.current.target >= 44
            Button(action: miniPlayer.toggleByUser) {
                Image(systemName: video.isFloating ? "pip.exit" : "pip.enter")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(Metrics.md)
            .opacity(hovering || touch ? 1 : 0)
            .help(video.isFloating ? "Back to the window" : "Picture in Picture  (⇧I)")
            .accessibilityLabel("Picture in Picture")
        }
    }
}

/// Puts a `VideoSurfaceView` into SwiftUI and keeps it attached to the
/// presenter for exactly as long as it is on screen.
struct VideoSurfaceRepresentable {
    let presenter: VideoPresenter
    /// Told about the surface so iOS's Picture in Picture can take its layer.
    /// `nil` only for the Mac mini player's own surface, which is not a source.
    var pictureInPicture: MiniPlayerController?

    final class Coordinator {
        var presenter: VideoPresenter?
        weak var pictureInPicture: MiniPlayerController?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    private func connect(_ view: VideoSurfaceView, _ coordinator: Coordinator) {
        if coordinator.pictureInPicture == nil, let pictureInPicture {
            coordinator.pictureInPicture = pictureInPicture
            pictureInPicture.adopt(surface: view)
        }
        guard coordinator.presenter !== presenter else { return }
        coordinator.presenter?.detach(view)
        coordinator.presenter = presenter
        presenter.attach(view)
    }
}

#if os(macOS)
extension VideoSurfaceRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> VideoSurfaceView {
        let view = VideoSurfaceView()
        connect(view, context.coordinator)
        return view
    }

    func updateNSView(_ view: VideoSurfaceView, context: Context) {
        connect(view, context.coordinator)
    }

    static func dismantleNSView(_ view: VideoSurfaceView, coordinator: Coordinator) {
        coordinator.presenter?.detach(view)
        coordinator.pictureInPicture?.release(surface: view)
    }
}
#else
extension VideoSurfaceRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> VideoSurfaceView {
        let view = VideoSurfaceView()
        connect(view, context.coordinator)
        return view
    }

    func updateUIView(_ view: VideoSurfaceView, context: Context) {
        connect(view, context.coordinator)
    }

    static func dismantleUIView(_ view: VideoSurfaceView, coordinator: Coordinator) {
        coordinator.presenter?.detach(view)
        coordinator.pictureInPicture?.release(surface: view)
    }
}
#endif
