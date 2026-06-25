import SwiftUI

/// The Library browse taxonomy: bold effect-family cards that replace the flat
/// category list.
///
/// A family is either a **single** card (taps straight through to a substance
/// list) or an **umbrella** that expands in place into its sub-classes. The
/// taxonomy is a *presentation* layer over ``SubstanceCategory``: every
/// browsable category is reachable through exactly one card or sub-class —
/// plus a tag-backed **Common** entry card that deliberately overlaps the
/// families, so someone who doesn't know cannabis is a "cannabinoid" (or that
/// it's filed under THC) still finds it by the familiar name.
struct LibraryFamily: Identifiable {
    /// Where a single card's tap leads — a resolved category, or a tag the
    /// substances are flagged with (Common).
    enum Source: Hashable {
        case category(SubstanceCategory)
        case tag(String)

        var route: PushRoute {
            switch self {
            case let .category(category): .libraryCategory(category)
            case let .tag(tag): .libraryTag(tag)
            }
        }
    }

    let id: String
    let title: LocalizedStringResource
    let blurb: LocalizedStringResource
    let icon: String
    let color: Color
    let molecule: String
    /// Single cards link straight to this list; `nil` for umbrellas.
    let source: Source?
    /// Umbrella sub-classes; empty for single cards.
    var subclasses: [LibrarySubclass] = []
    /// Opioids carry the overdose-risk badge.
    var highlightsRisk = false

    var isUmbrella: Bool {
        !subclasses.isEmpty
    }
}

/// One sub-class chip/row inside an umbrella family. Always backed by a real
/// ``SubstanceCategory``; the row label uses ``SubstanceCategory/browseTitle``
/// so it matches the screen the row pushes.
struct LibrarySubclass: Identifiable {
    let category: SubstanceCategory
    let blurb: LocalizedStringResource

    var id: String {
        category.rawValue
    }
    var title: LocalizedStringResource {
        category.browseTitle
    }
    var route: PushRoute {
        .libraryCategory(category)
    }
}

extension SubstanceCategory {
    /// Title used when browsing this category from the Library. A couple of
    /// categories read better here than their raw class chip: the circular
    /// "Depressant" (inside the *Sedatives & Depressants* family) becomes
    /// "Sedative-Hypnotic". The catch-all "Other" is a genuine miscellaneous
    /// bucket — *not* "Research Chemicals" (those are surfaced by the
    /// `research-chemical` tag instead, so medical odd-ones like Naloxone don't
    /// get mislabelled as RCs).
    var browseTitle: LocalizedStringResource {
        switch self {
        case .depressant: "Sedative-Hypnotic"
        case .other: "Other / Miscellaneous"
        default: displayName
        }
    }
}

extension LibraryFamily {
    /// Screen title for a tag-backed substance list (the Common card).
    static func tagTitle(_ tag: String) -> LocalizedStringResource {
        switch tag {
        case "common": "Common"
        case "research-chemical": "Research Chemicals"
        default: "\(tag)"
        }
    }

    /// The most recognizable substances in a single card's source, by curated
    /// popularity — shown as the card's example line. Drawn live so the names
    /// always reflect the real data.
    static func exemplars(for source: Source?, limit: Int = 3) -> [String] {
        let list: [Substance]
        switch source {
        case let .category(category): list = SubstanceLibrary.substances(in: category)
        case let .tag(tag): list = SubstanceLibrary.substances(taggedWith: tag)
        case .none: return []
        }
        return list
            .sorted { $0.popularity > $1.popularity }
            .prefix(limit)
            .map(\.displayTitle)
    }

    /// Families with their empty sub-classes (and empty single cards) pruned, so
    /// a class with nothing browsable never shows a dead card. Shared by the
    /// Library browse flow and the Search screen's class grid.
    static var browsable: [LibraryFamily] {
        // Count from the cheap histogram, not by materializing every category's
        // `Substance` list — those rows are built lazily only when a list is
        // actually opened.
        let summary = SubstanceLibrary.categorySummary()
        return all.compactMap { family in
            guard family.isUmbrella else {
                return family.hasSubstances(summary: summary) ? family : nil
            }
            let live = family.subclasses.filter { (summary[$0.category] ?? 0) > 0 }
            guard !live.isEmpty else { return nil }
            var pruned = family
            pruned.subclasses = live
            return pruned
        }
    }

    /// Whether a single card's source has any browsable substances — a histogram
    /// lookup for categories; tags still need their cross-category scan.
    private func hasSubstances(summary: [SubstanceCategory: Int]) -> Bool {
        switch source {
        case let .category(category): (summary[category] ?? 0) > 0
        case let .tag(tag): !SubstanceLibrary.substances(taggedWith: tag).isEmpty
        case .none: false
        }
    }

