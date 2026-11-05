import ArtscribeKit
import Foundation
import Observation
import Video

/// The open file's picture, as the views see it.
///
/// A child `@Observable`, like `CueMarkers`: the panel reads it, and nothing
/// that reads the waveform re-renders when it changes.
@MainActor
@Observable
public final class VideoState {
    public let info: VideoTrackInfo
    /// Why the picture cannot be shown, when the file has one this machine
    /// cannot decode. The sound plays regardless.
    public internal(set) var failure: String?
    /// What draws the picture; `nil` exactly when `failure` is set. Not
    /// observed: it is driven from the clock, never from a `body`, and a view
    /// that needs it reads it from the `VideoState` it was given.
    @ObservationIgnored public let presenter: VideoPresenter?

    init(info: VideoTrackInfo, failure: String?, presenter: VideoPresenter?) {
        self.info = info
        self.failure = failure
        self.presenter = presenter
    }
}

extension ViewerModel {
    public var hasVideo: Bool { video != nil }
    public var videoPresenter: VideoPresenter? { video?.presenter }

    /// Where the sound is, in the picture's terms: the audible playhead in
    /// seconds, and the loop only while it is *active* — a range drawn with
    /// looping off is not what plays next.
    var videoSnapshot: PlaybackSnapshot {
        let rate = sampleRate
        guard rate > 0 else {
            return PlaybackSnapshot(position: 0, isPlaying: false, speed: speed.ratio, loop: nil)
        }
        let loopSeconds: Range<Double>? =
            loop.isActive
            ? Double(loop.range.start) / rate..<Double(loop.range.start + loop.range.count) / rate
            : nil
        return PlaybackSnapshot(
            position: Double(playhead) / rate, isPlaying: isPlaying, speed: speed.ratio,
            loop: loopSeconds)
    }

    /// Installs the picture `TrackLoader` found, replacing any before it.
    func adoptPicture(_ picture: LoadedPicture?) {
        closePicture()
        guard let picture else { return }
        video = VideoState(
            info: picture.info, failure: picture.failure,
            presenter: picture.source.map { VideoPresenter(source: $0) })
    }

    /// Shuts the decoder, so no frame of this file can reach the next one's
    /// panel, and takes the panel away.
    func closePicture() {
        video?.presenter?.close()
        if video != nil { video = nil }
    }

    /// One tick of the picture: the frame for where the sound is now.
    func driveVideo() {
        videoPresenter?.update(videoSnapshot)
    }
}
