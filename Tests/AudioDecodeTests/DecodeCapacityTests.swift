import CoreMedia
import Testing

@testable import AudioDecode

/// The first allocation is the container's duration plus a second.
@Test func theFirstAllocationIsTheDurationPlusASecond() {
    let tenSeconds = CMTime(seconds: 10, preferredTimescale: 600)
    let elevenSecondsOfFrames = 11 * 44100
    #expect(
        AudioFileDecoder.initialCapacityFrames(duration: tenSeconds, sampleRate: 44100)
            == elevenSecondsOfFrames)
}

/// A duration that is not a number gets a minute's worth rather than a crash:
/// `Int(_:)` traps on NaN and infinity, and `.indefinite.seconds` is NaN.
@Test(arguments: [CMTime.indefinite, .invalid, .positiveInfinity, .negativeInfinity])
func aDurationThatIsNotANumberGetsAMinute(duration: CMTime) {
    #expect(
        AudioFileDecoder.initialCapacityFrames(duration: duration, sampleRate: 48000) == 60 * 48000)
}
