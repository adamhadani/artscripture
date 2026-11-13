import Foundation
import Testing

@testable import AudioDecode

private func fixture(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // AudioDecodeTests
        .deletingLastPathComponent()  // Tests
        .appendingPathComponent("Fixtures")
        .appendingPathComponent(name)
}

/// More decodes at once than the Swift concurrency pool has threads.
///
/// `copyNextSampleBuffer()` blocks, and while the decoder ran its read loop on
/// the pool, as many concurrent decodes as the pool has threads — 12 on a
/// 12-core Mac — waited forever at 0% CPU; eleven finished in 0.15 s. That is
/// what hung `swift test` whenever it ran the decode suites in parallel.
///
/// **A regression here hangs rather than fails**, and this test is what makes
/// it hang under `--no-parallel` too, which is how CI runs — without it, CI
/// would never see the regression, and only a local parallel `make check`
/// would, as a run that never ends. Twice the core count clears the pool's
/// width on any machine.
@Test func moreConcurrentDecodesThanThePoolHasThreadsAllFinish() async throws {
    let count = ProcessInfo.processInfo.activeProcessorCount * 2
    let finished = try await withThrowingTaskGroup(of: Int.self) { group in
        for _ in 0..<count {
            group.addTask {
                _ = try await AudioFileDecoder.decode(url: fixture("sine.flac"))
                return 1
            }
        }
        return try await group.reduce(0, +)
    }
    #expect(finished == count)
}

/// A decode whose task is cancelled stops and says so, rather than reading to
/// the end. The read loop runs on a queue of its own, where `Task.isCancelled`
/// is always false — there is no current task — so cancellation has to be
/// carried across to it explicitly. Cancelled before it starts, so the outcome
/// does not depend on how fast a short fixture decodes.
@Test func aCancelledDecodeStopsAndSaysSo() async {
    let decode = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await AudioFileDecoder.decode(url: fixture("sine.flac"))
    }
    await #expect(throws: DecodeError.cancelled) {
        _ = try await decode.value
    }
}
