import Foundation

/// A scanned label resolved to a Piru substance — the convergence type both the
/// barcode path (GTIN → openFDA → name) and the OCR path (text → alias match)
/// produce, and the input to QuickLog staging.
struct ResolvedDrug {
    enum Source { case barcode, ocr }

    /// The resolved canonical substance.
    let substance: Substance
    /// The scanned brand/alias the substance was recognized by ("Concerta"),
    /// preserved so the staged dose logs as the product the user holds. `nil`
    /// when the scan named the canonical substance.
    var brandName: String?
    /// Strength read off the label or barcode, in `unit`. `nil` when unreadable —
    /// staging then falls back to the substance's reference dose.
    var strength: Double?
    var unit: String?
    var route: RouteOfAdministration?
    let source: Source

    var canonicalName: String {
        substance.name
    }
    var stagingRoute: RouteOfAdministration {
        route ?? substance.defaultRoute
    }
    var stagingUnit: String {
        unit ?? substance.unit(for: stagingRoute)
    }
    /// The amount to pre-fill in QuickLog: the scanned strength, else the
    /// substance's reference (common) dose for the route, else 0.
    var stagingAmount: Double {
        strength
            ?? StagedDose.lookupReferenceDose(substance: substance, route: stagingRoute, unit: stagingUnit)
            ?? 0
    }
}

/// Turns scanned label text (or an openFDA product) into a `ResolvedDrug` by
/// fuzzy-matching against Piru's bundled substance name + alias indexes. The
/// matching itself is fully offline; only the barcode → openFDA hop upstream of
/// `resolve(product:)` touches the network.
enum LabelMatcher {
    // MARK: Strength

    /// A strength `(amount, normalized unit)` parsed from label text, e.g.
    /// `"36 mg"` → `(36, "mg")`, `"500 mcg"` → `(500, "µg")`, `"36 mg/1"` → `(36, "mg")`.
    static func parseStrength(_ text: String) -> (amount: Double, unit: String)? {
        // Digit, optional decimal, optional space, then a mass/volume unit.
        let pattern = #"(?<![\w.])(\d+(?:\.\d+)?)\s*(µg|mcg|ug|mg|g|ml|iu)(?![\w])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let amountRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let amount = Double(text[amountRange])
        else { return nil }
        return (amount, normalizedUnit(String(text[unitRange])))
    }

    private static func normalizedUnit(_ raw: String) -> String {
        switch raw.lowercased() {
        case "mcg", "ug", "µg": "µg"
        case "mg": "mg"
        case "g": "g"
        case "ml": "mL"
        case "iu": "IU"
        default: raw
        }
    }

    // MARK: Route

    /// Map an openFDA `route` list to a Piru route. First recognized entry wins.
    static func route(fromOpenFDA routes: [String]) -> RouteOfAdministration? {
        for route in routes {
            switch route.uppercased() {
            case "ORAL": return .oral
            case "SUBLINGUAL": return .sublingual
            case "BUCCAL": return .buccal
            case "NASAL": return .insufflation
            case "INHALATION", "RESPIRATORY (INHALATION)": return .inhalation
            case "INTRAVENOUS": return .intravenous
            case "INTRAMUSCULAR": return .intramuscular
            case "SUBCUTANEOUS": return .subcutaneous
            case "TRANSDERMAL", "TOPICAL": return .transdermal
            case "RECTAL": return .rectal
            default: continue
            }
        }
        return nil
    }

    // MARK: Resolution

