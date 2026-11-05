import CoreGraphics
import SwiftUI

/// Where the picture sits relative to the timeline.
///
/// **A value, not a layout.** One container (`VideoSplitView`) takes it and
/// arranges the timeline and the picture along its axis; nothing else knows
/// which side the picture is on. A new side is a new case here, an axis and a
/// title, and nothing more.
public enum VideoPlacement: String, CaseIterable, Sendable, Identifiable {
    /// Beside the timeline, on the right: the default, and the natural home
    /// for a portrait clip.
    case trailing
    /// Between the overview strip and the ruler: the timeline keeps its full
    /// width, and a widescreen clip fills the band.
    case top

    public var id: String { rawValue }

    public var axis: Axis {
        switch self {
        case .trailing: return .horizontal
        case .top: return .vertical
        }
    }

    /// The Settings picker's label.
    public var title: String {
        switch self {
        case .trailing: return "Right"
        case .top: return "Top"
        }
    }

    /// Whether the picture comes before the timeline along the axis.
    var pictureLeads: Bool { self == .top }
}

/// How much of the window the picture gets. Pure, so every device's answer is
/// checked in one `make check`.
///
/// Sizes are kept as a **fraction** of the space available, so the picture
/// grows with the window, and clamped in points when laid out. The timeline
/// always keeps its floor: it is what the loop is set on, and a picture that
/// squeezed it out would defeat the point of having both.
enum VideoSplitPolicy {
    /// Below this a picture of hands on keys stops being readable.
    static let minimumVideo: CGFloat = 160

    /// The least timeline worth having. A landscape iPhone has about 750 pt in
    /// all, so it gets a lower floor than the larger screens.
    static func minimumTimeline(on surface: EmptyStatePrompt.Surface) -> CGFloat {
        switch surface {
        case .desktop, .tabletWithDrop: return 320
        case .phone: return 200
        }
    }

    static func defaultFraction(for placement: VideoPlacement) -> Double {
        switch placement {
        case .trailing: return 0.35
        case .top: return 0.40
        }
    }

    /// The picture's size along the split axis, in points.
    static func videoExtent(
        fraction: Double, available: CGFloat, surface: EmptyStatePrompt.Surface
    ) -> CGFloat {
        clamp(CGFloat(fraction) * available, available: available, surface: surface)
    }

    /// The fraction a divider dragged to `extent` stands for, clamped the way
    /// the layout will clamp it, so what is saved is what was seen.
    static func fraction(
        dragTo extent: CGFloat, available: CGFloat, surface: EmptyStatePrompt.Surface
    ) -> Double {
        guard available > 0 else { return defaultFraction(for: .trailing) }
        return Double(clamp(extent, available: available, surface: surface) / available)
    }

    private static func clamp(
        _ extent: CGFloat, available: CGFloat, surface: EmptyStatePrompt.Surface
    ) -> CGFloat {
        let ceiling = available - minimumTimeline(on: surface)
        // Not enough room for both: the timeline wins, down to no picture.
        guard ceiling >= minimumVideo else { return max(0, ceiling) }
        return min(max(extent, minimumVideo), ceiling)
    }
}
