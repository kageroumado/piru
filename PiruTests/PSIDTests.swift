import Testing
@testable import Piru

/// Mirrors `pipeline/build/tests/test_psid.py` — the two PSID implementations
/// (Python pipeline, Swift app) must agree, or a PSID minted by the build fails
/// to validate here. Pure logic; no built DB needed. See Stage 0.2 of
/// `Specs/stereoisomer-and-release-form-axes.md`.
@Suite("PSID")
struct PSIDTests {
    static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    /// The same linear-congruential generator + seed as the Python suite, so the
    /// generated payloads (and thus the exercised bodies) match byte-for-byte.
    /// A plain value (no `Sequence` conformance — that would cross the project's
    /// default `@MainActor` isolation).
    struct LCG {
        var x: UInt64
        mutating func next() -> UInt64 {
            x = (1_103_515_245 &* x &+ 12_345) & 0x7FFF_FFFF
            return x
        }
    }

    static func payloads(_ count: Int, length: Int, seed: UInt64 = 42) -> [String] {
        var g = LCG(x: seed)
        return (0 ..< count).map { _ in
            String((0 ..< length).map { _ in alphabet[Int(g.next() % 36)] })
        }
    }

    // MARK: - Check character

    @Test
    func `Check char re-derivation is stable`() {
        for body in Self.payloads(400, length: 17) {
            let chk = PSID.iso7064CheckChar(body)
            #expect(chk != nil)
            #expect(PSID.iso7064CheckChar(body) == chk)
        }
    }

    @Test
    func `Every single-character substitution is detected`() throws {
        var undetected = 0
        for body in Self.payloads(300, length: 17) {
            let full = try body + String(#require(PSID.iso7064CheckChar(body)))
            let chars = Array(full)
            for i in chars.indices {
                for c in Self.alphabet where c != chars[i] {
                    var bad = chars
                    bad[i] = c
                    let bodyPart = String(bad.dropLast())
                    if try String(#require(PSID.iso7064CheckChar(bodyPart))) == String(#require(bad.last)) {
                        undetected += 1
                    }
                }
            }
        }
        #expect(undetected == 0, "a single-character substitution went undetected")
    }

    @Test
    func `Adjacent-transposition detection is strong`() throws {
        var undetected = 0
        var total = 0
        for body in Self.payloads(300, length: 17) {
            let full = try body + String(#require(PSID.iso7064CheckChar(body)))
            let chars = Array(full)
            for i in 0 ..< (chars.count - 1) where chars[i] != chars[i + 1] {
                total += 1
                var bad = chars
                bad.swapAt(i, i + 1)
                let bodyPart = String(bad.dropLast())
                if try String(#require(PSID.iso7064CheckChar(bodyPart))) == String(#require(bad.last)) {
                    undetected += 1
                }
            }
        }
        #expect(Double(undetected) / Double(total) < 0.01, "transposition detection unexpectedly weak")
    }

    // MARK: - Family

    @Test
    func `A real InChIKey block-1 is a well-formed block-1 family`() {
        #expect(PSID.isBlock1Family("DUGOZIWVEXMGBE"))
        #expect(PSID.isWellformedFamily("DUGOZIWVEXMGBE"))
        #expect(!PSID.isNameHashFamily("DUGOZIWVEXMGBE"))
    }

    @Test
    func `Malformed families are rejected`() {
        for bad in ["", "SHORT", "toolongfamilyvalue", "dugoziwvexmgbe", "12345678901234"] {
            #expect(!PSID.isWellformedFamily(bad), "\(bad) should be malformed")
        }
    }

    @Test
    func `A name-hash family is a sentinel digit + 13 uppercase letters`() throws {
        // A real name-hash sampled from the built DB (leading sentinel digit).
        let fam = "8YKFFRXMFUODYV"
        #expect(fam.count == 14)
        #expect(try #require(fam.first?.isNumber))
        #expect(PSID.isNameHashFamily(fam))
        #expect(PSID.isWellformedFamily(fam))
        #expect(!PSID.isBlock1Family(fam))
    }

    // MARK: - Compose / parse

    @Test
    func `Compose → parse round-trips with default facets`() throws {
        let p = try #require(PSID.compose(family: "DUGOZIWVEXMGBE"))
        #expect(p.hasPrefix("P1-DUGOZIWVEXMGBE-0-0-0-"))
        #expect(PSID.isValid(p))
        let parsed = try #require(PSID.parse(p))
        #expect(parsed.family == "DUGOZIWVEXMGBE")
        #expect(parsed.stereo == "0" && parsed.salt == "0" && parsed.release == "0")
    }

    @Test
    func `Compose carries facets through parse`() throws {
        let p = try #require(PSID.compose(family: "DUGOZIWVEXMGBE", stereo: "R", release: "XR"))
        let parsed = try #require(PSID.parse(p))
        #expect(parsed.stereo == "R")
        #expect(parsed.release == "XR")
        #expect(PSID.isValid(p))
    }

    @Test
    func `A tampered check character is rejected`() throws {
        let p = try #require(PSID.compose(family: "DUGOZIWVEXMGBE"))
        let bad = String(p.dropLast()) + (p.last != "X" ? "X" : "Y")
        #expect(!PSID.isValid(bad))
        #expect(PSID.parse(bad) == nil)
    }

    @Test
    func `Structurally malformed strings are rejected`() {
        for bad in ["", "P1-DUGOZIWVEXMGBE-0-0-0", "X1-DUGOZIWVEXMGBE-0-0-0-0", "garbage"] {
            #expect(PSID.parse(bad) == nil)
        }
    }

    @Test
    func `Swift check char matches the pipeline's for a known body`() {
        // `psid.compose("DUGOZIWVEXMGBE")` in the Python suite yields these exact
        // strings (pinned so a divergence in either port trips this test).
        #expect(PSID.compose(family: "DUGOZIWVEXMGBE") == "P1-DUGOZIWVEXMGBE-0-0-0-0")
        #expect(PSID.compose(family: "DUGOZIWVEXMGBE", stereo: "R", release: "XR") == "P1-DUGOZIWVEXMGBE-R-0-XR-O")
    }
}
