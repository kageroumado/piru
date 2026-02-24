import Foundation
import SwiftData

enum ChatContextBuilder {

    // MARK: - System Prompt

    /// Builds a system prompt that includes the user's recent dose history and daily medications.
    static func buildSystemPrompt(
        recentEntries: [DoseEntry],
        dailyItems: [DailyDoseItem]
    ) -> String {
        var parts: [String] = []

        parts.append("""
            You are a knowledgeable harm reduction assistant embedded in Piru, \
            a substance and medication tracking app. You help users understand \
            their medications, substance interactions, dosing, and general \
            pharmacology. You prioritize safety and harm reduction.

            Important guidelines:
            - Always recommend consulting a healthcare professional for medical decisions
            - Provide evidence-based harm reduction information
            - Be direct and factual about substance pharmacology
            - If you're unsure about something, say so clearly
            - Never encourage dangerous substance use
            - You may reference the user's logged data to provide personalized context
            """)

        if !dailyItems.isEmpty {
            var section = "The user's daily medications are:\n"
            for item in dailyItems {
                section += "- \(item.substance) \(item.amount.doseFormatted) \(item.unit) (\(item.route.displayName))\n"
            }
            parts.append(section)
        }

        if !recentEntries.isEmpty {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short

            var section = "The user's recent dose log (last 14 days):\n"
            for entry in recentEntries.prefix(50) {
                let dateStr = formatter.string(from: entry.timestamp)
                var line = "- \(dateStr): \(entry.substance) \(entry.amount.doseFormatted) \(entry.unit) (\(entry.route.displayName))"
                if let notes = entry.notes, !notes.isEmpty {
                    line += " — \(notes)"
                }
                section += line + "\n"
            }
            parts.append(section)
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Data Fetching

    /// Fetches recent entries (last 14 days) sorted by timestamp descending.
    static func fetchRecentEntries(context: ModelContext) -> [DoseEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        var descriptor = FetchDescriptor<DoseEntry>(
            predicate: #Predicate { $0.timestamp >= cutoff },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Fetches all daily dose items sorted by sort order.
    static func fetchDailyItems(context: ModelContext) -> [DailyDoseItem] {
        let descriptor = FetchDescriptor<DailyDoseItem>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
