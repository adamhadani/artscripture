import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import Synchronization

/// One decoded picture and the stretch of the timeline it is shown for.
///
/// `@unchecked Sendable` because `CVPixelBuffer` is not marked, and a decoded
/// buffer is never written again: the decoder hands it over and lets go.
public struct DecodedFrame: @unchecked Sendable {
    public let pts: Double
    public let duration: Double
    public let pixelBuffer: CVPixelBuffer

    public init(pts: Double, duration: Double, pixelBuffer: CVPixelBuffer) {
        self.pts = pts
        self.duration = duration
        self.pixelBuffer = pixelBuffer
    }
}

/// Decodes the picture a `FramePlan` asks for, ahead of when it is shown.
///
/// One serial queue and at most two `AVAssetReader`s:
///
/// * **main** follows the position, reading forward as the window slides.
/// * **head** reads the loop's first stretch and then *parks*, its cursor at
///   the end of that stretch. At the wrap the main window lands exactly there,
///   and the head reader simply **becomes** the main reader and carries on —
///   no new reader, and so no decode forward from a keyframe that may be
///   seconds before the loop's start. A fresh head is then primed, with a whole
///   repetition's time to do it.
///
/// Any other jump (a click, a nudge, a seek) starts a new reader where the
/// picture is missing. Requests coalesce: the decoder works on the latest plan
/// and abandons one that has been replaced, so a scrub decodes where it ends up
/// rather than everywhere it passed through.
public final class VideoFrameSource: @unchecked Sendable {
    // `@unchecked`: everything mutable is either in `shared`, behind its lock,
    // or one of the two readers, which only `queue` ever touches.

    struct Counters: Equatable, Sendable {
        var framesDecoded = 0
        var readersCreated = 0
        var handoffs = 0
        var cached = 0
    }

    private struct Shared {
        var cache = FrameCache<CVPixelBuffer>()
        var pending: FramePlan?
        var isDraining = false
        var isClosed = false
        var failure: String?
        var counters = Counters()
    }

    public let info: VideoTrackInfo
    private let asset: AVURLAsset
    private let track: AVAssetTrack
    /// Only for a turned track: renders the frames upright, so nothing above
    /// this has to know a phone was held sideways.
    private let composition: AVVideoComposition?
    private let frameBudget: Int
    private let shared = Mutex(Shared())
    private let queue = DispatchQueue(label: "com.artscribe.video.decode", qos: .userInitiated)

    // Confined to `queue`.
    private var main: Reader?
    private var head: Reader?

    private init(
        asset: AVURLAsset, track: AVAssetTrack, composition: AVVideoComposition?,
        info: VideoTrackInfo, frameBudget: Int
    ) {
        self.asset = asset
        self.track = track
        self.composition = composition
        self.info = info
        self.frameBudget = max(2, frameBudget)
    }

    /// The default budget: about 150 MB of 1080p frames, and far more than a
    /// plan at normal speeds asks for (a quarter-second each side at 60 fps is
    /// 30). The cap is for 2× on a 60 fps 4K clip, not for the common case.
    public static let defaultFrameBudget = 48

    public static func open(
        url: URL, info: VideoTrackInfo, frameBudget: Int = defaultFrameBudget
    ) async throws -> VideoFrameSource {
        let asset = AVURLAsset(url: url)
        guard let track = try await VideoTrackInfo.firstEnabledVideoTrack(of: asset) else {
            throw VideoSourceError.noPicture
        }
        let composition: AVVideoComposition? =
            info.isRotated
            ? try await AVVideoComposition.videoComposition(withPropertiesOf: asset)
            : nil
        return VideoFrameSource(
            asset: asset, track: track, composition: composition, info: info,
            frameBudget: frameBudget)
    }

    // MARK: - The caller's side

    /// Asks for `plan`'s frames. Returns at once; the newest plan wins.
    public func request(_ plan: FramePlan) {
        let schedule = shared.withLock { state -> Bool in
            guard !state.isClosed else { return false }
            state.pending = plan
            guard !state.isDraining else { return false }
            state.isDraining = true
            return true
        }
        if schedule { queue.async { self.drain() } }
    }

    /// The frame shown at `time`, if it has been decoded. The time is clamped
    /// into the picture, so the sound running past the picture's end holds its
    /// last frame.
    public func frame(at time: Double) -> DecodedFrame? {
        let clamped = min(max(time, info.start), info.end - info.frameInterval / 2)
        return shared.withLock { state in
            guard !state.isClosed, let entry = state.cache.entry(at: clamped) else { return nil }
            return DecodedFrame(
                pts: entry.pts, duration: entry.duration, pixelBuffer: entry.payload)
        }
    }

