import SwiftUI

/// Hands the window's undo manager to the model, which records loop edits on
/// it (`ViewerModel+LoopUndo`).
///
/// **This line is the whole connection**, and without it undo does nothing
/// and says nothing: the model records onto whatever manager it was given,
/// and was given none. That is the shape of the interruption callbacks that
/// were declared, called, tested and connected to nothing (CLAUDE.md), so the
/// join is checked end to end — the acceptance run drags a loop and then
/// chooses Edit ▸ Undo — rather than trusted.
///
/// `initial: true` because the manager is there from the first frame, and
/// `onChange` rather than `onAppear` because SwiftUI may hand over a different
/// one: the window's is the one Edit ▸ Undo, ⌘Z and shake-to-undo drive.
struct LoopUndoAttachment: ViewModifier {
    let model: ViewerModel
    @Environment(\.undoManager) private var undoManager

    func body(content: Content) -> some View {
        content.onChange(of: undoManager, initial: true) { _, manager in
            model.attachUndoManager(manager)
        }
    }
}
