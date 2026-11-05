import AVFoundation
import CoreGraphics
import Foundation

/// What a file's picture is, read once before anything is decoded.
///
/// `nil` from `probe` means the file has no picture to show — an audio file, or
/// a movie whose only video track is disabled — and is the one answer that
/// leaves the window exactly as it is for audio today.
public struct VideoTrackInfo: Equatable, Sendable {
    /// The coded size, before the track's transform.
    public let naturalSize: CGSize
    /// The track's `preferredTransform`. A phone held upright records a
    /// landscape picture and this says to turn it, which `AVAssetReader` does
    /// *not* do for us.
    public let transform: CGAffineTransform
    /// The size the picture is meant to be seen at: `naturalSize` turned by
    /// `transform`, always positive. What the panel lays out against.
    public let displaySize: CGSize
    /// Nominal frames per second, never zero (a track that does not say gets 30).
    public let frameRate: Double
    /// Where the picture starts on the file's timeline, in seconds.
    public let start: Double
    /// How long the picture runs, in seconds. Need not equal the sound's length.
    public let duration: Double

    public var frameInterval: Double { 1 / frameRate }
    public var end: Double { start + duration }
    public var isRotated: Bool { transform != .identity }

    /// What a track that does not state its frame rate is taken to have.
    static let fallbackFrameRate = 30.0

    init(
        naturalSize: CGSize, transform: CGAffineTransform = .identity,
        frameRate: Double, start: Double = 0, duration: Double
    ) {
        self.naturalSize = naturalSize
        self.transform = transform
        let turned = CGRect(origin: .zero, size: naturalSize).applying(transform)
        self.displaySize = CGSize(width: abs(turned.width), height: abs(turned.height))
        self.frameRate = frameRate > 0 ? frameRate : Self.fallbackFrameRate
        self.start = start
        self.duration = duration
    }

    /// The first *enabled* video track's facts, or `nil` when there is none.
    ///
    /// Enabled, not first, for the same reason the audio decoder takes the
    /// first enabled audio track: a file can carry alternates, and the flag is
    /// how it says which one a player should use.
    public static func probe(url: URL) async throws -> VideoTrackInfo? {
        guard let track = try await firstEnabledVideoTrack(of: AVURLAsset(url: url)) else {
            return nil
        }
        let (size, transform, rate, range) = try await track.load(
            .naturalSize, .preferredTransform, .nominalFrameRate, .timeRange)
        return VideoTrackInfo(
            naturalSize: size, transform: transform, frameRate: Double(rate),
            start: range.start.seconds, duration: range.duration.seconds)
    }

    /// The one rule for which picture a file has; the probe and the decoder
    /// both ask here, so they cannot disagree about it.
    static func firstEnabledVideoTrack(of asset: AVAsset) async throws -> AVAssetTrack? {
        for track in try await asset.loadTracks(withMediaType: .video)
        where try await track.load(.isEnabled) {
            return track
        }
        return nil
    }
}
