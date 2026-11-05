/// Decoded frames, kept sorted by presentation time.
///
/// Generic over the payload so its rules are tested on integers; the source
/// stores pixel buffers. Not thread-safe on its own — `VideoFrameSource` holds
/// it under a lock.
///
/// A frame *covers* `pts ..< pts + duration`. A time with no covering frame is
/// a miss, never "the nearest earlier frame": between two decoded stretches
/// that would be a picture from seconds ago presented as current.
struct FrameCache<Payload> {
    struct Entry {
        let pts: Double
        let duration: Double
        let payload: Payload
        var end: Double { pts + duration }
    }

    /// How far apart two frames may be and still count as one unbroken run.
    /// Timestamps come from a 600- or 90 000-tick timescale, so adjacent frames
    /// meet to within rounding, not exactly.
    static var tolerance: Double { 1e-4 }

    private(set) var entries: [Entry] = []

    var count: Int { entries.count }
    var payloads: [Payload] { entries.map(\.payload) }

    /// Adds a frame in its presentation-order place. A frame at a time already
    /// held replaces it: the same frame decoded again by a second reader.
    mutating func insert(pts: Double, duration: Double, _ payload: Payload) {
        let entry = Entry(pts: pts, duration: duration, payload: payload)
        let index = firstIndex(notBefore: pts - Self.tolerance)
        if index < entries.count, abs(entries[index].pts - pts) <= Self.tolerance {
            entries[index] = entry
        } else {
            entries.insert(entry, at: index)
        }
    }

    /// The frame shown at `time`, if one is decoded.
    func entry(at time: Double) -> Entry? {
        let index = firstIndex(notBefore: time + Self.tolerance) - 1
        guard index >= 0, time < entries[index].end - Self.tolerance / 2 else { return nil }
        return entries[index]
    }

    /// Where the unbroken run of frames starting at `time` ends, or `nil` when
    /// no frame covers `time` at all.
    func coveredEnd(from time: Double) -> Double? {
        guard let first = entry(at: time),
            var index = entries.firstIndex(where: { $0.pts == first.pts })
        else { return nil }
        var end = entries[index].end
        while index + 1 < entries.count, entries[index + 1].pts <= end + Self.tolerance {
            index += 1
            end = max(end, entries[index].end)
        }
        return end
    }

    func covers(_ window: Range<Double>) -> Bool {
        guard let end = coveredEnd(from: window.lowerBound) else { return false }
        return end >= window.upperBound - Self.tolerance
    }

    /// Drops every frame that meets none of `windows`.
    mutating func evict(outside windows: [Range<Double>]) {
        entries.removeAll { entry in
            !windows.contains { entry.pts < $0.upperBound && entry.end > $0.lowerBound }
        }
    }

    mutating func removeAll() { entries.removeAll() }

    /// Binary search: the first entry whose pts is at least `time`.
    private func firstIndex(notBefore time: Double) -> Int {
        var low = 0
        var high = entries.count
        while low < high {
            let mid = (low + high) / 2
            if entries[mid].pts < time { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
