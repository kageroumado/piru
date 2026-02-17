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
}
