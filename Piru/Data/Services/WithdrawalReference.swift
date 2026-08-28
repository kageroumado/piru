import Foundation

/// Coarse benzodiazepine duration class for the withdrawal-onset bands. A drug lands in one by its
/// **metabolite-extended** effective half-life, so a prodrug or short parent whose long-acting active
/// metabolite dominates the tail (chlordiazepoxide, clorazepate, ketazolam → nordazepam, t½ ≈ 70 h)
/// reads as long-acting because its metabolite is.
///
/// The order short → intermediate → long is the vocabulary's own, which is why ``rank`` is here and
/// not a column: the half-life intervals in `withdrawal_timing_bands` already say the same thing, and
/// a second stored ordering could only disagree with them.
nonisolated enum WithdrawalActingClass: String, Hashable, Sendable, CaseIterable {
    case short
    case intermediate
    case long

    /// Sort key: longer-acting ranks higher (governs the conservative onset placement).
    var rank: Int {
        switch self {
        case .short: 0
        case .intermediate: 1
        case .long: 2
        }
    }

    /// The band's name as the reader sees it.
    var title: LocalizedStringResource {
        switch self {
        case .short: "short-acting"
        case .intermediate: "intermediate"
        case .long: "long-acting"
        }
    }

    /// The recognisable drugs named as this band's examples. Kept as copy rather than read from
    /// `withdrawal_acting_class` because the names are translated — a Chinese reader sees 地西泮, and
    /// the database carries one canonical English name per substance. `WithdrawalReferenceTests`
    /// gates this list against the rows so a reclassified drug cannot leave a stale example behind.
    var examples: LocalizedStringResource {
        switch self {
        case .short: "triazolam, alprazolam, lorazepam, oxazepam"
        case .intermediate: "temazepam, bromazepam"
        case .long: "diazepam, chlordiazepoxide, clonazepam"
        }
    }
}

/// One onset/peak timing band: the effective-half-life interval that selects it, and the population
/// windows it carries. Windows are hours for every band so they stay comparable; the phrase a reader
/// sees picks days or hours for itself.
nonisolated struct TimingBand: Identifiable, Sendable {
    let actingClass: WithdrawalActingClass
    /// Inclusive lower bound of the effective-half-life interval this band covers.
    let minHalfLifeMinutes: Double
    /// Exclusive upper bound; `nil` for the unbounded longest-acting band.
    let maxHalfLifeMinutes: Double?
    /// When withdrawal peaks for this half-life class. `nil` when no source states one — the
    /// intermediate band, which no trial measured. A band with no window says nothing rather than
    /// interpolating between the two arms that were measured.
    let peakHours: ClosedRange<Double>?

    var id: Int {
        actingClass.rank
    }

    func contains(halfLifeMinutes minutes: Double) -> Bool {
        minutes >= minHalfLifeMinutes && (maxHalfLifeMinutes.map { minutes < $0 } ?? true)
    }

    /// The window as words, or `nil` when this band has none.
    var peakPhrase: String? {
        peakHours.map(Self.phrase)
    }

    /// Hours while the window fits inside a day, days once it does not — and days only when both
    /// bounds are whole days, so a 36-hour bound is never rounded away into "1–2 days".
    ///
    /// A window whose bounds coincide renders as one figure. Rickels measured the short-half-life
    /// peak at a single day, and "2–2 days" would read as a rounding artefact rather than as the
    /// precision the trial actually reported.
    private static func phrase(_ hours: ClosedRange<Double>) -> String {
        let (lower, upper) = (hours.lowerBound, hours.upperBound)
        let wholeDays = lower.truncatingRemainder(dividingBy: 24) == 0
            && upper.truncatingRemainder(dividingBy: 24) == 0
        if upper > 24, wholeDays {
            let (lowDays, highDays) = (Int(lower / 24), Int(upper / 24))
            return lowDays == highDays
                ? String(localized: "\(lowDays) days")
                : String(localized: "\(lowDays)–\(highDays) days")
        }
        return Int(lower) == Int(upper)
            ? String(localized: "\(Int(lower)) hours")
            : String(localized: "\(Int(lower))–\(Int(upper)) hours")
    }
}

/// The benzodiazepine discontinuation reference's population tables, resolved from the bundled DB's
/// `withdrawal_timing_bands` and `withdrawal_acting_class` and held as one value so the screen reads
/// them once.
///
/// The peak windows are Rickels 1990's two measured arms; the intermediate band carries none,
/// because no trial measured a middle one. Each band row's `notes` in the database records what its
/// window rests on, and why the onset windows this used to carry are gone.
nonisolated struct WithdrawalReference: Sendable {
    /// Longest-acting first, so the governing band reads at the top.
    let bands: [TimingBand]
    /// Lowercased drug name → the clinical floor the database places that drug at. The drugs a band
    /// names as its examples are exactly its entries here.
    let floors: [String: WithdrawalActingClass]

    init(bands: [TimingBand], floors: [String: WithdrawalActingClass]) {
        self.bands = bands.sorted { $0.actingClass.rank > $1.actingClass.rank }
        self.floors = floors
    }

    /// What the screen shows before the first read lands, and what it shows if the reference tables
    /// are missing: no bands, and every drug on its half-life alone.
    static let empty = WithdrawalReference(bands: [], floors: [:])

    func band(for actingClass: WithdrawalActingClass) -> TimingBand? {
        bands.first { $0.actingClass == actingClass }
    }

    /// The band a half-life falls in, or `nil` when no band covers it.
    func band(forMinutes minutes: Double) -> WithdrawalActingClass? {
        bands.first { $0.contains(halfLifeMinutes: minutes) }?.actingClass
    }

    /// The longer-acting of the drug's clinical floor and the band implied by its
    /// **metabolite-extended** half-life. `effectiveHalfLifeMinutes` is the slowest of the parent's
    /// own half-life and its foldable active metabolites'; `nil` falls back to the parent's half-life
    /// alone. Metabolite data only lengthens the band, so the two sources combine by taking the
    /// longer-acting.
    func classify(name: String, effectiveHalfLifeMinutes: Double?) -> WithdrawalActingClass {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        let metaboliteBand = effectiveHalfLifeMinutes.flatMap(band(forMinutes:))
        if let floor = floors[key] {
            return [floor, metaboliteBand].compactMap(\.self).max { $0.rank < $1.rank } ?? floor
        }
        if let metaboliteBand { return metaboliteBand }
        return .intermediate
    }
}
