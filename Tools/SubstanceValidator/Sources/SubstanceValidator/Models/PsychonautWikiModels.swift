import Foundation

// MARK: - PsychonautWiki GraphQL Response

struct PWGraphQLResponse: Codable {
    let data: PWData?
    let errors: [PWError]?
}

struct PWError: Codable {
    let message: String
}

struct PWData: Codable {
    let substances: [PWSubstance]?
}

struct PWSubstance: Codable {
    let name: String
    let summary: String?
    let roas: [PWROA]?
    let effects: [PWEffect]?
    let toxicity: [String]?
    let addictionPotential: String?
    let crossTolerances: [String]?
    let classes: PWClasses?
    let tolerance: PWTolerance?
}

struct PWROA: Codable {
    let name: String?
    let dose: PWDose?
    let duration: PWDuration?
}

struct PWDose: Codable {
    let units: String?
    let threshold: Double?
    let light: PWRange?
    let common: PWRange?
    let strong: PWRange?
    let heavy: Double?
}

struct PWRange: Codable {
    let min: Double?
    let max: Double?

    var closedRange: ClosedRange<Double>? {
        guard let min, let max else { return nil }
        return min...max
    }
}

struct PWDuration: Codable {
    let onset: PWTimeRange?
    let comeup: PWTimeRange?
    let peak: PWTimeRange?
    let offset: PWTimeRange?
    let afterglow: PWTimeRange?
    let total: PWTimeRange?
    let duration: PWTimeRange?
}

struct PWTimeRange: Codable {
    let min: Double?
    let max: Double?
    let units: String?
}

struct PWEffect: Codable {
    let name: String?
    let url: String?
}

struct PWClasses: Codable {
    let chemical: [String]?
    let psychoactive: [String]?
}

struct PWTolerance: Codable {
    let full: String?
    let half: String?
    let zero: String?
}
