import Foundation

/// Locale-independent, round-trippable `Double` encoding shared by canonical
/// tap identifiers. `%.17g` round-trips every `Double` and never uses locale
/// separators.
func encodeRoundTrippable(_ value: Double) -> String {
    String(format: "%.17g", value)
}

/// Order-sensitive FNV-1a digest over string tokens, independent of locale
/// and Foundation hashing seeds. Used for calibration-profile digests that
/// must be identical across machines and runs.
public struct DeterministicDigest: Equatable, Sendable {
    private var state: UInt64 = 0xcbf29ce484222325

    public init() {}

    public mutating func update(string: String) {
        for byte in string.utf8 {
            state ^= UInt64(byte)
            state = state &* 0x100000001b3
        }
        // Field separator so concatenated inputs can't collide.
        state ^= 0x1e
        state = state &* 0x100000001b3
    }

    public var value: String {
        String(format: "%016llx", state)
    }
}
