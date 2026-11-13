import AVFoundation
import CoreMedia
import Foundation
import Synchronization

extension AudioFileDecoder {

    /// What the read loop needs, handed to its queue. Checked `Sendable`: the
    /// one value that is not — the track — crosses separately, by name.
    struct ReadRequest: Sendable {
        let asset: AVURLAsset
        let format: StreamFormat
        let estimatedFrames: Int
        let progress: (@Sendable (Double) -> Void)?
    }

    /// Runs the read loop on a queue of its own and suspends until it is done.
    ///
    /// `copyNextSampleBuffer()` blocks until the reader has decoded the next
    /// buffer, and the loop calls it until the file ends: a whole decode spent
    /// blocked. Swift concurrency assumes a thread in its pool never waits like
    /// that, and the assumption is load-bearing here. With as many decodes on
    /// the pool as it has threads — 12 on a 12-core Mac — every one of them
    /// waited forever, at 0% CPU, for a buffer that never came; eleven finished
    /// in 0.15 s, and with a queue per decode forty-eight finished in 0.32 s.
    /// Measured 2026-11-13 on macOS 27.2. It is what hung `swift test` whenever
    /// it ran the decode suites in parallel, and nothing stopped an app or a
    /// CLI that decoded enough files at once from doing the same. `Video`'s
    /// reader has always kept its blocking reads on a queue for this reason.
    ///
    /// The reader is made on that queue and never leaves it. `Task.isCancelled`
    /// reads false there — there is no current task — so cancellation crosses
    /// as a flag the loop checks between buffers, and the loop then cancels the
    /// reader on its own queue, never from another thread mid-read. GCD cannot
    /// see a task's priority either, so the queue is given the caller's.
    /// `DecodeConcurrencyTests` holds all three.
    static func readOffThePool(
        _ request: ReadRequest, track: AVAssetTrack
    ) async throws -> (storage: AudioStorage, written: Int) {
        let cancellation = CancellationFlag()
        // Handed over, not shared: once its properties are loaded the decoding
        // task never touches the track again, and the queue only builds the
        // reader's output from it. `AVAssetTrack` is not marked `Sendable`.
        nonisolated(unsafe) let track = track
        let queue = DispatchQueue(
            label: "com.artscribe.AudioDecode.read", qos: queueQoS(for: Task.currentPriority))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    do {
                        continuation.resume(
                            returning: try read(request, track: track, cancellation: cancellation))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.raise()
        }
    }

    /// The queue's QoS for a caller at `priority`. On Apple platforms a task
    /// priority's raw value *is* a `qos_class_t`; anything that does not map —
    /// or maps to "unspecified" — gets what the app's loads ask for.
    static func queueQoS(for priority: TaskPriority) -> DispatchQoS {
        let qosClass = DispatchQoS.QoSClass(
            rawValue: qos_class_t(rawValue: UInt32(priority.rawValue)))
        guard let qosClass, qosClass != .unspecified else { return .userInitiated }
        return DispatchQoS(qosClass: qosClass, relativePriority: 0)
    }

    /// A task's cancellation, readable from a thread that has no task.
    final class CancellationFlag: Sendable {
        private let raised = Atomic<Bool>(false)
        func raise() { raised.store(true, ordering: .relaxed) }
        var isRaised: Bool { raised.load(ordering: .relaxed) }
    }

    /// Everything that happens on the read queue, in the order that matters.
    private static func read(
        _ request: ReadRequest, track: AVAssetTrack, cancellation: CancellationFlag
    ) throws -> (storage: AudioStorage, written: Int) {
        // Superseded before its turn came — a second file opened at once:
        // nothing opened, nothing allocated.
        guard !cancellation.isRaised else { throw DecodeError.cancelled }
        let reader = try makeReader(asset: request.asset, track: track)
        // Only once the reader has accepted the file. The storage is zero-filled
        // to the file's whole length up front, so a file the reader refuses —
        // protected, corrupt — must fail before it exists: a 70-minute stereo
        // file is 1.6 GB, which on a phone is a jetsam kill, not an error banner.
        let storage = AudioStorage(
            channels: request.format.channels, capacityFrames: max(request.estimatedFrames, 1))
        let written = try readAllSamples(
            using: reader, into: storage, for: request, cancellation: cancellation)
        return (storage, written)
    }

    private static func makeReader(
        asset: AVURLAsset, track: AVAssetTrack
    ) throws -> (reader: AVAssetReader, output: AVAssetReaderTrackOutput) {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch {
            throw DecodeError.unreadable(error.localizedDescription)
        }

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw DecodeError.unsupportedFormat("Reader rejected Float32 output.")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw DecodeError.unreadable(
                reader.error?.localizedDescription ?? "Reader failed to start.")
        }
        return (reader, output)
    }

    /// The read loop. It blocks for the whole decode, so it is `private` to this
    /// file: the only way in is `readOffThePool`, and the compiler holds that.
    private static func readAllSamples(
        using reader: (reader: AVAssetReader, output: AVAssetReaderTrackOutput),
        into storage: AudioStorage,
        for request: ReadRequest,
        cancellation: CancellationFlag
    ) throws -> Int {
        let (format, estimatedFrames, progress) =
            (request.format, request.estimatedFrames, request.progress)
        let channels = format.channels
        var written = 0
        var emptyBufferCount = 0
        let scratch = SampleScratch()
        let frameSize = MemoryLayout<Float>.size * channels

        while let sample = reader.output.copyNextSampleBuffer() {
            defer { CMSampleBufferInvalidate(sample) }
            guard let block = CMSampleBufferGetDataBuffer(sample) else {
                // A `CMSampleBuffer` with no data buffer carries no audio payload at
                // all -- some containers emit these as markers around a mid-stream
                // format-description change. There is nothing to lose by skipping
                // one, but a *run* of them would be a symptom of something else
                // going wrong, so this is counted and logged rather than silently
                // discarded.
                emptyBufferCount += 1
                continue
            }

            let decoded = CMSampleBufferGetFormatDescription(sample).flatMap {
                CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee
            }
            if let decoded {
                try verifyDecodedLayout(decoded, sampleRate: format.sampleRate, channels: channels)
            }

            let byteCount = try copyBytes(from: block, into: scratch)
            guard byteCount > 0 else {
                // A genuinely zero-length block buffer: same reasoning as above,
                // no payload existed to lose.
                emptyBufferCount += 1
                continue
            }
            // LPCM sample buffers from AVFoundation are always frame-aligned; a
            // partial frame here would mean real decoded bytes exist that don't
            // fit our layout assumptions. Never silently drop them -- throw
            // instead of truncating via integer division.
            let frames = try frameCount(inByteCount: byteCount, frameSize: frameSize)

            // Never silently truncate: if the file turns out longer than the
            // duration-based estimate predicted, grow rather than stop early.
            if written + frames > storage.capacityFrames {
                storage.grow(toAtLeast: written + frames, preserving: written)
            }
            deinterleave(scratch, frames: frames, channels: channels, into: storage, at: written)
            written += frames

            if let progress, estimatedFrames > 0 {
                progress(min(1.0, Double(written) / Double(estimatedFrames)))
            }
            if cancellation.isRaised {
                reader.reader.cancelReading()
                throw DecodeError.cancelled
            }
        }

        if reader.reader.status == .failed {
            throw DecodeError.unreadable(
                reader.reader.error?.localizedDescription ?? "Decode failed.")
        }
        if emptyBufferCount > 0 {
            logger.notice(
                "Skipped \(emptyBufferCount) empty sample buffer(s) with no audio payload.")
        }
        return written
    }
}
