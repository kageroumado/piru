import Foundation
import SwiftData
import SwiftUI

/// A day's resolved curves, markers, and interaction warnings.
struct ResolvedDay {
    var states: [ActiveSubstanceState] = []
    var markers: [DoseMarker] = []
    var interactions: [InteractionResult] = []
    /// Measured exposure changes between two things actually logged here —
    /// `drug_interactions_pk` rows resolved against the day's entries. Kept
    /// apart from `interactions`: those rank danger, these report a number.
    var pkFindings: [PKInteractionFinding] = []
    /// Distinct timeline lanes by kind, precomputed so `graphHeight` doesn't
    /// rebuild two name Sets on every height-animation frame.
    var curveLaneCount: Int = 0
    var markerLaneCount: Int = 0
    /// Render-ready, substance-resolved facts for each dose row, in `entries`
    /// order. Built here (once per content change) so the heavy per-row resolve
    /// — `SubstanceLibrary` lookup + dose-level classification + display-name
    /// override — never runs in a row `body`.
    var entryCores: [DayEntryCore] = []
    /// Engine inputs + support gate for the mechanistic lenses, resolved with
    /// the rest of the day so per-body reads never hit the substance store.
    var mechanisticDoses: [MechanisticSessionModel.DoseInput] = []
    var mechanisticSupported: Bool = false
    /// Resolved per-substance PK + binding (keyed by normalized name), fetched from
    /// the bundled pharmacology DB once per content change so the engine's per-substance
    /// params (`ke`/`ka`/transporter weights/`releaser`) are data-driven. The off-main
    /// simulation and the support gate both read this.
    var mechanisticPharmacology: [String: PharmacologyParameters] = [:]
}

/// Every substance-store resolve the session detail needs, as pure functions —
/// the timeline, the interaction and PK checks, the mechanistic engine's inputs,
/// and the per-row facts. Held apart from the view so its `body` reads finished
/// values and never a store lookup.
@MainActor
enum SessionResolveModel {
    /// The day's resolved timeline + interaction warnings, derived **synchronously
    /// and memoized** (see ``DayResolveCache``) per change to the day's
    /// entries/colors. Resolving a single day is cheap — a handful of
    /// `SubstanceLibrary` lookups plus one batch interaction check — so computing
    /// up front keeps the view tree's shape fixed from frame 1: `states` and
    /// `interactions` are never empty on the first render, so the `if !…isEmpty`
    /// Sections never flip in and rebuild the List content.
    static func resolvedDay(entries: [DoseEntry], colors: [SubstanceColor], startDate: Date, signature: Int) -> ResolvedDay {
        DayResolveCache.shared.resolve(signature: signature) {
            resolve(entries: entries, colors: colors, startDate: startDate)
        }
    }

    private static func resolve(entries: [DoseEntry], colors: [SubstanceColor], startDate: Date) -> ResolvedDay {
        let t = ActiveSubstanceState.timeline(for: entries, colors: colors)
        let names = Array(Set(entries.map(\.substance)))
        let interactions = names.count >= 2 ? InteractionChecker.checkBatch(names, against: []) : []
        // The measured layer. Every row here cites a study; matching is
        // canonical-name only, so a row naming a class ("CYP3A4 inhibitors")
        // stays on its own substance page rather than being inferred onto a
        // logged drug.
        let active = InteractionChecker.activeEntries(from: entries)
        var pkFindings: [PKInteractionFinding] = []
        var seenPK: Set<Int64> = []
        for name in names {
            for finding in InteractionChecker.pharmacokineticInteractions(name, against: active)
                where seenPK.insert(finding.id).inserted {
                pkFindings.append(finding)
            }
        }
        // Mirrors the renderer's own split: a marker lane exists only for a
        // substance with no curve lane (``markerOnlyLanes(excluding:)``).
        let curveNames = Set(t.states.map { $0.substanceName.lowercased() })
        let markerNames = Set(t.markers.map { $0.substanceName.lowercased() })
            .subtracting(curveNames)
        let mechanisticDoses = computeMechanisticDoses(entries, startDate: startDate)
        let mechanisticPharmacology = resolveMechanisticPharmacology(mechanisticDoses)
        return ResolvedDay(
            states: t.states,
            markers: t.markers,
            interactions: interactions,
            pkFindings: pkFindings,
            curveLaneCount: curveNames.count,
            markerLaneCount: markerNames.count,
            entryCores: DayEntryCore.make(from: entries),
            mechanisticDoses: mechanisticDoses,
            mechanisticSupported: MechanisticSessionModel.supportsMechanisticView(mechanisticDoses, pharmacology: mechanisticPharmacology),
            mechanisticPharmacology: mechanisticPharmacology,
        )
    }

    /// Each dose reduced to the effect engine's inputs, resolved **once** per
    /// content change alongside the rest of ``ResolvedDay`` — reading it in
    /// `body` (support gate, task signature) must never pay a store lookup.
    /// Doses whose substance isn't in the library are dropped — they can't be
    /// modeled anyway.
    private static func computeMechanisticDoses(_ entries: [DoseEntry], startDate: Date) -> [MechanisticSessionModel.DoseInput] {
        var inLibraryCache: [String: Bool] = [:]
        func inLibrary(_ name: String) -> Bool {
            let key = name.lowercased()
            if let cached = inLibraryCache[key] { return cached }
            let resolved = SubstanceLibrary.lookup(name) != nil
            inLibraryCache[key] = resolved
            return resolved
        }
        return entries.compactMap { entry in
            guard inLibrary(entry.substance) else { return nil }
            // The effect engine models absorption from the route's profile, which
            // is the immediate-release one — so an extended-release dose would be
            // simulated as if it landed all at once, and the whole session's
            // estimate would inherit that. A dose whose form we decline to model
            // is left out rather than modelled wrong.
            guard !entry.namesUnmodeledForm else { return nil }
            return MechanisticSessionModel.DoseInput(
                name: entry.substance,
                amount: entry.amount,
                route: entry.route,
                hours: entry.timestamp.timeIntervalSince(startDate) / 3_600,
            )
        }
    }

