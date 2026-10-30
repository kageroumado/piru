import Foundation

/// The one reader for a number the user typed or pasted into an amount,
/// volume, strength or concentration field.
///
/// `Double(_:)` alone reads only a dot decimal, and swapping every comma for a
/// dot turns a pasted "1,000" into 1 — a dose a thousand times too small. The
/// rules here read `.` and `,` by where they sit, with the locale breaking ties:
///
/// - **Both separators present:** the last one is the decimal, and everything
///   before it must be correctly grouped ("1,234.5", "1.234,5").
/// - **One separator, the locale's decimal:** a single one is the decimal; more
///   than one is read as grouping when correctly placed ("1.000.000" on an
///   English keyboard).
/// - **One separator, the locale's grouping (or a foreign one):** correct
///   grouping — a first group of 1–3 digits with no leading zero, then groups
///   of exactly three — is grouping ("1,000", "12,345,678"; "1.000" in Spanish);
///   any other single one is a decimal, because people type the other
///   convention's decimal into an app set to theirs ("1,5", "0,25", "1,23" on
///   an English keyboard; "1.5" in Spanish).
///
/// Anything else — letters, exponents, `inf`/`nan`, doubled or misplaced
/// separators, inner spaces, a bare separator — is `nil`, so a caller can tell
/// a typo from a zero. Full-width digits and separators from a CJK IME are
/// read as their ASCII forms.
nonisolated enum DecimalInput {
    /// The value of `text`, or `nil` when it is not a number.
    static func parse(_ text: String, locale: Locale = .current) -> Double? {
        var body = (text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var sign = ""
        if let first = body.first, first == "-" || first == "+" || first == "−" {
            sign = first == "+" ? "" : "-"
            body.removeFirst()
        }
        guard !body.isEmpty,
              body.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }),
              body.contains(where: \.isNumber)
        else { return nil }

        let localeDecimal: Character = locale.decimalSeparator == "," ? "," : "."
        let dots = body.count(where: { $0 == "." })
        let commas = body.count(where: { $0 == "," })

        let integer: Substring
        let fraction: Substring?
        switch (dots, commas) {
        case (0, 0):
            integer = Substring(body)
            fraction = nil
        case (_, 0), (0, _):
            let separator: Character = dots > 0 ? "." : ","
            let count = max(dots, commas)
            if separator == localeDecimal, count == 1 {
                (integer, fraction) = split(body, at: separator)
            } else if let grouped = ungrouped(Substring(body), separator: separator) {
                integer = grouped
                fraction = nil
            } else if count == 1 {
                (integer, fraction) = split(body, at: separator)
            } else {
                return nil
            }
        default:
            guard let decimalIndex = body.lastIndex(where: { $0 == "." || $0 == "," }) else { return nil }
            let decimal = body[decimalIndex]
            let grouping: Character = decimal == "." ? "," : "."
            let head = body[..<decimalIndex]
            let tail = body[body.index(after: decimalIndex)...]
            guard !tail.contains(grouping), let grouped = ungrouped(head, separator: grouping) else { return nil }
            integer = grouped
            fraction = tail
        }

        guard integer.allSatisfy(\.isNumber), fraction?.allSatisfy(\.isNumber) ?? true,
              !(integer.isEmpty && (fraction ?? "").isEmpty)
        else { return nil }
        let digits = fraction.flatMap { $0.isEmpty ? nil : "." + $0 } ?? ""
        let plain = sign + (integer.isEmpty ? "0" : String(integer)) + digits
        guard let value = Double(plain), value.isFinite else { return nil }
        return value
    }

    /// `value` as editable text for a field this parser reads back: the
    /// locale's decimal separator, no grouping, up to nine fraction digits. A
    /// dot-decimal "1.125" seeded into a Spanish field would read back as 1125.
    static func editingText(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(
            .number
                .grouping(.never)
                .precision(.fractionLength(0 ... 9))
                .locale(locale),
        )
    }

    private static func split(_ body: String, at separator: Character) -> (Substring, Substring?) {
        guard let index = body.firstIndex(of: separator) else { return (Substring(body), nil) }
        return (body[..<index], body[body.index(after: index)...])
    }

    /// `text` with its grouping separators removed, or `nil` unless it is
    /// grouped correctly: a first group of 1–3 digits that does not start with
    /// 0, then at least one group of exactly three.
    private static func ungrouped(_ text: Substring, separator: Character) -> Substring? {
        let groups = text.split(separator: separator, omittingEmptySubsequences: false)
        guard groups.count >= 2,
              let first = groups.first, (1 ... 3).contains(first.count), first.first != "0",
              groups.dropFirst().allSatisfy({ $0.count == 3 }),
              groups.allSatisfy({ $0.allSatisfy(\.isNumber) })
        else { return nil }
        return Substring(groups.joined())
    }
}
