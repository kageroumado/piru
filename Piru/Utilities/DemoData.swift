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

        /// Inserts a realistic 90-day dose history for app showcasing.
        ///
        /// Models an everyday journal: morning coffee with the occasional
        /// L-Theanine, a small supplement routine (Vitamin D3, Magnesium,
        /// Creatine on gym days), melatonin some nights, ibuprofen as needed —
        /// plus light weekend drinking, a couple of cannabis evenings a week,
        /// and two one-off events (an MDMA club night, a mushroom afternoon).
        /// Kept to a few entries per day so the journal cards and PK curves
        /// read cleanly in screenshots.
        ///
        /// Only runs when fewer than 50 entries exist; clears existing data first.
        ///
        /// Launch with `-piruNoDemoData` to suppress the seed — needed when
        /// restoring a real export onto a wiped simulator store, which would
        /// otherwise come up pre-seeded and merge the two histories.
        @MainActor
        static func insertShowcaseData(container: ModelContainer) {
            guard !ProcessInfo.processInfo.arguments.contains("-piruNoDemoData") else { return }
            let context = container.mainContext
            let count = (try? context.fetchCount(FetchDescriptor<DoseEntry>())) ?? 0
            guard count < 50 else { return }

            try? context.delete(model: DoseEntry.self)
            try? context.delete(model: SubstanceColor.self)
            try? context.delete(model: FavoriteSubstance.self)
            try? context.delete(model: DailyDoseItem.self)

            var rng = SeededRNG(seed: 20_260_611)
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let totalDays = 90

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
            entries.reserveCapacity(500)

            // One-off events land on specific past Saturdays so the recent
            // week stays tidy for the journal screenshot.
            var saturdaysAgo: [Int] = []
            for day in 0 ..< totalDays where cal.component(.weekday, from: today.addingTimeInterval(-Double(day) * 86_400)) == 7 {
                saturdaysAgo.append(day)
            }
            let clubNight = saturdaysAgo.count > 5 ? saturdaysAgo[5] : 38
            let mushroomDay = saturdaysAgo.count > 9 ? saturdaysAgo[9] : 66

            // Day 0 is handcrafted below as a live session — generating it from
            // the daily template would future-date entries (e.g. tonight's
            // magnesium at a 9 AM capture) and never satisfy the active-window
            // check the Journal's "Active Now" card keys on.
            // Day 1 ("Yesterday") is curated too: cannabis evening + ibuprofen,
            // no supplements — vitamins draw flat, meaningless curves that
            // crowd the hero/day graphs in screenshots, and an early-morning
            // capture pulls yesterday's stragglers into the current session.
            for day in (1 ..< totalDays).reversed() {
                let dayStart = today.addingTimeInterval(-Double(day) * 86_400)
                let weekday = cal.component(.weekday, from: dayStart)
                let isWeekend = cal.isDateInWeekend(dayStart)
                let isFridayOrSaturday = weekday == 6 || weekday == 7
                let isGymDay = weekday == 2 || weekday == 4 || weekday == 6
                let isYesterday = day == 1

                if isYesterday {
                    entries.append(DoseEntry(
                        substance: "Caffeine",
                        amount: 110, unit: "mg", route: .oral,
                        timestamp: ts(day, 8.2, variance: 15),
                        notes: "Flat white",
                        tags: ["coffee", "morning"],
                    ))
                    entries.append(DoseEntry(
                        substance: "Ibuprofen",
                        amount: 400, unit: "mg", route: .oral,
                        timestamp: ts(day, 14.0, variance: 20),
                        notes: "Headache",
                        tags: ["as-needed"],
                    ))
                    entries.append(DoseEntry(
                        substance: "Cannabis",
                        amount: 8, unit: "mg", route: .inhalation,
                        timestamp: ts(day, 21.2, variance: 20),
                        notes: "Movie night",
                        tags: ["chill"],
                    ))
                    continue
                }

                // ── Coffee ──────────────────────────────────────

                if takes(0.95) {
                    entries.append(DoseEntry(
                        substance: "Caffeine",
                        amount: (jitterAmount(110, plusOrMinus: 30) / 5).rounded() * 5,
                        unit: "mg", route: .oral,
                        timestamp: ts(day, 8.0, variance: 25, weekendShift: true),
                        notes: [nil, nil, nil, "Flat white"].randomElement(using: &rng)!,
                        tags: ["coffee", "morning"],
                    ))
                    // L-Theanine alongside, sometimes
                    if takes(0.35) {
                        entries.append(DoseEntry(
                            substance: "L-Theanine",
                            amount: 200, unit: "mg", route: .oral,
                            timestamp: ts(day, 8.2, variance: 25, weekendShift: true),
                            tags: ["coffee", "supplement"],
                        ))
                    }
                    // Afternoon cup on weekdays, mostly
                    if takes(isWeekend ? 0.25 : 0.55) {
                        entries.append(DoseEntry(
                            substance: "Caffeine",
                            amount: (jitterAmount(70, plusOrMinus: 15) / 5).rounded() * 5,
                            unit: "mg", route: .oral,
                            timestamp: ts(day, 13.5, variance: 40),
                            tags: ["coffee"],
                        ))
                    }
                }

                // ── Supplements ─────────────────────────────────

                if takes(0.85) {
                    entries.append(DoseEntry(
                        substance: "Vitamin D3",
                        amount: 4_000, unit: "IU", route: .oral,
                        timestamp: ts(day, 8.5, variance: 30, weekendShift: true),
                        tags: ["supplement"],
                    ))
                }
                if isGymDay, takes(0.7) {
                    entries.append(DoseEntry(
                        substance: "Creatine",
                        amount: 5, unit: "g", route: .oral,
                        timestamp: ts(day, 17.0, variance: 45),
                        notes: [nil, nil, "Post-workout"].randomElement(using: &rng)!,
                        tags: ["gym"],
                    ))
                }
                if takes(0.8) {
                    entries.append(DoseEntry(
                        substance: "Magnesium",
                        amount: jitterAmount(350, plusOrMinus: 50).rounded(),
                        unit: "mg", route: .oral,
                        timestamp: ts(day, 22.0, variance: 30),
                        tags: ["supplement", "sleep"],
                    ))
                }

                // Melatonin — some nights
                if takes(0.22) {
                    entries.append(DoseEntry(
                        substance: "Melatonin",
                        amount: takes(0.6) ? 0.5 : 1,
                        unit: "mg", route: .sublingual,
                        timestamp: ts(day, 23.0, variance: 25),
                        tags: ["sleep"],
                    ))
                }

                // Ibuprofen — as needed
                if takes(0.07) {
                    entries.append(DoseEntry(
                        substance: "Ibuprofen",
                        amount: 400, unit: "mg", route: .oral,
                        timestamp: ts(day, Double.random(in: 10 ... 20, using: &rng)),
                        notes: ["Headache", "Headache", "Sore from the gym"].randomElement(using: &rng)!,
                        tags: ["as-needed"],
                    ))
                }

                // ── Weekend drinks ──────────────────────────────

                if day == clubNight {
                    // One big night out, ~5 Saturdays back: MDMA + a couple of drinks.
                    entries.append(DoseEntry(
                        substance: "MDMA",
                        amount: 120, unit: "mg", route: .oral,
                        timestamp: ts(day, 22.5, variance: 15),
                        notes: "Club night",
                        tags: ["party"],
                    ))
                    entries.append(DoseEntry(
                        substance: "MDMA",
                        amount: 60, unit: "mg", route: .oral,
                        timestamp: ts(day, 24.5, variance: 15),
                        notes: "Redose",
                        tags: ["party"],
                    ))
                    entries.append(DoseEntry(
                        substance: "Alcohol",
                        amount: 2, unit: "units", route: .oral,
                        timestamp: ts(day, 21.0, variance: 20),
                        tags: ["party"],
                    ))
                } else if isFridayOrSaturday, takes(0.65) {
                    // A normal evening out or in: 2–4 drinks over a few hours.
                    let rounds = takes(0.5) ? 2 : (takes(0.5) ? 1 : 3)
                    for round in 0 ... rounds {
                        entries.append(DoseEntry(
                            substance: "Alcohol",
                            amount: takes(0.7) ? 1 : 2,
                            unit: "units", route: .oral,
                            timestamp: ts(day, 19.5 + Double(round) * 1.4, variance: 25),
                            notes: round == 0 ? [nil, nil, "Drinks with friends"].randomElement(using: &rng)! : nil,
                            tags: ["drinks", "social"],
                        ))
                    }
                } else if takes(0.08) {
                    // The odd weekday beer.
                    entries.append(DoseEntry(
                        substance: "Alcohol",
                        amount: 1, unit: "units", route: .oral,
                        timestamp: ts(day, 20.5, variance: 40),
                        tags: ["drinks"],
                    ))
                }

                // ── Cannabis — a couple of evenings a week ──────

                if day != clubNight, day != mushroomDay, takes(isWeekend ? 0.35 : 0.22) {
                    entries.append(DoseEntry(
                        substance: "Cannabis",
                        amount: jitterAmount(7, plusOrMinus: 3).rounded(),
                        unit: "mg", route: .inhalation,
                        timestamp: ts(day, 21.3, variance: 45),
                        notes: [nil, nil, nil, "Movie night"].randomElement(using: &rng)!,
                        tags: ["chill"],
                    ))
                }

                // ── Mushroom afternoon, ~9 Saturdays back ───────

                if day == mushroomDay {
                    entries.append(DoseEntry(
                        substance: "Psilocybin mushrooms",
                        amount: 1.8, unit: "g", route: .oral,
                        timestamp: ts(day, 14.0, variance: 20),
                        notes: "Forest walk",
                        tags: ["trip"],
                    ))
                }
            }

            // ── Today: a session that's active right now ────────
            // Anchored to the seeding moment (not clock hours) so the Journal's
            // "Active Now" card shows whenever screenshots are taken.
            // Session recovery only fetches the current session day, so clamp
            // each timestamp to just after the day cutoff — otherwise seeding
            // shortly after the cutoff (e.g. 04:15 with a 04:00 boundary)
            // back-dates the doses into yesterday and no session recovers.

            let now = Date()
            let sessionDayStart = cal.sessionDayStart(for: now)
            func recent(_ hoursAgo: Double, slot: Double) -> Date {
                let ideal = now.addingTimeInterval(-hoursAgo * 3_600)
                let floor = sessionDayStart.addingTimeInterval((5 + slot * 4) * 60)
                return max(ideal, floor)
            }
            entries.append(DoseEntry(
                substance: "Caffeine",
                amount: 110, unit: "mg", route: .oral,
                timestamp: recent(2.1, slot: 0),
                notes: "Flat white",
                tags: ["coffee"],
            ))
            entries.append(DoseEntry(
                substance: "Alcohol",
                amount: 2, unit: "units", route: .oral,
                timestamp: recent(1.3, slot: 1),
                notes: "Drinks with friends",
                tags: ["drinks", "social"],
            ))
            entries.append(DoseEntry(
                substance: "Alcohol",
                amount: 1, unit: "units", route: .oral,
                timestamp: recent(0.4, slot: 2),
                tags: ["drinks", "social"],
            ))

            for entry in entries {
                context.insert(entry)
            }

            // ── Substance Colors (preset palette) ──

            let colors: [(String, String)] = [
                ("caffeine", "F5A623"), // Mustard — amber
                ("l-theanine", "00b3a2"), // Cyan — teal
                ("vitamin d3", "F9E2AF"), // Honey — soft yellow
                ("creatine", "2ca2f5"), // Azure — bright blue
                ("magnesium", "A6E3A1"), // Sage — green
                ("melatonin", "8394ff"), // Lavender
                ("ibuprofen", "f17395"), // Rose
                ("alcohol", "CBA6F7"), // Violet — purple
                ("cannabis", "8FAE5C"), // Olive — sage
                ("mdma", "FF6B9D"), // Pink
                ("psilocybin mushrooms", "5C7CFA"), // Iris — blue
            ]
            for (name, hex) in colors {
                context.insert(SubstanceColor(substance: name, hexColor: hex))
            }

            // ── Favorites ──

            for name in ["Caffeine", "Magnesium", "Vitamin D3", "Melatonin"] {
                context.insert(FavoriteSubstance(substance: name))
            }

            // ── Daily supplement routine ──

            let schedule: [(String, Double, String, Int)] = [
                ("Vitamin D3", 4_000, "IU", 0),
                ("Magnesium", 350, "mg", 1),
            ]
            for (name, amount, unit, order) in schedule {
                context.insert(DailyDoseItem(substance: name, amount: amount, unit: unit, sortOrder: order))
            }

            try? context.save()
            // Cluster the freshly-seeded doses into sessions (the launch populate
            // pass already ran on the then-empty store).
            SessionService.assignUnassignedDoses(in: context)
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
            // Cluster the freshly-seeded doses into sessions (the launch populate
            // pass already ran on the then-empty store).
            SessionService.assignUnassignedDoses(in: context)
        }
    }

#endif
