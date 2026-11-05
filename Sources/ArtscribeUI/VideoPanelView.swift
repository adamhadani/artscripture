import SwiftUI
import Video

/// The picture of the open video file: black, aspect-fit, and saying why when
/// there is nothing to show.
struct VideoPanelView: View {
    let video: VideoState

    var body: some View {
        ZStack {
            Color.black
            if let presenter = video.presenter {
                VideoSurfaceRepresentable(presenter: presenter)
            }
            if let failure = video.failure {
                Text("This video's picture can't be shown. \(failure)")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(Metrics.lg)
            }
        }
        .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Video")
    }
}

/// Puts a `VideoSurfaceView` into SwiftUI and keeps it attached to the
/// presenter for exactly as long as it is on screen.
struct VideoSurfaceRepresentable {
    let presenter: VideoPresenter

    final class Coordinator {
        var presenter: VideoPresenter?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    private func connect(_ view: VideoSurfaceView, _ coordinator: Coordinator) {
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
    }
}
#endif
