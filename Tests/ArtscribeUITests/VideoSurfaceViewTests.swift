import AVFoundation
import CoreVideo
import Testing
import Video

@testable import ArtscribeUI

/// The view the picture is drawn into.
@MainActor
@Suite("Video surface view")
struct VideoSurfaceViewTests {

    /// **The backing layer, not a sublayer.** Spiked on macOS 27.2: with the
    /// display layer as a sublayer, Picture in Picture showed a zoomed-in
    /// corner of the frame; as the view's own layer it at least scales. iOS's
    /// PiP is built on the same layer, so this is the shape it needs.
    @Test func theSurfaceIsBackedByADisplayLayer() {
        let view = VideoSurfaceView()
        #expect(view.displayLayer === view.layer)
        #expect(view.displayLayer.videoGravity == .resizeAspect)
    }

    @Test func showingAFrameReachesTheRenderer() throws {
        let view = VideoSurfaceView()
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(
            nil, 48, 32, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        let frame = DecodedFrame(pts: 1, duration: 0.1, pixelBuffer: try #require(buffer))
        view.show(frame)
        #expect(view.framesShown == 1)
        #expect(view.displayLayer.sampleBufferRenderer.status != .failed)
    }
}
