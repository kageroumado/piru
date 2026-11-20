import Foundation

// MARK: - Quick Log Data Types

/// A recent/favorite substance with its route groups, backing one card in the
/// quick-log list. Built from the curated `QuickLogDose` rows, not raw history.
///
/// Identified by substance **identity** (``id`` = the PSID family + form facets),
/// not name — so a Concerta card (Methylphenidate·XR) and a Ritalin IR card
/// (Methylphenidate·IR) are two cards, not one merged history. See
/// ``QuickLogDose/identityKey``.
struct SubstanceCard: Identifiable, Equatable {
    /// The substance-identity key — also what favorites/staged-counts join on.
    let id: String
    /// The canonical substance name (the color key and the fallback title).
    let substanceName: String
    /// The product/form title to show ("Concerta", "Methylphenidate XR"), or
    /// `nil` for a plain card — which titles from the regionalized display name.
    let title: String?
    let tint: P3Color?
    let routes: [SubstanceGroup]
    let latestTimestamp: Date
    /// Identity components, carried so favoriting this card pins the same form.
    let substanceUID: String?
    let isomer: String?
    let releaseForm: String?
    let saltForm: String?
    let productName: String?
}

/// One (substance, route) pairing within a card, carrying its curated dose
/// chips sorted for display.
struct SubstanceGroup: Identifiable, Equatable {
    let id: String
    /// The card this group belongs to — its substance-identity key (== card id).
    let cardKey: String
    let substanceName: String
    let route: RouteOfAdministration
    let tint: P3Color?
    let librarySubstance: Substance?
    var latestTimestamp: Date
    /// Identity + product carried so a re-staged chip logs the same form/product.
    let substanceUID: String?
    let isomer: String?
    let releaseForm: String?
    let saltForm: String?
    let productName: String?

    /// One curated chip's backing data, including optional by-volume drink detail.
    private struct ChipEntry {
        var amount: Double
        var unit: String
        var sortOrder: Double
        var volumeML: Double?
        var abv: Double?
        var drinkName: String?
        var emoji: String?
    }

    private var chipEntries: [ChipEntry] = []

    /// Hand-written because `ChipEntry` isn't `Equatable`, so none is
    /// synthesized. Compares the display-relevant surface — identity, color,
    /// recency, the resolved library substance, and the rendered chips — which is
    /// exactly what a card's body draws, so two equal groups are visually
    /// interchangeable (and the card's `.equatable()` can skip rebuilding them).
    static func == (lhs: SubstanceGroup, rhs: SubstanceGroup) -> Bool {
        lhs.id == rhs.id
            && lhs.tint == rhs.tint
            && lhs.latestTimestamp == rhs.latestTimestamp
            && lhs.librarySubstance?.id == rhs.librarySubstance?.id
            && lhs.doses == rhs.doses
    }

    var doses: [DoseChip] {
        // Chips are the curated measurements the user actually logged. For a
        // by-volume substance (alcohol) a chip carries the recorded drink detail
        // (name / volume / % / grams) so it re-stages the exact drink; a plain
        // mass dose is just its amount. No hard-coded presets here — those live
        // in the editor's preset library, not the card.
        chipEntries
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { DoseChip(amount: $0.amount, unit: $0.unit, saltForm: saltForm, drinkName: $0.drinkName, emoji: $0.emoji, volumeML: $0.volumeML, abv: $0.abv) }
    }

    init(
        cardKey: String,
        substanceName: String,
        route: RouteOfAdministration,
        tint: P3Color?,
        librarySubstance: Substance?,
        latestTimestamp: Date,
        substanceUID: String? = nil,
        isomer: String? = nil,
        releaseForm: String? = nil,
        saltForm: String? = nil,
        productName: String? = nil,
    ) {
        self.id = "\(cardKey)|\(route.rawValue)"
        self.cardKey = cardKey
        self.substanceName = substanceName
        self.route = route
        self.tint = tint
        self.librarySubstance = librarySubstance
        self.latestTimestamp = latestTimestamp
        self.substanceUID = substanceUID
        self.isomer = isomer
        self.releaseForm = releaseForm
        self.saltForm = saltForm
        self.productName = productName
    }

    /// The product name to re-stage this group's chips under, so a tapped Concerta
    /// chip logs Concerta — not the canonical family. Prefers the user's literal
    /// word; for a faceted group with no product string, falls back to the composed
    /// form title ("Methylphenidate XR") so the release/isomer still round-trips
    /// through the staging pipeline (which keys off the product name). `nil` for a
    /// plain group, which stages canonically as before. Computed on tap, not in
    /// `body`, so the `formTitle` resolve is off the render path.
    var stageProductName: String? {
        if let product = productName?.trimmingCharacters(in: .whitespaces), !product.isEmpty {
            return product
        }
        let namesForm = (isomer?.isEmpty == false && isomer != "0")
            || (releaseForm?.isEmpty == false && releaseForm != "0")
        guard namesForm else { return nil }
        return SubstanceLibrary.formTitle(for: substanceName, isomer: isomer, release: releaseForm)
    }

