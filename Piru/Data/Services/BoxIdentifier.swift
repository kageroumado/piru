import Foundation

/// Everything the scanner read off one box: the text regions and barcode
/// payloads VisionKit recognized, in the order they appeared. Pure data — the
/// fixture flow builds one without a camera.
nonisolated struct BoxReading: Hashable {
    var texts: [String] = []
    var barcodes: [String] = []

    var isEmpty: Bool {
        texts.isEmpty && barcodes.isEmpty
    }
}

/// One thing the reading established, shown as a chip on the result screen.
nonisolated struct ReadChip: Hashable, Identifiable {
    enum Kind: Hashable {
        case barcode
        case brand
        case substance
        case strength
        case form
        case count
    }

    /// How sure the match is. Barcode and exact-alias hits are `.high`; a
    /// fuzzy name match and anything parsed from noisy OCR is `.medium`; an
    /// unresolved barcode is `.low`.
    enum Confidence: Hashable {
        case high
        case medium
        case low
    }

    let kind: Kind
    let text: String
    let confidence: Confidence

    var id: String {
        "\(kind)-\(text)"
    }
}

/// What a reading resolved to. `canonicalName` is the doorway to the Library
/// detail; `strength`/`packCount` are staged into logging and inventory.
nonisolated struct BoxIdentification: Hashable {
    enum Origin: Hashable {
        case barcode
        case text
    }

    let chips: [ReadChip]
    /// Canonical name of the resolved substance, `nil` when nothing local matched.
    let canonicalName: String?
    let psid: String?
    let brand: String?
    let strength: Double?
    let strengthUnit: String?
    let packCount: PackCount?
    /// Where the match came from, `nil` when nothing matched.
    let origin: Origin?
    /// The best token to search externally when nothing local matched.
    let searchToken: String?
    /// GS1 country of the first barcode, for the registry link.
    let barcodeCountry: String?

    var isResolved: Bool {
        canonicalName != nil
    }
}

/// Resolves a ``BoxReading`` locally: barcode registry first (exact), then the
/// name/alias index over the text (exact before fuzzy), with strength, form and
/// pack size parsed from the same lines. Links out only when nothing local matched.
@MainActor
enum BoxIdentifier {
    static func identify(_ reading: BoxReading) -> BoxIdentification {
        var chips: [ReadChip] = []
        var name: String?
        var psid: String?
        var brand: String?
        var origin: BoxIdentification.Origin?
        var strength = firstStrength(in: reading.texts)
        let packCount = PackCountParser.parse(lines: reading.texts)
        let form = reading.texts.lazy.compactMap(PackCountParser.form(in:)).first
        var barcodeCountry: String?

        // 1. Barcodes — the registry answers exactly or not at all.
        for payload in reading.barcodes {
            let keys = ProductCodeKey.candidates(forBarcode: payload)
            if barcodeCountry == nil, let key = keys.first {
                barcodeCountry = ProductCodeKey.countryCode(ofGTIN14: key)
            }
            if name == nil, let hit = SubstanceStore.shared.productCode(forBarcode: payload) {
                chips.append(ReadChip(kind: .barcode, text: keys.first ?? payload, confidence: .high))
                name = hit.canonicalName
                psid = hit.psid
                brand = hit.brand.map(titleCased)
                origin = .barcode
                if strength == nil, let parsed = hit.parsedStrength { strength = parsed }
            } else {
                chips.append(ReadChip(kind: .barcode, text: keys.first ?? payload, confidence: .low))
            }
        }

        // 2. A package NDC printed as text is the same key as its barcode.
        if name == nil {
            for line in reading.texts {
                if let hit = SubstanceStore.shared.productCode(forNDCText: line) {
                    chips.append(ReadChip(kind: .barcode, text: hit.gtin14, confidence: .high))
                    name = hit.canonicalName
                    psid = hit.psid
                    brand = hit.brand.map(titleCased)
                    origin = .barcode
                    if strength == nil, let parsed = hit.parsedStrength { strength = parsed }
                    break
                }
            }
        }

        // 3. Text — exact alias hits across every line before any fuzzy match,
        //    so a clean "Methylphenidate" line beats a smudged brand guess.
        var textConfidence: ReadChip.Confidence = .high
        if name == nil {
            if let resolved = firstMatch(in: reading.texts, highConfidenceOnly: true) {
                name = resolved.canonicalName
                brand = resolved.brandName
                origin = .text
            } else if let resolved = firstMatch(in: reading.texts, highConfidenceOnly: false) {
                name = resolved.canonicalName
                brand = resolved.brandName
                origin = .text
                textConfidence = .medium
            }
        }

        if let brand, brand.caseInsensitiveCompare(name ?? "") != .orderedSame {
            chips.append(ReadChip(kind: .brand, text: brand, confidence: origin == .barcode ? .high : textConfidence))
        }
        if let name {
            let substance = SubstanceLibrary.lookup(name)
            chips.append(ReadChip(kind: .substance, text: substance?.displayTitle ?? name, confidence: origin == .barcode ? .high : textConfidence))
            psid = psid ?? SubstanceLibrary.substanceUID(for: name).flatMap { PSID.compose(family: $0) }
        }
        if let strength {
            chips.append(ReadChip(kind: .strength, text: "\(strength.amount.doseFormatted) \(strength.unit)", confidence: .medium))
        }
        if let form {
            chips.append(ReadChip(kind: .form, text: formLabel(form), confidence: .medium))
        }
        if let packCount {
            chips.append(ReadChip(kind: .count, text: packLabel(packCount), confidence: .medium))
        }

        return BoxIdentification(
            chips: chips,
            canonicalName: name,
            psid: psid,
            brand: brand,
            strength: strength?.amount,
            strengthUnit: strength?.unit,
            packCount: packCount,
            origin: origin,
            searchToken: name == nil ? bestToken(in: reading.texts) : nil,
            barcodeCountry: barcodeCountry,
        )
    }

    // MARK: - Pieces

    private static func firstStrength(in lines: [String]) -> (amount: Double, unit: String)? {
        for line in lines {
            if let s = LabelMatcher.parseStrength(line) { return s }
        }
        return nil
    }

    private static func firstMatch(in lines: [String], highConfidenceOnly: Bool) -> ResolvedDrug? {
        for line in lines {
            if let resolved = LabelMatcher.resolve(ocrText: line, highConfidenceOnly: highConfidenceOnly) {
                return resolved
            }
        }
        return nil
    }

    /// The longest alphabetic token on the box — what a search engine is most
    /// likely to know when the library doesn't.
    private static func bestToken(in lines: [String]) -> String? {
        lines
            .map(LabelMatcher.bestCandidate(in:))
            .filter { $0.rangeOfCharacter(from: .letters) != nil && $0.count >= 3 }
            .max { $0.count < $1.count }
    }

    /// Registry brand strings are shouted ("CONCERTA"); read them as names.
    private static func titleCased(_ brand: String) -> String {
        brand == brand.uppercased() ? brand.capitalized : brand
    }

    private static func formLabel(_ unit: PackCount.Unit) -> String {
        switch unit {
        case .tablet: String(localized: "Tablet")
        case .capsule: String(localized: "Capsule")
        case .milliliter: String(localized: "Liquid")
        case .piece: String(localized: "Pieces")
        }
    }

    private static func packLabel(_ pack: PackCount) -> String {
        let count = pack.count.doseFormatted
        return switch pack.unit {
        case .tablet: String(localized: "\(count) tablets")
        case .capsule: String(localized: "\(count) capsules")
        case .milliliter: String(localized: "\(count) mL")
        case .piece: String(localized: "\(count) pieces")
        }
    }
}
