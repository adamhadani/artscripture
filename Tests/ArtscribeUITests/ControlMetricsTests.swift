import Foundation
import Testing

@testable import ArtscribeUI

/// Hit-target sizing, checked as the **invariant** rather than as the numbers.
///
/// A test that asserts `target == 44` restates the source and fails the moment
/// anyone changes it for a good reason. What is worth guarding is the property
/// the numbers exist to satisfy: every surface gives a control at least the
/// region its input device needs, and the derived ratios stay in a sane
/// relationship to it whatever `target` becomes.
///
/// Walking all three surfaces in one run is the point of keying on
/// `EmptyStatePrompt.Surface` rather than `#if` — see that type. The phone case
/// is the one that was wrong in shipping code and the one `make check` on a Mac
/// would otherwise never evaluate.
@Suite("Control metrics")
struct ControlMetricsTests {

    /// `allCases`, not a list written out here: a fourth surface must arrive
    /// already covered rather than quietly uncovered.
    private static var surfaces: [EmptyStatePrompt.Surface] { EmptyStatePrompt.Surface.allCases }

    /// Apple's stated minimum for a fingertip. Restated here rather than read
    /// off the type, so a change to the source has to be a change to the test
    /// too — this is the one number that is not ours to pick.
    private static let touchMinimum: CGFloat = 44
    /// macOS has no published minimum; this is where the platform's own
    /// image-only controls sit.
    private static let pointerMinimum: CGFloat = 24

    @Test("every surface meets the minimum hit region for its input device")
    func meetsTheGuidance() {
        for surface in Self.surfaces {
            let m = ControlMetrics.metrics(for: surface)
            let floor = surface == .desktop ? Self.pointerMinimum : Self.touchMinimum
            #expect(m.target >= floor, "\(surface) targets \(m.target), needs \(floor)")
        }
    }

