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
/// and abandons one that has been replaced — but **not before it has answered
/// it**, with the frame for the position it was made at (`latestAnswer`).
///
/// That last part is what makes a scrub show frames while the finger moves.
/// Until 2026-11 a replaced plan was dropped between any two frames, and
/// during a drag a new one arrives every tick while a seek into a long GOP
/// takes several: nothing finished until the finger stopped, and the picture
/// froze for the whole drag — "currently only happens when I stop dragging",
/// from an iPhone. It is Apple's "chase time" (Technical Q&A QA1820, for
/// `AVPlayer.seek`): let the seek in flight complete and show it, keep only
/// the newest target, and go there next. Frames then change at the rate the
/// decoder manages, never at the rate the finger moves.
public final class VideoFrameSource: @unchecked Sendable {
    // `@unchecked`: everything mutable is either in `shared`, behind its lock,
    // or one of the two readers, which only `queue` ever touches.

    struct Counters: Equatable, Sendable {
        var framesDecoded = 0
        var readersCreated = 0
        var readerAttempts = 0
        var handoffs = 0
        var cached = 0
    }

    /// The frame a plan was answered with, numbered so the presenter can tell
    /// a new answer from one it has already shown.
    public struct Answer: Sendable {
        public let serial: Int
        public let frame: DecodedFrame
    }

    private struct Shared {
        var cache = FrameCache<CVPixelBuffer>()
        var answer: Answer?
        /// Never reset, so an answer's serial is never reused — not even
        /// across a `release()`, which a presenter that outlives it would not
        /// notice.
        var answersGiven = 0
        /// Moved on by `release()` and `close()`: a decode still in flight
        /// from before carries the old one and gives no answer.
        var generation = 0
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
    private let budget: Int
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
        self.budget = max(2, frameBudget)
    }

    /// How much decoded picture to keep, in bytes. A count would not do: a
    /// 4K frame is four times a 1080p one, and 48 of them are about 600 MB —
    /// which iOS ends an app for, in the background with Picture in Picture
    /// above all.
    public static let memoryBudget = 128_000_000.0

    /// Frames that fit `memoryBudget` at this picture's size (4:2:0, a byte
    /// and a half a pixel), between 8 — enough to play from at all — and 48.
    public static func frameBudget(for info: VideoTrackInfo) -> Int {
        let bytes = max(1, info.displaySize.width * info.displaySize.height * 1.5)
        return min(48, max(8, Int(memoryBudget / Double(bytes))))
    }

    public static func open(
        url: URL, info: VideoTrackInfo, frameBudget: Int? = nil
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
            frameBudget: frameBudget ?? Self.frameBudget(for: info))
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

    /// The frame for the position of the last plan the decoder finished
    /// answering — kept even after a newer plan evicts it from the cache.
    ///
    /// What a scrub shows between exact frames: by the time a frame is decoded
    /// the finger has moved on and `frame(at:)` misses, but this is still the
    /// newest picture of where the finger *was*, which is the point of seeing
    /// frames while scrubbing at all.
    public var latestAnswer: Answer? { shared.withLock { $0.answer } }

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
            state.answer = nil
            state.generation += 1
        }
        queue.async {
            self.main = nil
            self.head = nil
        }
    }

    /// Lets every decoded frame go, and the readers with them: nothing is
    /// showing the picture. The next request starts afresh.
    public func release() {
        shared.withLock { state in
            state.pending = nil
            state.cache.removeAll()
            state.answer = nil
            state.generation += 1
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
        // A picture that failed stays failed: the reason is on screen, and a
        // new reader per plan would fail the same way 60 times a second.
        guard shared.withLock({ $0.failure == nil }) else { return }
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
        if let main, main.canReach(gap, interval: info.frameInterval, within: Self.catchUp) {
            // Behind is fine: reading forward costs a frame's decode per frame,
            // where a new reader decodes from the keyframe — and on a long GOP,
            // replacing a reader that is behind on every tick never catches up.
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
        pull(reader, from: window.lowerBound, until: window.upperBound, answering: true)
    }

    /// How far behind the main reader may be and still be read forward rather
    /// than replaced: about a GOP, the cost of the replacement.
    static let catchUp = 2.0

    private func prime(_ window: Range<Double>) {
        let isForThisLoop = head.map {
            abs($0.origin - window.lowerBound) <= FrameCache<Int>.tolerance
        }
        if isForThisLoop != true { head = makeReader(at: window.lowerBound) }
        if let head { pull(head, from: window.lowerBound, until: window.upperBound) }
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

    /// Reads `reader` forward until it passes `end`. Frames that finish
    /// before `start` — read on the way, catching up — are not kept: they
    /// would only fill the budget with pictures nobody will see.
    ///
    /// `answering`: this is the main window, and a newer plan does not stop it
    /// until the frame covering `start` has been decoded and recorded as the
    /// answer (see the type's note on scrubbing). Closing still stops it at
    /// once.
    private func pull(
        _ reader: Reader, from start: Double, until end: Double, answering: Bool = false
    ) {
        var owesAnswer = answering
        let generation = shared.withLock { $0.generation }
        while reader.cursor < end - FrameCache<Int>.tolerance, !reader.isFinished {
            let stop = shared.withLock { $0.isClosed || ($0.pending != nil && !owesAnswer) }
            guard !stop else { return }
            let full = shared.withLock { $0.cache.count >= budget }
            guard !full else { return }
            switch reader.next(fallbackDuration: info.frameInterval) {
            case .frame(let frame):
                guard frame.pts + frame.duration > start + FrameCache<Int>.tolerance else {
                    shared.withLock { $0.counters.framesDecoded += 1 }
                    continue
                }
                let answers = owesAnswer && frame.pts <= start + FrameCache<Int>.tolerance
                shared.withLock { state in
                    state.cache.insert(pts: frame.pts, duration: frame.duration, frame.pixelBuffer)
                    state.counters.framesDecoded += 1
                    if answers && state.generation == generation {
                        state.answersGiven += 1
                        state.answer = Answer(serial: state.answersGiven, frame: frame)
                    }
                }
                // The first frame kept is the one the plan was waiting for, or
                // the gap after frames already cached: either way it is owed no
                // longer, and a newer plan may take over from here.
                owesAnswer = false
            case .end:
                // Ending without a single frame, inside the picture, is not the
                // end of the file but a stretch that cannot be read — a damaged
                // or incomplete file. iOS reports it this way rather than as a
                // failure; without this every plan would open another reader
                // that ends the same way.
                if reader.framesRead == 0, reader.origin < info.end - info.frameInterval {
                    shared.withLock {
                        $0.failure = "The file may be damaged or incomplete from here on."
                    }
                }
                return
            case .failed(let reason):
                shared.withLock { $0.failure = reason }
                return
            }
        }
    }

    private func makeReader(at time: Double) -> Reader? {
        let start = min(max(time, info.start), info.end - info.frameInterval / 2)
        shared.withLock { $0.counters.readerAttempts += 1 }
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
