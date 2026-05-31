import Foundation

enum TagExtractor {
    /// Extract hashtags from text (e.g., "#headache #sleep" -> ["headache", "sleep"])
    static func extractTags(from text: String) -> [String] {
        let pattern = #"#(\w+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        var seen = Set<String>()
        return matches.compactMap { match in
            guard let tagRange = Range(match.range(at: 1), in: text) else { return nil }
            let tag = String(text[tagRange]).lowercased()
            guard !seen.contains(tag) else { return nil }
            seen.insert(tag)
            return tag
        }
    }

    /// Common tag suggestions for quick access
    static let suggestions = [
        "headache", "anxiety", "sleep", "pain", "nausea",
        "mood", "energy", "focus", "relax", "appetite",
    ]
}
