import Foundation
import SwiftUI

/// The picture's app-wide preferences. Not per document: hiding the video is a
/// statement about how you like to work, and it holds for the next clip too.
public struct VideoPreferences: Equatable, Sendable {
    /// Whether a video file's picture is on screen. A clip opens with it shown.
    public var shown = true
    public var placement = VideoPlacement.trailing
    /// Whether the mini player floats when the app is not in front.
    public var floatsWhenInactive = true
    /// The divider's position for each placement, where the user moved it.
    /// One per placement because a share of the width and a share of the
    /// height are different numbers.
    public var fractions: [VideoPlacement: Double] = [:]

    public static let defaults = VideoPreferences()

    public func fraction(for placement: VideoPlacement) -> Double {
        fractions[placement] ?? VideoSplitPolicy.defaultFraction(for: placement)
    }
}

/// Reads and writes `VideoPreferences` in `UserDefaults`.
///
/// A default is stored as **no key**, as `InteractionSettings` does, so a
/// default changed in a later version reaches everyone who never touched it.
@MainActor
public final class VideoSettings {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static let shownKey = "video.shown"
    static let placementKey = "video.placement"
    static let floatsKey = "video.floatWhenInactive"
    static func fractionKey(_ placement: VideoPlacement) -> String {
        "video.fraction.\(placement.rawValue)"
    }

    public func load() -> VideoPreferences {
        var preferences = VideoPreferences.defaults
        // `object(forKey:) as?`, not `bool(forKey:)`: the latter cannot tell
        // "absent" from "false".
        if let shown = defaults.object(forKey: Self.shownKey) as? Bool {
            preferences.shown = shown
        }
        let storedPlacement = defaults.string(forKey: Self.placementKey)
        if let placement = storedPlacement.flatMap(VideoPlacement.init(rawValue:)) {
            preferences.placement = placement
        }
        if let floats = defaults.object(forKey: Self.floatsKey) as? Bool {
            preferences.floatsWhenInactive = floats
        }
        for placement in VideoPlacement.allCases {
            let stored = defaults.object(forKey: Self.fractionKey(placement)) as? Double
            if let stored, stored > 0, stored < 1 { preferences.fractions[placement] = stored }
        }
        return preferences
    }

    public func save(_ preferences: VideoPreferences) {
        let base = VideoPreferences.defaults
        store(preferences.shown, Self.shownKey, isDefault: preferences.shown == base.shown)
        store(
            preferences.placement.rawValue, Self.placementKey,
            isDefault: preferences.placement == base.placement)
        store(
            preferences.floatsWhenInactive, Self.floatsKey,
            isDefault: preferences.floatsWhenInactive == base.floatsWhenInactive)
        for placement in VideoPlacement.allCases {
            let value = preferences.fractions[placement]
            store(
                value as Any, Self.fractionKey(placement),
                isDefault: value == nil
                    || value == VideoSplitPolicy.defaultFraction(for: placement))
        }
    }

    private func store(_ value: Any, _ key: String, isDefault: Bool) {
        if isDefault {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(value, forKey: key)
        }
    }
}

extension Preferences {
    public func adopt(video settings: VideoSettings) {
        videoStore = settings
        let loaded = settings.load()
        if loaded != video { video = loaded }
    }

    /// `V`, the transport button, and View ▸ Video.
    public func toggleVideoShown() {
        applyVideo { $0.shown.toggle() }
    }

    public func setVideoPlacement(_ placement: VideoPlacement) {
        applyVideo { $0.placement = placement }
    }

    public func setFloatVideoWhenInactive(_ floats: Bool) {
        applyVideo { $0.floatsWhenInactive = floats }
    }

    /// Where the divider was left. Called when a drag *ends*, not on every
    /// step of it: the drag itself is view state.
    public func setVideoFraction(_ fraction: Double, for placement: VideoPlacement) {
        applyVideo { $0.fractions[placement] = fraction }
    }

    /// A double-click on the divider.
    public func restoreVideoFraction(for placement: VideoPlacement) {
        applyVideo { $0.fractions[placement] = nil }
    }

    /// Compared before assigning, so an unchanged value does not invalidate
    /// every view reading the preferences.
    private func applyVideo(_ change: (inout VideoPreferences) -> Void) {
        var next = video
        change(&next)
        guard next != video else { return }
        video = next
        videoStore?.save(next)
    }
}

/// Settings ▸ Video: where the picture goes, and whether it floats when the
/// app is not in front.
struct VideoSettingsTab: View {
    let prefs: Preferences

    var body: some View {
        Form {
            Section {
                Picker(
                    "Video position",
                    selection: Binding(
                        get: { prefs.video.placement },
                        set: { prefs.setVideoPlacement($0) })
                ) {
                    ForEach(VideoPlacement.allCases) { Text($0.title).tag($0) }
                }
                #if os(macOS)
                Toggle(
                    "Float video when switching apps",
                    isOn: Binding(
                        get: { prefs.video.floatsWhenInactive },
                        set: { prefs.setFloatVideoWhenInactive($0) }))
                #endif
            } footer: {
                Text(Self.footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    #if os(macOS)
    private static let footer =
        "For video files. Drag the line between the video and the waveform to resize it; "
        + "double-click it to restore. When the app is not in front, a playing video "
        + "carries on in a small floating window."
    #else
    private static let footer =
        "For video files. Drag the line between the video and the waveform to resize it; "
        + "double-tap it to restore."
    #endif
}
