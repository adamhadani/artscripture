import Foundation
import Testing
import UniformTypeIdentifiers

@testable import ArtscribeUI

/// What the open panel and the iPad document picker will let someone choose.
///
/// The panel greys out anything whose type conforms to nothing in
/// `allowedContentTypes`, so "is this file offered" is exactly
/// `accepts(...)` below — the same decision, made without a window.
@Suite struct AudioFileTypesTests {
    private func accepts(_ type: UTType) -> Bool {
        AudioFileTypes.supported.contains { type.conforms(to: $0) }
    }

    private func accepts(extension ext: String) -> Bool {
        guard let type = UTType(filenameExtension: ext) else { return false }
        return accepts(type)
    }

    /// The bug this exists for: an `.mp4` with a picture in it is
    /// `public.mpeg-4`, which conforms to `public.movie` and *not* to
    /// `public.audio`, so it sat greyed out in the panel even though the
    /// decoder reads its soundtrack perfectly well.
    @Test(arguments: ["mp4", "mov", "m4v"])
    func thePickerOffersVideoContainersTheDecoderReads(ext: String) {
        #expect(accepts(extension: ext), ".\(ext) is greyed out in the open panel")
    }

    @Test(arguments: ["mp3", "m4a", "flac", "wav", "aiff", "caf", "opus"])
    func thePickerStillOffersAudio(ext: String) {
        #expect(accepts(extension: ext), ".\(ext) is greyed out in the open panel")
    }

    /// The tempting simplification is to add `.movie` and be done. That would
    /// offer AVI, MKV and the rest of what conforms to it — containers
    /// AVFoundation cannot open — and a picker that offers a file the app then
    /// refuses is worse than one that greys it out. The video containers are
    /// named one by one for that reason, and this keeps them so.
    @Test func thePickerDoesNotOfferEveryMovie() {
        #expect(!AudioFileTypes.supported.contains(.movie))
        #expect(!AudioFileTypes.supported.contains(.video))
        #expect(!accepts(.avi), "AVI is offered, and AVFoundation cannot decode it")
    }

    // MARK: - The document types have to agree with the picker

    /// Finder's Open With (macOS) and the share sheet's Open In (iOS) come from
    /// `CFBundleDocumentTypes`, not from the picker, so a container the picker
    /// offers but the plist omits opens one way and not the other.
    private static func documentContentTypes(plist relativePath: String) throws -> Set<String> {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ArtscribeUITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repository root
            .appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        let types = (plist as? [String: Any])?["CFBundleDocumentTypes"] as? [[String: Any]] ?? []
        return Set(types.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] })
    }

    @Test(arguments: ["App/Info.plist", "App/iOS/Info.plist"])
    func everyVideoContainerIsADocumentType(plist: String) throws {
        let declared = try Self.documentContentTypes(plist: plist)
        #expect(!AudioFileTypes.videoContainers.isEmpty)
        for type in AudioFileTypes.videoContainers {
            #expect(
                declared.contains(type.identifier), "\(plist) does not declare \(type.identifier)")
        }
    }
}
