import Foundation

/// Distress-keyword detection shared by the quick-log dock and the library
/// search, so both surface crisis resources for the same queries and the
/// matchers can't drift apart.
enum CrisisKeywords {
    private static let keywords: Set<String> = [
        "help", "emergency", "overdose", "bad trip", "dying", "scared",
        "panic", "ambulance", "hospital", "not okay", "freaking out",
        "call 911", "911", "poisoning", "too much", "od", "can't breathe",
    ]

    /// Whether the query reads as a call for help. Single-word keywords match
    /// on whole-word boundaries so a substance name that merely *contains* a
    /// keyword as a substring (e.g. "armod" contains "od") doesn't trip the
    /// crisis panel. Multi-word keywords ("bad trip", "call 911") are matched
    /// as phrases.
    static func matches(_ query: String) -> Bool {
        let query = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return false }
        let words = Set(query.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        return keywords.contains { keyword in
            keyword.contains(" ") ? query.contains(keyword) : words.contains(keyword)
        }
    }
}