    /// Resolve each distinct substance's PK + binding from the bundled pharmacology
    /// DB, keyed by normalized name. Runs with the rest of the day resolve (main
    /// actor, memoized), so the engine's per-substance params are data-driven
    /// without a store lookup in `body` or in the off-main simulation.
    private static func resolveMechanisticPharmacology(_ doses: [MechanisticSessionModel.DoseInput]) -> [String: PharmacologyParameters] {
        var result: [String: PharmacologyParameters] = [:]
        for dose in doses {
            let key = SubstanceModelDatabase.normalize(dose.name)
            if result[key] == nil {
                result[key] = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: dose.name)
            }
        }
        return result
    }

    /// Content fingerprint of the day's doses + color count — the memo key, so
    /// the resolve re-runs on an edit but not on every body re-evaluation.
    static func timelineSignature(entries: [DoseEntry], colorCount: Int) -> Int {
        var hasher = Hasher()
        for entry in entries {
            hasher.combine(entry.persistentModelID)
            hasher.combine(entry.timestamp)
            hasher.combine(entry.amount)
            hasher.combine(entry.substance)
            hasher.combine(entry.route)
        }
        hasher.combine(colorCount)
        return hasher.finalize()
    }

    /// Cheap: hashes the small, already-memoized dose inputs (which carry no
    /// color — a recolor must not re-trigger the simulation task).
    static func mechanisticSignature(doses: [MechanisticSessionModel.DoseInput]) -> Int {
        var hasher = Hasher()
        hasher.combine(doses)
        return hasher.finalize()
    }

    /// The line to show where the timeline would be when the session names a form
    /// the app declines to model (``DoseEntry/namesUnmodeledForm``) — a Concerta, a
    /// depot injection. `nil` when nothing here needs explaining. Runs only over
    /// the (rare, few) unmodeled doses, so it costs nothing on an ordinary session.
    static func unmodeledFormNote(entries: [DoseEntry]) -> UnmodeledFormNote.Content? {
        // Only doses that truly draw nothing — a named ER product with an authored
        // envelope (Concerta) now draws a real curve, so it isn't "unmodeled" here.
        let unmodeled = entries.filter(\.drawsNoAcuteCurve)
        guard !unmodeled.isEmpty else { return nil }
        var seen = Set<String>()
        var pairs: [(product: String, base: String)] = []
        for entry in unmodeled {
            let base = SubstanceLibrary.lookup(entry.substance)?.name ?? entry.substance
            let product = DoseTitle.resolve(for: entry)
            if seen.insert(product.lowercased() + "\u{1}" + base.lowercased()).inserted {
                pairs.append((product, base))
            }
        }
        // Name the form only when there's exactly one and its title isn't just the
        // base with a suffix — "the Methylphenidate XR form of Methylphenidate"
        // reads badly, so that (and any multi-form session) gets the neutral line.
        if pairs.count == 1, !pairs[0].product.localizedCaseInsensitiveContains(pairs[0].base) {
            return .named(product: pairs[0].product, base: pairs[0].base)
        }
        return .generic
    }

    /// Split the session's distinct substances into those the engine models
    /// (they shape the curves) and those it can't (silently dropped) — the
    /// coverage disclaimer's data. Display names, in first-seen order.
    static func mechanisticPartition(
        entries: [DoseEntry],
        pharmacology: [String: PharmacologyParameters],
    ) -> (modeled: [String], ignored: [String]) {
        var seen = Set<String>()
        var modeled: [String] = []
        var ignored: [String] = []
        for entry in entries {
            guard seen.insert(entry.substance.lowercased()).inserted else { continue }
            let display = CustomSubstanceStore.shared.displayName(for: entry.substance)
            let key = SubstanceModelDatabase.normalize(entry.substance)
            // "Modeled" == what `compute` actually simulates: any substance whose params
            // resolve (DB-derived or curated-override-only, e.g. PPAP/BPAP), not just those
            // with a DB pharmacology row.
            if SubstanceModelDatabase.params(name: entry.substance, pharmacology: pharmacology[key]) != nil {
                modeled.append(display)
            } else {
                ignored.append(display)
            }
        }
        return (modeled, ignored)
    }

    /// The guided comedown categories present in this session, first-seen order —
    /// the Recovery section's rows. Empty when nothing logged maps to a category
    /// with dedicated guidance (then the section falls back to a plain link).
    static func recoveryCategories(entries: [DoseEntry]) -> [SubstanceCategory] {
        var seen = Set<SubstanceCategory>()
        var result: [SubstanceCategory] = []
        for entry in entries {
            guard let category = SubstanceLibrary.lookup(entry.substance)?.category,
                  ComedownGuideView.guidedCategories.contains(category),
                  seen.insert(category).inserted else { continue }
            result.append(category)
        }
        return result
    }

    /// The session's notes as graph markers. The summary sits at the session start
    /// and carries no rating, so it is left off the axis — the row list shows it.
    static func noteMarkers(notes: [SessionNote]) -> [NoteMarker] {
        notes
            .filter { $0.kind != .summary }
            .map { NoteMarker(id: $0.id, timestamp: $0.timestamp, kind: $0.kind, shulgin: $0.shulgin) }
    }
}
