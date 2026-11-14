import ArtscribeKit
import Foundation

/// Undo and redo for the loop — and only the loop (2026-11-14).
///
/// **Why the loop and nothing else.** The user asked for a step back after a
/// loop set with care went at a stray touch, and chose the small version.
/// Research into comparable tools pointed the same way: practice apps protect
/// loops (Transcribe!'s stored loops, Anytune's Loopmarks), Reaper alone puts
/// loop points in undo, and nothing undoes the playhead, the transport or the
/// zoom. Speed and pitch are settings, one key from 100%, and stay out.
///
/// **One step per thing the user did.** A drag is one step however many
/// events it took; a held `C` or `⇧→` is one step for the whole run
/// (`coalescingWindow`); an edit that changed nothing is no step at all.
/// Switching looping on and off is a step too, so the history is simply every
/// change you made to the loop, in order.
///
/// **On the window's `UndoManager`, not a stack of our own.** That is what the
/// Mac's Edit ▸ Undo and ⌘Z, an iPad keyboard's ⌘Z and an iPhone's shake and
/// three-finger swipe all already drive, labelled ("Undo Move Loop") by
/// `setActionName`. `DocumentView` hands the manager over; until it does —
/// and in a unit test that never attaches one — edits work and record nothing.
///
/// **Undo is an edit, and follows the edit rules.** It goes out through
/// `applyLoop`, the one `.setLoop` path. A loop that comes back somewhere else
/// is the one you hear (`enterLoopIfOutside`), as a moved or new one is; one
/// undone to nothing stops a ramp, as Clear Loop does. The history is per
/// track: loading or closing one empties it, because frames mean nothing in
/// another recording.
@MainActor
final class LoopUndo {
    /// The window's, handed over by `DocumentView`. Weak: it belongs to the
    /// window, and a model must not keep a closed window's history alive.
    weak var manager: UndoManager?
    /// Seconds on a steady clock; injectable so a test can space key presses.
    var now: () -> Double = { ProcessInfo.processInfo.systemUptime }
    /// The last step a key-repeat run may merge into, and when it last grew.
    var run: (edit: LoopEdit, time: Double)?

    /// How long a key can rest and still be part of the same run. Long enough
    /// for macOS's longest *Delay until repeat* (1.8 s) before a held key's
    /// first repeat, so a held key is one step at every setting; short enough
    /// that presses with a real pause between them are separate steps.
    static let coalescingWindow = 2.0
}

/// What an undo step is called, as the Edit menu shows it after "Undo ".
enum LoopEdit: Equatable, Sendable {
    case newLoop, setStart, setEnd, move, moveStart, moveEnd, extend, wholeFile, clear
    case loopingOn, loopingOff

    var title: String {
        switch self {
        case .newLoop: return "New Loop"
        case .setStart: return "Set Loop Start"
        case .setEnd: return "Set Loop End"
        case .move: return "Move Loop"
        case .moveStart: return "Move Loop Start"
        case .moveEnd: return "Move Loop End"
        case .extend: return "Extend Loop"
        case .wholeFile: return "Loop Whole File"
        case .clear: return "Clear Loop"
        case .loopingOn: return "Turn Looping On"
        case .loopingOff: return "Turn Looping Off"
        }
    }

    /// What a lane drag latched as `mode` did to the loop, if it could do
    /// anything: a pan, a zoom and a scrub never touch it.
    init?(laneDrag mode: LaneDragMode?) {
        switch mode {
        case .edge(.loopBody): self = .move
        case .edge(.loopStart): self = .moveStart
        case .edge(.loopEnd): self = .moveEnd
        case .range(extending: false): self = .newLoop
        case .range(extending: true): self = .extend
        case .zoom, .scrub, .pan, nil: return nil
        }
    }
}

extension ViewerModel {

    /// The window's undo manager, from `DocumentView`. A new one — another
    /// window, or the first — starts with nothing of ours on it.
    ///
    /// A `nil` is ignored rather than taken as "no manager": SwiftUI may pass
    /// one in passing, and clearing the live manager's history on it would
    /// empty Undo without a word. The reference is weak, so a window that
    /// really goes away takes its manager with it.
    public func attachUndoManager(_ manager: UndoManager?) {
        guard let manager, manager !== loopUndo.manager else { return }
        forgetLoopHistory()
        loopUndo.manager = manager
    }