    /// The chrome is *drawn* smaller than the region that answers it, and
    /// `hitRegion(target:drawn:)` makes up the difference — see
    /// `ControlMetrics.chromeHeight`, which exists because drawing at the full
    /// 44 pt gave a header whose Open… button touched the rules above and below.
    ///
    /// Two bounds, and the lower one matters as much: a region much taller than
    /// what it draws is a control that swallows taps meant for its neighbour.
    @Test("drawn chrome sits inside its hit region without disappearing into it")
    func chromeIsSmallerThanTheRegionButNotLost() {
        for surface in Self.surfaces {
            let m = ControlMetrics.metrics(for: surface)
            #expect(m.chromeHeight <= m.target, "\(surface) draws outside its own target")
            #expect(
                m.chromeHeight >= m.target * 0.6,
                "\(surface) draws \(m.chromeHeight) inside a \(m.target) region — too invisible")
            // The transport is drawn between the two: never smaller than the
            // header's chrome, never outside its own target.
            #expect(m.buttonHeight >= m.chromeHeight, "\(surface) transport smaller than header")
            #expect(m.buttonHeight <= m.target, "\(surface) transport draws outside its target")
        }
    }

    /// The user's call (2026-11), from four layouts rendered on a phone: on
    /// touch the transport — what gets pressed most — is drawn at the full
    /// target, taller than the header's inset chrome, and a 64 pt row stands
    /// over a one-line status bar instead of a 44 pt row under a two-line one.
    @Test("on touch the transport is drawn at the full target, above the header's chrome")
    func touchTransportIsFullHeight() {
        for surface in [EmptyStatePrompt.Surface.tabletWithDrop, .phone] {
            let m = ControlMetrics.metrics(for: surface)
            #expect(m.buttonHeight == m.target)
            #expect(m.buttonHeight > m.chromeHeight)
            #expect(m.buttonHeight + 2 * m.rowPadding == 64)
        }
    }

    /// The expansion has to be real, and it has to cost nothing on a Mac, whose
    /// chrome already clears the pointer minimum.
    @Test("the hit region is grown only where the chrome falls short")
    func theRegionIsGrownOnlyWhereNeeded() {
        let desktop = ControlMetrics.metrics(for: .desktop)
        #expect(desktop.chromeHeight == desktop.target, "the Mac should need no expansion")

        let phone = ControlMetrics.metrics(for: .phone)
        #expect(phone.chromeHeight < phone.target, "touch chrome should be inset from its region")
    }

    /// The bar has to be tall enough to hold the region it hands out, or a
    /// transport button's 44 pt band reaches into the status bar below it and
    /// starts taking touches meant for the volume slider.
    @Test("a bar is tall enough to contain the targets it draws")
    func barsContainTheirTargets() {
        for surface in Self.surfaces {
            let m = ControlMetrics.metrics(for: surface)
            let row = m.buttonHeight + 2 * m.rowPadding
            let header = m.chromeHeight + 2 * m.barPadding
            #expect(row >= m.target, "\(surface) transport row \(row) < target \(m.target)")
            #expect(header >= m.target, "\(surface) header \(header) < target \(m.target)")
        }
    }

    /// The width floor is allowed to sit under the target, and this records
    /// *why*: fourteen transport buttons at full width do not cross a phone in
    /// landscape, and the system keyboard makes the same trade. What is not
    /// allowed is squeezing past the point where two neighbours read as one
    /// key, so the compact width plus the gap must still clear three quarters
    /// of the target.
    @Test("a compressed button still reads as its own key")
    func compressionHasAFloor() {
        for surface in Self.surfaces {
            let m = ControlMetrics.metrics(for: surface)
            #expect(m.compactWidth <= m.buttonWidth, "\(surface) cannot compress at all")
            #expect(
                m.compactWidth + m.spacing >= m.target * 0.75,
                "\(surface) squeezes to \(m.compactWidth) + \(m.spacing) gap")
        }
    }

    /// **The regression this test was written for happened.** Deriving the
    /// group padding and the bar inset from `target` looked principled and put
    /// 132 pt of group padding and 37 pt of bar inset on a phone; the transport
    /// row then overflowed the safe area on both sides and drew under the
    /// notch. Whitespace is not a hit target.
    ///
    /// Checked against the narrowest screen the app runs on: **iPhone in
    /// landscape, about 734 pt**, measured off a screenshot once the safe areas
    /// are taken off rather than assumed.
    @Test("the tightest transport row fits an iPhone in landscape")
    func theDenseRowFitsTheNarrowestScreen() {
        let m = ControlMetrics.metrics(for: .phone)
        let needed = TransportDensity.width(
            buttonWidth: m.compactWidth, readoutsAtFloor: true, row: Self.row, metrics: m)
        #expect(needed <= 734, "the transport row needs \(needed) pt of 734")
    }

    /// The whole point of measuring: more room buys a roomier row, and the
    /// order is monotone. A density that widened as the screen narrowed would
    /// be worse than no adaptation at all.
    @Test("more width buys a roomier row, and never the other way round")
    func densityIsMonotone() {
        let m = ControlMetrics.metrics(for: .phone)
        var last: CGFloat = 0
        for available in stride(from: CGFloat(600), through: 1600, by: 50) {
            let width = TransportDensity.fitting(available: available, row: Self.row, metrics: m)
                .buttonWidth
            #expect(width >= last, "narrowing at \(available) pt: \(last) -> \(width)")
            last = width
        }
        #expect(last == m.buttonWidth, "an iPad-width row never reaches the preferred width")
    }

    /// **The phone's row stretches its buttons to fill it** rather than dropping
    /// to the floor. With fixed steps (55, 44, 30) a landscape phone fell to 30
    /// and left about 110 pt of the row empty — the user: *"stretch out buttons
    /// horizontally a bit so doesn't look weird and fills up the space more
    /// naturally"*. The width chosen is the widest that fits: one point more
    /// would not.
    @Test("a phone's transport stretches its buttons to fill the row")
    func thePhoneRowStretches() {
        let m = ControlMetrics.metrics(for: .phone)
        let available: CGFloat = 750  // an iPhone 17 Pro in landscape, safe area off
        let density = TransportDensity.fitting(available: available, row: Self.phoneRow, metrics: m)
        let width = density.buttonWidth
        #expect(width > m.compactWidth && width < m.buttonWidth, "\(width) pt")
        #expect(!density.readoutsAtFloor)
        let needed = { (w: CGFloat) in
            TransportDensity.width(
                buttonWidth: w, readoutsAtFloor: false, row: Self.phoneRow, metrics: m)
        }
        #expect(needed(width) <= available, "the stretched row overflows: \(needed(width))")
        #expect(needed(width + 1) > available, "\(width) pt is not the widest that fits")
    }

    /// A ⏪ runs about 1.4× its point size across: a glyph sized for a wide
    /// button clipped both sides of a 30 pt one when the mocks were rendered.
    @Test("a transport glyph never outgrows its button, and is full size when it can be")
    func theGlyphFitsTheButton() {
        for surface in Self.surfaces {
            let m = ControlMetrics.metrics(for: surface)
            for width in stride(from: m.compactWidth, through: m.buttonWidth, by: 1) {
                let glyph = TransportDensity.glyph(forWidth: width, metrics: m)
                #expect(glyph * 1.4 < width, "\(surface): \(glyph) pt in \(width) pt")
                #expect(glyph <= m.buttonGlyph)
            }
            #expect(TransportDensity.glyph(forWidth: m.buttonWidth, metrics: m) == m.buttonGlyph)
        }
    }

    /// Zero is what the first layout pass reports, before any geometry exists.
    /// Guessing wide there draws one frame of a row hanging out under the notch.
    @Test("an unmeasured bar starts tight rather than wide")
    func unmeasuredStartsTight() {
        let m = ControlMetrics.metrics(for: .phone)
        let density = TransportDensity.fitting(available: 0, row: Self.row, metrics: m)
        #expect(density.buttonWidth == m.compactWidth)
        #expect(density.readoutsAtFloor)
    }

    /// The bar as `TransportBarView` builds it. Written out rather than read
    /// from the view, so a control added to the bar without updating the
    /// arithmetic shows up here as a stale number rather than as agreement.
    private static let row = TransportDensity.Row(
        buttons: TransportControl.allCases.count,
        groups: TransportControl.groups.count,
        gaps: TransportControl.groups.reduce(0) { $0 + max(0, $1.count - 1) },
        speedPreferred: 46, speedFloor: 38,
        sliderPreferred: 92, sliderFloor: 56,
        labelPreferred: 58, labelFloor: 40,
        pitchGap: Metrics.sm, slack: Metrics.md)

    /// The phone's bar: no zoom buttons and, for audio, no Video button.
    private static let phoneRow: TransportDensity.Row = {
        let groups = TransportControl.groups.map {
            $0.filter { ![.zoomIn, .zoomOut, .video].contains($0) }
        }.filter { !$0.isEmpty }
        return TransportDensity.Row(
            buttons: groups.reduce(0) { $0 + $1.count }, groups: groups.count,
            gaps: groups.reduce(0) { $0 + max(0, $1.count - 1) },
            speedPreferred: 46, speedFloor: 38, sliderPreferred: 92, sliderFloor: 56,
            labelPreferred: 58, labelFloor: 40, pitchGap: Metrics.sm, slack: Metrics.md)
    }()

    @Test("the derived shape stays proportional to the target")
    func ratiosHold() {
        for surface in Self.surfaces {
            let m = ControlMetrics.metrics(for: surface)
            #expect(m.buttonWidth > m.buttonHeight, "\(surface) buttons are not key-shaped")
            #expect(m.spacing > 0 && m.spacing < m.groupPadding, "\(surface) grouping is flat")
            #expect(m.cornerRadius < m.target / 2, "\(surface) buttons are capsules")
            #expect(m.glyph < m.target, "\(surface) glyph overflows its button")
            #expect(m.buttonGlyph < m.buttonHeight, "\(surface) transport glyph overflows")
        }
    }

    /// The regression this file exists for. The overflow menu was a 15 pt glyph
    /// with no frame — a 15 × 15 pt target, on the **only** route to Settings,
    /// Shortcuts, Practice and About that a device without a hardware keyboard
    /// has.
    @Test("a touch surface's target is comfortably larger than the old bare glyph")
    func theReportedDefectCannotReturn() {
        let oldBareGlyph: CGFloat = 15
        for surface in [EmptyStatePrompt.Surface.tabletWithDrop, .phone] {
            #expect(ControlMetrics.metrics(for: surface).target > oldBareGlyph * 2.5)
        }
    }

    // MARK: - Dynamic Type

    @Test("larger text grows the targets")
    func typeScaleGrowsTargets() {
        let base = ControlMetrics.metrics(for: .phone)
        let grown = base.scaled(by: 1.2)
        #expect(grown.target > base.target)
        #expect(grown.glyph > base.glyph)
        #expect(grown.compactWidth > base.compactWidth)
    }

    /// **iPhone is landscape-only**, so the short axis is about 402 pt and the
    /// chrome is competing with the waveform for it. An unclamped
    /// `@ScaledMetric` passes 2× at the accessibility sizes, which would leave
    /// the instrument as a stripe.
    @Test("growth is clamped, and never shrinks below the guidance")
    func typeScaleIsClamped() {
        let base = ControlMetrics.metrics(for: .phone)
        let huge = base.scaled(by: 4)
        #expect(huge.target == base.target * ControlMetrics.maximumTypeScale)

        // A smaller text setting must not take a target back under 44.
        let small = base.scaled(by: 0.6)
        #expect(small.target == base.target)
    }

    @Test("padding does not follow the text size")
    func whitespaceDoesNotScale() {
        let base = ControlMetrics.metrics(for: .desktop)
        let grown = base.scaled(by: ControlMetrics.maximumTypeScale)
        #expect(grown.barPadding == base.barPadding)
        #expect(grown.rowPadding == base.rowPadding)
    }

    // MARK: - The Mac must not move

    /// The ratios were derived from the Mac layout this replaces, and that is
    /// the evidence they are the right ratios. If a future edit to `target`
    /// drifts them, the desktop changes appearance for no reason anyone asked
    /// for — so the old hand-tuned numbers are pinned here.
    @Test("the desktop reproduces the layout it had before this type existed")
    func desktopIsUnchanged() {
        let m = ControlMetrics.metrics(for: .desktop)
        #expect(abs(m.buttonWidth - 30) < 0.25)
        #expect(abs(m.buttonHeight - 24) < 0.25)
        #expect(abs(m.spacing - 3) < 0.25)
        #expect(abs(m.groupPadding - 7) < 0.25)
        #expect(abs(m.cornerRadius - 5) < 0.25)
        #expect(abs(m.barInset - 10) < 0.25)
        #expect(m.glyph == 13)
        #expect(m.barPadding == 9)
        #expect(m.rowPadding == 5)
        #expect(m.buttonGlyph == 13)
        // The stretch never touches a Mac: its preferred and floor widths are
        // the same 30 pt, so there is nothing between them to stretch into.
        #expect(m.compactWidth == m.buttonWidth)
    }
}

