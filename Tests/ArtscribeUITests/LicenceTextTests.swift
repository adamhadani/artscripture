import Foundation
import Testing

@testable import ArtscribeUI

/// The full licence text behind every row of the About panel's list.
///
/// The list used to name each component and its terms — "Signalsmith Stretch —
/// MIT" — and stop there. MIT's single condition is that "the above copyright
/// notice and this permission notice shall be included in all copies", and the
/// name of a licence includes neither; the GPL likewise wants the recipient given
/// the licence itself. The iPhone/iPad build carried no licence text at all.
///
/// So each row now opens its text, bundled in `Resources/Licences`, and these
/// tests hold the two things that make that true: every row on every platform
/// has a text that says what its licence requires it to say, and every bundled
/// copy is still byte-identical to the one in `LICENSE` / `LICENSES/`.
@Suite struct LicenceTextTests {
    private static func licence(_ component: String, on platform: AboutPlatform) -> AboutLicence? {
        AboutInfo.licences(on: platform).first { $0.component == component }
    }

    @Test(arguments: AboutPlatform.allCases)
    func everyRowOpensAFullLicenceText(platform: AboutPlatform) {
        for licence in AboutInfo.licences(on: platform) {
            let text = licence.fullText ?? ""
            #expect(
                text.count > 500,
                "\(platform): \(licence.component) opens \(text.count) characters of licence")
        }
    }

    /// Both halves of what MIT requires to travel with the binary — the copyright
    /// line and the permission notice — on the build where Signalsmith is the
    /// *only* stretcher, which is also the one sold through the App Store.
    @Test(arguments: [
        ("Signalsmith Stretch", "Copyright (c) 2022 Geraint Luff / Signalsmith Audio Ltd."),
        ("Signalsmith Linear", "Copyright (c) 2025 Signalsmith Audio")
    ])
    func theMITRowsCarryTheirCopyrightAndPermissionNotice(component: String, holder: String) {
        let text = Self.licence(component, on: .iPadOS)?.fullText ?? ""
        #expect(text.contains(holder), "\(component): no copyright line")
        #expect(text.contains("Permission is hereby granted"), "\(component): no permission notice")
    }

    /// Version **3**, because the macOS binary is the combined work and is
    /// distributed under v3 — and the preface has to say where the source is.
    @Test func rubberBandOpensTheGPLThisBuildIsDistributedUnder() {
        let text = Self.licence("Rubber Band Library", on: .macOS)?.fullText ?? ""
        #expect(text.contains("Particular Programs Ltd"))
        #expect(text.contains("GNU GENERAL PUBLIC LICENSE"))
        #expect(text.contains("Version 3, 29 June 2007"))
        #expect(text.contains("https://github.com/adamhadani/artscripture/releases"))
    }

    @Test func libsamplerateOpensItsBSDNotice() {
        let text = Self.licence("libsamplerate", on: .macOS)?.fullText ?? ""
        #expect(text.contains("Erik de Castro Lopo"))
        #expect(text.contains("Redistribution and use in source and binary forms"))
    }

    @Test func artscriptureOpensApacheWithItsCopyright() {
        let text = Self.licence("Artscripture", on: .iPadOS)?.fullText ?? ""
        #expect(text.contains("Copyright 2026 Adam Ever-Hadani"))
        #expect(text.contains("Apache License"))
        #expect(text.contains("Version 2.0, January 2004"))
    }

    @Test func theSampleTrackOpensCC0() {
        let text = Self.licence(SampleTrack.title, on: .iPadOS)?.fullText ?? ""
        #expect(text.contains("Kimiko Ishizaka"))
        #expect(text.contains("CC0 1.0 Universal"))
    }

    /// The iPhone/iPad list's claim to contain no GPL code is about the *code*.
    /// Its texts must not drift into contradicting it either.
    @Test func noIPadOSRowOpensTheGPL() {
        for licence in AboutInfo.licences(on: .iPadOS) {
            #expect(
                !(licence.fullText ?? "").contains("GNU GENERAL PUBLIC LICENSE"),
                "\(licence.component) opens the GPL on the build that has no GPL code")
        }
    }

    // MARK: - The bundled copies are the repository's copies

    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // ArtscribeUITests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()

    /// Two copies of each text exist — `LICENSE`/`LICENSES/` is what a reader of
    /// the repository finds, `Resources/Licences` is what ships — and two copies
    /// drift. This is what stops them.
    @Test(arguments: [
        ("Apache-2.0", "LICENSE"),
        ("MIT-signalsmith-stretch", "LICENSES/MIT-signalsmith-stretch.txt"),
        ("MIT-signalsmith-linear", "LICENSES/MIT-signalsmith-linear.txt"),
        ("GPL-3.0", "LICENSES/GPL-3.0.txt"),
        ("BSD-2-Clause-libsamplerate", "LICENSES/BSD-2-Clause-libsamplerate.txt"),
        ("CC0-1.0", "LICENSES/CC0-1.0.txt")
    ])
    func theBundledCopyIsTheRepositorysCopy(resource: String, path: String) throws {
        let bundled = try #require(
            AboutLicence.bundledText(named: resource), "\(resource).txt is not in the bundle")
        let original = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(path), encoding: .utf8)
        #expect(bundled == original, "\(resource).txt has drifted from \(path)")
    }

    /// And the list of copies above is the list the panel uses: a row added
    /// without a matching entry there would ship a text nothing checks.
    @Test func everyRowsTextIsOneTheDriftCheckCovers() {
        let checked: Set = [
            "Apache-2.0", "MIT-signalsmith-stretch", "MIT-signalsmith-linear", "GPL-3.0",
            "BSD-2-Clause-libsamplerate", "CC0-1.0"
        ]
        for platform in AboutPlatform.allCases {
            for licence in AboutInfo.licences(on: platform) {
                #expect(
                    checked.contains(licence.textResource), "\(licence.textResource) is unchecked")
            }
        }
    }
}
