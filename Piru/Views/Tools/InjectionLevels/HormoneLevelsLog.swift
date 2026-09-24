import Foundation

/// Reads the dose log into **per-ester** injection buckets for the Hormone Levels
/// insight (Specs/injection-levels-v3.md §4). Where the prediction Tool collapses the
/// log to one dominant ester, this keeps each ester distinct: a valerate → cypionate
/// switch, or a mix of two esters at different concentrations, is grouped by the ester
/// named on each dose's `saltForm` so the serum total can sum each ester's own depot
/// curve instead of flattening everything to one shape.
enum HormoneLevelsLog {
    /// The log grouped by resolved ester for one analyte.
    struct Grouped {
        /// One entry per **modelable** ester the user logged, each carrying that
        /// ester's own doses in mass (mg). The summed serum curve is built from these.
        var esterGroups: [(ester: EsterPKRecord, injections: [(date: Date, doseMg: Double)])] = []
        /// Doses of a catalog-only ester (no validated curve, e.g. Undecylate):
        /// drawn as a labeled marker, never a fabricated curve.
        var catalogOnlyMarkers: [(ester: EsterPKRecord, date: Date)] = []
        /// Injections logged in mL that await a vial strength before they can join.
        var volumeLoggedCount = 0

        /// Whether any modelable ester has a dose to draw.
        var hasModelableInjections: Bool {
            esterGroups.contains { !$0.injections.isEmpty }
        }

        /// Every modelable injection, flattened — the calibration set and the log-only
        /// span both read the whole history regardless of which ester each dose was.
        var allInjections: [(date: Date, doseMg: Double)] {
            esterGroups.flatMap(\.injections).sorted { $0.date < $1.date }
        }
    }

    /// Whether the log holds any injectable hormone dose at all — a cheap gate for
    /// whether to show the Hormone Levels card, without building every curve. True for
    /// any IM/SC dose in an analyte family that ships ester data (even an mL-only dose
    /// still awaiting a vial strength). Requires ``SubstanceStore`` loaded.
    static func hasInjectableHormone(in entries: [DoseEntry]) -> Bool {
        let store = SubstanceStore.shared
        for analyte in Analyte.allCases {
            guard store.analytesWithEsterData().contains(analyte.key) else { continue }
            let familyUIDs = Set(store.estersForAnalyte(analyte.key).compactMap(\.parentUID))
            guard !familyUIDs.isEmpty else { continue }
            for entry in entries {
                guard entry.route == .intramuscular || entry.route == .subcutaneous else { continue }
                let uid = entry.substanceUID ?? store.substanceUID(forNameOrAlias: entry.substance)
                if let uid, familyUIDs.contains(uid) { return true }
            }
        }
        return false
    }

    /// Bucket the log's qualifying IM/SC doses for `analyte` by their own ester. A dose
    /// that names no ester falls back to the analyte's default (the ester the user logs
    /// most, else the first modelable one) — the same default the Tool opens on.
    static func grouped(
        from entries: [DoseEntry],
        analyte: Analyte,
        volumeConcentrationMgPerML: Double?,
    ) -> Grouped {
        let store = SubstanceStore.shared
        let modelable = store.estersForAnalyte(analyte.key) // modelable only, ester-id-ordered
        let familyUIDs = Set(modelable.compactMap(\.parentUID))
        var result = Grouped()
        guard !familyUIDs.isEmpty else { return result }

        let defaultEsterID = InjectionLevelsView.dominantEsterID(from: entries, analyte: analyte)
            ?? modelable.first?.esterID

        var buckets: [String: [(date: Date, doseMg: Double)]] = [:]
        var markers: [(ester: EsterPKRecord, date: Date)] = []

        for entry in entries {
            guard entry.route == .intramuscular || entry.route == .subcutaneous else { continue }
            let uid = entry.substanceUID ?? store.substanceUID(forNameOrAlias: entry.substance)
            guard let uid, familyUIDs.contains(uid) else { continue }

            // Resolve this dose's ester from its own `saltForm` (a legacy dose names it
            // in the substance string), falling back to the analyte default.
            let label = entry.saltForm ?? store.saltForm(forNameOrAlias: entry.substance)
            let record: EsterPKRecord? = if let label,
                                            let match = store.esters(forParentUID: uid).first(where: { $0.label == label }) {
                match
            } else {
                defaultEsterID.flatMap { store.esterPK(forEsterID: $0) }
            }

            let mass = InjectionLevelsView.doseMassMg(entry, volumeConcentrationMgPerML: volumeConcentrationMgPerML)
            if mass.isVolumeUnit { result.volumeLoggedCount += 1 }
            guard let record else { continue }
            if record.isModelable {
                guard let mg = mass.mg else { continue }
                buckets[record.esterID, default: []].append((entry.timestamp, mg))
            } else {
                markers.append((ester: record, date: entry.timestamp))
            }
        }

        result.esterGroups = buckets
            .sorted { $0.key < $1.key }
            .compactMap { id, doses in
                store.esterPK(forEsterID: id).map { (ester: $0, injections: doses.sorted { $0.date < $1.date }) }
            }
        result.catalogOnlyMarkers = markers.sorted { $0.date < $1.date }
        return result
    }
}
