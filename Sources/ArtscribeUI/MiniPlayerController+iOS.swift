#if !os(macOS)
import AVKit
import CoreMedia
import Observation
import UIKit

/// iOS's mini player is the system's Picture in Picture, fed from the main
/// panel's own display layer — a sample-buffer content source, so the frames
/// stay ours and its buttons drive our transport rather than an `AVPlayer`.
///
/// Every decision is `MiniPlayerPolicy`'s or `PictureInPictureBridge`'s, both
/// tested on the Mac; this file only translates.
extension MiniPlayerController {

    func adoptPictureInPictureSource(_ surface: VideoSurfaceView) {
        guard surface !== pipSurface, AVPictureInPictureController.isPictureInPictureSupported()
        else { return }
        pipSurface = surface
        let delegate = PictureInPictureDelegate(controller: self)
        let pip = AVPictureInPictureController(
            contentSource: .init(
                sampleBufferDisplayLayer: surface.displayLayer, playbackDelegate: delegate))
        pip.delegate = delegate
        // Live: the position jumps back at every loop wrap, so a scrubber
        // would misreport it. Play/pause is what the window is for.
        pip.requiresLinearPlayback = false
        self.pip = pip
        pipDelegate = delegate
        updateAutomaticStart()
    }

    func releasePictureInPictureSource(_ surface: VideoSurfaceView) {
        guard surface === pipSurface else { return }
        pip?.stopPictureInPicture()
        pip = nil
        pipDelegate = nil
        pipSurface = nil
    }

    func present() {
        guard let pip, pip.isPictureInPicturePossible else {
            pictureInPictureEnded()
            return
        }
        pip.startPictureInPicture()
    }

    func dismiss() {
        pip?.stopPictureInPicture()
    }

    /// Whether the system may start it on its own when the app goes to the
    /// background. It adds "playing" by asking `isPlaybackPaused`.
    func updateAutomaticStart() {
        refreshFacts()
        pip?.canStartPictureInPictureAutomaticallyFromInline =
            PictureInPictureBridge.startsAutomatically(state)
    }

    // MARK: - From the system

    func pictureInPictureBegan() {
        state.isShowing = true
        model.video?.isFloating = true
    }

    func pictureInPictureEnded() {
        state.isShowing = false
        state.openedByUser = false
        model.video?.isFloating = false
    }

    func setPlaying(_ playing: Bool) {
        guard
            PictureInPictureBridge.shouldToggle(
                requestedPlaying: playing, isPlaying: model.isPlaying)
        else { return }
        model.togglePlayPause()
    }

    var isPaused: Bool { !model.isPlaying }

    func skip(by seconds: Double) {
        let frames = PictureInPictureBridge.frames(forSkip: seconds, sampleRate: model.sampleRate)
        model.seek(to: min(max(0, model.playhead + frames), model.totalFrames))
    }

    /// The window's play button reads `isPlaybackPaused`; it is only asked
    /// again when told the answer changed.
    func observePlaying() {
        withObservationTracking {
            _ = model.isPlaying
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.pip?.invalidatePlaybackState()
                self?.observePlaying()
            }
        }
    }
}

/// AVKit's two delegate protocols, forwarded to the controller. AVKit calls
/// both on the main thread.
@MainActor
final class PictureInPictureDelegate: NSObject {
    private weak var controller: MiniPlayerController?

    init(controller: MiniPlayerController) {
        self.controller = controller
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool
    ) {
        controller?.setPlaying(playing)
    }

    func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        controller?.isPaused ?? true
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime
    ) async {
        controller?.skip(by: skipInterval.seconds)
    }

    func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        controller?.pictureInPictureBegan()
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        controller?.pictureInPictureEnded()
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: any Error
    ) {
        controller?.pictureInPictureEnded()
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler:
            @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}
// The conformances on their own, so the declaration fits on one line; the
// methods above satisfy them.
typealias SampleBufferPlaybackDelegate = AVPictureInPictureSampleBufferPlaybackDelegate
extension PictureInPictureDelegate: @preconcurrency SampleBufferPlaybackDelegate {}
extension PictureInPictureDelegate: @preconcurrency AVPictureInPictureControllerDelegate {}
#endif
