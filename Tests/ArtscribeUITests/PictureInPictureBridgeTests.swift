import Testing

@testable import ArtscribeUI

/// What iOS's Picture in Picture asks of the app, answered without AVKit — so
/// it runs in `make check`, on the Mac, where a test of the iOS-only code
/// itself could not run at all.
@Suite("Picture in Picture bridge")
struct PictureInPictureBridgeTests {

    /// The window's play button sends the state it wants, not "toggle". A
    /// request that matches what is already happening must change nothing —
    /// the system repeats itself, and a toggle would flip it back.
    @Test func aRequestOnlyActsWhenItChangesSomething() {
        #expect(PictureInPictureBridge.shouldToggle(requestedPlaying: true, isPlaying: false))
        #expect(PictureInPictureBridge.shouldToggle(requestedPlaying: false, isPlaying: true))
        #expect(!PictureInPictureBridge.shouldToggle(requestedPlaying: true, isPlaying: true))
        #expect(!PictureInPictureBridge.shouldToggle(requestedPlaying: false, isPlaying: false))
    }

    /// The system starts it on its own only for what the Mac would float:
    /// a picture, on screen, with the setting on. (The system adds "playing".)
    @Test func automaticStartFollowsTheSameRuleAsTheMac() {
        let ready = MiniPlayerState(hasVideo: true, isPanelShown: true, floatsWhenInactive: true)
        #expect(PictureInPictureBridge.startsAutomatically(ready))
        var hidden = ready
        hidden.isPanelShown = false
        #expect(!PictureInPictureBridge.startsAutomatically(hidden))
        var off = ready
        off.floatsWhenInactive = false
        #expect(!PictureInPictureBridge.startsAutomatically(off))
        var audio = ready
        audio.hasVideo = false
        #expect(!PictureInPictureBridge.startsAutomatically(audio))
    }

    /// The window's ±skip buttons, as frames for the model's seek.
    @Test func skipIntervalsBecomeFrames() {
        #expect(PictureInPictureBridge.frames(forSkip: 10, sampleRate: 48_000) == 480_000)
        #expect(PictureInPictureBridge.frames(forSkip: -15, sampleRate: 44_100) == -661_500)
        #expect(PictureInPictureBridge.frames(forSkip: 10, sampleRate: 0) == 0)
    }
}
