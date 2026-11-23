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
    /// get mislabeled as RCs).
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
    /// popularity — shown as the card's example line.
    ///
    /// Memoized per source: resolving it materializes the source's *entire*
    /// `[Substance]` list (each a ~40-field value) just to take the top three
    /// names, and this is called from the card's `body` on every Library /
    /// Search browse-grid render. The top-three-by-popularity is effectively
    /// static (curated popularity over the curated catalog), so caching the
    /// resolved names is safe; a source reorder that reshuffles them is
    /// cosmetic and refreshes on relaunch.
    @MainActor private static var exemplarsCache: [Source: [String]] = [:]
    /// The English-names preference and app language `exemplarsCache` was filled
    /// under. The names are display titles, so changing either in Settings
    /// empties the cache.
    @MainActor private static var exemplarsCacheKey = ExemplarsKey(usesEnglishNames: false, language: .en)

    private struct ExemplarsKey: Equatable {
        let usesEnglishNames: Bool
        let language: ContentLanguage
    }

    static func exemplars(for source: Source?) -> [String] {
        guard let source else { return [] }
        let key = ExemplarsKey(usesEnglishNames: LocalizedSubstanceName.usesEnglishNames, language: .current)
        if key != exemplarsCacheKey {
            exemplarsCache.removeAll()
            exemplarsCacheKey = key
        }
        if let cached = exemplarsCache[source] { return cached }
        let list: [Substance] = switch source {
        case let .category(category): SubstanceLibrary.substances(in: category)
        case let .tag(tag): SubstanceLibrary.substances(taggedWith: tag)
        }
        let result = list
            .sorted { $0.popularity > $1.popularity }
            .prefix(exemplarCount)
            .map(\.displayTitle)
        exemplarsCache[source] = result
        return result
    }

    /// How many names a card's exemplar line shows.
    private static let exemplarCount = 2

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
            icon: "flame.fill",
            // Cool cornflower blue keeps the meta-cards clear of the warm
            // Stimulants orange.
            color: .Family.Common.accent,
            molecule: "caffeine",
            source: .tag("common"),
        ),
        LibraryFamily(
            id: "stimulant",
            title: "Stimulants",
            icon: "bolt.fill",
            color: .Family.Stimulant.accent,
            molecule: "amphetamine",
            source: .category(.stimulant),
        ),
        LibraryFamily(
            id: "empathogen",
            title: "Empathogens",
            icon: "heart.fill",
            color: .Family.Empathogen.accent,
            molecule: "mdma",
            source: .category(.empathogen),
        ),
        LibraryFamily(
            id: "hallucinogen",
            title: "Hallucinogens",
            icon: "eye.fill",
            color: .Family.Hallucinogen.accent,
            molecule: "mescaline",
            source: nil,
            subclasses: [
                .init(category: .psychedelic, blurb: "Serotonergic: LSD, psilocybin, mescaline."),
                .init(category: .dissociative, blurb: "NMDA antagonists: ketamine, DXM, PCP."),
                .init(category: .deliriant, blurb: "Anticholinergic: DPH, datura, Benadryl."),
                .init(category: .dysdelic, blurb: "κ-opioid agonists: salvia, salvinorin A."),
            ],
        ),
        LibraryFamily(
            id: "cannabinoid",
            title: "Cannabinoids",
            icon: "leaf.fill",
            color: .Family.Cannabinoid.accent,
            molecule: "thc",
            source: .category(.cannabinoid),
        ),
        LibraryFamily(
            id: "opioid",
            title: "Opioids",
            icon: "cross.fill",
            color: .Family.Opioid.accent,
            molecule: "morphine",
            source: .category(.opioid),
            highlightsRisk: true,
        ),
        LibraryFamily(
            id: "sedative",
            title: "Sedatives & Depressants",
            icon: "moon.fill",
            color: .Family.Sedative.accent,
            molecule: "diazepam",
            source: nil,
            subclasses: [
                .init(category: .benzodiazepine, blurb: "GABA-A modulators: diazepam, alprazolam."),
                .init(category: .gabapentinoid, blurb: "GABAergics & gabapentinoids: GHB, pregabalin, phenibut."),
                .init(category: .depressant, blurb: "Barbiturates, sedative-hypnotics, and Z-drugs."),
            ],
        ),
        LibraryFamily(
            id: "peptide",
            title: "Peptides",
            icon: "link.circle.fill",
            color: .Family.Peptide.accent,
            molecule: "peptide",
            source: .category(.peptide),
        ),
        LibraryFamily(
            id: "mind",
            title: "Mind & Cognition",
            icon: "brain.fill",
            color: .Family.Mind.accent,
            molecule: "fluoxetine",
            source: nil,
            subclasses: [
                .init(category: .antidepressant, blurb: "SSRIs, SNRIs, and MAOIs."),
                .init(category: .antipsychotic, blurb: "Dopamine antagonists: quetiapine, risperidone."),
                .init(category: .nootropic, blurb: "Racetams, choline, and cognitive aids."),
                .init(category: .ampakine, blurb: "AMPA-receptor positive modulators."),
                .init(category: .eugeroic, blurb: "Wakefulness: modafinil, armodafinil."),
            ],
        ),
        LibraryFamily(
            id: "pharmaceutical",
            title: "Pharmaceuticals",
            icon: "cross.case.fill",
            color: .Family.Pharmaceutical.accent,
            molecule: "aspirin",
            source: nil,
            subclasses: [
                .init(category: .analgesic, blurb: "Non-opioid pain relief: NSAIDs, paracetamol."),
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
            icon: "drop.fill",
            color: .Family.Supplement.accent,
            molecule: "ascorbic",
            source: .category(.supplement),
        ),
        LibraryFamily(
            id: "research",
            title: "Research Chemicals",
            icon: "flask.fill",
            color: .Family.Research.accent,
            molecule: "twocb",
            // Tag-driven, not the catch-all category: only compounds flagged
            // `research-chemical` surface here, so medical odd-ones (Naloxone,
            // Naltrexone) that resolve to "Other" stay out.
            source: .tag("research-chemical"),
        ),
        LibraryFamily(
            id: "other",
            title: "Other / Miscellaneous",
            icon: "ellipsis.circle.fill",
            color: .Family.Other.accent,
            molecule: "twocb",
            source: .category(.other),
        ),
    ]
}
