import ArtscribeKit
import AudioDecode
import Foundation
import Synchronization
import Video
import Waveform

/// A decoded file and everything derived from it that the viewer needs.
///
/// `DecodedAudio` hands out raw pointers into its storage, so this value has to
/// stay alive for as long as anything draws from it — the model holds it.
struct LoadedTrack: Sendable {
    let audio: DecodedAudio
    let pyramid: PeakPyramid
    /// The file's picture, when it has one. `nil` for audio — and for a movie
    /// whose picture could not even be probed, which is then simply its sound.
    var picture: LoadedPicture?
}

/// A video file's picture, opened alongside its sound.
///
/// `source` is `nil` exactly when `failure` is not: the file has a picture,
/// and this machine cannot decode it. The sound plays regardless, and the
/// panel says why it is empty rather than sitting black.
struct LoadedPicture: Sendable {
    let info: VideoTrackInfo
    let source: VideoFrameSource?
    let failure: String?
}

/// Turns a file URL into a `LoadedTrack`, off the main actor.
enum TrackLoader {

    /// `nonisolated` so it never adopts the caller's actor: decoding a
    /// ten-minute file on the main actor would freeze the window for seconds.
    ///
    /// `onPhaseChange` fires once, between decode finishing and the pyramid
    /// build starting — the one phase transition this function can see that
    /// the progress callback cannot, since `PeakPyramid.build` reports no
    /// progress of its own.
    nonisolated static func load(
        url: URL, reporter: ProgressReporter,
        onPhaseChange: @escaping @Sendable (ViewerModel.LoadPhase) -> Void
    ) async throws -> LoadedTrack {
        let audio = try await AudioFileDecoder.decode(url: url, progress: reporter.callback)
        try Task.checkCancellation()
        onPhaseChange(.buildingWaveform)
        let pyramid = PeakPyramid.build(audio)
        // After the sound, not beside it: the probe is milliseconds, and a file
        // whose sound cannot be decoded has no use for its picture.
        let picture = await loadPicture(url: url)
        try Task.checkCancellation()
        return LoadedTrack(audio: audio, pyramid: pyramid, picture: picture)
    }

    /// The picture's facts and a decoder for it, or `nil` for a file with no
    /// picture. Never throws: a picture that fails must not cost the sound.
    nonisolated static func loadPicture(url: URL) async -> LoadedPicture? {
        guard let info = try? await VideoTrackInfo.probe(url: url) else { return nil }
        do {
            let source = try await VideoFrameSource.open(url: url, info: info)
            return LoadedPicture(info: info, source: source, failure: nil)
        } catch {
            return LoadedPicture(info: info, source: nil, failure: message(for: error))
        }
    }

    /// The text the inline banner shows. `DecodeError` supplies a real reason;
    /// anything else at least gets its own description rather than a shrug.
    nonisolated static func message(for error: any Error) -> String {
        (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

/// Bridges the decoder's `@Sendable` progress callback onto the main actor
/// without spawning a hop per decoded chunk: only whole-percent changes are
/// forwarded, which is all the progress bar can show anyway.
final class ProgressReporter: Sendable {
    private let lastPercent = Mutex<Int>(-1)
    private let deliver: @Sendable (Double) -> Void

    init(deliver: @escaping @Sendable (Double) -> Void) {
        self.deliver = deliver
    }

    var callback: @Sendable (Double) -> Void {
        { [self] value in
            let percent = Int((value * 100).rounded())
            let shouldDeliver = lastPercent.withLock { stored -> Bool in
                guard percent != stored else { return false }
                stored = percent
                return true
            }
            if shouldDeliver { deliver(value) }
        }
    }
}
