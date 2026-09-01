import Foundation

/// Normalizes whatever the camera or the OCR read off a box into the 14-digit
/// GTIN keys the bundled `product_codes` table is keyed by (see
/// `pipeline/product_codes.py` — the two sides must agree digit for digit).
///
/// - A GS1 DataMatrix / GS1-128 payload carries its GTIN in AI `01`.
/// - EAN-13 (French CIP13, most EU boxes), EAN-8 and UPC-A are GTINs of
///   shorter length: left-pad to 14.
/// - A US package NDC printed as text (`NDC 50458-586-01`) is the same product
///   as its barcode: `003` + NDC-10 + check digit.
nonisolated enum ProductCodeKey {
    /// GS1 mod-10 check digit for a run of data digits (rightmost weight 3).
    static func checkDigit(_ digits: String) -> Character? {
        var total = 0
        for (i, ch) in digits.reversed().enumerated() {
            guard let v = ch.wholeNumberValue else { return nil }
            total += v * (i % 2 == 0 ? 3 : 1)
        }
        return Character(String((10 - total % 10) % 10))
    }

    /// A GTIN-8/12/13/14 with a verified check digit, left-padded to 14 digits;
    /// `nil` for any other string.
    static func gtin14(fromGTIN code: String) -> String? {
        let digits = code.filter(\.isNumber)
        guard [8, 12, 13, 14].contains(digits.count),
              let expected = checkDigit(String(digits.dropLast())),
              digits.last == expected
        else { return nil }
        return String(repeating: "0", count: 14 - digits.count) + digits
    }

    /// The GTIN-14 a US package NDC prints as. Accepts the hyphenated label form
    /// in any of the three configurations (4-4-2, 5-3-2, 5-4-1) — ten digits
    /// either way — and the 11-digit zero-padded 5-4-2 form, whose padding zero
    /// is dropped from whichever segment carries it.
    static func gtin14(fromNDC ndc: String) -> String? {
        let segments = ndc.split(separator: "-").map { $0.filter(\.isNumber) }
        var digits: String
        if segments.count == 3, segments.map(\.count) == [5, 4, 2] {
            // 11-digit HIPAA form: one segment was zero-padded. The padded one
            // is whichever leads with 0 — labeler (5), product (4) or package (2).
            let (l, p, k) = (segments[0], segments[1], segments[2])
            if l.first == "0" { digits = String(l.dropFirst()) + p + k }
            else if p.first == "0" { digits = l + String(p.dropFirst()) + k }
            else if k.first == "0" { digits = l + p + String(k.dropFirst()) }
            else { return nil }
        } else {
            digits = segments.joined()
        }
        guard digits.count == 10 else { return nil }
        let body = "003" + digits
        guard let check = checkDigit(body) else { return nil }
        return body + String(check)
    }

    /// Every GTIN-14 key a raw barcode payload could mean, best first: the
    /// GS1 `01` GTIN when the payload is an element string, else the payload as
    /// a plain GTIN.
    static func candidates(forBarcode payload: String) -> [String] {
        var out: [String] = []
        if let gtin = GS1Parser.parse(payload).gtin, let key = gtin14(fromGTIN: gtin) {
            out.append(key)
        }
        if let key = gtin14(fromGTIN: payload), !out.contains(key) {
            out.append(key)
        }
        return out
    }

    /// `NDC 50458-586-01` / `NDC: 0093-5211-58` — a package NDC printed on a US
    /// box. Only the three-segment package form is a product code; a two-segment
    /// product NDC names every pack size at once and has no barcode.
    private static let ndcRegex = try? NSRegularExpression(
        pattern: #"\bNDC\s*:?\s*(\d{4,5}-\d{3,4}-\d{1,2})\b"#,
        options: [.caseInsensitive],
    )

    /// The GTIN-14 of a package NDC printed in OCR text, when one is.
    static func gtin14(fromText text: String) -> String? {
        guard let regex = ndcRegex else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let ndcRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return gtin14(fromNDC: String(text[ndcRange]))
    }

    /// The GS1 company-prefix country of a GTIN — the first three digits after
    /// the indicator — for routing an unknown barcode to its national registry.
    /// Only ranges a registry link exists for are named; everything else is `nil`.
    static func countryCode(ofGTIN14 gtin: String) -> String? {
        guard gtin.count == 14, let prefix = Int(gtin.dropFirst().prefix(3)) else { return nil }
        switch prefix {
        case 0 ... 139: return "US"
        case 300 ... 379: return "FR"
        case 400 ... 440: return "DE"
        case 450 ... 459, 490 ... 499: return "JP"
        case 500 ... 509: return "GB"
        case 540 ... 549: return "BE"
        case 760 ... 769: return "CH"
        case 800 ... 839: return "IT"
        case 840 ... 849: return "ES"
        case 870 ... 879: return "NL"
        default: return nil
        }
    }
}