/// The keyboard map's key caps.
@Suite("Keyboard key caps")
struct KeyboardMetricsTests {

    /// **A glyph that moves with the length of the caption under it.** The cap
    /// is a centred stack of glyph over caption; a two-line caption pushed its
    /// glyph up and a one-line caption left it lower, so across a board the
    /// letters would not sit still. Reserving two lines' worth for every
    /// caption fixes the glyph's position whatever the caption says.
    @Test("a caption reserves the same height whether it wraps or not")
    func captionHeightDoesNotDependOnTheText() {
        for side in [Double(200), 600, 1200] {
            let m = KeyboardMetrics(size: CGSize(width: side * 3, height: side))
            #expect(
                m.labelHeight >= m.labelSize * 2,
                "\(side): \(m.labelHeight) cannot hold two lines of \(m.labelSize)")
            // And not so tall it swallows the glyph's own row.
            #expect(m.labelHeight + m.glyphSize <= m.keyHeight * 1.2, "\(side): cap overflows")
        }
    }
}

/// Key-cap captions on the keyboard map.
///
/// The board carries one type size, so a caption that will not fit has to give
/// in words rather than in points — see `KeyCapCaption`. What is worth guarding
/// is that **every entry in the real catalog** fits at every key size the board
/// actually draws labels at, because the one that does not is the one nobody
/// looks at until a user reports a smear.
@Suite("Key cap captions")
struct KeyCapCaptionTests {

