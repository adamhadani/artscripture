import ArtscribeKit
import Foundation
import Testing

@testable import ArtscribeUI

/// The "stored in Application Support" banner, collapsible to a badge.
///
/// Reported from an iPhone during 1.2's TestFlight: the banner is four lines
/// tall in landscape and had no way to put it away. It describes a condition
/// rather than an event, so dismissing it must leave a trace (spec §8): it
/// collapses to a badge by the file name, and the badge brings it back. The
/// choice is remembered for the track.
@MainActor
@Suite("Session fallback notice: banner and badge")
struct FallbackNoticeTests {

    /// A model whose session had to go to Application Support, because the
    /// track's folder is read-only.
    private func fellBack(_ scratch: SessionScratch) throws -> ViewerModel {
        let model = SessionTestModel.make(scratch)
        model.setSpeedPreset(0.5)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: scratch.tracks.path)
        model.saveSession()
        return model
    }

    @Test("a fallback shows the banner, not the badge")
    func bannerFirst() throws {
        let scratch = try SessionScratch()
        let model = try fellBack(scratch)
        #expect(model.isSessionStoredAwayFromTheTrack)
        #expect(model.showsFallbackBanner)
        #expect(!model.showsFallbackBadge)
    }

    @Test("Dismiss collapses the banner to the badge, and the badge brings it back")
    func collapseAndExpand() throws {
        let scratch = try SessionScratch()
        let model = try fellBack(scratch)
        model.collapseFallbackNotice()
        #expect(!model.showsFallbackBanner)
        #expect(model.showsFallbackBadge)
        model.expandFallbackNotice()
        #expect(model.showsFallbackBanner)
        #expect(!model.showsFallbackBadge)
    }

    @Test("collapsing is remembered: the track reopens with the badge")
    func rememberedForTheTrack() throws {
        let scratch = try SessionScratch()
        let model = try fellBack(scratch)
        model.collapseFallbackNotice()

        let reopened = SessionTestModel.make(scratch)
        #expect(reopened.isSessionStoredAwayFromTheTrack)
        #expect(reopened.showsFallbackBadge)
        #expect(!reopened.showsFallbackBanner)
    }

    @Test("collapsing is not an edit to the session")
    func notAnEdit() throws {
        let scratch = try SessionScratch()
        let model = try fellBack(scratch)
        #expect(!model.isDirty)
        model.collapseFallbackNotice()
        #expect(!model.isDirty)
    }

    @Test("a session beside its track shows neither")
    func besideTheTrackShowsNothing() throws {
        let scratch = try SessionScratch()
        let model = SessionTestModel.make(scratch)
        model.setSpeedPreset(0.5)
        model.saveSession()
        #expect(!model.isSessionStoredAwayFromTheTrack)
        #expect(!model.showsFallbackBanner)
        #expect(!model.showsFallbackBadge)
        model.collapseFallbackNotice()
        #expect(!model.showsFallbackBadge)
    }
}
