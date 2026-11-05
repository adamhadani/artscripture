import SwiftUI

/// Everything under the overview strip and above the transport: the timeline,
/// and a video file's picture beside it.
///
/// The picture sits beside the *timeline* — the ruler, the marks and the
/// lanes, which share one x-mapping and so must move together. The overview
/// maps the whole track to its own width and stays full width above both.
struct TimelineAndPictureView: View {
    let model: ViewerModel
    let appearance: Appearance
    let miniPlayer: MiniPlayerController

    var body: some View {
        let preferences = model.prefs.video
        let placement = preferences.placement
        VideoSplitView(
            placement: placement,
            showsPicture: model.video != nil && preferences.shown,
            fraction: preferences.fraction(for: placement),
            onResize: { model.prefs.setVideoFraction($0, for: placement) },
            onReset: { model.prefs.restoreVideoFraction(for: placement) },
            timeline: { timeline },
            picture: {
                if let video = model.video {
                    VideoPanelView(video: video) { miniPlayer.toggleByUser() }
                }
            })
    }

    private var timeline: some View {
        VStack(spacing: 0) {
            TimeRulerView(model: model)
            // Only when the file has a cue sheet and the user has not put the
            // lane away, so a track with no markers costs no height at all —
            // which is most of them.
            if model.showsTrackMarks {
                CueMarkerLaneView(model: model, appearance: appearance)
            }
            WaveformLanesView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
