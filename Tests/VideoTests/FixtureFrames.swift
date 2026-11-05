import CoreVideo
import Foundation

/// The committed test media, and the one fact the frame-index clips encode.
///
/// `frame_index.mp4` is flat grey frames whose luma is `16 + 7n` for frame `n`
/// (see `Tests/Fixtures/generate.sh`), so any pixel says which frame it came
/// from. Located by `#filePath` like the audio fixtures, which also holds on an
/// iOS simulator: it runs against the Mac's file system.
enum FixtureFrames {
    static func url(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // VideoTests
            .deletingLastPathComponent()  // Tests
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
    }

    static let indexClip = url("frame_index.mp4")
    static let rotatedClip = url("frame_index_rotated.mov")

    /// The frame number a decoded buffer shows, read from its centre luma.
    ///
    /// Expects the bi-planar video-range format the source decodes to: plane 0
    /// is luma, one byte a pixel, already in 16…235 — no range conversion.
    static func index(of buffer: CVPixelBuffer) -> Int {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return -1 }
        let row = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let luma = base.load(fromByteOffset: (height / 2) * row + width / 2, as: UInt8.self)
        return Int((Double(luma) - 16) / 7 + 0.5)
    }
}
