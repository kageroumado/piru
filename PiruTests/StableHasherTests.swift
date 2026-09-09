import Foundation
import Testing
@testable import Piru

@Suite("StableHasher")
struct StableHasherTests {
    @Test
    func `The same input hashes to the same value, and the value is fixed across processes`() {
        var a = StableHasher()
        a.combine("Caffeine")
        a.combine(90.0)
        a.combine(Date(timeIntervalSinceReferenceDate: 810_000_000))
        var b = StableHasher()
        b.combine("Caffeine")
        b.combine(90.0)
        b.combine(Date(timeIntervalSinceReferenceDate: 810_000_000))
        #expect(a.finalize() == b.finalize())

        // Pinned values: a launch cache written by one build must compare
        // against fingerprints computed by the next, so the function itself
        // is part of the cache format. FNV-1a 64: the offset basis, then one
        // byte folded in followed by the string separator.
        var empty = StableHasher()
        #expect(empty.finalize() == Int(Int64(bitPattern: 0xCBF2_9CE4_8422_2325)))
        var one = StableHasher()
        one.combine("a")
        let afterA = (0xCBF2_9CE4_8422_2325 ^ UInt64(0x61)) &* 0x0000_0100_0000_01B3
        let afterSeparator = (afterA ^ 0xFF) &* 0x0000_0100_0000_01B3
        #expect(one.finalize() == Int(Int64(bitPattern: afterSeparator)))
    }

    @Test
    func `Strings are separated, so a boundary shift changes the hash`() {
        var a = StableHasher()
        a.combine("ab")
        a.combine("c")
        var b = StableHasher()
        b.combine("a")
        b.combine("bc")
        #expect(a.finalize() != b.finalize())
    }

    @Test
    func `Field order matters`() {
        var a = StableHasher()
        a.combine(1.0)
        a.combine(2.0)
        var b = StableHasher()
        b.combine(2.0)
        b.combine(1.0)
        #expect(a.finalize() != b.finalize())
    }
}