    /// Runs `change` and records it as one step if it changed the loop.
    /// `coalescing` is for a key that repeats while held: see `LoopUndo`.
    func recordingLoopEdit(
        _ edit: LoopEdit, coalescing: Bool = false, _ change: () -> Void
    ) {
        // A range only drawn so far never reached the engine, so it is not
        // the state to come back to: the loop before that drag is (PR #101
        // review — Esc mid-drag, then Undo, brought back a half-drawn range).
        let before = loopIsStaged ? (loopBeforeLaneDrag ?? loop) : loop
        change()
        recordLoopEdit(edit, from: before, coalescing: coalescing)
    }

    /// Records the step from `before` to the loop as it now is. Nothing is
    /// recorded for a change that came to nothing, or one only drawn so far —
    /// a staged range is recorded when it reaches the engine.
    func recordLoopEdit(_ edit: LoopEdit, from before: LoopRegion, coalescing: Bool = false) {
        guard loop != before, !loopIsStaged else { return }
        let now = loopUndo.now()
        defer { loopUndo.run = coalescing ? (edit, now) : nil }
        // The step on top already puts back where this run began.
        if coalescing && continuesRun(edit, at: now) { return }
        registerLoopUndo(edit, restoring: before)
    }

    /// Whether `edit` at `now` belongs to the key-repeat run on top of the
    /// history: the same edit, soon enough, and still the step Undo would take.
    private func continuesRun(_ edit: LoopEdit, at now: Double) -> Bool {
        guard let run = loopUndo.run, run.edit == edit else { return false }
        return now - run.time < LoopUndo.coalescingWindow
            && loopUndo.manager?.undoActionName == edit.title
    }

    /// The step a lane drag made, recorded once, at its end — or at the start
    /// of the next gesture for one whose end never came.
    func recordLaneDragEdit(_ mode: LaneDragMode?, from before: LoopRegion?) {
        guard let before, let edit = LoopEdit(laneDrag: mode) else { return }
        // A ⇧-drag with no loop made one: it is a new loop, not an extension.
        recordLoopEdit(edit == .extend && before.range.isEmpty ? .newLoop : edit, from: before)
    }

    /// Empties the history: a different track, or no track.
    func forgetLoopHistory() {
        loopUndo.manager?.removeAllActions(withTarget: self)
        loopUndo.run = nil
    }

    /// Puts `snapshot` back, and registers its own inverse — which the undo
    /// manager files as the redo while undoing and as the undo while redoing.
    func restoreLoop(_ snapshot: LoopRegion, undoing edit: LoopEdit) {
        guard hasTrack else { return }
        // A gesture in flight is abandoned rather than left to write over
        // what was just put back.
        cancelLaneDrag()
        loopUndo.run = nil
        let current = loop
        registerLoopUndo(edit, restoring: current)
        rangeAnchor = nil
        applyLoop(snapshot)
        if snapshot.range.isEmpty {
            stopRamp()
        } else if snapshot.range != current.range {
            enterLoopIfOutside()
            // Shown, as a key's move is (`reveal`): an undo that happens off
            // screen looks like one that did nothing. The edge that moved.
            let start = snapshot.range.start != current.range.start
            reveal(start ? snapshot.range.start : snapshot.range.end)
        }
    }

    private func registerLoopUndo(_ edit: LoopEdit, restoring snapshot: LoopRegion) {
        guard let manager = loopUndo.manager else { return }
        // A manager that groups by event (every window's) opens a group for
        // us; one that does not — a test's — needs it opened, except while it
        // is undoing or redoing, when it is already collecting the inverse.
        let opens =
            !manager.groupsByEvent && manager.groupingLevel == 0
            && !manager.isUndoing && !manager.isRedoing
        if opens { manager.beginUndoGrouping() }
        manager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.restoreLoop(snapshot, undoing: edit) }
        }
        manager.setActionName(edit.title)
        if opens { manager.endUndoGrouping() }
    }
}
