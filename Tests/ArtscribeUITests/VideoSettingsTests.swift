import Foundation
import Testing

@testable import ArtscribeUI

/// The picture's app-wide preferences, and where they are kept.
@MainActor
@Suite("Video settings")
final class VideoSettingsTests {
    /// One suite per test, removed when it ends: a suite left behind is a
    /// plist in ~/Library/Preferences for every run of `make check`.
    private let suiteName = "video-settings-\(UUID().uuidString)"

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: suiteName))
    }

    @Test func defaultsWhenNothingStored() throws {
        let loaded = VideoSettings(defaults: try defaults()).load()
        #expect(loaded == .defaults)
        #expect(loaded.shown)
        #expect(loaded.placement == .trailing)
        #expect(loaded.floatsWhenInactive)
        #expect(loaded.fraction(for: .trailing) == VideoSplitPolicy.defaultFraction(for: .trailing))
    }

    @Test func aSavedPlacementLoads() throws {
        let store = VideoSettings(defaults: try defaults())
        var preferences = VideoPreferences.defaults
        preferences.placement = .top
        preferences.shown = false
        preferences.floatsWhenInactive = false
        preferences.fractions[.trailing] = 0.5
        store.save(preferences)
        #expect(store.load() == preferences)
    }

    /// A default is stored as no key at all, so changing a default later
    /// reaches everyone who never touched it.
    @Test func restoringADefaultRemovesTheKey() throws {
        let suite = try defaults()
        let store = VideoSettings(defaults: suite)
        var preferences = VideoPreferences.defaults
        preferences.placement = .top
        preferences.fractions[.top] = 0.6
        store.save(preferences)
        store.save(.defaults)
        #expect(suite.dictionaryRepresentation().keys.filter { $0.hasPrefix("video.") }.isEmpty)
    }

    @Test func togglingThePanelPersists() throws {
        let store = VideoSettings(defaults: try defaults())
        let prefs = Preferences()
        prefs.adopt(video: store)
        prefs.toggleVideoShown()
        #expect(!prefs.video.shown)
        #expect(!store.load().shown)
    }

    @Test func aDraggedSizeIsKeptPerPlacement() throws {
        let store = VideoSettings(defaults: try defaults())
        let prefs = Preferences()
        prefs.adopt(video: store)
        prefs.setVideoFraction(0.5, for: .trailing)
        #expect(store.load().fraction(for: .trailing) == 0.5)
        #expect(store.load().fraction(for: .top) == VideoSplitPolicy.defaultFraction(for: .top))
    }
}
