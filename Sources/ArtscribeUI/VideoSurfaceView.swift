import AVFoundation
import CoreMedia
import Video

#if os(macOS)
import AppKit
public typealias PlatformView = NSView
#else
import UIKit
public typealias PlatformView = UIView
#endif

/// A view whose own layer is an `AVSampleBufferDisplayLayer`, showing whatever
/// frame the presenter hands it.
///
/// **The backing layer, not a sublayer**, and that is measured rather than
/// taste. A spike on macOS 27.2 put the display layer in as a sublayer and
/// Picture in Picture showed a zoomed-in corner of the frame — the bug the
/// developer forums report for 26.4. As the view's own layer it scaled. iOS's
/// Picture in Picture is built on this same layer.
///
/// Frames go in marked *display immediately*: the presenter has already chosen
/// the frame for this instant from the audible position, so the layer is not
/// given a timebase of its own to second-guess it with.
public final class VideoSurfaceView: PlatformView, VideoSurface {
    /// How many frames this view has been handed. For tests and the harness.
    public private(set) var framesShown = 0

    #if os(macOS)
    public init() {
        super.init(frame: .zero)
        wantsLayer = true
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override public func makeBackingLayer() -> CALayer { AVSampleBufferDisplayLayer() }

    // swiftlint:disable:next force_cast
    public var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
    #else
    public init() {
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override public static var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    // swiftlint:disable:next force_cast
    public var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
    #endif

    private func configure() {
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = CGColor(gray: 0, alpha: 1)
    }

    public func show(_ frame: DecodedFrame) {
        guard let sample = Self.sampleBuffer(for: frame.pixelBuffer) else { return }
        let renderer = displayLayer.sampleBufferRenderer
        // A renderer that failed — the GPU was reset, the display changed —
        // stays failed until flushed, and shows nothing in the meantime.
        if renderer.status == .failed { renderer.flush() }
        renderer.enqueue(sample)
        framesShown += 1
    }

    /// Wraps a decoded buffer for the layer, marked to be shown on arrival.
    private static func sampleBuffer(for buffer: CVPixelBuffer) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
        guard let format else { return nil }
        var timing = CMSampleTimingInfo(
            duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil, imageBuffer: buffer, formatDescription: format,
            sampleTiming: &timing, sampleBufferOut: &sample)
        guard let sample,
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sample, createIfNecessary: true),
            CFArrayGetCount(attachments) > 0
        else { return nil }
        let first = unsafeBitCast(
            CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(
            first,
            Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
            Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        return sample
    }
}
