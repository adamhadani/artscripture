import AppKit
import ArtscribeKit
import ArtscribeUI

/// Loop undo, end to end (2026-11-14): a real drag moves the loop, and the
/// Edit menu — the one a person would use — names the step and puts it back.
///
/// The unit suite drives a real `UndoManager`, but one the test made. Only
/// this proves `DocumentView` handed the *window's* manager to the model
/// (`LoopUndoAttachment`): without that one line every unit test still
/// passes and Edit ▸ Undo does nothing, which is the shape of a callback
/// declared, invoked, tested and connected to nothing (CLAUDE.md).
extension AcceptanceRun {

    static let loopUndoChecks = [
        "after a real drag moves the loop, Edit ▸ Undo is named for it",
        "and choosing it puts the loop back",
        "and Edit ▸ Redo moves it again"
    ]

    @MainActor
    static func checkLoopUndo(model: ViewerModel, lanes: CGRect, log: inout Logger) async {
        setLoop(model, fromPoint: 300, toPoint: 500)
        startAFreshHistory()
        let before = model.loop
        await pointerDrag(
            from: CGPoint(x: lanes.minX + 400, y: lanes.midY),
            to: CGPoint(x: lanes.minX + 600, y: lanes.midY))
        await settle(seconds: 0.3)
        let moved = model.loop

        let undoTitle = performEditItem(prefix: "Undo")
        log.check(
            "after a real drag moves the loop, Edit ▸ Undo is named for it "
                + "(\(undoTitle ?? "no enabled Undo item"))",
            moved != before && undoTitle == "Undo Move Loop")
        await settle(seconds: 0.3)
        log.check(
            "and choosing it puts the loop back "
                + "(\(model.loop.range.start)…\(model.loop.range.end) vs "
                + "\(before.range.start)…\(before.range.end))",
            moved != before && model.loop == before)

        let redoTitle = performEditItem(prefix: "Redo")
        await settle(seconds: 0.3)
        log.check(
            "and Edit ▸ Redo moves it again (\(redoTitle ?? "no enabled Redo item"))",
            redoTitle == "Redo Move Loop" && model.loop == moved)
    }

    /// Empties the window's undo history, so the drag that follows is the
    /// only thing on it.
    ///
    /// A window's undo manager groups by event: it closes the group when the
    /// run loop next passes through the default mode, which the app's does
    /// after every event. This harness's never does — measured 2026-11-14, it
    /// sits in `NSEventTrackingRunLoopMode` for the whole run, most likely
    /// inside the tracking loop of a synthesised mouse-down whose mouse-up was
    /// delivered by `sendEvent` rather than through the queue. Without this
    /// every loop edit since launch, the A/S that set this loop up included,
    /// is one group, and Undo put back a loop three edits old. Closing the
    /// group by hand crashed SwiftUI's menu update; clearing does not need to,
    /// because Undo closes an open top-level group itself before undoing it.
    @MainActor
    private static func startAFreshHistory() {
        NSApp.keyWindow?.undoManager?.removeAllActions()
    }

    /// Validates the Edit menu the way opening it would, then chooses the
    /// first enabled item whose title starts with `prefix`. Answers the title
    /// it chose, or `nil` when there was none to choose.
    @MainActor
    private static func performEditItem(prefix: String) -> String? {
        guard let edit = NSApp.mainMenu?.items.first(where: { $0.title == "Edit" })?.submenu
        else { return nil }
        edit.update()
        guard
            let index = edit.items.firstIndex(where: { $0.title.hasPrefix(prefix) }),
            edit.items[index].isEnabled
        else { return nil }
        let title = edit.items[index].title
        edit.performActionForItem(at: index)
        return title
    }
}
