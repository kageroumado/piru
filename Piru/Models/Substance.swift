import Foundation

struct DoseRange {
    let threshold: Double?
    let light: ClosedRange<Double>?
    let common: ClosedRange<Double>?
    let strong: ClosedRange<Double>?
    let heavy: Double?
    let fatal: Double?

    init(
        threshold: Double?,
        light: ClosedRange<Double>?,
        common: ClosedRange<Double>?,
        strong: ClosedRange<Double>?,
        heavy: Double?,
        fatal: Double? = nil
    ) {
        self.threshold = threshold
        self.light = light
        self.common = common
        self.strong = strong
        self.heavy = heavy
        self.fatal = fatal
    }

    func level(for dose: Double) -> DoseLevel {
        if let fatal, dose >= fatal { return .fatal }
        if let heavy, dose >= heavy { return .heavy }
        if let strong, strong.contains(dose) || dose > strong.upperBound { return .strong }
        if let common, common.contains(dose) || dose > common.upperBound { return .common }
        if let light, light.contains(dose) || dose > light.upperBound { return .light }
        if let threshold, dose >= threshold { return .threshold }
        return .sub
    }
}

enum DoseLevel: String, CaseIterable {
    case sub = "Sub-threshold"
    case threshold = "Threshold"
    case light = "Light"
    case common = "Common"
    case strong = "Strong"
    case heavy = "Heavy"
    case fatal = "Fatal Overdose"
}

extension Double {
    /// Format a dose value: show integer for whole numbers under 10000, otherwise default formatting
    var doseFormatted: String {
        if self == rounded() && self < 10000 {
            return String(format: "%.0f", self)
        }
        return formatted()
    }
}

// MARK: - Duration

struct TimeRange {
    let min: Double
    let max: Double

    var midpoint: Double { (min + max) / 2 }

    var displayString: String {
        if max >= 120 {
            let minH = min / 60
            let maxH = max / 60
            return "~\(Self.fmt(minH))-\(Self.fmt(maxH)) hours"
        }
        return "~\(Self.fmt(min))-\(Self.fmt(max)) minutes"
    }

    private static func fmt(_ v: Double) -> String {
        v == v.rounded(.toNearestOrEven) ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }
}

struct DurationProfile {
    let onset: TimeRange?
    let comeup: TimeRange?
    let peak: TimeRange?
    let offset: TimeRange?
    let afterglow: TimeRange?
    let total: TimeRange?

    var estimatedTotalMinutes: Double {
        if let total { return total.midpoint }
        let phases = [onset, comeup, peak, offset].compactMap { $0?.midpoint }
        return phases.reduce(0, +)
    }

    var phaseBoundaries: PhaseBoundaries {
        let onsetEnd = onset?.midpoint ?? 0
        let comeupEnd = onsetEnd + (comeup?.midpoint ?? 0)
        let peakEnd = comeupEnd + (peak?.midpoint ?? 0)
        let offsetEnd = peakEnd + (offset?.midpoint ?? 0)
        let afterglowEnd = offsetEnd + (afterglow?.midpoint ?? 0)
        return PhaseBoundaries(
            onsetEnd: onsetEnd,
            comeupEnd: comeupEnd,
            peakEnd: peakEnd,
            offsetEnd: offsetEnd,
            afterglowEnd: afterglowEnd
        )
    }
}

struct PhaseBoundaries {
    let onsetEnd: Double
    let comeupEnd: Double
    let peakEnd: Double
    let offsetEnd: Double
    let afterglowEnd: Double
}

// MARK: - Route

struct SubstanceRoute {
    let route: RouteOfAdministration
    let unit: String
    let doses: DoseRange
    let duration: DurationProfile?

    init(
        route: RouteOfAdministration,
        unit: String,
        doses: DoseRange,
        duration: DurationProfile? = nil
    ) {
        self.route = route
        self.unit = unit
        self.doses = doses
        self.duration = duration
    }
}

enum SubstanceCategory: String, CaseIterable, Identifiable {
    case stimulant = "Stimulant"
    case psychedelic = "Psychedelic"
    case dissociative = "Dissociative"
    case opioid = "Opioid"
    case benzodiazepine = "Benzodiazepine"
    case gabapentinoid = "GABAergic"
    case empathogen = "Empathogen"
    case cannabinoid = "Cannabinoid"
    case nootropic = "Nootropic"
    case depressant = "Depressant"
    case antidepressant = "Antidepressant"
    case antipsychotic = "Antipsychotic"
    case analgesic = "Analgesic"
    case antihistamine = "Antihistamine"
    case supplement = "Supplement"
    case other = "Other"

    var id: String { rawValue }
}

struct SubjectiveEffect {
    let name: String
    let description: String
}

struct ToleranceInfo {
    let halfLife: Double       // days for tolerance to halve
    let fullResetDays: Double  // days for full tolerance reset
    let buildRate: String      // "rapid" | "moderate" | "slow"
}

struct Substance: Identifiable {
    let id = UUID()
    let name: String
    let aliases: [String]
    let category: SubstanceCategory
    let defaultRoute: RouteOfAdministration
    let routes: [SubstanceRoute]
    let effects: [String]
    let subjectiveEffects: [SubjectiveEffect]
    let toleranceInfo: ToleranceInfo?
    let halfLifeMinutes: Double?

    init(
        name: String,
        aliases: [String],
        category: SubstanceCategory,
        defaultRoute: RouteOfAdministration,
        routes: [SubstanceRoute],
        effects: [String],
        subjectiveEffects: [SubjectiveEffect] = [],
        toleranceInfo: ToleranceInfo? = nil,
        halfLifeMinutes: Double? = nil
    ) {
        self.name = name
        self.aliases = aliases
        self.category = category
        self.defaultRoute = defaultRoute
        self.routes = routes
        self.effects = effects
        self.subjectiveEffects = subjectiveEffects
        self.toleranceInfo = toleranceInfo
        self.halfLifeMinutes = halfLifeMinutes
    }

    var defaultUnit: String {
        routes.first { $0.route == defaultRoute }?.unit
            ?? routes.first?.unit
            ?? "mg"
    }

    func doseRange(for route: RouteOfAdministration) -> DoseRange? {
        routes.first { $0.route == route }?.doses
    }

    func unit(for route: RouteOfAdministration) -> String {
        routes.first { $0.route == route }?.unit ?? defaultUnit
    }

    func duration(for route: RouteOfAdministration) -> DurationProfile? {
        routes.first { $0.route == route }?.duration
    }

    func matches(_ query: String) -> Bool {
        let q = query.lowercased()
        return name.lowercased().contains(q)
            || aliases.contains { $0.lowercased().contains(q) }
    }
}
