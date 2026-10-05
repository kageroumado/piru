import Foundation

/// Published reference data, deliberately separate from DurationProfile's
/// sequential lengths and its missing-phase synthesis.
struct WikiTimingRecord: Identifiable {
    let id: String
    let sourceName: String
    let route: String?
    let kind: String
    let entryIndex: Int
    let releaseID: String?
    let hasSourceException: Bool
    let formulation: String?
    let curve: WikiTimingCurve?
    let study: WikiTimingStudy?
    let timingText: [String: String]

    init(
        id: String, sourceName: String, route: String?, kind: String,
        entryIndex: Int, releaseID: String?, entryJSON: String, timingTextJSON: String,
        hasSourceException: Bool = false,
    ) throws {
        self.id = id
        self.sourceName = sourceName
        self.route = route
        self.kind = kind
        self.entryIndex = entryIndex
        self.releaseID = releaseID
        self.hasSourceException = hasSourceException
        let decoder = JSONDecoder()
        let data = Data(entryJSON.utf8)
        if kind == "duration_study" {
            study = try decoder.decode(WikiTimingStudy.self, from: data)
            curve = nil
            formulation = study?.context.formulation
        } else {
            let entry = try decoder.decode(WikiTimingEntry.self, from: data)
            curve = kind == "partial_duration_curve" ? entry.partialCurve : entry.curve
            formulation = entry.formulation
            study = nil
        }
        timingText = try decoder.decode([String: String].self, from: Data(timingTextJSON.utf8))
    }

    var sourceURL: URL? {
        let slug = sourceName.decomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "[\\u0300-\\u036f]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "α", with: "alpha")
            .replacingOccurrences(of: "β", with: "beta")
            .replacingOccurrences(of: "Δ", with: "delta")
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return URL(string: "https://substance.wiki/drug/\(slug)")
    }
}

private struct WikiTimingEntry: Decodable {
    let curve: WikiTimingCurve?
    let partialCurve: WikiTimingCurve?
    let formulation: String?

    enum CodingKeys: String, CodingKey {
        case curve = "duration_curve"
        case partialCurve = "partial_duration_curve"
        case formulation
    }
}

struct WikiTimingWindow: Decodable {
    let start: Double?
    let end: Double?
}

struct WikiTimingTotal: Decodable {
    let min: Double?
    let max: Double?
    let note: String?
}

struct WikiTimingCurve: Decodable {
    let units: String?
    let onset: WikiTimingWindow?
    let peak: WikiTimingWindow?
    let offset: WikiTimingWindow?
    let afterEffects: WikiTimingWindow?
    let total: WikiTimingTotal?
    let reference: String?

    enum CodingKeys: String, CodingKey {
        case units
        case onset
        case peak
        case offset
        case reference
        case afterEffects = "after_effects"
        case total = "total_duration"
    }

    var plotMaximum: Double? {
        let values = [
            onset?.start,
            onset?.end,
            peak?.start,
            peak?.end,
            offset?.start,
            offset?.end,
            afterEffects?.start,
            afterEffects?.end,
        ]
        .compactMap(\.self).filter { $0.isFinite && $0 >= 0 }
        guard let maximum = values.max(), maximum > 0 else { return nil }
        return maximum
    }
}

struct WikiTimingStudy: Decodable {
    let schemaVersion: String
    let id: String
    let units: String
    let nominalStudyDoseMicrogramsBase: Double
    let context: Context
    let points: [Statistic]
    let activeDuration: Statistic
    let rangeMeaning: String
    let source: Source

    struct Context: Decodable {
        let route: String
        let formulation: String
        let population: String
        let participantCount: Int
        let endpoint: String
        let clockOrigin: String
        let condition: String
        let studyDesign: String
        let onsetOffsetThresholdFraction: Double
        let thresholdBasis: String
    }

    struct Statistic: Decodable, Identifiable {
        let key: String?
        let label: String?
        let mean: Double
        let standardDeviation: Double
        let participantRange: Range
        let quantity: String
        let sourceCell: String

        var id: String { key ?? sourceCell }
    }

    struct Range: Decodable {
        let min: Double
        let max: Double
    }

    struct Source: Decodable {
        let articleUrl: String
        let tableUrl: String
        let doi: String
        let locator: String
    }
}
