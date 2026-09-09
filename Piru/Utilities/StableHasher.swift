import Foundation

/// A content hash that is the same in every process: FNV-1a over the bytes
/// of what it is fed. `Hasher` is seeded per process, so a fingerprint that
/// must survive a relaunch (a launch cache's key, a cached row's identity)
/// is built with this instead.
nonisolated struct StableHasher {
    private var state: UInt64 = 0xCBF2_9CE4_8422_2325

    init() {}

    mutating func combine(_ value: UInt64) {
        var v = value
        withUnsafeBytes(of: &v) { combine(bytes: $0) }
    }

    mutating func combine(_ value: Int) {
        combine(UInt64(bitPattern: Int64(value)))
    }

    mutating func combine(_ value: Double) {
        combine(value.bitPattern)
    }

    mutating func combine(_ value: Date) {
        combine(value.timeIntervalSinceReferenceDate)
    }

    mutating func combine(_ value: String) {
        for byte in value.utf8 {
            state ^= UInt64(byte)
            state = state &* 0x0000_0100_0000_01B3
        }
        // A separator, so ("ab", "c") and ("a", "bc") hash apart.
        state ^= 0xFF
        state = state &* 0x0000_0100_0000_01B3
    }

    mutating func combine(bytes: some Sequence<UInt8>) {
        for byte in bytes {
            state ^= UInt64(byte)
            state = state &* 0x0000_0100_0000_01B3
        }
    }

    func finalize() -> Int {
        Int(Int64(bitPattern: state))
    }
}
