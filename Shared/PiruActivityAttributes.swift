import ActivityKit
import Foundation

struct PiruActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var activeSubstances: [ActiveSubstanceState]
        var lastUpdated: Date
    }

    let startTime: Date
}

struct ActiveSubstanceState: Codable, Hashable {
    let substanceName: String
    let colorHex: String
    let doseTimestamp: Date
    let amount: Double
    let unit: String
    let route: String
    let onsetEndMinutes: Double
    let comeupEndMinutes: Double
    let peakEndMinutes: Double
    let offsetEndMinutes: Double
    let afterglowEndMinutes: Double?
    let totalMinutes: Double
    /// How intense this dose is relative to the substance's heavy threshold (0.15...1.0).
    /// Substances without dose range data default to 1.0.
    let doseIntensity: Double

    init(substanceName: String, colorHex: String, doseTimestamp: Date, amount: Double, unit: String, route: String, onsetEndMinutes: Double, comeupEndMinutes: Double, peakEndMinutes: Double, offsetEndMinutes: Double, afterglowEndMinutes: Double?, totalMinutes: Double, doseIntensity: Double = 1.0) {
        self.substanceName = substanceName
        self.colorHex = colorHex
        self.doseTimestamp = doseTimestamp
        self.amount = amount
        self.unit = unit
        self.route = route
        self.onsetEndMinutes = onsetEndMinutes
        self.comeupEndMinutes = comeupEndMinutes
        self.peakEndMinutes = peakEndMinutes
        self.offsetEndMinutes = offsetEndMinutes
        self.afterglowEndMinutes = afterglowEndMinutes
        self.totalMinutes = totalMinutes
        self.doseIntensity = doseIntensity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        substanceName = try c.decode(String.self, forKey: .substanceName)
        colorHex = try c.decode(String.self, forKey: .colorHex)
        doseTimestamp = try c.decode(Date.self, forKey: .doseTimestamp)
        amount = try c.decode(Double.self, forKey: .amount)
        unit = try c.decode(String.self, forKey: .unit)
        route = try c.decode(String.self, forKey: .route)
        onsetEndMinutes = try c.decode(Double.self, forKey: .onsetEndMinutes)
        comeupEndMinutes = try c.decode(Double.self, forKey: .comeupEndMinutes)
        peakEndMinutes = try c.decode(Double.self, forKey: .peakEndMinutes)
        offsetEndMinutes = try c.decode(Double.self, forKey: .offsetEndMinutes)
        afterglowEndMinutes = try c.decodeIfPresent(Double.self, forKey: .afterglowEndMinutes)
        totalMinutes = try c.decode(Double.self, forKey: .totalMinutes)
        doseIntensity = try c.decodeIfPresent(Double.self, forKey: .doseIntensity) ?? 1.0
    }
}