    /// Add a curated chip (sorted by `sortOrder` for display). Tracks the most
    /// recent use so cards order by recency. By-volume detail rides along for
    /// alcohol drinks; `nil` for ordinary mass doses.
    mutating func addChip(
        amount: Double,
        unit: String,
        sortOrder: Double,
        lastUsedAt: Date,
        volumeML: Double? = nil,
        abv: Double? = nil,
        drinkName: String? = nil,
        emoji: String? = nil,
    ) {
        chipEntries.append(ChipEntry(
            amount: amount, unit: unit, sortOrder: sortOrder,
            volumeML: volumeML, abv: abv, drinkName: drinkName, emoji: emoji,
        ))
        if lastUsedAt > latestTimestamp {
            latestTimestamp = lastUsedAt
        }
    }
}

/// A single tappable dose amount within a `SubstanceGroup`. For a by-volume
/// substance (alcohol) a chip carries the recorded drink detail — emoji, name,
/// volume, and %ABV — so it renders as "🍺 IPA · 330 mL · 6% · 16 g" and
/// re-stages that exact drink; a plain mass dose is just its amount. The salt
/// or ester rides along so a tapped chip stages the form its card names
/// ("Estradiol Enanthate", in the title) rather than the route's default salt.
struct DoseChip: Identifiable, Equatable {
    let amount: Double
    let unit: String
    let saltForm: String?
    let drinkName: String?
    let emoji: String?
    let volumeML: Double?
    let abv: Double?

    init(
        amount: Double,
        unit: String,
        saltForm: String? = nil,
        drinkName: String? = nil,
        emoji: String? = nil,
        volumeML: Double? = nil,
        abv: Double? = nil,
    ) {
        self.amount = amount
        self.unit = unit
        self.saltForm = saltForm
        self.drinkName = drinkName
        self.emoji = emoji
        self.volumeML = volumeML
        self.abv = abv
    }

    var id: String {
        QuickLogDose.makeKey(
            substance: "",
            route: .oral,
            amount: amount,
            unit: unit,
            volumeML: volumeML,
            abv: abv,
            drinkName: drinkName,
        )
    }

    /// A drink chip carries measured/named detail; a plain dose is just grams.
    var hasDrinkDetail: Bool {
        drinkName != nil || volumeML != nil || abv != nil
    }

    var formattedAmount: String {
        amount.doseFormatted
    }

    /// Subtitle for a detailed by-volume chip: "330 mL · 6% · 16 g" for alcohol,
    /// "1 mL · 40 mg/mL · 40 mg" for an injectable ester (volume/strength only
    /// shown when known); falls back to just the amount.
    var detailLine: String {
        var parts: [String] = []
        // `doseFormatted`, so a 0.12 mL draw reads as itself and never "0 mL".
        if let volumeML { parts.append("\(volumeML.doseFormatted) mL") }
        if let abv {
            // Alcohol (canonical "g") logs %ABV; a mass-per-volume ester logs a
            // concentration in <unit>/mL.
            parts.append(unit == "g"
                ? "\(ByVolumeDosing.formatTrimmed(abv))%"
                : "\(ByVolumeDosing.formatTrimmed(abv)) \(unit)/mL")
        }
        parts.append("\(formattedAmount) \(unit)")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Card PK badge

/// Precomputed PK badge data for one card, built when `cachedMostRecent`
/// rebuilds — so `DosePK.status` (two `SubstanceLibrary` lookups + PK math) and
/// the last-dose field reads run once per history change in the model, not per
/// card on every `body` evaluation. Carries the narrow last-dose values the
/// card's badge + expanded card need, never the live `DoseEntry`.
struct CardPKBadge: Equatable {
    let remainingPercent: Double
    let lastDoseAmount: Double
    let lastDoseUnit: String
    let lastDoseTimestamp: Date
    let lastDoseRoute: RouteOfAdministration

    /// The badge shows only above a 5% floor (matching the full card).
    var showsBadge: Bool {
        remainingPercent > 5
    }

    /// VoiceOver value for the badge — the visible chip's numbers spoken as a
    /// sentence, since the badge button's label is just a short noun ("Active
    /// dose"). Mirrors `DosePKBadge.label`, so the two never disagree.
    var accessibilityValue: String {
        let active = (lastDoseAmount * remainingPercent / 100).doseFormatted
        let ago = DosePK.shortElapsed(since: lastDoseTimestamp)
        return String(localized: "estimated \(active) \(lastDoseUnit) active, last dose \(ago) ago")
    }
}
