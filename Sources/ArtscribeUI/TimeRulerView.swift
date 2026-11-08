import ArtscribeKit
import SwiftUI

/// The time ruler above the lanes. Tick spacing comes from `RulerTicks`, which is
/// pure and tested; this view only paints what it is given.
struct TimeRulerView: View {
    let model: ViewerModel
    @Environment(\.palette) private var palette
    /// Whether the pointer is over the playhead's grip, for the Mac's cursor.
    @State private var overGrip = false
    /// True while a ruler gesture is in flight. Reset by SwiftUI on cancel as
    /// well as on end — and only an end calls `onEnded` — which is how a
    /// cancelled scrub is noticed at all (`rulerDragCancelled`).
    @GestureState private var rulerPressed = false

    /// The ruler's height, and therefore its hit area.
    ///
    /// It was 24, which is a comfortable *reading* height and a mean drag
    /// target — and as of Task 16 this strip carries the app's only
    /// modifier-free continuous zoom, which the user reaches for constantly.
    /// 32 clears Apple's 28-point minimum for a pointer target with room to
    /// spare while staying a thin strip: the ticks and the label keep their
    /// spacing (both are laid out from the bottom edge), so the extra eight
    /// points are quiet background rather than more ink.
    ///
    /// It is not extended past the drawn ruler in either direction — the
    /// playhead's grip included, which is why it lives on the ruler at all
    /// (`PlayheadScrub`). Downwards would steal from the waveform lanes, where
    /// a bare drag marks a loop; upwards
    /// would steal from the overview strip, where a bare drag scrubs. Both are
    /// gestures with no modifier, so an invisible margin over either would make
    /// the wrong thing happen with the pointer apparently in the right place.
    static let height: Double = 32

    private static let majorTickHeight: Double = 9
    private static let minorTickHeight: Double = 4
    /// The tick labels' baseline, measured from the bottom edge so the label
    /// keeps its relationship to the ticks whatever the height is.
    private static let labelBaseline: Double = 16

