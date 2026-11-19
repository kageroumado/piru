import Foundation
import os

/// The **category floor** for the substance detail card's Pharmacology section, and the composer
/// that decides what that section shows.
///
/// All of it is data in the bundled SQLite: per-substance rows in `mechanisms_summary` and
/// `bindings`, class-level ones fanned out from `data/curated/class-mechanisms.json`, and the
/// per-category floor beneath them (`data/curated/category-mechanisms.json` → `category_mechanisms`
/// + `category_mechanism_bindings`), the text shown for a substance no source has described. The
/// floor is installed here once at index build by ``SubstanceStore`` via ``loadCategoryFloor(prose:bindings:)``;
/// this type is the composer that reads it, not a table — edit the curated JSON and rebuild.
///
/// **The floor is composed at runtime, never fanned out to substances at build time.** The choice
/// between a substance's own prose and the floor is language-dependent (a Chinese reader seeing
/// English-only DB prose must fall to the localized floor), and the shipped DB carries one row set
/// for every language, so only the running app can make it. A class-level fact still belongs in
/// `class-mechanisms.json`, whose ingester writes it only where the substance has nothing of its
/// own; a per-substance one belongs in `mechanisms.json`.
enum MechanismOfActionDatabase {
    /// The category floor, loaded from the bundled DB. Held in a lock because it is read from
    /// `nonisolated` code (the off-main Pharma-table seed) with no store reference; empty before the
    /// load, which yields no floor until the store is open.
    private struct Floor {
        let prose: [String: (summary: String, description: String)] // language code → prose
        let bindings: [ReceptorBinding]
    }

    private static let floor = OSAllocatedUnfairLock<[SubstanceCategory: Floor]>(initialState: [:])

    /// Install the per-category floor read from `category_mechanisms` + `category_mechanism_bindings`.
    /// Called once per store init.
    static func loadCategoryFloor(
        prose: [SubstanceReadModel.CategoryFloorProse],
        bindings: [SubstanceReadModel.CategoryFloorBinding],
    ) {
        var proseByCategory: [SubstanceCategory: [String: (summary: String, description: String)]] = [:]
        for row in prose {
            guard let category = SubstanceCategory(rawValue: row.category) else { continue }
            proseByCategory[category, default: [:]][row.language] = (row.summary, row.description)
        }
        var bindingsByCategory: [SubstanceCategory: [ReceptorBinding]] = [:]
        for row in bindings {
            guard let category = SubstanceCategory(rawValue: row.category),
                  let action = BindingAction(rawValue: row.action),
                  let affinity = BindingAffinity(rawValue: row.tier) else { continue }
            bindingsByCategory[category, default: []].append(
                ReceptorBinding(target: row.target, action: action, affinity: affinity),
            )
        }
        var table: [SubstanceCategory: Floor] = [:]
        for (category, languages) in proseByCategory {
            table[category] = Floor(prose: languages, bindings: bindingsByCategory[category] ?? [])
        }
        let built = table
        floor.withLock { $0 = built }
    }

    /// The category floor for `category`, in the app's current content language (English where that
    /// language has no row). `nil` when the category carries no floor.
    static func categoryFallback(for category: SubstanceCategory) -> MechanismOfAction? {
        guard let entry = floor.withLock({ $0[category] }) else { return nil }
        let language = ContentLanguage.current.rawValue
        guard let prose = entry.prose[language] ?? entry.prose["en"] else { return nil }
        return MechanismOfAction(summary: prose.summary, description: prose.description, bindings: entry.bindings)
    }

    /// Composes the mechanism shown in the substance detail card.
    ///
    /// - **Summary text**: the DB `mechanisms_summary` (a non-empty summary on `dbMechanism`)
    ///   wins; otherwise the per-category floor.
    /// - **Bindings**: the DB set, or the floor's when it is empty. A substance with nothing
    ///   measured shows its summary and no receptor list — an absence, not a placeholder.
    ///
    /// Pure and deterministic so it can be unit-tested without a database.
    static func resolvedMechanism(
        dbMechanism: MechanismOfAction?,
        category: SubstanceCategory,
    ) -> MechanismOfAction? {
        let categoryMoa = categoryFallback(for: category)

        let hasDBSummary = !(dbMechanism?.summary.isEmpty ?? true)
        // A Chinese reader seeing English-only DB prose should get the localized
        // category floor instead — it is generic but in their language.
        let dbLanguageMismatch: Bool = {
            guard ContentLanguage.current.isChinese,
                  let lang = dbMechanism?.summaryLanguage else { return false }
            return !lang.hasPrefix("zh")
        }()
        let preferDB = hasDBSummary && !dbLanguageMismatch
        let textSource: MechanismOfAction? = preferDB ? dbMechanism : (categoryMoa ?? dbMechanism)
        guard let textSource else { return nil }

        var bindings = dbMechanism?.bindings ?? []
        if bindings.isEmpty { bindings = categoryMoa?.bindings ?? [] }

        return MechanismOfAction(
            summary: textSource.summary,
            description: textSource.description,
            bindings: bindings,
        )
    }
}
