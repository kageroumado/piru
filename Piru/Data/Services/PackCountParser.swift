import Foundation

/// What a box says it holds, read from its printed text: "30 comprimés",
/// "28 tablets", "100 Stück", "20 capsules", "30 mL", "2 × 14 tablets".
nonisolated struct PackCount: Hashable {
    enum Unit: Hashable {
        case tablet
        case capsule
        case milliliter
        /// A countable noun the parser recognized as a pack unit but has no
        /// dosage form for ("Stück", "pieces", "doses").
        case piece
    }

    let count: Double
    let unit: Unit

    /// The inventory unit this pack counts in.
    var inventoryUnit: String {
        switch unit {
        case .tablet: "tabs"
        case .capsule: "caps"
        case .milliliter: "mL"
        case .piece: "pieces"
        }
    }
}

/// Reads a pack size out of label text. Pure: the count is always parsed from
/// what the box *says*, never counted from the image.
nonisolated enum PackCountParser {
    /// Countable pack nouns, singular/plural, in the languages a tourist's box
    /// is likely printed in. Each maps to its `PackCount.Unit`.
    private static let tabletNouns = [
        "tablets?", "tabs?", "comprim[ée]s?", "tabletten", "tabletas?", "compresse", "comprimidos?",
        "pills?", "caplets?", "dragees?", "drag[ée]es?", "lozenges?", "pastilles?", "tabl\\.?",
        "錠", "片",
    ]
    private static let capsuleNouns = [
        "capsules?", "caps", "g[ée]lules?", "kapseln", "c[áa]psulas?", "softgels?", "gelcaps?",
        "胶囊", "膠囊", "粒",
    ]
    private static let pieceNouns = [
        "st[üu]ck", "st\\.", "pieces?", "pcs", "units?", "doses?", "sachets?", "patches?", "films?",
        "suppositor(?:y|ies)", "ampoules?", "ampules?", "vials?", "個", "个",
    ]

    private static func alternation(_ nouns: [String]) -> String {
        "(?:" + nouns.joined(separator: "|") + ")"
    }

    /// `N × M noun` / `N x M noun` — blisters of M. Both numbers multiply.
    private static let multipliedRegex = try? NSRegularExpression(
        pattern: #"(?<![\d.,])(\d{1,3})\s*[x×]\s*(\d{1,4})\s*(?:(\#(alternation(tabletNouns)))|(\#(alternation(capsuleNouns)))|(\#(alternation(pieceNouns))))?(?![\p{L}\d])"#,
        options: [.caseInsensitive],
    )

    /// `N noun` — "30 comprimés", "28 Tablets", "100 Stück".
    private static let countedRegex = try? NSRegularExpression(
        pattern: #"(?<![\d.,x×]\s?)(\d{1,4})\s*(?:(\#(alternation(tabletNouns)))|(\#(alternation(capsuleNouns)))|(\#(alternation(pieceNouns))))(?![\p{L}])"#,
        options: [.caseInsensitive],
    )

    /// `N mL` — a liquid's volume. A number followed by a *mass* unit is a
    /// strength, not a pack size, so only volume counts here.
    private static let volumeRegex = try? NSRegularExpression(
        pattern: #"(?<![\d.,/])(\d{1,4}(?:[.,]\d{1,2})?)\s*(?:ml|mL|毫升)(?![\p{L}])"#,
        options: [],
    )

    /// "Boîte de 30", "Pack of 28", "Packung mit 20", "Contents: 30" — a count
    /// with its noun elsewhere on the box. Reported as pieces.
    private static let containerRegex = try? NSRegularExpression(
        pattern: #"(?:bo[iî]te\s+de|pack(?:ung)?\s+(?:of|mit|à|de)|contents?\s*:?|contenu\s*:?|inhalt\s*:?)\s*(\d{1,4})(?![\d\p{L}])"#,
        options: [.caseInsensitive],
    )

    /// The pack size stated in `text`, or `nil` when none is. Multiplied packs
    /// ("2 × 14") win over a bare count, a bare count over a volume, and a
    /// container phrase is the last resort.
    static func parse(_ text: String) -> PackCount? {
        let range = NSRange(text.startIndex..., in: text)

        if let regex = multipliedRegex, let m = regex.firstMatch(in: text, range: range),
           let a = number(m.range(at: 1), in: text), let b = number(m.range(at: 2), in: text) {
            return PackCount(count: a * b, unit: unit(from: m, in: text, tabletGroup: 3) ?? .piece)
        }
        if let regex = countedRegex, let m = regex.firstMatch(in: text, range: range),
           let n = number(m.range(at: 1), in: text) {
            return PackCount(count: n, unit: unit(from: m, in: text, tabletGroup: 2) ?? .piece)
        }
        if let regex = volumeRegex, let m = regex.firstMatch(in: text, range: range),
           let n = number(m.range(at: 1), in: text) {
            return PackCount(count: n, unit: .milliliter)
        }
        if let regex = containerRegex, let m = regex.firstMatch(in: text, range: range),
           let n = number(m.range(at: 1), in: text) {
            return PackCount(count: n, unit: .piece)
        }
        return nil
    }

    /// The first pack size stated across several lines of label text.
    static func parse(lines: [String]) -> PackCount? {
        for line in lines {
            if let pack = parse(line) { return pack }
        }
        return nil
    }

    /// The dosage form a line names, when it names one, independent of any
    /// count — "Extended-Release Tablets", "gélules", "Kapseln".
    static func form(in text: String) -> PackCount.Unit? {
        let range = NSRange(text.startIndex..., in: text)
        for (nouns, unit) in [(tabletNouns, PackCount.Unit.tablet), (capsuleNouns, .capsule)] {
            guard let regex = try? NSRegularExpression(
                pattern: #"(?<![\p{L}])"# + alternation(nouns) + #"(?![\p{L}])"#,
                options: [.caseInsensitive],
            ) else { continue }
            if regex.firstMatch(in: text, range: range) != nil { return unit }
        }
        return nil
    }

    private static func number(_ nsRange: NSRange, in text: String) -> Double? {
        guard nsRange.location != NSNotFound, let r = Range(nsRange, in: text) else { return nil }
        return Double(text[r].replacingOccurrences(of: ",", with: "."))
    }

    /// Which noun group matched: `tabletGroup`, +1 capsule, +2 piece.
    private static func unit(from match: NSTextCheckingResult, in _: String, tabletGroup: Int) -> PackCount.Unit? {
        if match.range(at: tabletGroup).location != NSNotFound { return .tablet }
        if match.range(at: tabletGroup + 1).location != NSNotFound { return .capsule }
        if match.range(at: tabletGroup + 2).location != NSNotFound { return .piece }
        return nil
    }
}
