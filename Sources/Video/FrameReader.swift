import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

/// One `AVAssetReader` reading forward from `origin`. Confined to the source's
/// queue.
final class Reader {
    enum Next {
        case frame(DecodedFrame)
        case end
        case failed(String)
    }

    let origin: Double
    /// The end of the latest frame read: where this reader's picture runs out.
    private(set) var cursor: Double
    private(set) var isFinished = false
    /// Frames this reader has produced. A reader that ends having produced
    /// none, inside the picture, has met a file it cannot read there.
    private(set) var framesRead = 0
    private let reader: AVAssetReader
    private let output: AVAssetReaderOutput

    /// Decoded straight to the format the display layer takes without a copy:
    /// bi-planar 4:2:0 in video range, IOSurface-backed.
    private static var settings: [String: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ]
    }

    init(
        asset: AVAsset, track: AVAssetTrack, composition: AVVideoComposition?,
        range: Range<Double>
    ) throws {
        reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: range.lowerBound, preferredTimescale: 90_000),
            end: CMTime(seconds: range.upperBound, preferredTimescale: 90_000))
        if let composition {
            let output = AVAssetReaderVideoCompositionOutput(
                videoTracks: [track], videoSettings: Self.settings)
            output.videoComposition = composition
            self.output = output
        } else {
            self.output = AVAssetReaderTrackOutput(track: track, outputSettings: Self.settings)
        }
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else {
            throw VideoSourceError.couldNotStart(
                reader.error?.localizedDescription ?? "The video could not be read.")
        }
        origin = range.lowerBound
        cursor = range.lowerBound
    }

    /// Whether this reader's next frame is the one that starts at `time`.
    func isAt(_ time: Double, interval: Double) -> Bool {
        !isFinished && abs(cursor - time) < interval / 2
    }

    /// Whether reading forward reaches `time` within `catchUp` seconds:
    /// readers only go forward, so a time behind the cursor never qualifies.
    func canReach(_ time: Double, interval: Double, within catchUp: Double) -> Bool {
        !isFinished && cursor <= time + interval / 2 && time - cursor <= catchUp
    }

    func next(fallbackDuration: Double) -> Next {
        guard let sample = output.copyNextSampleBuffer() else {
            isFinished = true
            if reader.status == .failed {
                return .failed(
                    reader.error?.localizedDescription ?? "The video could not be decoded.")
            }
            return .end
        }
        guard let image = CMSampleBufferGetImageBuffer(sample) else {
            return next(fallbackDuration: fallbackDuration)
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        let stated = CMSampleBufferGetDuration(sample)
        let duration = stated.isValid && stated.seconds > 0 ? stated.seconds : fallbackDuration
        cursor = max(cursor, pts + duration)
        framesRead += 1
        return .frame(DecodedFrame(pts: pts, duration: duration, pixelBuffer: image))
    }
}
