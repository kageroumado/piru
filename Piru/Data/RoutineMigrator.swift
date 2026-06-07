import Foundation
import SwiftData

/// One-time bootstrap of ``DoseRoutine`` rows from the pre-routines data:
/// the ordered `dailyDoseCategories` AppStorage list, any stray item
/// categories, and a "Daily" routine that adopts uncategorized items.
///
/// Runs wherever routines are first needed (quick-log, the Routines screen);
/// a non-zero `DoseRoutine` count makes it a no-op, so calling it from
/// several places is safe.
@MainActor
enum RoutineMigrator {
    static func seedIfNeeded(context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<DoseRoutine>())) ?? 0
        guard existing == 0 else { return }

        let items = (try? context.fetch(FetchDescriptor<DailyDoseItem>())) ?? []

        var names: [String] = []
        if let data = UserDefaults.standard.data(forKey: "dailyDoseCategories"),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            names = decoded
        }
        for item in items where !item.category.isEmpty && !names.contains(item.category) {
            names.append(item.category)
        }

        // Uncategorized items become a "Daily" routine so every item lives in
        // exactly one routine going forward.
        let uncategorized = items.filter(\.category.isEmpty)
        if !uncategorized.isEmpty {
            let fallback = String(localized: "Daily")
            if !names.contains(fallback) {
                names.append(fallback)
            }
            for item in uncategorized {
                item.category = fallback
            }
        }

        for (index, name) in names.enumerated() {
            context.insert(DoseRoutine(name: name, sortOrder: index))
        }
    }
}