    /// The ordered family taxonomy. `Common` leads as a friendly entry point;
    /// the rest run from recreational effect-families through clinical classes
    /// to supplements and the research-chemical bucket.
    static let all: [LibraryFamily] = [
        LibraryFamily(
            id: "common",
            title: "Common",
            blurb: "Everyday substances, by the names most people know.",
            icon: "flame.fill",
            // Cool cornflower blue — keeps the meta-cards clear of the warm
            // Stimulants orange they used to blur into.
            color: Color(red: 0.28, green: 0.46, blue: 0.74),
            molecule: "caffeine",
            source: .tag("common"),
        ),
        LibraryFamily(
            id: "stimulant",
            title: "Stimulants",
            blurb: "Energy, focus, and wakefulness.",
            icon: "bolt.fill",
            color: .orange,
            molecule: "amphetamine",
            source: .category(.stimulant),
        ),
        LibraryFamily(
            id: "empathogen",
            title: "Empathogens",
            blurb: "Warmth, empathy, and emotional openness.",
            icon: "heart.fill",
            color: .pink,
            molecule: "mdma",
            source: .category(.empathogen),
        ),
        LibraryFamily(
            id: "hallucinogen",
            title: "Hallucinogens",
            blurb: "Alter perception, thought, and sense of reality.",
            icon: "eye.fill",
            color: Color(red: 0.56, green: 0.27, blue: 0.79),
            molecule: "mescaline",
            source: nil,
            subclasses: [
                .init(category: .psychedelic, blurb: "Serotonergic — LSD, psilocybin, mescaline."),
                .init(category: .dissociative, blurb: "NMDA antagonists — ketamine, DXM, PCP."),
                .init(category: .deliriant, blurb: "Anticholinergic — DPH, datura, Benadryl."),
                .init(category: .dysdelic, blurb: "κ-opioid agonists — salvia, salvinorin A."),
            ],
        ),
        LibraryFamily(
            id: "cannabinoid",
            title: "Cannabinoids",
            blurb: "Relaxation, euphoria, and altered senses.",
            icon: "leaf.fill",
            color: .green,
            molecule: "thc",
            source: .category(.cannabinoid),
        ),
        LibraryFamily(
            id: "opioid",
            title: "Opioids",
            blurb: "Pain relief, euphoria, and sedation.",
            icon: "cross.fill",
            color: .red,
            molecule: "morphine",
            source: .category(.opioid),
            highlightsRisk: true,
        ),
        LibraryFamily(
            id: "sedative",
            title: "Sedatives & Depressants",
            blurb: "Calm and slow the central nervous system.",
            icon: "moon.fill",
            color: .blue,
            molecule: "diazepam",
            source: nil,
            subclasses: [
                .init(category: .benzodiazepine, blurb: "GABA-A modulators — diazepam, alprazolam."),
                .init(category: .gabapentinoid, blurb: "GABAergics & gabapentinoids — GHB, pregabalin, phenibut."),
                .init(category: .depressant, blurb: "Barbiturates, sedative-hypnotics, and Z-drugs."),
            ],
        ),
        LibraryFamily(
            id: "peptide",
            title: "Peptides",
            blurb: "GLP-1, healing, and research peptides.",
            icon: "link.circle.fill",
            color: Color(red: 0.40, green: 0.65, blue: 0.85),
            molecule: "peptide",
            source: .category(.peptide),
        ),
        LibraryFamily(
            id: "mind",
            title: "Mind & Cognition",
            blurb: "Mood, psychiatric, and cognitive medications.",
            icon: "brain.fill",
            // Deeper teal than the system color — `.teal` is too light for white
            // text on the gradient's near-white end (failed the contrast check).
            color: Color(red: 0.11, green: 0.47, blue: 0.52),
            molecule: "fluoxetine",
            source: nil,
            subclasses: [
                .init(category: .antidepressant, blurb: "SSRIs, SNRIs, and MAOIs."),
                .init(category: .antipsychotic, blurb: "Dopamine antagonists — quetiapine, risperidone."),
                .init(category: .nootropic, blurb: "Racetams, choline, and cognitive aids."),
                .init(category: .ampakine, blurb: "AMPA-receptor positive modulators."),
                .init(category: .eugeroic, blurb: "Wakefulness — modafinil, armodafinil."),
            ],
        ),
        LibraryFamily(
            id: "pharmaceutical",
            title: "Pharmaceuticals",
            blurb: "Clinical medications, by therapeutic class.",
            icon: "cross.case.fill",
            color: Color(red: 0.43, green: 0.48, blue: 0.56),
            molecule: "aspirin",
            source: nil,
            subclasses: [
                .init(category: .analgesic, blurb: "Non-opioid pain relief — NSAIDs, paracetamol."),
                .init(category: .antihistamine, blurb: "Allergy and sleep antihistamines."),
                .init(category: .cardiovascular, blurb: "Blood pressure, heart, and cholesterol."),
                .init(category: .antimicrobial, blurb: "Antibiotics, antivirals, and antifungals."),
                .init(category: .gastrointestinal, blurb: "Acid, nausea, and gut motility."),
                .init(category: .respiratory, blurb: "Inhalers, decongestants, and cough."),
                .init(category: .endocrine, blurb: "Hormones, thyroid, and metabolic drugs."),
                .init(category: .immunological, blurb: "Immune modulators and steroids."),
                .init(category: .anticonvulsant, blurb: "Seizure and mood-stabilizing drugs."),
            ],
        ),
        LibraryFamily(
            id: "supplement",
            title: "Supplements",
            blurb: "Vitamins, minerals, and nutrients.",
            icon: "drop.fill",
            color: Color(red: 0.32, green: 0.74, blue: 0.46),
            molecule: "ascorbic",
            source: .category(.supplement),
        ),
        LibraryFamily(
            id: "research",
            title: "Research Chemicals",
            blurb: "Novel and lesser-characterized compounds.",
            icon: "flask.fill",
            color: Color(red: 0.53, green: 0.55, blue: 0.60),
            molecule: "twocb",
            // Tag-driven, not the catch-all category: only compounds actually
            // flagged `research-chemical` surface here, so medical odd-ones
            // (Naloxone, Naltrexone) that resolve to "Other" no longer appear.
            source: .tag("research-chemical"),
        ),
        LibraryFamily(
            id: "other",
            title: "Other / Miscellaneous",
            blurb: "Everything that doesn't fit a class above.",
            icon: "ellipsis.circle.fill",
            color: Color(red: 0.45, green: 0.47, blue: 0.50),
            molecule: "twocb",
            source: .category(.other),
        ),
    ]
}
