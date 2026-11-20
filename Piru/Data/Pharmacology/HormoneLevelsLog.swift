import Foundation

/// Reads the dose log for the depot-ester curves. ``injections(from:analyte:volumeConcentrationMgPerML:)``
/// and ``dominantEsterID(from:analyte:)`` feed the prediction Tool, which collapses
/// the log to one dominant ester; ``grouped(from:analyte:volumeConcentrationMgPerML:)``
/// feeds the Hormone Levels insight, which keeps each ester distinct: a valerate →
/// cypionate switch, or a mix of two esters at different concentrations, is grouped by
/// the ester named on each dose's `saltForm` so the serum total can sum each ester's
/// own depot curve instead of flattening everything to one shape.
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

        let defaultEsterID = dominantEsterID(from: entries, analyte: analyte)
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

            let mass = doseMassMg(entry, volumeConcentrationMgPerML: volumeConcentrationMgPerML)
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

    /// What the dose log holds for an analyte: the injections the curve can use, how
    /// many more were logged in mL and await a vial concentration, and the
    /// concentration the user most recently logged a volumetric dose at.
    struct LogInjections {
        var injections: [(date: Date, doseMg: Double)] = []
        var volumeLoggedCount = 0
        var latestLoggedConcentration: Double?
    }

    /// Pull qualifying injections from the dose log for an analyte: IM/SC route and a
    /// substance in the analyte's PSID family. A dose in mg (or µg) joins as is; a
    /// dose logged in mL joins at `volumeConcentrationMgPerML`, and is only counted
    /// while that is unset.
    static func injections(
        from entries: [DoseEntry],
        analyte: Analyte,
        volumeConcentrationMgPerML: Double? = nil,
    ) -> LogInjections {
        let store = SubstanceStore.shared
        let familyUIDs = Set(store.estersForAnalyte(analyte.key).compactMap(\.parentUID))
        guard !familyUIDs.isEmpty else { return LogInjections() }
        var log = LogInjections()
        for entry in entries {
            guard entry.route == .intramuscular || entry.route == .subcutaneous else { continue }
            let uid = entry.substanceUID ?? store.substanceUID(forNameOrAlias: entry.substance)
            guard let uid, familyUIDs.contains(uid) else { continue }
            // A dose logged by volume × concentration keeps its mass in `amount`;
            // its concentration is the best default for the mL-only doses.
            if entry.volumeML != nil, let concentration = entry.abv, concentration > 0 {
                log.latestLoggedConcentration = concentration
            }
            let mass = doseMassMg(entry, volumeConcentrationMgPerML: volumeConcentrationMgPerML)
            if mass.isVolumeUnit { log.volumeLoggedCount += 1 }
            guard let mg = mass.mg else { continue }
            log.injections.append((entry.timestamp, mg))
        }
        return log
    }

    /// The injectable mass one logged dose contributes (canonical mg), and whether it
    /// was logged in a volume unit. A dose in µg/mg/g converts to mg; a dose
    /// in mL joins at `volumeConcentrationMgPerML` (its `mg` is `nil` until a vial
    /// strength is known, but it is still counted as volume-logged). Anything else
    /// (a non-mass, non-volume unit) contributes nothing.
    static func doseMassMg(
        _ entry: DoseEntry, volumeConcentrationMgPerML: Double?,
    ) -> (mg: Double?, isVolumeUnit: Bool) {
        switch entry.quantity {
        case let .mass(mass)?:
            let mg = mass.value(in: .milligrams)
            return (mg > 0 ? mg : nil, false)
        case let .volume(volume)?:
            guard let concentration = volumeConcentrationMgPerML, concentration > 0 else { return (nil, true) }
            let mg = volume.converted(to: .milliliters).value * concentration
            return (mg > 0 ? mg : nil, true)
        case .count?, nil:
            return (nil, false)
        }
    }

    /// The modelable ester the user logs most for `analyte`, from the ester named on
    /// their qualifying doses' `saltForm` — the log-first default ester. `nil` when
    /// no logged dose names a modelable ester (→ fall back to the first ester).
    static func dominantEsterID(from entries: [DoseEntry], analyte: Analyte) -> String? {
        let store = SubstanceStore.shared
        let esters = store.estersForAnalyte(analyte.key) // modelable only
        let familyUIDs = Set(esters.compactMap(\.parentUID))
        guard !familyUIDs.isEmpty else { return nil }
        var counts: [String: Int] = [:] // esterID → times logged
        for entry in entries {
            guard entry.route == .intramuscular || entry.route == .subcutaneous else { continue }
            let uid = entry.substanceUID ?? store.substanceUID(forNameOrAlias: entry.substance)
            // A dose logged before esters moved onto `saltForm` names its ester in
            // the substance string ("Estradiol Enanthate").
            let label = entry.saltForm ?? store.saltForm(forNameOrAlias: entry.substance)
            guard let uid, familyUIDs.contains(uid), let label else { continue }
            guard let esterID = esters.first(where: { $0.label == label && $0.parentUID == uid })?.esterID else { continue }
            counts[esterID, default: 0] += 1
        }
        // Most-logged wins; ties break on esterID for a stable default.
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.first?.key
    }

    /// The median gap between consecutive injection dates, in days — the cycle a
    /// chart projects past the last dose. `dates` must be sorted ascending; `nil`
    /// with fewer than two distinct dates.
    static func medianIntervalDays(_ dates: [Date]) -> Double? {
        guard dates.count >= 2 else { return nil }
        let gaps = zip(dates.dropFirst(), dates).map { $0.timeIntervalSince($1) / PKModel.secondsPerDay }
            .filter { $0 > 0 }.sorted()
        guard !gaps.isEmpty else { return nil }
        return gaps[gaps.count / 2]
    }
}