    var body: some View {
        // Read at body level, not inside the `Canvas` closure: SwiftUI's
        // `@Observable` tracking is only guaranteed where `body` itself reads
        // the property. This view's body previously read nothing from `model`
        // at all, so panning or zooming risked leaving the ruler frozen.
        let hasTrack = model.hasTrack
        let viewport = model.viewport
        let sampleRate = model.sampleRate
        let loop = model.loop
        let playhead = model.playhead
        let reach = model.prefs.handleReach

        Canvas(rendersAsynchronously: false) { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(palette.background.color()))
            context.fill(
                Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)),
                with: .color(palette.rule.color()))
            guard hasTrack else { return }

            for tick in RulerTicks.ticks(viewport: viewport, sampleRate: sampleRate) {
                let x = viewport.pixel(forFrame: tick.frame).rounded()
                guard x >= 0, x <= size.width else { continue }
                let height = tick.isMajor ? Self.majorTickHeight : Self.minorTickHeight
                context.fill(
                    Path(CGRect(x: x, y: size.height - height - 1, width: 1, height: height)),
                    with: .color(
                        tick.isMajor
                            ? palette.dimmed.color()
                            : palette.dimmed.color(opacity: 0.45)))

                if let label = tick.label, x + 44 < size.width {
                    context.draw(
                        Text(label)
                            .font(Typography.tick)
                            .foregroundStyle(palette.dimmed.color()),
                        at: CGPoint(x: x + 4, y: size.height - Self.labelBaseline),
                        anchor: .leading)
                }
            }

            drawLoopMarkers(in: &context, size: size, loop: loop, viewport: viewport)
            drawPlayhead(
                in: &context, size: size, frame: playhead, viewport: viewport, reach: reach)
        }
        .frame(height: Self.height)
        .contentShape(.rect)
        // A drag nobody can see is not an affordance. Asked through the same
        // function as the lanes', so the scheme lives in one place: up and
        // down everywhere, sideways over the playhead's grip.
        #if os(macOS)
        .pointerStyle(
            PointerAffordance.over(
                .timeRuler, optionHeld: false, laneDrag: nil, onPlayheadGrip: overGrip
            ).pointerStyle
        )
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                let over = model.isOverPlayheadGrip(atX: point.x)
                if over != overGrip { overGrip = over }
            case .ended:
                if overGrip { overGrip = false }
            }
        }
        #endif
        .gesture(rulerGesture)
        .onChange(of: rulerPressed) { _, pressed in
            // After this turn of the run loop, so a normal end's `onEnded` has
            // run first and this finds nothing to cancel.
            guard !pressed else { return }
            Task { @MainActor in model.rulerDragCancelled() }
        }
        // Reported for the same reason the lanes report theirs: so a pointer
        // aimed at the ruler is aimed at where the ruler actually is. Nothing
        // draws from it.
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: {
            model.setRulerFrame($0)
        }
    }

    /// Drag vertically to zoom, smoothly, anchored where the drag began — the
    /// beat-time ruler convention Ableton Live and Melodyne both document, and
    /// the only continuous zoom control the app has that needs no modifier and
    /// no trackpad. Horizontal travel is ignored; see
    /// `ViewerModel.zoomDragChanged`.
    ///
    /// **Except sideways from the playhead's grip, which scrubs** (2026-11) —
    /// see `PlayheadScrub`. An up-or-down drag from the grip is still the zoom,
    /// so a zoom started at the playhead works as it always did.
    ///
    /// `coordinateSpace: .local` puts `x` in the ruler's own points, which is
    /// the space the viewport maps from — the ruler and the lanes are siblings
    /// in the same full-width `VStack`, so a point means the same thing in
    /// both, and both draw through `viewport.pixel(forFrame:)`.
    private var rulerGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($rulerPressed) { _, pressed, _ in pressed = true }
            .onChanged { model.rulerDragChanged(start: $0.startLocation, current: $0.location) }
            .onEnded { _ in model.rulerDragEnded() }
    }

    /// The loop shown as a bar spanning the region, so the in and out points stay
    /// findable when the lanes are busy — the same job the selection markers do.
    private func drawLoopMarkers(
        in context: inout GraphicsContext, size: CGSize, loop: LoopRegion, viewport: Viewport
    ) {
        guard !loop.range.isEmpty else { return }
        let startX = viewport.pixel(forFrame: loop.range.start)
        let endX = viewport.pixel(forFrame: loop.range.end)
        guard endX > 0, startX < size.width else { return }
        let opacity = loop.isEnabled ? 1.0 : Palette.loopDisabledOpacity
        let left = max(0, startX)
        let width = max(1, min(size.width, endX) - left)
        context.fill(
            Path(CGRect(x: left, y: 0, width: width, height: 3)),
            with: .color(palette.loop.color(opacity: opacity)))
    }

    /// The playhead marker, and its grip. Drawn last so it is never hidden
    /// under a loop bar or a selection post.
    ///
    /// The grip says "drag me" the way the loop's edges do (`PlayheadGrip`,
    /// the loop grips' shape), in the playhead's own colour so the two are
    /// never confused — and here on the ruler, where it shares nothing with
    /// the loop's gestures in the lanes.
    private func drawPlayhead(
        in context: inout GraphicsContext, size: CGSize, frame: FrameIndex, viewport: Viewport,
        reach: HandleReach
    ) {
        let x = viewport.pixel(forFrame: frame)
        guard x >= 0, x <= size.width else { return }
        context.fill(
            Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)),
            with: .color(palette.accent.color()))
        let tab = PlayheadGrip.tab(atX: x, rulerHeight: size.height, reach: reach)
        context.fill(
            Path(roundedRect: tab, cornerRadius: LoopGrip.cornerRadius(of: tab)),
            with: .color(palette.accent.color()))
        for line in LoopGrip.gripLines(in: tab) {
            context.fill(Path(line), with: .color(palette.background.color(opacity: 0.85)))
        }
    }
}
