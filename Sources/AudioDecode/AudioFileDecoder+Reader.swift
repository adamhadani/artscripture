import AVFoundation
import Foundation
import Synchronization

extension AudioFileDecoder {

    /// Everything the read loop needs, handed to its queue in one piece.
    ///
    /// `@unchecked` for one field: `AVAssetTrack` is not marked `Sendable`. It is
    /// handed over, not shared — once its properties are loaded the decoding task
    /// never touches it again, and the queue only builds the reader's output
    /// from it.
    struct ReadRequest: @unchecked Sendable {
        let asset: AVURLAsset
        let track: AVAssetTrack
        let format: StreamFormat
        let storage: AudioStorage
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
    /// reader on its own queue, never from another thread mid-read.
    /// `DecodeConcurrencyTests` holds both halves.
    static func readOffThePool(_ request: ReadRequest) async throws -> Int {
        let cancellation = CancellationFlag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue(label: "com.artscribe.AudioDecode.read", qos: .userInitiated).async {
                    do {
                        let reader = try makeReader(for: request)
                        continuation.resume(
                            returning: try readAllSamples(
                                using: reader, for: request, cancellation: cancellation))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.raise()
        }
    }

    /// A task's cancellation, readable from a thread that has no task.
    final class CancellationFlag: Sendable {
        private let raised = Atomic<Bool>(false)
        func raise() { raised.store(true, ordering: .relaxed) }
        var isRaised: Bool { raised.load(ordering: .relaxed) }
    }

    private static func makeReader(
        for request: ReadRequest
    ) throws -> (reader: AVAssetReader, output: AVAssetReaderTrackOutput) {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: request.asset) } catch {
            throw DecodeError.unreadable(error.localizedDescription)
        }

        let output = AVAssetReaderTrackOutput(track: request.track, outputSettings: settings)
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
}
