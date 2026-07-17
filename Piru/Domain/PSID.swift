import Foundation

/// PSID (Piru Substance ID) primitives — the stable substance-identity scheme.
///
/// This is the Swift port of `pipeline/psid.py`; the two must stay in lockstep
/// (a change to the grammar or the check-character algorithm has to land on both
/// sides, or a PSID minted by the pipeline fails to validate in the app). The
/// pipeline is the source of truth — this port exists so the app can *validate*
/// and *compose* a PSID at its deep-link / import boundary without a round-trip.
///
/// Grammar (see `Specs/stereoisomer-and-release-form-axes.md`):
///
///     P1-<FAMILY>-<stereo>-<salt>-<release>-<chk>
///
/// - `P1` — scheme version, so the grammar can evolve without stranding stored ids.
/// - `FAMILY` — a 14-char skeleton hash. For a structure-bearing substance whose
///   InChIKey connectivity block (block 1) is unique and trusted in the catalog,
///   the FAMILY *is* that block 1 verbatim (14 uppercase letters), so it
///   cross-references PubChem. For a structure-less row, or a member of a
///   same-block-1 collision of *distinct* drugs, the FAMILY is a name-hash in the
///   same alphabet with a **sentinel leading digit** — real block-1s are always
///   14 letters, so a leading digit unambiguously marks "this is a name-hash".
/// - `<stereo>` / `<salt>` / `<release>` — the three orthogonal form facets;
///   `0` = racemic/freebase/standard (unspecified).
/// - `<chk>` — an ISO 7064 MOD 37,36 hybrid check character over the key body
///   (scheme + family + facets, separators stripped). It detects every
///   single-char substitution and nearly all adjacent transpositions, so a
///   truncated or mistyped PSID fails fast instead of silently resolving to a
///   *different* valid substance.
enum PSID {
    static let scheme = "P1"
    static let unspecifiedFacet = "0"

    /// ISO 7064 radix-36 alphabet: a character's value is its index (0-9, then A-Z).
    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private static let m = 36 // radix
    private static let n = 37 // modulus (m + 1)
    private static let familyLength = 14

    /// Value of a radix-36 alphabet character, or `nil` when out of alphabet.
    private static func value(of ch: Character) -> Int? {
        alphabet.firstIndex(of: ch)
    }

    /// ISO 7064 MOD 37,36 hybrid check character over `body` (all chars in the
    /// radix-36 alphabet). Detects every single-character substitution and
    /// nearly all adjacent transpositions. Returns `nil` if `body` contains a
    /// character outside the alphabet (a malformed body has no defined check).
    static func iso7064CheckChar(_ body: String) -> Character? {
        var p = m
        for ch in body {
            guard let v = value(of: ch) else { return nil }
            p = (p + v) % m
            if p == 0 { p = m }
            p = (p * 2) % n
        }
        return alphabet[(n - p) % m]
    }

    /// True when FAMILY is a real InChIKey connectivity block (14 uppercase
    /// ASCII letters), as opposed to a sentinel-digit name-hash.
    static func isBlock1Family(_ family: String) -> Bool {
        family.count == familyLength && family.allSatisfy(\.isUppercaseASCIILetter)
    }

    /// True when FAMILY is a name-hash (sentinel leading digit + 13 uppercase letters).
    static func isNameHashFamily(_ family: String) -> Bool {
        guard family.count == familyLength else { return false }
        var chars = Array(family)
        let first = chars.removeFirst()
        return first.isASCIIDigit && chars.allSatisfy(\.isUppercaseASCIILetter)
    }

    /// A FAMILY is either a real block-1 or a name-hash — never anything else.
    static func isWellformedFamily(_ family: String) -> Bool {
        isBlock1Family(family) || isNameHashFamily(family)
    }

    private static func body(family: String, stereo: String, salt: String, release: String) -> String {
        scheme + family + stereo + salt + release
    }

    /// The full check-valid PSID string for a FAMILY + facets, or `nil` if the
    /// family/facets aren't well-formed (so a caller can't accidentally mint a
    /// PSID the parser would reject).
    static func compose(
        family: String,
        stereo: String = unspecifiedFacet,
        salt: String = unspecifiedFacet,
        release: String = unspecifiedFacet,
    ) -> String? {
        guard isWellformedFamily(family),
              isFacet(stereo), isFacet(salt), isFacet(release),
              let chk = iso7064CheckChar(body(family: family, stereo: stereo, salt: salt, release: release))
        else { return nil }
        return "\(scheme)-\(family)-\(stereo)-\(salt)-\(release)-\(chk)"
    }

    /// A parsed PSID's structural components (the check char has already verified).
    struct Components: Equatable {
        let family: String
        let stereo: String
        let salt: String
        let release: String
    }

    /// A facet segment is one or more radix-36 alphabet characters.
    private static func isFacet(_ segment: String) -> Bool {
        !segment.isEmpty && segment.allSatisfy { value(of: $0) != nil }
    }

    /// Parse a PSID string into its components when it is well-formed AND its
    /// check character is valid; otherwise `nil`. This is the fail-fast gate for
    /// PSIDs arriving from deep links / imports.
    static func parse(_ psid: String) -> Components? {
        let parts = psid.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 6 else { return nil }
        let (scheme, family, stereo, salt, release, chk) = (parts[0], parts[1], parts[2], parts[3], parts[4], parts[5])
        guard scheme == Self.scheme, isWellformedFamily(family) else { return nil }
        guard isFacet(stereo), isFacet(salt), isFacet(release) else { return nil }
        guard chk.count == 1,
              let expected = iso7064CheckChar(body(family: family, stereo: stereo, salt: salt, release: release)),
              String(expected) == chk
        else { return nil }
        return Components(family: family, stereo: stereo, salt: salt, release: release)
    }

    /// True when `psid` parses and its check character verifies.
    static func isValid(_ psid: String) -> Bool {
        parse(psid) != nil
    }
}

private extension Character {
    /// ASCII A–Z, matching the pipeline's `isalpha() and isupper()` gate for the
    /// FAMILY alphabet without pulling in lowercase or Unicode letters.
    var isUppercaseASCIILetter: Bool {
        isASCII && isLetter && isUppercase
    }

    /// ASCII 0–9, matching the sentinel-digit test.
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