    @Test("a caption that already fits is left exactly as it was")
    func shortTitlesAreUntouched() {
        #expect(KeyCapCaption.caption(for: "Loop", perLine: 9) == "Loop")
        #expect(KeyCapCaption.caption(for: "Nudge Forward", perLine: 9) == "Nudge Forward")
        // Two words, two lines, nine characters each — the boundary case.
        #expect(KeyCapCaption.caption(for: "Selection → Loop", perLine: 9) == "Selection → Loop")
    }

    /// An authored short name wins over the title, and over the mechanical
    /// abbreviation, and does so at *every* width — so a cap does not reword
    /// itself as the window is resized.
    @Test("an action with a short name uses it")
    func shortNamesWin() {
        #expect(KeyCapCaption.caption(for: "Move Loop Left", perLine: 9) == "Loop ←")
        #expect(KeyCapCaption.caption(for: "Move Loop Left", perLine: 40) == "Loop ←")
    }

    /// Nothing else is abbreviated mechanically today, but the rule is what
    /// catches an action added tomorrow whose title is long and whose short
    /// name nobody wrote.
    @Test("a title with no short name still gives up a word rather than fitting badly")
    func longTitlesAbbreviate() {
        #expect(KeyCapCaption.caption(for: "Widen Selection Now", perLine: 9) == "Widen Sel. Now")
    }

