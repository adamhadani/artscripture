import Foundation

/// Whether the user put away the "stored in Application Support" banner for a
/// track, remembered as an empty marker file beside that track's fallback
/// session — so it is per track, lives with the session it describes, and goes
/// when the session does.
///
/// Only a fallback location has one: a sidecar beside the track raises no
/// banner, so there is nothing to remember.
extension SessionStore {

    public func isFallbackNoticeCollapsed(for location: SessionLocation) -> Bool {
        guard let marker = Self.noticeMarker(for: location) else { return false }
        return FileManager.default.fileExists(atPath: marker.path)
    }

    public func setFallbackNoticeCollapsed(_ collapsed: Bool, for location: SessionLocation) {
        guard let marker = Self.noticeMarker(for: location) else { return }
        if collapsed {
            try? Data().write(to: marker)
        } else {
            try? FileManager.default.removeItem(at: marker)
        }
    }

    static func noticeMarker(for location: SessionLocation) -> URL? {
        guard case .applicationSupport(let url) = location else { return nil }
        return url.appendingPathExtension("notice-collapsed")
    }
}
