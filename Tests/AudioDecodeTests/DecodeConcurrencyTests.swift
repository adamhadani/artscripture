import Dispatch
import Foundation
import Synchronization
import Testing

@testable import AudioDecode

/// Ends the process, by name, unless disarmed in time.
///
/// A deadlocked concurrency pool cannot run Swift Testing's own `.timeLimit` —
/// its timer needs a pool thread too — and CI would sit to its 25-minute job
/// timeout with no test named. **A thread of its own, not a GCD timer:** with
/// the read loop put back on the pool, `DispatchQueue.global().asyncAfter`
/// never fired inside the deadlocked test process (sampled at 80 s), though it
/// does in a standalone one. A plain thread depends on neither.
private final class Watchdog: Sendable {
    private let disarmed = Atomic<Bool>(false)

    init(seconds: Double, _ message: String) {
        Thread.detachNewThread { [self] in
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                if disarmed.load(ordering: .acquiring) { return }
                Thread.sleep(forTimeInterval: 0.25)
            }
            fatalError(message)
        }
    }

    func disarm() { disarmed.store(true, ordering: .releasing) }
}

/// More decodes at once than the Swift concurrency pool has threads.
///
/// `copyNextSampleBuffer()` blocks, and while the decoder ran its read loop on
/// the pool, as many concurrent decodes as the pool has threads — 12 on a
/// 12-core Mac — waited forever at 0% CPU; eleven finished in 0.15 s. That is
/// what hung `swift test` whenever it ran the decode suites in parallel.
///
/// A regression deadlocks rather than fails, under `--no-parallel` too — which
/// is how CI runs, and why this test exists: without it only a local parallel
/// run would ever see one. The watchdog turns that deadlock into a crash that
/// names the cause. Twice the core count clears the pool's width anywhere.
@Test func moreConcurrentDecodesThanThePoolHasThreadsAllFinish() async throws {
    let count = ProcessInfo.processInfo.activeProcessorCount * 2
    let watchdog = Watchdog(
        seconds: 60,
        "\(count) concurrent decodes did not finish in 60 s: the read loop is blocking "
            + "the Swift concurrency pool again. See AudioFileDecoder+Reader.swift.")
    defer { watchdog.disarm() }

    let frameCounts = try await withThrowingTaskGroup(of: Int.self) { group in
        for _ in 0..<count {
            group.addTask {
                Int(try await AudioFileDecoder.decode(url: fixture("sine.flac")).frameCount)
            }
        }
        var counts: [Int] = []
        for try await frames in group { counts.append(frames) }
        return counts
    }
    #expect(frameCounts.count == count)
    #expect(
        Set(frameCounts).count == 1,
        "every concurrent decode reads the whole file: \(Set(frameCounts).sorted())")
}

/// A decode whose task is cancelled before it starts stops and says so,
/// without opening a reader. `withTaskCancellationHandler` runs the handler
/// at once for a task that is already cancelled, so this is the cheap half.
@Test func aDecodeCancelledBeforeItStartsStopsAndSaysSo() async {
    let decode = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await AudioFileDecoder.decode(url: fixture("sine.flac"))
    }
    await #expect(throws: DecodeError.cancelled) {
        _ = try await decode.value
    }
}

/// The app's case: the user opens a second file while the first is decoding,
/// and `loadTask?.cancel()` arrives with the read loop already running on its
/// queue. Off the pool `Task.isCancelled` is always false, so this is the half
/// that proves the cancellation actually crosses to the loop.
///
/// Deterministic, not a race: the first progress report parks the read queue
/// until the task has been cancelled. Blocking there is safe because that
/// queue is not the pool — the property under test.
@Test func aDecodeCancelledMidReadStopsAndSaysSo() async {
    let firstReport = AsyncStream.makeStream(of: Void.self)
    let cancelled = DispatchSemaphore(value: 0)
    let isFirst = Atomic<Bool>(true)
    let decode = Task {
        try await AudioFileDecoder.decode(url: fixture("sine.flac")) { _ in
            guard isFirst.exchange(false, ordering: .relaxed) else { return }
            firstReport.continuation.yield()
            cancelled.wait()
        }
    }
    for await _ in firstReport.stream { break }
    decode.cancel()
    cancelled.signal()

    await #expect(throws: DecodeError.cancelled) {
        _ = try await decode.value
    }
}

/// The read queue runs at its caller's priority. A task priority's raw value is
/// a `qos_class_t` on Apple platforms, so the mapping is exact for every case.
@Test func theReadQueueRunsAtItsCallersPriority() {
    let expected: [(TaskPriority, DispatchQoS.QoSClass)] = [
        (.userInitiated, .userInitiated), (.high, .userInitiated),
        (.medium, .default), (.utility, .utility), (.low, .utility),
        (.background, .background)
    ]
    for (priority, qosClass) in expected {
        #expect(AudioFileDecoder.queueQoS(for: priority).qosClass == qosClass, "\(priority)")
    }
}
