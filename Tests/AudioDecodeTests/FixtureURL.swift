import Foundation

/// A file in `Tests/Fixtures`. One copy for the whole target; there used to be
/// one per test file, four in all, each `private` and identical.
func fixture(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // AudioDecodeTests
        .deletingLastPathComponent()  // Tests
        .appendingPathComponent("Fixtures")
        .appendingPathComponent(name)
}
