import Testing

@testable import ArtscribeUI

/// When the picture floats in its own small window. One table for both
/// platforms; only what draws the window differs.
@Suite("Mini player policy")
struct MiniPlayerPolicyTests {

    /// A video playing, the panel up, the setting on: the case it exists for.
    private var playing: MiniPlayerState {
        MiniPlayerState(
            isShowing: false, openedByUser: false, hasVideo: true, isPanelShown: true,
            isPlaying: true, floatsWhenInactive: true)
    }

    private func next(_ state: MiniPlayerState, _ event: MiniPlayerEvent) -> MiniPlayerState {
        var state = state
        (state.isShowing, state.openedByUser) = MiniPlayerPolicy.next(state, on: event)
        return state
    }

    @Test func leavingTheAppWhilePlayingFloatsIt() {
        let after = next(playing, .appResigned)
        #expect(after.isShowing)
        #expect(!after.openedByUser)
    }

    /// Clicking away from a paused track must not make a window appear.
    @Test func leavingWhilePausedDoesNot() {
        var paused = playing
        paused.isPlaying = false
        #expect(!next(paused, .appResigned).isShowing)
    }

    @Test func theSettingTurnsItOff() {
        var off = playing
        off.floatsWhenInactive = false
        #expect(!next(off, .appResigned).isShowing)
    }

    /// The user hid the picture; it does not reappear in a window instead.
    @Test func aHiddenPanelDoesNotFloat() {
        var hidden = playing
        hidden.isPanelShown = false
        #expect(!next(hidden, .appResigned).isShowing)
    }

    @Test func comingBackPutsItAway() {
        let floated = next(playing, .appResigned)
        #expect(!next(floated, .appActivated).isShowing)
    }

    /// Opened on purpose, it stays until it is closed on purpose.
    @Test func oneOpenedByHandSurvivesComingBack() {
        let opened = next(playing, .userToggled)
        #expect(opened.isShowing && opened.openedByUser)
        #expect(next(opened, .appActivated).isShowing)
        #expect(!next(opened, .userToggled).isShowing)
        #expect(!next(opened, .closed).isShowing)
    }

    @Test func noPictureNoWindow() {
        var audio = playing
        audio.hasVideo = false
        for event in [MiniPlayerEvent.appResigned, .userToggled] {
            #expect(!next(audio, event).isShowing)
        }
        let opened = next(playing, .userToggled)
        var gone = opened
        gone.hasVideo = false
        #expect(!next(gone, .trackChanged).isShowing)
    }
}
