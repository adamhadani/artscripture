import ArtscribeKit
import Testing

@testable import ArtscribeUI

/// The header's Practice button: an invitation at rest, a readout while a ramp
/// runs. Every word it shows comes from `PracticeButtonFace`, so this is where
/// those words are checked.
@Suite("Practice button face")
struct PracticeButtonFaceTests {

    /// 50% → 100% over five passes: 50, 62.5, 75, 87.5, 100.
    private static func ramp(advancedBy passes: Int = 0, started: Bool = true) -> SpeedRamp {
        var ramp = SpeedRamp(
            schedule: RampSchedule(startRatio: 0.5, endRatio: 1.0, repetitions: 5))
        guard started else { return ramp }
        ramp.start()
        for _ in 0..<passes { _ = ramp.advance() }
        return ramp
    }

    @Test("at rest it is the filled invitation, with nothing to stop")
    func idleIsTheInvitation() {
        for compact in [false, true] {
            let face = PracticeButtonFace.face(for: Self.ramp(started: false), compact: compact)
            #expect(face.style == .invitation)
            #expect(face.title == "Practice")
            #expect(face.progress == nil)
            #expect(face.stopSymbol == nil)
            #expect(face.stopAccessibilityLabel == nil)
        }
    }

    @Test("while running it names the repetition and the speed being played")
    func runningReadsOut() {
        let ramp = Self.ramp(advancedBy: 2)
        let face = PracticeButtonFace.face(for: ramp, compact: false)
        #expect(face.style == .progress)
        #expect(face.title == "Rep 3 of 5 · 75%")
        #expect(face.stopSymbol == "stop.fill")
        #expect(face.stopAccessibilityLabel == "Stop ramp")
        #expect(face.accessibilityLabel == "Practice: repetition 3 of 5, at 75%")
    }

    /// The phone drops the word, never the numbers.
    @Test("compact keeps both numbers and drops the word")
    func compactKeepsTheNumbers() {
        let face = PracticeButtonFace.face(for: Self.ramp(advancedBy: 2), compact: true)
        #expect(face.title == "3/5 · 75%")
        // VoiceOver is not short of room: the spoken label is the full one.
        #expect(face.accessibilityLabel == "Practice: repetition 3 of 5, at 75%")
    }

    /// The wash must not show a fifth of the bar filled before a note has been
    /// played — `SpeedRamp.progress` counts completed passes, and the face passes
    /// it through rather than recomputing `repetition / total`.
    @Test("progress is passes completed: empty on the first, half at the third of five")
    func progressCountsCompletedPasses() {
        #expect(PracticeButtonFace.face(for: Self.ramp(), compact: false).progress == 0)
        #expect(
            PracticeButtonFace.face(for: Self.ramp(advancedBy: 2), compact: false).progress == 0.5)
        #expect(
            PracticeButtonFace.face(for: Self.ramp(advancedBy: 4), compact: false).progress == 1)
    }

    /// A finished ramp holds its last speed (see `SpeedRamp`), so the readout
    /// stays up and says so; its second segment puts the readout away rather
    /// than "stopping" something that has already stopped climbing.
    @Test("a finished ramp says it is holding, and offers to dismiss")
    func completeHolds() {
        let ramp = Self.ramp(advancedBy: 5)
        #expect(ramp.phase == .complete)
        let face = PracticeButtonFace.face(for: ramp, compact: false)
        #expect(face.style == .progress)
        #expect(face.title == "Ramp done · 100%")
        #expect(face.progress == 1)
        #expect(face.stopSymbol == "xmark")
        #expect(face.stopAccessibilityLabel == "Dismiss finished ramp")
        #expect(PracticeButtonFace.face(for: ramp, compact: true).title == "Done · 100%")
    }

    @Test("stopping returns the button to the invitation")
    func stopRestoresTheInvitation() {
        var ramp = Self.ramp(advancedBy: 1)
        ramp.stop()
        #expect(PracticeButtonFace.face(for: ramp, compact: false).style == .invitation)
    }
}
