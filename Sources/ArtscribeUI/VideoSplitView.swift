import SwiftUI

/// The timeline and the picture, side by side or one above the other, with a
/// divider between them that can be dragged.
///
/// Generic over both halves and told nothing but a `VideoPlacement`, so moving
/// the picture somewhere else is a new placement case, not a new layout.
///
/// `AnyLayout` rather than an `if` between an `HStack` and a `VStack`: it keeps
/// the timeline's identity when the placement changes or the picture is
/// toggled, so the waveform is re-laid-out rather than rebuilt.
struct VideoSplitView<Timeline: View, Picture: View>: View {
    let placement: VideoPlacement
    let showsPicture: Bool
    /// The saved share of the window, before clamping.
    let fraction: Double
    /// Called once, when a drag ends, with the fraction to keep.
    let onResize: (Double) -> Void
    /// A double-click on the divider.
    let onReset: () -> Void
    @ViewBuilder let timeline: () -> Timeline
    @ViewBuilder let picture: () -> Picture

    @Environment(\.palette) private var palette
    @State private var available: CGFloat = 0
    /// The fraction while a drag is under way; `nil` otherwise.
    @State private var dragging: Double?
    @State private var hovering = false

    private let surface = EmptyStatePrompt.current

    var body: some View {
        let layout =
            placement.axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        let extent = VideoSplitPolicy.videoExtent(
            fraction: dragging ?? fraction, available: available, surface: surface)
        let showing = showsPicture && extent > 0
        layout {
            if showing, placement.pictureLeads {
                sized(picture(), extent)
                divider
            }
            timeline()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showing, !placement.pictureLeads {
                divider
                sized(picture(), extent)
            }
        }
        .coordinateSpace(.named(Self.space))
        .onGeometryChange(for: CGFloat.self) { proxy in
            placement.axis == .horizontal ? proxy.size.width : proxy.size.height
        } action: {
            available = $0
        }
    }

    private static var space: String { "videoSplit" }

    @ViewBuilder
    private func sized(_ view: Picture, _ extent: CGFloat) -> some View {
        switch placement.axis {
        case .horizontal: view.frame(width: extent).frame(maxHeight: .infinity)
        case .vertical: view.frame(height: extent).frame(maxWidth: .infinity)
        }
    }

    /// A hairline with a **grip tab** on it — the loop edges' shape, so the
    /// window has one vocabulary for "this can be dragged". The whole strip
    /// answers, not just the tab: `grab` points across, 44 on touch.
    private var divider: some View {
        let touch = ControlMetrics.current.target >= 44
        let grab = touch ? 44 : Self.desktopGrab
        let horizontal = placement.axis == .horizontal
        let lit = hovering || dragging != nil
        return Rectangle()
            .fill(lit ? palette.dimmed.color() : palette.rule.color())
            .frame(
                width: horizontal ? Metrics.hairline : nil,
                height: horizontal ? nil : Metrics.hairline
            )
            .overlay {
                ZStack {
                    Color.clear
                        .frame(width: horizontal ? grab : nil, height: horizontal ? nil : grab)
                    SplitGripTab(axis: placement.axis, touch: touch, lit: lit)
                }
                .contentShape(.rect)
                .gesture(drag)
                .onTapGesture(count: 2) { onReset() }
                .onHover { hovering = $0 }
                #if os(macOS)
                .pointerStyle(horizontal ? .columnResize : .rowResize)
                #endif
            }
            .zIndex(1)
            .accessibilityLabel("Video size")
            .accessibilityHint("Drag to make the video larger or smaller.")
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
            .onChanged { value in
                dragging = fraction(at: value.location)
            }
            .onEnded { value in
                let final = fraction(at: value.location)
                dragging = nil
                onResize(final)
            }
    }

    /// The picture's share if the divider sat at `point`.
    private func fraction(at point: CGPoint) -> Double {
        let along = placement.axis == .horizontal ? point.x : point.y
        let extent = placement.pictureLeads ? along : available - along
        return VideoSplitPolicy.fraction(dragTo: extent, available: available, surface: surface)
    }

    /// Wide enough to find with a pointer without hunting for a 1 pt line.
    private static var desktopGrab: CGFloat { 9 }
}

/// The divider's grip tab: the loop edges' rounded tab with two grip lines,
/// a size up, laid across whichever way the divider runs.
enum SplitGrip {
    /// `axis` is the split's: `.horizontal` means a vertical divider between
    /// side-by-side halves, so the tab stands tall.
    static func size(across axis: Axis, touch: Bool) -> CGSize {
        let thick: CGFloat = touch ? 16 : 12
        let long: CGFloat = touch ? 68 : 56
        return axis == .horizontal
            ? CGSize(width: thick, height: long) : CGSize(width: long, height: thick)
    }
}

struct SplitGripTab: View {
    let axis: Axis
    let touch: Bool
    /// Hovered or being dragged.
    let lit: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        let size = SplitGrip.size(across: axis, touch: touch)
        let lineLength = (axis == .horizontal ? size.height : size.width) / 2
        let lines = ForEach(0..<2, id: \.self) { _ in
            Rectangle()
                .fill(palette.background.color(opacity: 0.85))
                .frame(
                    width: axis == .horizontal ? 1 : lineLength,
                    height: axis == .horizontal ? lineLength : 1)
        }
        Capsule()
            .fill(palette.text.color(opacity: lit ? 1 : 0.6))
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
            .frame(width: size.width, height: size.height)
            .overlay {
                if axis == .horizontal {
                    HStack(spacing: 2) { lines }
                } else {
                    VStack(spacing: 2) { lines }
                }
            }
    }
}
