import ArtscribeKit
import AudioDecode
import Foundation
import Testing
import Waveform

@testable import ArtscribeUI

/// **Stop stops.** The user, from 1.4: *"clicking stop on Practice … doesn't
/// actually stop playback (just stops the 'practice' iterations)"*. Start
/// plays, so the Stop a person presses pauses (`stopPractice`); the app's own
/// stops (`stopRamp`) end the ramp and leave the transport alone.
/// `transport.request(true)` stands in for the playing a real output would
/// confirm — a unit test has no graph; the acceptance run checks the real one.
@MainActor
@Suite("Practice stop")
struct PracticeStopTests {

    private static let sampleRate: Double = 44100
    private static let totalFrames: FrameIndex = 441_000  // 10 s

    /// A four-second loop, three seconds in — a realistic practice region, and
    /// long enough that half of it is unambiguous.
    private static let loopStart: FrameIndex = 132_300
    private static let loopCount: FrameIndex = 176_400

    private func makeModel() -> ViewerModel {
        let storage = AudioStorage(channels: 1, capacityFrames: Int(Self.totalFrames))
        let audio = DecodedAudio(
            channels: 1, sampleRate: Self.sampleRate, frameCount: Self.totalFrames,
            storage: storage)
        let model = ViewerModel()
        model.loadForTesting(audio: audio, pyramid: PeakPyramid.build(audio), widthPixels: 1000)
        return model
    }

    /// A model with an enabled loop, ready to ramp.
    private func makeLoopedModel() -> ViewerModel {
        let model = makeModel()
        model.seek(to: Self.loopStart)
        model.setLoopIn()
        model.seek(to: Self.loopStart + Self.loopCount)
        model.setLoopOut()
        return model
    }

    /// Plays one whole repetition, sampled `polls` times, and reports whether a
    /// wrap was seen. The final position is just inside the loop's in point,
    /// which is where the engine puts the playhead when it goes round.
    @discardableResult
    private func playOneRepetition(_ model: ViewerModel, polls: Int = 12) -> Bool {
        let start = model.loop.range.start
        let span = model.loop.range.count - 1
        for step in 1...polls {
            model.notePlayhead(start + span * FrameIndex(step) / FrameIndex(polls))
        }
        let before = model.ramp.index
        model.notePlayhead(start + 512)
        return model.ramp.index != before || model.ramp.phase == .complete
    }

    /// The user, from 1.4: *"clicking stop on Practice … doesn't actually stop
    /// playback (just stops the 'practice' iterations)"*. Start plays, so the
    /// Stop a person presses pauses. `transport.request(true)` stands in for
    /// the playing a real output would confirm; a unit test has no graph.
    @Test("Stop, as pressed in the header, ends a running ramp and pauses")
    func pressedStopPauses() {
        let model = makeLoopedModel()
        model.setRampSchedule(RampSchedule(startRatio: 0.5, endRatio: 1.0, repetitions: 5))
        model.startRamp()
        model.transport.request(true, now: 0)
        playOneRepetition(model)
        #expect(model.speed.ratio == 0.625)

        model.stopPractice()
        #expect(model.ramp.isIdle)
        #expect(!model.isPlaying, "the track played on after Stop")
        #expect(model.speed.ratio == 0.625, "Stop snapped the speed back")
    }

    @Test("the Practice panel's Stop, the menu item and ⌥R pause too")
    func toggledStopPauses() {
        let model = makeLoopedModel()
        model.setRampSchedule(RampSchedule(startRatio: 0.5, endRatio: 1.0, repetitions: 5))
        model.toggleRamp()
        model.transport.request(true, now: 0)
        model.toggleRamp()
        #expect(model.ramp.isIdle)
        #expect(!model.isPlaying)
    }

    /// A finished ramp holds its last speed and keeps playing on purpose; the
    /// header offers ✕ then, to put the readout away, not Stop.
    @Test("putting a completed ramp's readout away leaves it playing")
    func dismissingACompletedRampDoesNotPause() {
        let model = makeLoopedModel()
        model.setRampSchedule(RampSchedule(startRatio: 0.5, endRatio: 1.0, repetitions: 2))
        model.startRamp()
        model.transport.request(true, now: 0)
        playOneRepetition(model)
        playOneRepetition(model)
        #expect(model.ramp.phase == .complete)

        model.stopPractice()
        #expect(model.ramp.isIdle)
        #expect(model.isPlaying)
    }

    /// The app's own stops end the ramp and nothing else — clearing the loop
    /// while a track plays must not silence it.
    @Test("clearing the loop ends the ramp but not the playing")
    func clearingTheLoopDoesNotPause() {
        let model = makeLoopedModel()
        model.setRampSchedule(RampSchedule(startRatio: 0.5, endRatio: 1.0, repetitions: 5))
        model.startRamp()
        model.transport.request(true, now: 0)
        model.clearLoop()
        #expect(model.ramp.isIdle)
        #expect(model.isPlaying)
    }
}
