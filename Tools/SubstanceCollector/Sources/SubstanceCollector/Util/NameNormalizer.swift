import Foundation

/// Substance-name normalization used as the dedup fallback when neither
/// InChIKey nor PubChem CID is available. Lowercases, strips stereochemistry
/// prefixes and common salt suffixes, and removes all non-alphanumerics.
enum NameNormalizer {
    private static let prefixes = [
        "(+)-", "(-)-", "(±)-", "(+/-)-", "(s)-", "(r)-", "(rs)-",
        "(2s)-", "(2r)-", "(2r,3s)-", "dl-", "d-", "l-", "rac-",
        "α-", "β-", "alpha-", "beta-", "gamma-", "γ-",
    ]

    private static let saltSuffixes = [
        " hcl", "·hcl", " hydrochloride", " hbr", " hydrobromide",
        " sulfate", " sulphate", " citrate", " mesylate", " tartrate",
        " maleate", " fumarate", " acetate", " phosphate", " besylate",
        " napsylate", " pamoate", " succinate", " hemifumarate",
        " hemisulfate", " oxalate", " freebase", " base", " ·",
    ]

    static func normalize(_ raw: String) -> String {
        var s = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Repeatedly strip prefixes (some compounds have multiple, e.g. "(s)-(+)-").
        var changed = true
        while changed {
            changed = false
            for p in prefixes where s.hasPrefix(p) {
                s = String(s.dropFirst(p.count))
                changed = true
            }
        }
        // Strip salt forms — only the suffix, then re-strip whitespace.
        for suf in saltSuffixes where s.hasSuffix(suf) {
            s = String(s.dropLast(suf.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        // Collapse to alphanumeric tokens; this also kills spaces, commas,
        // brackets, and assorted punctuation that varies across sources.
        return s.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .reduce(into: "") { $0.append(Character($1)) }
    }
}
