import Foundation
import SwiftData

#if DEBUG

    /// The data shapes the chart review captures every chart under: a heavy
    /// six-month log, one daily med and nothing else, a first day, and a night
    /// with many substances active at once. Every seed is placed from
    /// `DebugClock.now` with a fixed-seed generator, and nothing lands after
    /// the present.
    extension DemoData {
        /// One dose entry with its catalog identity, the way a log would make it.
        @MainActor
        private static func chartDose(
            _ name: String, _ amount: Double, _ unit: String, route: RouteOfAdministration = .oral,
            at timestamp: Date, tags: [String] = [], session: Session? = nil, in context: ModelContext,
        ) {
            let entry = DoseEntry(
                substance: name, amount: amount, unit: unit, route: route,
                substanceUID: SubstanceLibrary.substanceUID(for: name), timestamp: timestamp, tags: tags,
            )
            entry.session = session
            context.insert(entry)
        }

        // MARK: - Heavy logging

        /// Two hundred days ending now, 28 substances across stimulants,
        /// depressants, psychedelics, dissociatives, opioids and supplements:
        ///
        /// - morning methylphenidate (with a week of misses) and daily sertraline,
        ///   both in My Meds; caffeine one to four times a day;
        /// - nicotine most days until 80 days ago, then none;
        /// - evening alcohol, cannabis and sleep aids on a share of nights;
        /// - weekend parties with redoses (MDMA, ketamine, cocaine, GHB,
        ///   amphetamine, 2C-B), and every night of a party burst 40 to 30 days ago;
        /// - a psychedelic session roughly monthly;
        /// - occasional one-offs (gabapentinoids, benzos, opioids, kratom, phenibut);
        /// - nothing at all from 125 to 104 days ago, a three-week gap.
        @MainActor
        static func seedHeavyLogging(context: ModelContext, now: Date) {
            var rng = SeededRNG(seed: 20_261_123)
            let cal = Calendar.current
            let today = cal.startOfDay(for: now)
            func at(_ daysAgo: Int, _ hour: Double) -> Date {
                today.addingTimeInterval(-Double(daysAgo) * 86_400 + hour * 3_600)
            }
            func chance(_ p: Double) -> Bool {
                Double.random(in: 0 ..< 1, using: &rng) < p
            }
            func jitter(_ minutes: Double) -> Double {
                Double.random(in: -minutes ... minutes, using: &rng) / 60
            }
            func dose(_ name: String, _ amount: Double, _ unit: String, route: RouteOfAdministration = .oral, _ time: Date, tags: [String] = []) {
                guard time <= now else { return }
                chartDose(name, amount, unit, route: route, at: time, tags: tags, in: context)
            }

            context.insert(DailyDoseItem(
                substance: "Methylphenidate", amount: 20, unit: "mg", sortOrder: 0,
                substanceUID: SubstanceLibrary.substanceUID(for: "Methylphenidate"), reminderTimesMinutes: [8 * 60],
            ))
            context.insert(DailyDoseItem(
                substance: "Sertraline", amount: 100, unit: "mg", sortOrder: 1,
                substanceUID: SubstanceLibrary.substanceUID(for: "Sertraline"), reminderTimesMinutes: [9 * 60],
            ))

            let psychedelicDays: [Int: (String, Double, String, RouteOfAdministration)] = [
                190: ("LSD", 100, "µg", .sublingual), 160: ("Psilocybin mushrooms", 2.5, "g", .oral),
                98: ("LSD", 150, "µg", .sublingual), 70: ("Psilocybin mushrooms", 3.5, "g", .oral),
                45: ("LSD", 100, "µg", .sublingual), 20: ("Psilocybin mushrooms", 2, "g", .oral),
            ]

            for daysAgo in (0 ... 200).reversed() {
                if (104 ... 125).contains(daysAgo) { continue }
                let weekday = cal.component(.weekday, from: at(daysAgo, 12))
                let isWeekend = weekday == 6 || weekday == 7

                // Meds: methylphenidate (missed 60–54 days ago, modafinil on a
                // few of those mornings instead) and sertraline.
                if (54 ... 60).contains(daysAgo) {
                    if chance(0.5) { dose("Modafinil", 100, "mg", at(daysAgo, 8.5 + jitter(30)), tags: ["meds"]) }
                } else if chance(0.9) {
                    dose("Methylphenidate", 20, "mg", at(daysAgo, 8 + jitter(25)), tags: ["meds"])
                }
                if chance(0.95) { dose("Sertraline", 100, "mg", at(daysAgo, 9 + jitter(20)), tags: ["meds"]) }

                // Caffeine through the day.
                let coffees = Int.random(in: 1 ... 4, using: &rng)
                for cup in 0 ..< coffees {
                    dose("Caffeine", cup == 0 ? 120 : 80, "mg", at(daysAgo, 7.5 + Double(cup) * 2.5 + jitter(20)), tags: ["coffee"])
                }

                // Nicotine until it was quit 80 days ago.
                if daysAgo > 80 {
                    for hit in 0 ..< Int.random(in: 0 ... 6, using: &rng) {
                        dose("Nicotine", 1, "mg", route: .inhalation, at(daysAgo, 10 + Double(hit) * 2 + jitter(40)))
                    }
                }

                // Evenings.
                if chance(isWeekend ? 0.5 : 0.2) {
                    for drink in 0 ..< Int.random(in: 2 ... 4, using: &rng) {
                        dose("Alcohol", 20, "g", at(daysAgo, 19 + Double(drink) * 0.9 + jitter(10)), tags: ["drinks"])
                    }
                }
                if chance(0.12) { dose("Cannabis", 3, "mg THC", route: .inhalation, at(daysAgo, 21.5 + jitter(30))) }
                if chance(0.12) {
                    dose("Zolpidem", 10, "mg", at(daysAgo, 23.2 + jitter(20)), tags: ["sleep"])
                } else if chance(0.1) {
                    dose("Melatonin", 1, "mg", route: .sublingual, at(daysAgo, 23 + jitter(20)), tags: ["sleep"])
                } else if chance(0.05) {
                    dose("Lorazepam", 1, "mg", at(daysAgo, 23.4 + jitter(20)), tags: ["sleep"])
                }

                // Parties: most weekends, and every night of the burst.
                let burst = (30 ... 40).contains(daysAgo)
                if burst || (isWeekend && chance(0.45)) {
                    let kit = burst ? 2 : Int.random(in: 0 ... 5, using: &rng)
                    let start = 22 + jitter(30)
                    switch kit {
                    case 0:
                        dose("MDMA", 120, "mg", at(daysAgo, start), tags: ["party"])
                        dose("MDMA", 60, "mg", at(daysAgo, start + 2), tags: ["party"])
                    case 1:
                        for bump in 0 ..< Int.random(in: 3 ... 5, using: &rng) {
                            dose("Ketamine", 40, "mg", route: .insufflation, at(daysAgo, start + Double(bump) * 0.7), tags: ["party"])
                        }
                    case 2:
                        for line in 0 ..< Int.random(in: 3 ... 6, using: &rng) {
                            dose("Cocaine", 50, "mg", route: .insufflation, at(daysAgo, start + Double(line) * 0.75), tags: ["party"])
                        }
                        for drink in 0 ..< 3 {
                            dose("Alcohol", 20, "g", at(daysAgo, start + Double(drink) * 1.2 + 0.2), tags: ["drinks"])
                        }
                    case 3:
                        for dip in 0 ..< 3 {
                            dose("GHB", 1.5, "g", at(daysAgo, start + Double(dip) * 2), tags: ["party"])
                        }
                    case 4:
                        dose("Amphetamine", 20, "mg", at(daysAgo, start), tags: ["party"])
                        dose("Amphetamine", 15, "mg", at(daysAgo, start + 3), tags: ["party"])
                    default:
                        dose("2C-B", 18, "mg", at(daysAgo, start), tags: ["party"])
                    }
                }

                if let trip = psychedelicDays[daysAgo] {
                    dose(trip.0, trip.1, trip.2, route: trip.3, at(daysAgo, 14 + jitter(30)), tags: ["trip"])
                }

                // One-offs.
                if chance(0.06) { dose("Ibuprofen", 400, "mg", at(daysAgo, 13 + jitter(60))) }
                if (40 ... 90).contains(daysAgo), chance(0.15) { dose("Kratom", 3, "g", at(daysAgo, 17 + jitter(40))) }
                if chance(0.03) { dose("Gabapentin", 600, "mg", at(daysAgo, 20 + jitter(40))) }
                if chance(0.02) { dose("Pregabalin", 150, "mg", at(daysAgo, 20 + jitter(40))) }
                if weekday == 3, chance(0.2) { dose("Phenibut", 1_000, "mg", at(daysAgo, 18 + jitter(30))) }
                if chance(0.02) { dose("Etizolam", 1, "mg", at(daysAgo, 21 + jitter(30))) }
                if chance(0.02) { dose("Clonazepam", 0.5, "mg", at(daysAgo, 22 + jitter(30))) }
                if chance(0.03) { dose("Diazepam", 5, "mg", at(daysAgo, 22 + jitter(30))) }
                if chance(0.02) { dose("Codeine", 30, "mg", at(daysAgo, 15 + jitter(60))) }
                if chance(0.02) { dose("Tramadol", 50, "mg", at(daysAgo, 15 + jitter(60))) }
            }

            for name in [
                "methylphenidate", "sertraline", "caffeine", "nicotine", "alcohol", "cannabis", "zolpidem",
                "melatonin", "lorazepam", "mdma", "ketamine", "cocaine", "ghb", "amphetamine", "2c-b", "lsd",
                "psilocybin mushrooms", "ibuprofen", "kratom", "gabapentin", "pregabalin", "phenibut",
                "etizolam", "clonazepam", "diazepam", "codeine", "tramadol", "modafinil",
            ] {
                insertClassColor(name, in: context)
            }
            context.insert(QuickLogDose(substance: "Methylphenidate", route: .oral, amount: 20, unit: "mg", sortOrder: 0))
            context.insert(QuickLogDose(substance: "Caffeine", route: .oral, amount: 80, unit: "mg", sortOrder: 1))
            context.insert(QuickLogDose(substance: "Alcohol", route: .oral, amount: 20, unit: "g", sortOrder: 2))
        }

        // MARK: - One substance

        /// Sertraline 100 mg each morning for 180 days, in My Meds, about one
        /// morning in thirty missed; nothing else is ever logged.
        @MainActor
        static func seedSingleDaily(context: ModelContext, now: Date) {
            var rng = SeededRNG(seed: 20_261_124)
            let today = Calendar.current.startOfDay(for: now)
            context.insert(DailyDoseItem(
                substance: "Sertraline", amount: 100, unit: "mg", sortOrder: 0,
                substanceUID: SubstanceLibrary.substanceUID(for: "Sertraline"), reminderTimesMinutes: [9 * 60],
            ))
            for daysAgo in (0 ... 179).reversed() {
                let missed = Double.random(in: 0 ..< 1, using: &rng) < 0.035
                let minutes = Double.random(in: -20 ... 40, using: &rng)
                let time = today.addingTimeInterval(-Double(daysAgo) * 86_400 + 9 * 3_600 + minutes * 60)
                guard !missed, time <= now else { continue }
                chartDose("Sertraline", 100, "mg", at: time, tags: ["meds"], in: context)
            }
            insertClassColor("sertraline", in: context)
            context.insert(QuickLogDose(substance: "Sertraline", route: .oral, amount: 100, unit: "mg", sortOrder: 0))
        }

        // MARK: - First day

        /// The first day of use: a coffee two hours ago and ibuprofen forty
        /// minutes ago, and nothing before today.
        @MainActor
        static func seedFirstDay(context: ModelContext, now: Date) {
            chartDose("Caffeine", 90, "mg", at: now.addingTimeInterval(-120 * 60), tags: ["coffee"], in: context)
            chartDose("Ibuprofen", 400, "mg", at: now.addingTimeInterval(-40 * 60), in: context)
            for name in ["caffeine", "ibuprofen"] {
                insertClassColor(name, in: context)
            }
        }

        // MARK: - Many at once

        /// Eight substances active together: "Warehouse night", started four
        /// hours ago and still running, with redoses of MDMA, ketamine and
        /// cocaine beside alcohol, cannabis, nicotine, GHB and 2C-B. A finished
        /// party with seven of them ("House party", eight days ago) and a few
        /// weekday coffees and drinks between give the history charts something
        /// to draw.
        @MainActor
        static func seedCrowdedSession(context: ModelContext, now: Date) {
            let today = Calendar.current.startOfDay(for: now)
            func party(_ title: String, start: Date, minutes doses: [(Double, String, Double, String, RouteOfAdministration)]) {
                let session = Session(startDate: start, title: title)
                context.insert(session)
                for (offset, name, amount, unit, route) in doses {
                    let time = start.addingTimeInterval(offset * 60)
                    guard time <= now else { continue }
                    chartDose(name, amount, unit, route: route, at: time, tags: ["party"], session: session, in: context)
                }
                session.refreshDoseBounds()
            }
            party("Warehouse night", start: now.addingTimeInterval(-240 * 60), minutes: [
                (0, "Alcohol", 20, "g", .oral), (5, "Nicotine", 1, "mg", .inhalation),
                (20, "MDMA", 120, "mg", .oral), (60, "Alcohol", 20, "g", .oral),
                (75, "Cannabis", 3, "mg THC", .inhalation), (95, "Ketamine", 40, "mg", .insufflation),
                (120, "Nicotine", 1, "mg", .inhalation), (135, "Ketamine", 30, "mg", .insufflation),
                (140, "MDMA", 60, "mg", .oral), (160, "Cocaine", 50, "mg", .insufflation),
                (175, "2C-B", 15, "mg", .oral), (190, "GHB", 1.5, "g", .oral),
                (205, "Cocaine", 40, "mg", .insufflation), (215, "Ketamine", 30, "mg", .insufflation),
                (225, "Nicotine", 1, "mg", .inhalation),
            ])
            party("House party", start: today.addingTimeInterval(-8 * 86_400 + 21 * 3_600), minutes: [
                (0, "Alcohol", 20, "g", .oral), (30, "MDMA", 100, "mg", .oral), (50, "Alcohol", 20, "g", .oral),
                (90, "Cannabis", 3, "mg THC", .inhalation), (120, "Ketamine", 40, "mg", .insufflation),
                (150, "MDMA", 50, "mg", .oral), (170, "Cocaine", 50, "mg", .insufflation),
                (200, "Ketamine", 30, "mg", .insufflation), (230, "GHB", 1.5, "g", .oral),
                (260, "Nicotine", 1, "mg", .inhalation),
            ])
            for daysAgo in [1, 2, 3, 5, 6, 7, 9, 10, 12] {
                chartDose("Caffeine", 90, "mg", at: today.addingTimeInterval(-Double(daysAgo) * 86_400 + 8.5 * 3_600), tags: ["coffee"], in: context)
            }
            for daysAgo in [3, 10] {
                chartDose("Alcohol", 20, "g", at: today.addingTimeInterval(-Double(daysAgo) * 86_400 + 19.5 * 3_600), tags: ["drinks"], in: context)
            }
            for name in ["alcohol", "nicotine", "mdma", "cannabis", "ketamine", "cocaine", "2c-b", "ghb", "caffeine"] {
                insertClassColor(name, in: context)
            }
        }
    }

#endif