    /// Why the picture cannot be decoded, when it cannot. The sound is
    /// unaffected either way.
    public var failure: String? { shared.withLock { $0.failure } }

    /// Stops for good: frames already decoded are released and nothing more
    /// is answered, so a picture of this file can never reach the next one's
    /// panel.
    public func close() {
        shared.withLock { state in
            state.isClosed = true
            state.pending = nil
            state.cache.removeAll()
        }
        queue.async {
            self.main = nil
            self.head = nil
        }
    }

    /// Resolves once the decoder has caught up with every request made so far.
    public func idle() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }

    var counters: Counters {
        shared.withLock { state in
            var counters = state.counters
            counters.cached = state.cache.count
            return counters
        }
    }

    // MARK: - The decoder's side (on `queue`)

    private func drain() {
        while let plan = takePending() { work(on: plan) }
    }

    private func takePending() -> FramePlan? {
        let next = shared.withLock { state -> FramePlan? in
            guard !state.isClosed, let plan = state.pending else {
                state.isDraining = false
                return nil
            }
            state.pending = nil
            return plan
        }
        if next == nil, shared.withLock({ $0.isClosed }) {
            main = nil
            head = nil
        }
        return next
    }

    /// A newer plan has arrived, or the source has closed: stop this one.
    private var isSuperseded: Bool { shared.withLock { $0.pending != nil || $0.isClosed } }

    private func work(on plan: FramePlan) {
        shared.withLock { $0.cache.evict(outside: plan.all) }
        // What is on screen next comes first. A window after the loop's end is
        // the loop head's to provide, and it is decoded below.
        if let window = plan.main.first { fill(window) }
        guard !isSuperseded else { return }
        if let window = plan.loopHead {
            prime(window)
        } else {
            head = nil
        }
    }

    private func fill(_ window: Range<Double>) {
        guard let gap = firstGap(in: window) else { return }
        let reader: Reader
        if let main, main.isAt(gap, interval: info.frameInterval) {
            reader = main
        } else if let head, head.isAt(gap, interval: info.frameInterval) {
            // The wrap: the parked head reader is exactly where the picture
            // goes next.
            reader = head
            self.main = head
            self.head = nil
            shared.withLock { $0.counters.handoffs += 1 }
        } else if let fresh = makeReader(at: gap) {
            reader = fresh
            main = fresh
        } else {
            return
        }
        pull(reader, until: window.upperBound)
    }

    private func prime(_ window: Range<Double>) {
        let isForThisLoop = head.map {
            abs($0.origin - window.lowerBound) <= FrameCache<Int>.tolerance
        }
        if isForThisLoop != true { head = makeReader(at: window.lowerBound) }
        if let head { pull(head, until: window.upperBound) }
    }

    /// Where `window` stops being decoded, or `nil` when all of it is.
    private func firstGap(in window: Range<Double>) -> Double? {
        shared.withLock { state in
            guard let end = state.cache.coveredEnd(from: window.lowerBound) else {
                return window.lowerBound
            }
            return end >= window.upperBound - FrameCache<Int>.tolerance ? nil : end
        }
    }

    private func pull(_ reader: Reader, until end: Double) {
        while reader.cursor < end - FrameCache<Int>.tolerance, !reader.isFinished {
            guard !isSuperseded else { return }
            let full = shared.withLock { $0.cache.count >= frameBudget }
            guard !full else { return }
            switch reader.next(fallbackDuration: info.frameInterval) {
            case .frame(let frame):
                shared.withLock { state in
                    state.cache.insert(pts: frame.pts, duration: frame.duration, frame.pixelBuffer)
                    state.counters.framesDecoded += 1
                }
            case .end:
                return
            case .failed(let reason):
                shared.withLock { $0.failure = reason }
                return
            }
        }
    }

    private func makeReader(at time: Double) -> Reader? {
        let start = min(max(time, info.start), info.end - info.frameInterval / 2)
        do {
            let reader = try Reader(
                asset: asset, track: track, composition: composition,
                range: start..<info.end)
            shared.withLock { $0.counters.readersCreated += 1 }
            return reader
        } catch {
            shared.withLock { $0.failure = error.localizedDescription }
            return nil
        }
    }
}

public enum VideoSourceError: Error, Equatable {
    case noPicture
    case couldNotStart(String)
}

/// One `AVAssetReader` reading forward from `origin`. Confined to the source's
/// queue.
private final class Reader {
    enum Next {
        case frame(DecodedFrame)
        case end
        case failed(String)
    }

    let origin: Double
    /// The end of the latest frame read: where this reader's picture runs out.
    private(set) var cursor: Double
    private(set) var isFinished = false
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
        return .frame(DecodedFrame(pts: pts, duration: duration, pixelBuffer: image))
    }
}