    @Test("a word longer than the line is never left to be truncated")
    func overlongWordsAbbreviate() {
        #expect(KeyCapCaption.fits("Selection", perLine: 6, lines: 2) == false)
        #expect(KeyCapCaption.caption(for: "Clear Selection", perLine: 6) == "Clear Sel.")
    }

    /// The whole catalog, at the smallest board that still draws labels and at
    /// a comfortable one. A failure here names the entry.
    @Test("every action's caption fits a key cap at every size labels are drawn")
    func theCatalogFits() {
        for side in [Double(260), 400, 700, 1200] {
            let m = KeyboardMetrics(size: CGSize(width: side * 3, height: side))
            guard m.showsLabels else { continue }
            let perLine = KeyCapCaption.charactersPerLine(
                width: m.unit - KeyboardMetrics.gap, labelSize: m.labelSize)
            // The last resort is `minimumScale`, which buys proportionally
            // more characters per line. Nothing may need more than that,
            // because past it the text engine truncates instead of shrinking.
            let floor = Int(Double(perLine) / KeyCapCaption.minimumScale)
            for entry in ActionCatalog.entries {
                let caption = KeyCapCaption.caption(for: entry.title, perLine: perLine)
                #expect(
                    KeyCapCaption.fits(caption, perLine: floor, lines: 2),
                    "\(entry.title) -> \(caption) does not fit \(floor) chars at \(side)")
            }
        }
    }
}
