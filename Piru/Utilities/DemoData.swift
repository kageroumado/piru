import SwiftData
import Foundation

#if DEBUG
enum DemoData {
    @MainActor
    static func insertIfNeeded(container: ModelContainer) {
        let context = container.mainContext
        let descriptor = FetchDescriptor<DoseEntry>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        
        // Only insert if there are fewer than 5 entries
        guard count < 5 else { return }
        
        let now = Date()
        let cal = Calendar.current
        
        // Today's entries — will show nice overlapping PK curves
        let today = cal.startOfDay(for: now)
        
        let entries: [DoseEntry] = [
            // Today
            DoseEntry(substance: "Caffeine", amount: 200, unit: "mg", route: .oral,
                     timestamp: today.addingTimeInterval(8 * 3600), // 8am
                     tags: ["morning"]),
            DoseEntry(substance: "Vyvanse", amount: 30, unit: "mg", route: .oral,
                     timestamp: today.addingTimeInterval(8.5 * 3600), // 8:30am
                     notes: "With breakfast", tags: ["daily", "prescription"]),
            DoseEntry(substance: "Magnesium", amount: 400, unit: "mg", route: .oral,
                     timestamp: today.addingTimeInterval(9 * 3600), // 9am
                     tags: ["supplement"]),
            DoseEntry(substance: "Caffeine", amount: 100, unit: "mg", route: .oral,
                     timestamp: today.addingTimeInterval(13 * 3600), // 1pm
                     tags: ["afternoon"]),
            DoseEntry(substance: "L-Theanine", amount: 200, unit: "mg", route: .oral,
                     timestamp: today.addingTimeInterval(13 * 3600), // 1pm
                     tags: ["supplement"]),
            
            // Yesterday
            DoseEntry(substance: "Caffeine", amount: 200, unit: "mg", route: .oral,
                     timestamp: today.addingTimeInterval(-16 * 3600), // yesterday 8am
                     tags: ["morning"]),
            DoseEntry(substance: "Vyvanse", amount: 30, unit: "mg", route: .oral,
                     timestamp: today.addingTimeInterval(-15.5 * 3600),
                     tags: ["daily", "prescription"]),
            DoseEntry(substance: "Ibuprofen", amount: 400, unit: "mg", route: .oral,
                     timestamp: today.addingTimeInterval(-12 * 3600),
                     notes: "Headache", tags: ["as-needed"]),
            DoseEntry(substance: "Melatonin", amount: 3, unit: "mg", route: .sublingual,
                     timestamp: today.addingTimeInterval(-1.5 * 3600), // yesterday 10:30pm
                     tags: ["sleep"]),
            
            // 2 days ago
            DoseEntry(substance: "Caffeine", amount: 200, unit: "mg", route: .oral,
                     timestamp: today.addingTimeInterval(-40 * 3600),
                     tags: ["morning"]),
            DoseEntry(substance: "Vyvanse", amount: 30, unit: "mg", route: .oral,
                     timestamp: today.addingTimeInterval(-39.5 * 3600),
                     tags: ["daily", "prescription"]),
            DoseEntry(substance: "Ashwagandha", amount: 600, unit: "mg", route: .oral,
                     timestamp: today.addingTimeInterval(-39 * 3600),
                     tags: ["supplement"]),
            
            // 3 days ago
            DoseEntry(substance: "Caffeine", amount: 150, unit: "mg", route: .oral,
                     timestamp: today.addingTimeInterval(-64 * 3600),
                     tags: ["morning"]),
            DoseEntry(substance: "Vyvanse", amount: 30, unit: "mg", route: .oral,
                     timestamp: today.addingTimeInterval(-63.5 * 3600),
                     tags: ["daily", "prescription"]),
            DoseEntry(substance: "Acetaminophen", amount: 500, unit: "mg", route: .oral,
                     timestamp: today.addingTimeInterval(-56 * 3600),
                     tags: ["as-needed"]),
        ]
        
        for entry in entries {
            context.insert(entry)
        }
        
        // Add some colors
        let colors: [(String, String)] = [
            ("caffeine", "89B4FA"),    // blue
            ("vyvanse", "CBA6F7"),     // purple
            ("magnesium", "A6E3A1"),   // green
            ("l-theanine", "94E2D5"),  // teal
            ("ibuprofen", "FAB387"),   // peach
            ("melatonin", "B4BEFE"),   // lavender
            ("ashwagandha", "F9E2AF"), // yellow
            ("acetaminophen", "F5C2E7"), // pink
        ]
        
        for (name, hex) in colors {
            let color = SubstanceColor(substance: name, hexColor: hex)
            context.insert(color)
        }
        
        try? context.save()
    }
}
#endif
