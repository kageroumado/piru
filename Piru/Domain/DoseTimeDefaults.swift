import Foundation

/// The user-configurable relative-time presets shown in the "When" menu, stored
/// as a comma-joined list of minutes in the shared app-group suite. Parse falls
/// back to the defaults for empty/garbled input, so a bad write can never leave
/// the menu with no quick times.
enum DoseTimeDefaults {
    static let suite = AppIdentity.appGroup
    static let choicesKey = "doseTimeOffsetChoices"

    static let defaultChoices = [15, 30, 60, 120]
    static let defaultRaw = "15,30,60,120"

    /// A single preset spans one minute to a full day.
    static let range = 1 ... (24 * 60)
    /// The menu stays legible with a bounded number of presets.
    static let maxCount = 6

    static func parse(_ raw: String) -> [Int] {
        let minutes = raw
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { range.contains($0) }
        return minutes.isEmpty ? defaultChoices : minutes
    }

    static func format(_ choices: [Int]) -> String {
        choices.map(String.init).joined(separator: ",")
    }
}
