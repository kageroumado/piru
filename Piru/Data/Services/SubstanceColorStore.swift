import Foundation
import OSLog
import SwiftData

private nonisolated let logger = Logger(subsystem: "dev.yumeji.piru", category: "SubstanceColorStore")

/// What the color picker hands back.
enum SubstanceColorChoice: Hashable {
    /// The generated color for the substance's class and identity.
    case `default`
    case custom(P3Color)
}

/// Writes ``SubstanceColor`` rows: the default a substance is given when it is
/// first met, the user's own pick, and the passes that keep defaults current.
enum SubstanceColorStore {
    /// The generated color for `name`: from its catalog or custom-substance
    /// record when it resolves, else from the name alone in the gray class.
    @MainActor
    static func defaultTint(for name: String) -> P3Color {
        if let substance = SubstanceLibrary.lookup(name) {
            return SubstanceColorGenerator.color(for: substance).displayP3
        }
        return SubstanceColorGenerator.color(category: .other, seed: name.lowercased()).displayP3
    }

    /// Publishes every catalog substance's default to ``CatalogTints``, which
    /// backs ``SubstancePalette``'s fallback off the main actor. Requires a
    /// warm catalog (`SubstanceStore.ensureAllLoaded()`).
    @MainActor
    static func installCatalogTints() {
        var tints: [String: P3Color] = [:]
        for substance in SubstanceLibrary.all {
            tints[substance.name.lowercased()] = SubstanceColorGenerator.color(for: substance).displayP3
        }
        CatalogTints.install(tints)
    }

    /// Gives `name` a default-colored row when it has none. Returns the new
    /// row so a caller holding a snapshot of the table can append it.
    @MainActor
    @discardableResult
    static func ensureRow(for name: String, existing: [SubstanceColor], in context: ModelContext) -> SubstanceColor? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !existing.hasColor(for: trimmed) else { return nil }
        let row = SubstanceColor(substance: trimmed, tint: defaultTint(for: trimmed), usesDefault: true)
        context.insert(row)
        return row
    }

    /// Applies a picker result to `name`'s row, creating it when absent.
    @MainActor
    static func apply(_ choice: SubstanceColorChoice, to name: String, in context: ModelContext) {
        let rows = (try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? []
        let tint: P3Color
        let usesDefault: Bool
        switch choice {
        case .default: (tint, usesDefault) = (defaultTint(for: name), true)
        case let .custom(picked): (tint, usesDefault) = (picked, false)
        }
        if let row = rows.first(where: { $0.substance.lowercased() == name.lowercased() }) {
            row.set(tint, usesDefault: usesDefault)
        } else {
            context.insert(SubstanceColor(substance: name, tint: tint, usesDefault: usesDefault))
        }
        try? context.save()
        ActiveSessionManager.shared.applyColorUpdates(allColors: (try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? [])
    }

    /// Returns every custom row to its default.
    @MainActor
    static func resetAll(in context: ModelContext) {
        let rows = (try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? []
        for row in rows where !row.usesDefault || row.isLegacy {
            row.set(defaultTint(for: row.substance), usesDefault: true)
        }
        try? context.save()
        ActiveSessionManager.shared.applyColorUpdates(allColors: rows)
    }

    /// Brings default rows in line with the generator: a database rebuild or a
    /// source-priority change can move a substance's class or identity.
    /// Legacy rows are left for the color-update notice.
    ///
    /// Rows are edited on the main context, never a background one: a live
    /// `@Query` does not re-read an existing row that another context saved,
    /// so the timeline would keep the colors it was built with.
    @MainActor
    static func refreshDefaults(in context: ModelContext) {
        let rows = (try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? []
        var changed = false
        for row in rows where row.usesDefault && !row.isLegacy {
            let tint = defaultTint(for: row.substance)
            guard row.tint != tint else { continue }
            row.set(tint, usesDefault: true)
            changed = true
        }
        guard changed else { return }
        try? context.save()
        ActiveSessionManager.shared.applyColorUpdates(allColors: rows)
    }

    /// Mints a default row for every logged, stocked or scheduled substance
    /// that lacks one: doses arriving from the watch and the widget's Take-Med
    /// intent are written with no catalog at hand.
    @DatabaseActor
    static func mintMissingRows(container: ModelContainer, defaults: @Sendable (String) -> P3Color) {
        let context = ModelContext(container)
        let rows = (try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? []
        var known = Set(rows.map { $0.substance.lowercased() })
        // Whole rows, never `propertiesToFetch`: a narrowed fetch makes every
        // object a partial fault that fires a one-row fetch on its first read,
        // one per dose — measured at 12.5k faults on a real log.
        var names = ((try? context.fetch(FetchDescriptor<DoseEntry>())) ?? []).map(\.substance)
        names += ((try? context.fetch(FetchDescriptor<InventoryItem>())) ?? []).map(\.substance)
        names += ((try? context.fetch(FetchDescriptor<DailyDoseItem>())) ?? []).map(\.substance)
        var changed = 0
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, known.insert(trimmed.lowercased()).inserted else { continue }
            context.insert(SubstanceColor(substance: trimmed, tint: defaults(trimmed), usesDefault: true))
            changed += 1
        }
        save(context, changed: changed, pass: "mint")
    }

    @DatabaseActor
    private static func save(_ context: ModelContext, changed: Int, pass: String) {
        guard changed > 0 else { return }
        do {
            try context.save()
            logger.notice("Substance colors \(pass, privacy: .public): \(changed, privacy: .public) row(s).")
        } catch {
            logger.error("Substance colors \(pass, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Number of rows still holding a pre-class-colors hex.
    @MainActor
    static func legacyRowCount(in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<SubstanceColor>(predicate: #Predicate { $0.hexColor != "" }))) ?? 0
    }

    /// Answers the color-update notice: `adoptClassColors` moves every legacy
    /// row to its generated default; otherwise each keeps the color it had, as
    /// a custom color. On the main context, for the reason
    /// ``refreshDefaults(in:)`` gives.
    @MainActor
    static func resolveLegacyRows(adoptClassColors: Bool, in context: ModelContext) {
        let rows = (try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? []
        for row in rows where row.isLegacy {
            if adoptClassColors {
                row.set(defaultTint(for: row.substance), usesDefault: true)
            } else {
                row.set(row.tint, usesDefault: false)
            }
        }
        try? context.save()
        ActiveSessionManager.shared.applyColorUpdates(allColors: rows)
    }

    /// The default resolver the ``DatabaseActor`` mint pass takes: the installed
    /// catalog table, then the gray class seeded by the name.
    nonisolated static let backgroundDefaults: @Sendable (String) -> P3Color = { name in
        CatalogTints.tint(for: name)
            ?? SubstanceColorGenerator.color(category: .other, seed: name.lowercased()).displayP3
    }
}
