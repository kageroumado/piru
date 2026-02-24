import Foundation
import SwiftData

enum ChatContextBuilder {
    static func buildSystemPrompt(context: ModelContext) -> String {
        let recentEntries = fetchRecentEntries(context: context)
        let dailyItems = fetchDailyItems(context: context)

        var prompt = """
        You are a knowledgeable harm reduction assistant integrated into Piru, \
        a substance and medication tracking app. You have access to the user's \
        recent dose history and daily medication schedule.

        Important guidelines:
        - Prioritize safety and harm reduction in all responses.
        - Provide accurate pharmacological information when asked.
        - Never encourage unsafe substance use or dangerous combinations.
        - If asked about dangerous interactions, clearly warn the user.
        - Be concise and helpful. Use plain language.
        - You can reference the user's dose history to answer questions about \
        their usage patterns, timing, and adherence.
        """

        if !dailyItems.isEmpty {
            prompt += "\n\nThe user's daily medication schedule:\n"
            for item in dailyItems {
                prompt += "- \(item.substance): \(item.amount) \(item.unit) (\(item.route.rawValue))\n"
            }
        }

        if !recentEntries.isEmpty {
            prompt += "\n\nRecent dose log (last 14 days):\n"
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            for entry in recentEntries {
                var line = "- \(formatter.string(from: entry.timestamp)): \(entry.substance) \(entry.amount) \(entry.unit) (\(entry.route.rawValue))"
                if let notes = entry.notes, !notes.isEmpty {
                    line += " — \(notes)"
                }
                prompt += line + "\n"
            }
        } else {
            prompt += "\n\nThe user has no recent dose entries in the last 14 days."
        }

        return prompt
    }

    private static func fetchRecentEntries(context: ModelContext) -> [DoseEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        let predicate = #Predicate<DoseEntry> { $0.timestamp >= cutoff }
        var descriptor = FetchDescriptor<DoseEntry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func fetchDailyItems(context: ModelContext) -> [DailyDoseItem] {
        let descriptor = FetchDescriptor<DailyDoseItem>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
