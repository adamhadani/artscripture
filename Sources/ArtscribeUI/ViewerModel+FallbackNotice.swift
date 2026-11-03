import Foundation

/// The "stored in Application Support" banner and its badge (spec §8).
///
/// The banner describes a **condition**, not an event — this track's loop
/// points are not beside the music — so it was undismissible: put it away and
/// nothing would say where the session went. Reported from an iPhone during
/// 1.2's TestFlight as four lines of landscape screen with no way to close it.
/// So Dismiss **collapses** it to a badge by the file name, which brings it back,
/// and the choice is remembered for the track (`SessionStore`'s marker file).
/// Not a session edit: it describes the session, it is not in it.
extension ViewerModel {

    public var showsFallbackBanner: Bool {
        isSessionStoredAwayFromTheTrack && !fallbackNoticeCollapsed
    }

    public var showsFallbackBadge: Bool {
        isSessionStoredAwayFromTheTrack && fallbackNoticeCollapsed
    }

    public func collapseFallbackNotice() { setFallbackNotice(collapsed: true) }

    public func expandFallbackNotice() { setFallbackNotice(collapsed: false) }

    private func setFallbackNotice(collapsed: Bool) {
        guard isSessionStoredAwayFromTheTrack, let sessionLocation else { return }
        sessions?.setFallbackNoticeCollapsed(collapsed, for: sessionLocation)
        if fallbackNoticeCollapsed != collapsed { fallbackNoticeCollapsed = collapsed }
    }

    /// Re-read for whatever session is now open. Called when the location
    /// changes — a load, a save that fell back, a track closed.
    func refreshFallbackNotice() {
        let collapsed =
            sessionLocation.map { sessions?.isFallbackNoticeCollapsed(for: $0) ?? false } ?? false
        if fallbackNoticeCollapsed != collapsed { fallbackNoticeCollapsed = collapsed }
    }
}