    /// Resolve a recognized OCR text region. Parses any strength it carries, then
    /// matches the drug name against the alias index. `nil` when no substance
    /// matches — the caller then offers a manual search with `bestCandidate`.
    ///
    /// `highConfidenceOnly` restricts matching to an exact canonical/alias hit
    /// (skipping the fuzzy cascade) — the live auto-surface path uses it so the
    /// scanner only fills in a name without a tap when it is certain, never a
    /// guess.
    static func resolve(
        ocrText: String,
        source: ResolvedDrug.Source = .ocr,
        highConfidenceOnly: Bool = false,
    ) -> ResolvedDrug? {
        let strength = parseStrength(ocrText)
        guard let (substance, brand) = matchSubstance(in: ocrText, highConfidenceOnly: highConfidenceOnly)
        else { return nil }
        return ResolvedDrug(
            substance: substance,
            brandName: brand,
            strength: strength?.amount,
            unit: strength?.unit,
            route: nil,
            source: source,
        )
    }

    /// Resolve an openFDA product (from the barcode path) to a substance.
    static func resolve(product: NDCProduct) -> ResolvedDrug? {
        guard let name = product.displayName,
              let (substance, aliasBrand) = matchSubstance(in: name)
        else { return nil }
        let strength = product.strengthText.flatMap(parseStrength)
        return ResolvedDrug(
            substance: substance,
            // Prefer openFDA's own brand string; fall back to the matched alias.
            brandName: product.brandName ?? aliasBrand,
            strength: strength?.amount,
            unit: strength?.unit,
            route: route(fromOpenFDA: product.routes),
            source: .barcode,
        )
    }

    /// The best drug-name candidate to seed a manual search with when nothing
    /// resolved — the longest alphabetic run in the scanned text.
    static func bestCandidate(in text: String) -> String {
        candidateStrings(from: text).first ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Matching internals

    /// Try to resolve a substance from arbitrary label text: the whole cleaned
    /// string first (an exact alias like "Concerta"), then progressively shorter
    /// candidates. Returns the substance and the brand string it matched by (`nil`
    /// when the match was the canonical name itself).
    private static func matchSubstance(
        in text: String,
        highConfidenceOnly: Bool = false,
    ) -> (Substance, brand: String?)? {
        for candidate in candidateStrings(from: text) {
            // Exact canonical/alias hit — highest confidence, overlay-aware.
            if let substance = SubstanceLibrary.resolveFull(candidate) {
                return (substance, brand(for: candidate, substance: substance))
            }
            // Ranked fuzzy cascade for near-misses (OCR slips, casing). Skipped
            // for the high-confidence path — a fuzzy near-miss is exactly what
            // must wait for a deliberate tap, not auto-surface.
            if !highConfidenceOnly, let match = SubstanceLibrary.searchMatches(candidate, limit: 1).first {
                return (match.substance, match.matchedAlias)
            }
        }
        return nil
    }

    /// A brand label for a matched candidate — the scanned string when it isn't
    /// the canonical name, else `nil` (the substance names itself).
    private static func brand(for candidate: String, substance: Substance) -> String? {
        candidate.caseInsensitiveCompare(substance.name) == .orderedSame ? nil : candidate
    }

    /// Candidate name strings to try, in priority order: the full cleaned line,
    /// then individual words (longest first) of at least 4 characters. Strength
    /// tokens are stripped so "Concerta 36 mg" yields "Concerta". Only a number
    /// with a unit is stripped — a bare number keeps its place (so "5-HTP" stays
    /// intact); word-splitting drops any lone number on its own.
    private static func candidateStrings(from text: String) -> [String] {
        let stripped = text.replacingOccurrences(
            of: #"(?<![\w.])\d+(?:\.\d+)?\s*(µg|mcg|ug|mg|g|ml|iu)(?![\w])"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive],
        )
        let cleaned = stripped
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        var candidates: [String] = []
        let whole = cleaned.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if whole.count >= 3 { candidates.append(whole) }

        let words = cleaned
            .map { $0.trimmingCharacters(in: CharacterSet.alphanumerics.inverted) }
            .filter { $0.count >= 4 && $0.rangeOfCharacter(from: .letters) != nil }
            .sorted { $0.count > $1.count }
        for word in words where !candidates.contains(word) {
            candidates.append(word)
        }
        return candidates
    }
}
