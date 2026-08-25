import Foundation

/// The one receptor-target normalization: `ReceptorClasses.canonicalTarget`
/// returns ``display(_:)``, `SubstanceReadModel.normalizedBindingTarget`
/// returns ``fold(_:)``, and `SignatureTarget.normalized` folds through it
/// before its exact-match switch. (`ReceptorClasses.matchTarget` deliberately
/// stays on the raw string — see its doc.)
nonisolated enum ReceptorTargetKey {
    /// Case-preserving display form: strips a non-leading parenthetical
    /// qualifier and everything after it (`"NMDA receptor (PCP site)"` →
    /// `"NMDA"`, `"MOR (+)-tramadol"` → `"MOR"`), leading enantiomer prefixes
    /// (`"(+)-"`, `"(−)-"`), and a trailing `" receptor"`/`" receptors"`.
    /// A parenthetical that opens the string is the whole name and is kept —
    /// stripping it turned `"(prodrug — no direct affinity)"` into an empty
    /// dedup key.
    static func display(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if let open = s.firstIndex(of: "("), open != s.startIndex {
            s = String(s[..<open]).trimmingCharacters(in: .whitespaces)
        }
        for prefix in ["(+)-", "(−)-", "(-)-", "(±)-"] {
            s = s.replacingOccurrences(of: prefix, with: "")
        }
        for suffix in [" receptors", " receptor"] where s.hasSuffix(suffix) {
            s = String(s.dropLast(suffix.count))
            break
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Case- and whitespace-insensitive fold of ``display(_:)``, for
    /// dictionary keys and dedup.
    static func fold(_ raw: String) -> String {
        display(raw).lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
