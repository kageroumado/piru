import Foundation

/// Formats chemical/substance names with proper capitalization following
/// chemical nomenclature conventions.
enum ChemicalNameFormatter {
    /// Chemical prefixes/segments that should be fully uppercased.
    private static let uppercaseSegments: Set<String> = [
        "lsd", "mdma", "mdea", "mda", "dmt", "thc", "cbd", "cbg", "cbn",
        "ghb", "gbl", "gaba", "dxm", "dxe", "pcp", "amt", "bzp", "dob",
        "doi", "dom", "don", "dpt", "det", "eph", "nep", "neb", "pvp",
        "php", "phip", "pbp", "2cb", "nbome", "nboh", "nbf",
        "meo", "ho", "aco", "mpt", "mipt", "dipt", "ept", "dalt",
        "met", "mal", "mmc", "cmc", "mec", "fmc", "fea", "epd",
        "fdck", "pce", "pcmo", "pcpr", "pcpy",
        "ai", "pa", "pta", "oh", "bk", "ab", "apb", "mapb",
        "ssri", "snri", "maoi", "tcp", "dck",
    ]

    /// Segments that should stay lowercase (stereochemistry, minor connectors).
    private static let lowercaseSegments: Set<String> = [
        "dl", "nor", "des", "di", "tri", "bis", "iso", "neo", "meta", "para", "ortho",
    ]

    /// Known proper-cased substance names (override everything).
    private static let knownNames: [String: String] = [
        "lsd": "LSD",
        "mdma": "MDMA",
        "mda": "MDA",
        "mdea": "MDEA",
        "dmt": "DMT",
        "thc": "THC",
        "cbd": "CBD",
        "ghb": "GHB",
        "gbl": "GBL",
        "gaba": "GABA",
        "dxm": "DXM",
        "pcp": "PCP",
        "amt": "AMT",
        "bzp": "BZP",
        "dph": "DPH",
        "dxe": "DXE",
        "opium": "Opium",
        "changa": "Changa",
        "kratom": "Kratom",
        "kanna": "Kanna",
        "kava": "Kava",
        "salvia": "Salvia",
    ]

    /// Format a TripSit drug key name into a properly capitalized substance name.
    static func format(_ rawName: String) -> String {
        let lower = rawName.lowercased().trimmingCharacters(in: .whitespaces)

        // Check known names first
        if let known = knownNames[lower.filter { $0.isLetter || $0.isNumber }] {
            return known
        }

        // Split on hyphens, preserving them
        let segments = lower.split(separator: "-", omittingEmptySubsequences: false).map(String.init)

        let formatted = segments.enumerated().map { index, segment -> String in
            let stripped = segment.filter { $0.isLetter || $0.isNumber }

            // Check if this segment should be all-uppercase (chemical abbreviation)
            if uppercaseSegments.contains(stripped) {
                return segment.uppercased()
            }

            // Numeric prefix segments like "2c", "4f", "5f", "25" stay as-is with uppercase letter
            if segment.count <= 3 && segment.first?.isNumber == true {
                return formatNumericSegment(segment)
            }

            // Standard title case for regular words
            if index == 0 || !lowercaseSegments.contains(stripped) {
                return titleCase(segment)
            }

            return segment
        }

        return formatted.joined(separator: "-")
    }

    /// Format a numeric segment like "2c" → "2C", "4f" → "4F", "25b" → "25B"
    private static func formatNumericSegment(_ segment: String) -> String {
        var result = ""
        for char in segment {
            if char.isLetter {
                result.append(char.uppercased().first!)
            } else {
                result.append(char)
            }
        }
        return result
    }

    /// Standard title case: first letter uppercase, rest lowercase.
    private static func titleCase(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }
}
