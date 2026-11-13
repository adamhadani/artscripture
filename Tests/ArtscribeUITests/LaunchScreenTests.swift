import Foundation
import Testing

@testable import ArtscribeUI

/// The iPhone and iPad launch screen: `App/iOS/LaunchScreen.storyboard`.
///
/// iOS draws it before any of our code runs, so none of it can be computed —
/// the colour, the image's name and its size are literals in a storyboard, each
/// of which has to agree with something that lives elsewhere, and none of which
/// fails a build when it stops agreeing. A name the catalog does not have is
/// not an error; it is an app that launches to a bare field. These read the
/// files from the repository, as `everyVideoContainerIsADocumentType` does, so
/// they run on the Mac though what they guard is iOS.
@Suite struct LaunchScreenTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // ArtscribeUITests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repository root

    private static func file(_ relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }

    private static func infoPlist() throws -> [String: Any] {
        let data = try Data(contentsOf: file("App/iOS/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: Any])
    }

    private static func storyboard() throws -> XMLDocument {
        let name = try #require(infoPlist()["UILaunchStoryboardName"] as? String)
        return try XMLDocument(contentsOf: file("App/iOS/\(name).storyboard"))
    }

    /// The root view of the one scene, which is the whole launch screen.
    private static func rootView(of document: XMLDocument) throws -> XMLElement {
        let views = try document.nodes(forXPath: "//viewController/view[@key='view']")
        #expect(views.count == 1)
        return try #require(views.first as? XMLElement)
    }

    private static func number(_ element: XMLElement, _ attribute: String) -> Double? {
        element.attribute(forName: attribute)?.stringValue.flatMap(Double.init)
    }

    /// The plist names a storyboard that exists — and names it one way only.
    /// `UILaunchScreen` is the other way to say it, and the empty dictionary
    /// this replaced is exactly what a merge would put back.
    @Test func thePlistNamesTheStoryboardAndNothingElse() throws {
        let plist = try Self.infoPlist()
        let name = try #require(plist["UILaunchStoryboardName"] as? String)
        #expect(
            FileManager.default.fileExists(atPath: Self.file("App/iOS/\(name).storyboard").path))
        #expect(plist["UILaunchScreen"] == nil, "two launch screens are declared")
        #expect(plist["UILaunchScreens"] == nil, "two launch screens are declared")
    }

    /// The field is the dark panel — the colour of the screen the app opens on,
    /// so the launch screen gives way to it without a step. Held to the palette
    /// because the storyboard cannot refer to it: change `Palette.dark.panel`
    /// and this is the only thing that says the launch screen was left behind.
    @Test func theFieldIsTheDarkPanel() throws {
        let view = try Self.rootView(of: Self.storyboard())
        let colours = try view.nodes(forXPath: "color[@key='backgroundColor']")
        let colour = try #require(colours.first as? XMLElement)
        #expect(colour.attribute(forName: "customColorSpace")?.stringValue == "sRGB")

        let panel = Palette.dark.panel
        let half = 0.5 / 255
        for (attribute, expected) in [
            ("red", panel.red), ("green", panel.green), ("blue", panel.blue)
        ] {
            let stored = try #require(Self.number(colour, attribute))
            #expect(
                abs(stored - expected) < half,
                "\(attribute) is \(stored), the panel's is \(expected)")
        }
        #expect(Self.number(colour, "alpha") == 1)
    }

    /// Every image the storyboard draws is in the catalog, at both scales a
    /// device can ask for. The PNGs themselves are generated and gitignored, so
    /// what is checked is the declaration that says where they go.
    ///
    /// **The name is compared against the directory listing, not opened.** The
    /// catalog's lookup is case-sensitive and this Mac's filesystem is not, so
    /// `Launchmark.imageset/Contents.json` opens here perfectly well for a name
    /// iOS would not find. The first version of this test did that, and a
    /// deliberate wrong-case name passed it.
    @Test func everyImageIsInTheCatalog() throws {
        let document = try Self.storyboard()
        let imageViews = try document.nodes(forXPath: "//imageView").compactMap {
            $0 as? XMLElement
        }
        #expect(!imageViews.isEmpty, "the launch screen draws no mark")

        let catalog = Self.file("App/iOS/Assets.xcassets")
        let entries = try FileManager.default.contentsOfDirectory(atPath: catalog.path)
        for imageView in imageViews {
            let name = try #require(imageView.attribute(forName: "image")?.stringValue)
            try #require(
                entries.contains("\(name).imageset"), "the catalog has no image named \(name)")
            let contents = catalog.appendingPathComponent("\(name).imageset/Contents.json")
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: contents))
            let images = (json as? [String: Any])?["images"] as? [[String: Any]] ?? []
            let filed = images.filter { $0["filename"] is String }.compactMap {
                $0["scale"] as? String
            }
            #expect(Set(filed) == ["2x", "3x"], "\(name) has files for \(filed.sorted())")
        }
    }

    /// The mark is drawn at exactly the size it was generated at.
    ///
    /// `GenerateIcon.swift` rounds every bar to whole pixels for one particular
    /// size. The image view states that size again, as two constraints, and an
    /// aspect-fit view at any other size resamples the mark — soft edges, and
    /// nothing to say why.
    @Test func theMarkIsDrawnAtTheSizeItWasGeneratedAt() throws {
        let generator = try String(contentsOf: Self.file("App/GenerateIcon.swift"), encoding: .utf8)
        let match = try #require(generator.firstMatch(of: /let launchMarkPoints = (\d+)/))
        let generated = try #require(Double(match.1))

        let document = try Self.storyboard()
        for dimension in ["width", "height"] {
            let path = "//imageView/constraints/constraint[@firstAttribute='\(dimension)']"
            let constraints = try document.nodes(forXPath: path).compactMap { $0 as? XMLElement }
            #expect(constraints.count == 1, "the mark's \(dimension) is not fixed")
            for constraint in constraints {
                #expect(Self.number(constraint, "constant") == generated)
            }
        }
    }

    /// Centred on the screen itself, not on the safe area: on a landscape phone
    /// the safe area is not centred top to bottom, and the mark would sit high.
    @Test func theMarkIsCentredOnTheScreen() throws {
        let document = try Self.storyboard()
        let view = try Self.rootView(of: document)
        let viewID = try #require(view.attribute(forName: "id")?.stringValue)
        let mark = try #require(try document.nodes(forXPath: "//imageView").first as? XMLElement)
        let markID = try #require(mark.attribute(forName: "id")?.stringValue)

        for centre in ["centerX", "centerY"] {
            let path =
                "constraints/constraint[@firstItem='\(markID)' and @firstAttribute='\(centre)'"
                + " and @secondItem='\(viewID)' and @secondAttribute='\(centre)']"
            let found = try view.nodes(forXPath: path).compactMap { $0 as? XMLElement }
            #expect(found.count == 1, "the mark is not pinned to the screen's \(centre)")
            #expect(found.allSatisfy { Self.number($0, "constant") == nil }, "\(centre) is offset")
        }
    }

    /// No words. A launch screen is one frame for every language, so text on it
    /// is never localised — and it is where a version number goes to go stale.
    @Test func theLaunchScreenHasNoText() throws {
        let document = try Self.storyboard()
        #expect(try document.nodes(forXPath: "//label | //textField | //textView").isEmpty)
    }
}
