import Foundation
import SwiftData

#if DEBUG

    enum DemoData {
        // MARK: - Reproducible RNG (SplitMix64)

        private struct SeededRNG: RandomNumberGenerator {
            private var state: UInt64

            init(seed: UInt64) {
                state = seed
            }

            mutating func next() -> UInt64 {
                state &+= 0x9E37_79B9_7F4A_7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                return z ^ (z >> 31)
            }
        }

        // MARK: - Showcase Data (~500 entries)

        /// Inserts a realistic 120-day dose history for app showcasing.
        ///
        /// Models the kind of journal Piru is actually used for in the wild: a
        /// nootropic stack (Pregabalin nightly, Memantine for stimulant tolerance,
        /// Kratom across the day) with weekday stimulant rotation (2-FMA,
        /// Amphetamine, occasional 4F-MPH) and infrequent recreational doses
        /// (3-MMC weekends, Bromazepam PRN, the occasional dissociative session).
        /// Patterns and dose ranges are derived from a real journal export; names
        /// are kept as-is so timeline / interaction / half-life surfaces all
        /// exercise the merged DB.
        ///
        /// Only runs when fewer than 50 entries exist; clears existing data first.
        @MainActor
        static func insertShowcaseData(container: ModelContainer) {
            let context = container.mainContext
            let count = (try? context.fetchCount(FetchDescriptor<DoseEntry>())) ?? 0
            guard count < 50 else { return }

            try? context.delete(model: DoseEntry.self)
            try? context.delete(model: SubstanceColor.self)
            try? context.delete(model: FavoriteSubstance.self)
            try? context.delete(model: DailyDoseItem.self)

            var rng = SeededRNG(seed: 20_260_315)
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let totalDays = 120

            func ts(_ daysAgo: Int, _ hour: Double, variance: Double = 20, weekendShift: Bool = false) -> Date {
                let dayStart = today.addingTimeInterval(-Double(daysAgo) * 86_400)
                let shift: Double = (weekendShift && cal.isDateInWeekend(dayStart) && hour < 12) ? 1.5 : 0
                let jitter = Double.random(in: -variance ... variance, using: &rng) * 60
                return dayStart.addingTimeInterval((hour + shift) * 3_600 + jitter)
            }

            func takes(_ rate: Double) -> Bool {
                Double.random(in: 0 ..< 1, using: &rng) < rate
            }

            func jitterAmount(_ base: Double, plusOrMinus: Double) -> Double {
                base + Double.random(in: -plusOrMinus ... plusOrMinus, using: &rng)
            }

            var entries: [DoseEntry] = []
            entries.reserveCapacity(700)

            for day in (0 ..< totalDays).reversed() {
                let dayStart = today.addingTimeInterval(-Double(day) * 86_400)
                let isWeekend = cal.isDateInWeekend(dayStart)

                // ── Nightly anxiolytic ──────────────────────────

                // Pregabalin 200mg oral — evening, ~92% adherence
                if takes(0.92) {
                    entries.append(DoseEntry(
                        substance: "Pregabalin",
                        amount: jitterAmount(200, plusOrMinus: 25),
                        unit: "mg", route: .oral,
                        timestamp: ts(day, 22.0, variance: 30),
                        tags: ["nightly", "anxiolytic"],
                    ))
                }

                // ── Tolerance management ────────────────────────

                // Memantine 20mg oral — morning, ~75% adherence (skipped some weekends)
                if takes(isWeekend ? 0.55 : 0.85) {
                    entries.append(DoseEntry(
                        substance: "Memantine",
                        amount: takes(0.7) ? 20 : 10,
                        unit: "mg", route: .oral,
                        timestamp: ts(day, 9.0, weekendShift: true),
                        tags: ["nootropic", "tolerance"],
                    ))
                }

                // ── Daily Kratom — 1–3x/day with redoses ───────

                let kratomBouts: Int = {
                    if takes(0.85) {
                        if takes(0.4) { return 3 }
                        if takes(0.6) { return 2 }
                        return 1
                    }
                    return 0
                }()
                for bout in 0 ..< kratomBouts {
                    let hour = 10.5 + Double(bout) * 4.5 + Double.random(in: -0.5 ... 0.5, using: &rng)
                    entries.append(DoseEntry(
                        substance: "Kratom",
                        amount: jitterAmount(3.0, plusOrMinus: 0.7),
                        unit: "g", route: .oral,
                        timestamp: ts(day, hour),
                        notes: bout == 0
                            ? [nil, nil, nil, "Empty stomach"].randomElement(using: &rng)!
                            : [nil, nil, "Top-up", "Redose"].randomElement(using: &rng)!,
                        tags: ["kratom", bout == 0 ? "primary" : "redose"],
                    ))
                }

                // ── Stimulant rotation (weekday-leaning) ────────

                // 2-FMA 60mg oral — preferred functional stimulant
                if !isWeekend, takes(0.55) {
                    entries.append(DoseEntry(
                        substance: "2-FMA",
                        amount: jitterAmount(60, plusOrMinus: 15),
                        unit: "mg", route: .oral,
                        timestamp: ts(day, 11.0, variance: 25),
                        tags: ["stimulant"],
                    ))
                    // Mid-afternoon redose, sometimes
                    if takes(0.4) {
                        entries.append(DoseEntry(
                            substance: "2-FMA",
                            amount: jitterAmount(30, plusOrMinus: 10),
                            unit: "mg", route: .oral,
                            timestamp: ts(day, 15.5, variance: 25),
                            notes: "Redose",
                            tags: ["stimulant", "redose"],
                        ))
                    }
                } else if takes(0.30) {
                    // Amphetamine alternative on days without 2-FMA
                    entries.append(DoseEntry(
                        substance: "Amphetamine",
                        amount: jitterAmount(25, plusOrMinus: 5),
                        unit: "mg", route: .oral,
                        timestamp: ts(day, 11.5, variance: 30),
                        tags: ["stimulant"],
                    ))
                }

                // 4F-MPH — occasional sublingual, ~12% of days
                if takes(0.12) {
                    entries.append(DoseEntry(
                        substance: "4F-MPH",
                        amount: jitterAmount(15, plusOrMinus: 5),
                        unit: "mg", route: .sublingual,
                        timestamp: ts(day, 13.0, variance: 60),
                        tags: ["stimulant", "as-needed"],
                    ))
                }

                // ── PRN anxiolytic / dissociative / recreational ─

                // Bromazepam 3mg sublingual — anxiolytic PRN, ~8% of days
                if takes(0.08) {
                    entries.append(DoseEntry(
                        substance: "Bromazepam",
                        amount: 3, unit: "mg", route: .sublingual,
                        timestamp: ts(day, Double.random(in: 19 ... 22, using: &rng)),
                        notes: [nil, nil, "Anxiety", "Wind-down"].randomElement(using: &rng)!,
                        tags: ["benzo", "as-needed"],
                    ))
                }

                // 3-MMC 100mg — recreational, weekend leaning, ~10% of weekends
                if isWeekend, takes(0.15) {
                    entries.append(DoseEntry(
                        substance: "3-MMC",
                        amount: jitterAmount(100, plusOrMinus: 25),
                        unit: "mg",
                        route: takes(0.4) ? .insufflation : .oral,
                        timestamp: ts(day, Double.random(in: 20 ... 23, using: &rng)),
                        tags: ["recreational", "weekend"],
                    ))
                }

                // 2-Fluorodeschloroketamine — occasional, ~3% of days
                if takes(0.03) {
                    entries.append(DoseEntry(
                        substance: "2-Fluorodeschloroketamine",
                        amount: jitterAmount(40, plusOrMinus: 10),
                        unit: "mg",
                        route: .insufflation,
                        timestamp: ts(day, Double.random(in: 20 ... 23, using: &rng)),
                        tags: ["dissociative", "as-needed"],
                    ))
                }
            }

            for entry in entries {
                context.insert(entry)
            }

            // ── Substance Colors (preset palette) ──

            let colors: [(String, String)] = [
                ("pregabalin", "5C7CFA"), // Iris — blue
                ("memantine", "F5A623"), // Mustard — amber
                ("kratom", "8FAE5C"), // Olive — sage
                ("2-fma", "21b26a"), // Green
                ("amphetamine", "2ca2f5"), // Azure — bright blue
                ("4f-mph", "00b3a2"), // Cyan — teal
                ("bromazepam", "8394ff"), // Lavender
                ("3-mmc", "CBA6F7"), // Violet — purple
                ("2-fluorodeschloroketamine", "f17395"), // Rose
            ]
            for (name, hex) in colors {
                context.insert(SubstanceColor(substance: name, hexColor: hex))
            }

            // ── Favorites ──

            for name in ["Pregabalin", "Kratom", "Memantine", "2-FMA"] {
                context.insert(FavoriteSubstance(substance: name))
            }

            // ── Daily medication schedule (the regular ones) ──

            let schedule: [(String, Double, String, Int)] = [
                ("Memantine", 20, "mg", 0),
                ("Pregabalin", 200, "mg", 1),
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
                DoseEntry(
                    substance: "Caffeine",
                    amount: 200,
                    unit: "mg",
                    route: .oral,
                    timestamp: today.addingTimeInterval(8 * 3_600), // 8am
                    tags: ["morning"],
                ),
                DoseEntry(
                    substance: "Vyvanse",
                    amount: 30,
                    unit: "mg",
                    route: .oral,
                    timestamp: today.addingTimeInterval(8.5 * 3_600), // 8:30am
                    notes: "With breakfast",
                    tags: ["daily", "prescription"],
                ),
                DoseEntry(
                    substance: "Magnesium",
                    amount: 400,
                    unit: "mg",
                    route: .oral,
                    timestamp: today.addingTimeInterval(9 * 3_600), // 9am
                    tags: ["supplement"],
                ),
                DoseEntry(
                    substance: "Caffeine",
                    amount: 100,
                    unit: "mg",
                    route: .oral,
                    timestamp: today.addingTimeInterval(13 * 3_600), // 1pm
                    tags: ["afternoon"],
                ),
                DoseEntry(
                    substance: "L-Theanine",
                    amount: 200,
                    unit: "mg",
                    route: .oral,
                    timestamp: today.addingTimeInterval(13 * 3_600), // 1pm
                    tags: ["supplement"],
                ),

                // Yesterday
                DoseEntry(
                    substance: "Caffeine",
                    amount: 200,
                    unit: "mg",
                    route: .oral,
                    timestamp: today.addingTimeInterval(-16 * 3_600), // yesterday 8am
                    tags: ["morning"],
                ),
                DoseEntry(
                    substance: "Vyvanse",
                    amount: 30,
                    unit: "mg",
                    route: .oral,
                    timestamp: today.addingTimeInterval(-15.5 * 3_600),
                    tags: ["daily", "prescription"],
                ),
                DoseEntry(
                    substance: "Ibuprofen",
                    amount: 400,
                    unit: "mg",
                    route: .oral,
                    timestamp: today.addingTimeInterval(-12 * 3_600),
                    notes: "Headache",
                    tags: ["as-needed"],
                ),
                DoseEntry(
                    substance: "Melatonin",
                    amount: 3,
                    unit: "mg",
                    route: .sublingual,
                    timestamp: today.addingTimeInterval(-1.5 * 3_600), // yesterday 10:30pm
                    tags: ["sleep"],
                ),

                // 2 days ago
                DoseEntry(
                    substance: "Caffeine",
                    amount: 200,
                    unit: "mg",
                    route: .oral,
                    timestamp: today.addingTimeInterval(-40 * 3_600),
                    tags: ["morning"],
                ),
                DoseEntry(
                    substance: "Vyvanse",
                    amount: 30,
                    unit: "mg",
                    route: .oral,
                    timestamp: today.addingTimeInterval(-39.5 * 3_600),
                    tags: ["daily", "prescription"],
                ),
                DoseEntry(
                    substance: "Ashwagandha",
                    amount: 600,
                    unit: "mg",
                    route: .oral,
                    timestamp: today.addingTimeInterval(-39 * 3_600),
                    tags: ["supplement"],
                ),

                // 3 days ago
                DoseEntry(
                    substance: "Caffeine",
                    amount: 150,
                    unit: "mg",
                    route: .oral,
                    timestamp: today.addingTimeInterval(-64 * 3_600),
                    tags: ["morning"],
                ),
                DoseEntry(
                    substance: "Vyvanse",
                    amount: 30,
                    unit: "mg",
                    route: .oral,
                    timestamp: today.addingTimeInterval(-63.5 * 3_600),
                    tags: ["daily", "prescription"],
                ),
                DoseEntry(
                    substance: "Acetaminophen",
                    amount: 500,
                    unit: "mg",
                    route: .oral,
                    timestamp: today.addingTimeInterval(-56 * 3_600),
                    tags: ["as-needed"],
                ),
            ]

            for entry in entries {
                context.insert(entry)
            }

            // Add some colors
            let colors: [(String, String)] = [
                ("caffeine", "89B4FA"), // blue
                ("vyvanse", "CBA6F7"), // purple
                ("magnesium", "A6E3A1"), // green
                ("l-theanine", "94E2D5"), // teal
                ("ibuprofen", "FAB387"), // peach
                ("melatonin", "B4BEFE"), // lavender
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
