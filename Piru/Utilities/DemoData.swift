import SwiftData
import Foundation

#if DEBUG

enum DemoData {

    // MARK: - Reproducible RNG (SplitMix64)

    private struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    // MARK: - Showcase Data (500+ entries)

    /// Inserts a realistic 120-day medical dose history for app showcasing.
    ///
    /// Simulates a patient managing hypothyroidism (Levothyroxine), mild hypertension
    /// (Lisinopril), type 2 diabetes (Metformin), plus supplements and PRN medications.
    /// Includes a 7-day Amoxicillin course for a sinus infection and seasonal allergy
    /// management with Loratadine.
    ///
    /// Only runs when fewer than 50 entries exist; clears existing data first.
    @MainActor
    static func insertShowcaseData(container: ModelContainer) {
        let context = container.mainContext
        let count = (try? context.fetchCount(FetchDescriptor<DoseEntry>())) ?? 0
        guard count < 50 else { return }

        // Clear any existing small dataset
        try? context.delete(model: DoseEntry.self)
        try? context.delete(model: SubstanceColor.self)
        try? context.delete(model: FavoriteSubstance.self)
        try? context.delete(model: DailyDoseItem.self)

        var rng = SeededRNG(seed: 2026_0315)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let totalDays = 120

        /// Creates a timestamp with natural variance; morning doses shift ~1.5h later on weekends.
        func ts(_ daysAgo: Int, _ hour: Double, variance: Double = 15, weekendShift: Bool = true) -> Date {
            let dayStart = today.addingTimeInterval(-Double(daysAgo) * 86400)
            let shift: Double = (weekendShift && cal.isDateInWeekend(dayStart) && hour < 12) ? 1.5 : 0
            let jitter = Double.random(in: -variance...variance, using: &rng) * 60
            return dayStart.addingTimeInterval((hour + shift) * 3600 + jitter)
        }

        func takes(_ rate: Double) -> Bool {
            Double.random(in: 0..<1, using: &rng) < rate
        }

        var entries: [DoseEntry] = []
        entries.reserveCapacity(600)

        // Iterate oldest → newest so entries array is chronological
        for day in (0..<totalDays).reversed() {

            // ── Daily Prescriptions ─────────────────────────

            // Levothyroxine 75µg — thyroid, fasting morning dose, 96% adherence
            if takes(0.96) {
                entries.append(DoseEntry(
                    substance: "Levothyroxine", amount: 75, unit: "µg", route: .oral,
                    timestamp: ts(day, 6.5, variance: 10),
                    notes: [nil, nil, nil, nil, nil, "Empty stomach", "Before coffee"]
                        .randomElement(using: &rng)!,
                    tags: ["prescription", "daily"]
                ))
            }

            // Lisinopril 10mg — blood pressure, 93% adherence
            if takes(0.93) {
                entries.append(DoseEntry(
                    substance: "Lisinopril", amount: 10, unit: "mg", route: .oral,
                    timestamp: ts(day, 7.0),
                    notes: [nil, nil, nil, nil, nil, nil, "With water"]
                        .randomElement(using: &rng)!,
                    tags: ["prescription", "daily"]
                ))
            }

            // Metformin 500mg — morning with breakfast, 90% adherence
            if takes(0.90) {
                entries.append(DoseEntry(
                    substance: "Metformin", amount: 500, unit: "mg", route: .oral,
                    timestamp: ts(day, 8.0),
                    notes: [nil, nil, nil, "With breakfast"]
                        .randomElement(using: &rng)!,
                    tags: ["prescription", "daily"]
                ))
            }

            // Metformin 500mg — evening with dinner, 82% (lower evening adherence)
            if takes(0.82) {
                entries.append(DoseEntry(
                    substance: "Metformin", amount: 500, unit: "mg", route: .oral,
                    timestamp: ts(day, 18.5, variance: 30, weekendShift: false),
                    notes: [nil, nil, nil, nil, "With dinner"]
                        .randomElement(using: &rng)!,
                    tags: ["prescription", "daily"]
                ))
            }

            // ── Supplements ─────────────────────────────────

            // Vitamin D3 2000 IU — 50% adherence (often forgotten)
            if takes(0.50) {
                entries.append(DoseEntry(
                    substance: "Vitamin D3", amount: 2000, unit: "IU", route: .oral,
                    timestamp: ts(day, 7.5),
                    tags: ["supplement"]
                ))
            }

            // Magnesium Glycinate 400mg — evening, 45% adherence
            if takes(0.45) {
                entries.append(DoseEntry(
                    substance: "Magnesium Glycinate", amount: 400, unit: "mg", route: .oral,
                    timestamp: ts(day, 21.0, variance: 25, weekendShift: false),
                    notes: [nil, nil, nil, "Before bed"]
                        .randomElement(using: &rng)!,
                    tags: ["supplement"]
                ))
            }

            // ── Antibiotic Course (days 48–42 ago: 7-day sinus infection) ──

            if day >= 42 && day <= 48 {
                let courseDay = 49 - day
                for hour in [8.0, 14.0, 22.0] {
                    if takes(0.95) {
                        entries.append(DoseEntry(
                            substance: "Amoxicillin", amount: 500, unit: "mg", route: .oral,
                            timestamp: ts(day, hour, variance: 20),
                            notes: "Sinus infection — day \(courseDay) of 7",
                            tags: ["prescription", "antibiotic"]
                        ))
                    }
                }
            }

            // ── PRN (As-Needed) ─────────────────────────────

            // Loratadine 10mg — allergy season, last ~35 days, 30% of days
            if day < 35 && takes(0.30) {
                entries.append(DoseEntry(
                    substance: "Loratadine", amount: 10, unit: "mg", route: .oral,
                    timestamp: ts(day, 9.0),
                    notes: [nil, nil, "Allergies", "Pollen"]
                        .randomElement(using: &rng)!,
                    tags: ["as-needed"]
                ))
            }

            // Ibuprofen 400mg — occasional pain, ~10% of days
            if takes(0.10) {
                let hour = Double.random(in: 10...20, using: &rng)
                entries.append(DoseEntry(
                    substance: "Ibuprofen", amount: 400, unit: "mg", route: .oral,
                    timestamp: ts(day, hour, weekendShift: false),
                    notes: [nil, "Headache", "Back pain", "Muscle soreness"]
                        .randomElement(using: &rng)!,
                    tags: ["as-needed"]
                ))
            }

            // Acetaminophen 500mg — occasional, ~5% of days
            if takes(0.05) {
                let hour = Double.random(in: 9...21, using: &rng)
                entries.append(DoseEntry(
                    substance: "Acetaminophen", amount: 500, unit: "mg", route: .oral,
                    timestamp: ts(day, hour, weekendShift: false),
                    notes: [nil, nil, "Mild headache", "Fever"]
                        .randomElement(using: &rng)!,
                    tags: ["as-needed"]
                ))
            }

            // Melatonin 3mg sublingual — occasional insomnia, ~7% of days
            if takes(0.07) {
                entries.append(DoseEntry(
                    substance: "Melatonin", amount: 3, unit: "mg", route: .sublingual,
                    timestamp: ts(day, 22.5, variance: 20, weekendShift: false),
                    notes: [nil, nil, "Can't sleep", "Restless"]
                        .randomElement(using: &rng)!,
                    tags: ["as-needed", "sleep"]
                ))
            }
        }

        for entry in entries { context.insert(entry) }

        // ── Substance Colors (app's own PresetColor palette) ──

        let colors: [(String, String)] = [
            ("levothyroxine", "2ca2f5"),          // Iris — blue
            ("lisinopril", "f17395"),             // Azure — rose
            ("metformin", "9B8DF7"),              // Violet — purple
            ("vitamin d3", "bb9900"),             // Mustard — yellow
            ("magnesium glycinate", "21b26a"),    // Green
            ("amoxicillin", "f27859"),            // Mulberry — orange
            ("loratadine", "00b3a2"),             // Cyan — teal
            ("ibuprofen", "e08600"),              // Flamingo — amber
            ("acetaminophen", "CB7FDD"),          // Orchid — purple
            ("melatonin", "8394ff"),              // Lavender
        ]
        for (name, hex) in colors {
            context.insert(SubstanceColor(substance: name, hexColor: hex))
        }

        // ── Favorites (daily prescriptions) ──

        for name in ["Levothyroxine", "Lisinopril", "Metformin"] {
            context.insert(FavoriteSubstance(substance: name))
        }

        // ── Daily Medication Schedule ──

        let schedule: [(String, Double, String, Int)] = [
            ("Levothyroxine", 75, "µg", 0),
            ("Lisinopril", 10, "mg", 1),
            ("Metformin", 500, "mg", 2),
            ("Vitamin D3", 2000, "IU", 3),
            ("Magnesium Glycinate", 400, "mg", 4),
        ]
        for (name, amount, unit, order) in schedule {
            context.insert(DailyDoseItem(substance: name, amount: amount, unit: unit, sortOrder: order))
        }

        try? context.save()
    }

    // MARK: - Quick Demo (small dataset)

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
