import CoreGraphics
import SwiftUI
import Testing

@testable import ArtscribeUI

/// How much of the window the picture gets: what the divider is dragged
/// between, and what the timeline keeps whatever happens.
@Suite("Video split")
struct VideoSplitPolicyTests {

    private func extent(
        _ fraction: Double, of available: CGFloat,
        on surface: EmptyStatePrompt.Surface = .desktop
    ) -> CGFloat {
        VideoSplitPolicy.videoExtent(fraction: fraction, available: available, surface: surface)
    }

    @Test func extentFollowsTheFraction() {
        #expect(extent(0.35, of: 1000) == 350)
    }

    @Test func extentNeverBelowTheVideoMinimum() {
        #expect(extent(0.05, of: 1000) == VideoSplitPolicy.minimumVideo)
    }

    /// The timeline is what you set the loop on; it is never squeezed out.
    @Test func theTimelineKeepsItsFloor() {
        let floor = VideoSplitPolicy.minimumTimeline(on: .desktop)
        #expect(extent(0.9, of: 1000) == 1000 - floor)
    }

    /// Too small for both: the picture gives way, down to nothing.
    @Test func aTinyWindowGivesTheTimelineEverything() {
        let floor = VideoSplitPolicy.minimumTimeline(on: .desktop)
        #expect(extent(0.35, of: floor + 80) == 80)
        #expect(extent(0.35, of: floor - 20) == 0)
    }

    /// A landscape iPhone has about 750 pt; 320 of timeline would leave the
    /// picture too little to be worth showing.
    @Test func phoneHasALowerTimelineFloor() {
        #expect(
            VideoSplitPolicy.minimumTimeline(on: .phone)
                < VideoSplitPolicy.minimumTimeline(on: .desktop))
        #expect(extent(0.9, of: 600, on: .phone) > extent(0.9, of: 600, on: .desktop))
    }

    @Test func dragFractionRoundTrips() {
        for dragged: CGFloat in [100, 300, 500, 900] {
            let fraction = VideoSplitPolicy.fraction(
                dragTo: dragged, available: 1000, surface: .desktop)
            let clamped = min(max(dragged, VideoSplitPolicy.minimumVideo), 1000 - 320)
            #expect(abs(extent(fraction, of: 1000) - clamped) < 0.001)
        }
    }

    @Test func placementAxes() {
        #expect(VideoPlacement.trailing.axis == .horizontal)
        #expect(VideoPlacement.top.axis == .vertical)
        #expect(VideoPlacement.trailing.title == "Right")
        #expect(VideoPlacement.top.title == "Top")
    }

    @Test func eachPlacementHasADefault() {
        #expect(VideoSplitPolicy.defaultFraction(for: .trailing) == 0.35)
        #expect(VideoSplitPolicy.defaultFraction(for: .top) == 0.40)
    }

    /// The divider's tab stands across the line: tall on a vertical divider,
    /// wide on a horizontal one.
    @Test func theGripTabStandsAcrossTheDivider() {
        let beside = SplitGrip.size(across: .horizontal, touch: false)
        #expect(beside.height > beside.width)
        let above = SplitGrip.size(across: .vertical, touch: false)
        #expect(above.width > above.height)
        #expect(above.width == beside.height)
    }

    /// Chunkier than a loop edge's tab, and chunkier again for a finger.
    @Test func theGripTabIsAtLeastALoopTab() {
        let pointer = SplitGrip.size(across: .horizontal, touch: false)
        let finger = SplitGrip.size(across: .horizontal, touch: true)
        let loopTab = LoopGrip.tab(atX: 0, laneHeight: 1000, reach: .pointer)
        #expect(pointer.width >= loopTab.width && pointer.height > loopTab.height)
        #expect(finger.width > pointer.width && finger.height > pointer.height)
    }
}
