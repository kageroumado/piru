#if DEBUG
    import Foundation
    import SwiftData

    extension PerfFixtures {
        // MARK: - Meds

        /// Scheduled meds with every past day's routine occurrence, the doses
        /// that satisfied them, and stock with refills and corrections.
        struct Meds {
            var rng: PerfRNG
            let now: Date
            let days: Int
            let items: Int

            init(seed: UInt64, now: Date, days: Int, items: Int) {
                rng = PerfRNG(seed: seed)
                self.now = now
                self.days = days
                self.items = items
            }

            private static let plans: [(substance: String, amount: Double, unit: String, slots: [Int], product: String?, quiet: Bool)] = [
                ("Methylphenidate", 36, "mg", [8 * 60], "Concerta", false),
                ("Sertraline", 100, "mg", [9 * 60], nil, false),
                ("Vitamin D", 2_000, "IU", [9 * 60], nil, true),
                ("Lamotrigine", 100, "mg", [8 * 60, 20 * 60], nil, false),
                ("Propranolol", 10, "mg", [8 * 60, 14 * 60, 20 * 60], nil, false),
                ("Magnesium", 350, "mg", [22 * 60], nil, true),
                ("Levothyroxine", 75, "µg", [7 * 60], nil, false),
                ("Melatonin", 1, "mg", [23 * 60], nil, false),
                ("Omega-3", 1_000, "mg", [9 * 60], nil, true),
                ("Guanfacine", 2, "mg", [21 * 60], nil, false),
            ]

            mutating func insert(into context: ModelContext, summary: inout Summary) {
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: now)
                let plans = Self.plans.prefix(items)
                for (order, plan) in plans.enumerated() {
                    let uid = SubstanceLibrary.substanceUID(for: plan.substance)
                    let item = DailyDoseItem(
                        substance: plan.substance, amount: plan.amount, unit: plan.unit, sortOrder: order,
                        isBackgroundMed: plan.quiet, substanceUID: uid,
                        isomer: plan.product.flatMap(SubstanceLibrary.isomer(for:)),
                        releaseForm: plan.product.flatMap(SubstanceLibrary.releaseForm(for:)),
                        productName: plan.product, reminderTimesMinutes: plan.slots, isQuiet: plan.quiet,
                    )
                    context.insert(item)
                    summary.meds += 1
                    let tookRate = 0.8 + Double(order % 3) * 0.06
                    var taken = 0.0
                    for daysAgo in (1 ... days).reversed() {
                        guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
                        for slot in plan.slots {
                            let occurrence = RoutineOccurrence(
                                substance: plan.substance, substanceUID: uid, route: .oral, dueDay: day, slotMinutes: slot,
                            )
                            if rng.chance(tookRate) {
                                let late = Double.random(in: -15 ... 90, using: &rng) * 60
                                let entry = DoseEntry(
                                    substance: plan.substance, amount: plan.amount, unit: plan.unit,
                                    productName: plan.product, substanceUID: uid, timestamp: day.addingTimeInterval(Double(slot) * 60 + late),
                                    medSlotMinutes: slot, tags: ["meds"], isBackgroundMed: plan.quiet,
                                )
                                context.insert(entry)
                                occurrence.state = .logged
                                occurrence.satisfyingEntryID = entry.id
                                summary.doses += 1
                                taken += plan.amount
                            } else {
                                occurrence.state = rng.chance(0.3) ? .skipped : .missed
                            }
                            context.insert(occurrence)
                            summary.occurrences += 1
                        }
                    }
                    context.insert(SubstanceColor(
                        substance: plan.substance.lowercased(), tint: SubstanceColorStore.defaultTint(for: plan.substance), usesDefault: true,
                    ))
                    insertStock(for: plan.substance, product: plan.product, unit: plan.unit, perDay: plan.amount * Double(plan.slots.count), order: order, into: context)
                    summary.inventory += 1
                }
            }

            /// Monthly refills sized to run the stock down, a correction every
            /// few months, and the last refill short for every third item so it
            /// reads low.
            private mutating func insertStock(for substance: String, product: String?, unit: String, perDay: Double, order: Int, into context: ModelContext) {
                let start = now.addingTimeInterval(-Double(days) * 86_400)
                var events = [ManualEvent(kind: .initial, amount: perDay * 30, date: start, note: "First fill", setsBaseline: true)]
                var month = 1
                while Double(month * 30) < Double(days) {
                    let date = start.addingTimeInterval(Double(month * 30) * 86_400)
                    let short = order % 3 == 0 && Double((month + 1) * 30) >= Double(days)
                    events.append(ManualEvent(kind: .restock, amount: perDay * (short ? 4 : 30), date: date, note: "Pharmacy refill"))
                    if month % 4 == 0 {
                        events.append(ManualEvent(
                            kind: .adjustment, amount: Double.random(in: -3 ... 3, using: &rng).rounded() * perDay / 2,
                            date: date.addingTimeInterval(86_400), note: "Counted the box",
                        ))
                    }
                    month += 1
                }
                context.insert(InventoryItem(
                    substance: substance, productName: product, unit: unit, trackingStart: start,
                    lowStockThreshold: perDay * 7, baselineQuantity: perDay * 30, doseSize: perDay,
                    manualEvents: events, sortOrder: order,
                ))
            }
        }

        // MARK: - Custom data

        /// Net-new custom substances (with durations), relabels and duration
        /// overrides of library substances, picked colors and custom units.
        struct CustomLayer {
            var rng: PerfRNG

            init(seed: UInt64) {
                rng = PerfRNG(seed: seed)
            }

            static let customNames = (1 ... 15).map { "Perf compound \($0)" }

            static let relabels = [
                ("Cannabis", "weed"), ("Caffeine", "coffee"), ("Alcohol", "drinks"), ("Methylphenidate", "meds"),
                ("Ibuprofen", "advil"), ("Melatonin", "sleep"), ("Nicotine", "snus"), ("Ketamine", "k"),
                ("Psilocybin mushrooms", "shrooms"), ("MDMA", "molly"),
            ]

            static let overrides = ["LSD", "Cocaine", "Kratom", "Alprazolam", "Gabapentin", "Codeine", "2C-B", "Modafinil"]

            mutating func insert(into context: ModelContext, summary: inout Summary) {
                let store = CustomSubstanceStore.shared
                for (index, name) in Self.customNames.enumerated() {
                    store.add(CustomSubstanceEntry(
                        name: name, category: rng.pick([.stimulant, .depressant, .psychedelic, .other]),
                        unit: "mg", notes: "Fixture substance \(index + 1).",
                        doses: nil, duration: duration(scale: Double(index % 5 + 1)), halfLifeMinutes: Double(60 * (index % 6 + 1)),
                    ))
                    summary.customSubstances += 1
                }
                for (name, label) in Self.relabels {
                    store.add(CustomSubstanceEntry(name: name, displayName: label))
                    summary.customSubstances += 1
                }
                for (index, name) in Self.overrides.enumerated() {
                    store.add(CustomSubstanceEntry(name: name, duration: duration(scale: Double(index % 3 + 2))))
                    summary.customSubstances += 1
                }
                let picked = (try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? []
                for (name, _) in Self.relabels {
                    let key = name.lowercased()
                    let tint = P3Color(red: Double.random(in: 0 ... 1, using: &rng), green: Double.random(in: 0 ... 1, using: &rng), blue: Double.random(in: 0 ... 1, using: &rng))
                    if let row = picked.first(where: { $0.substance == key }) {
                        context.delete(row)
                    }
                    context.insert(SubstanceColor(substance: key, tint: tint, usesDefault: false))
                }
                let units = CustomUnitStore.shared
                for (substance, label, amount, unit) in [
                    ("Cannabis", "gram joint", 1.0, "g"), ("Alcohol", "pint", 28.0, "g"), ("MDMA", "cap", 110.0, "mg"),
                    ("Kratom", "tablespoon", 7.0, "g"), ("Psilocybin mushrooms", "cap", 0.5, "g"), ("Caffeine", "can", 80.0, "mg"),
                ] where !units.hasLabel(label, forSubstanceNamed: substance) {
                    units.add(substanceName: substance, label: label, amountPerUnit: amount, unit: unit)
                    summary.customUnits += 1
                }
            }

            private func duration(scale: Double) -> DurationProfile {
                func range(_ low: Double, _ high: Double) -> DurationRange {
                    DurationRange(min: low * scale, max: high * scale)
                }
                return DurationProfile(
                    onset: range(10, 20), comeup: range(15, 30), peak: range(45, 90),
                    offset: range(30, 60), afterglow: range(60, 120), total: range(150, 300),
                )
            }
        }

        // MARK: - Profiles

        /// Three more profiles beside the owner, each with its own journal, and
        /// 20 nights every profile logged as one shared session.
        struct Profiles {
            static let namePrefix = "Perf "
            let seed: UInt64
            let now: Date

            init(seed: UInt64, now: Date) {
                self.seed = seed
                self.now = now
            }

            func insert(owner: ModelContext, summary: inout Summary) {
                let directory = ProfileDirectory.shared
                let people: [(String, ProfileColor)] = [("Alice", .ocean), ("Bob", .amber), ("Chiaki", .violet)]
                let nights = (0 ..< 20).map { index in
                    (UUID(), Calendar.current.startOfDay(for: now).addingTimeInterval(-Double(index * 9 + 2) * 86_400 + 21 * 3_600))
                }
                insertSharedNights(nights, into: owner, salt: 0, summary: &summary)
                for (offset, person) in people.enumerated() {
                    guard let profile = try? directory.addProfile(name: Self.namePrefix + person.0, color: person.1),
                          let container = directory.container(for: profile.id, writable: true) else { continue }
                    summary.profiles += 1
                    ProfileScope.$pinned.withValue(profile.id) {
                        let context = container.mainContext
                        DemoData.wipeUserData(context: context)
                        var journal = Journal(seed: seed + UInt64(offset) + 1, now: now, days: 365, target: 1_500)
                        journal.insert(into: context, summary: &summary)
                        insertSharedNights(nights, into: context, salt: offset + 1, summary: &summary)
                        try? context.save()
                        DoseLogService.shared.changed()
                    }
                }
                SharedExperienceStore.shared.invalidate()
            }

            private func insertSharedNights(_ nights: [(UUID, Date)], into context: ModelContext, salt: Int, summary: inout Summary) {
                for (index, (experience, start)) in nights.enumerated() {
                    let session = Session(startDate: start, title: index.isMultiple(of: 3) ? "Shared night \(index + 1)" : nil)
                    session.sharedExperienceID = experience
                    context.insert(session)
                    for round in 0 ..< 2 {
                        let entry = DoseEntry(
                            substance: round == 0 ? "MDMA" : "Alcohol", amount: round == 0 ? 90 + Double(salt * 10) : 16.5,
                            unit: round == 0 ? "mg" : "g", substanceUID: SubstanceLibrary.substanceUID(for: round == 0 ? "MDMA" : "Alcohol"),
                            timestamp: start.addingTimeInterval(Double(round) * 5_400 + Double(salt) * 300),
                        )
                        context.insert(entry)
                        entry.session = session
                        summary.doses += 1
                    }
                    session.refreshDoseBounds()
                    summary.sessions += 1
                }
            }
        }

        // MARK: - Hormones

        /// Estradiol valerate every 5 days for a year, then cypionate weekly;
        /// daily spironolactone and nightly progesterone; monthly labs.
        struct Hormones {
            var rng: PerfRNG
            let now: Date

            init(seed: UInt64, now: Date) {
                rng = PerfRNG(seed: seed)
                self.now = now
            }

            mutating func insert(into context: ModelContext, summary: inout Summary) {
                let today = Calendar.current.startOfDay(for: now)
                let sites = InjectionSite.Area.allCases.flatMap { area in InjectionSite.Side.allCases.map { InjectionSite(area: area, side: $0) } }
                var daysAgo = 730
                var shot = 0
                while daysAgo >= 0 {
                    let valerate = daysAgo > 365
                    context.insert(DoseEntry(
                        substance: "Estradiol", amount: valerate ? 4 : 5, unit: "mg", route: .intramuscular,
                        saltForm: valerate ? "Valerate" : "Cypionate",
                        substanceUID: SubstanceLibrary.substanceUID(for: "Estradiol"),
                        timestamp: today.addingTimeInterval(-Double(daysAgo) * 86_400 + 9 * 3_600 + Double.random(in: -1_800 ... 1_800, using: &rng)),
                        tags: ["hrt"], injectionSite: sites[shot % sites.count],
                    ))
                    shot += 1
                    summary.doses += 1
                    daysAgo -= valerate ? 5 : 7
                }
                for day in 0 ... 730 {
                    let base = today.addingTimeInterval(-Double(day) * 86_400)
                    context.insert(DoseEntry(substance: "Spironolactone", amount: 100, unit: "mg", timestamp: base.addingTimeInterval(8.5 * 3_600), tags: ["hrt"]))
                    summary.doses += 1
                    if day < 400, rng.chance(0.9) {
                        context.insert(DoseEntry(substance: "Progesterone", amount: 100, unit: "mg", route: .rectal, timestamp: base.addingTimeInterval(22.5 * 3_600), tags: ["hrt"]))
                        summary.doses += 1
                    }
                }
                for month in 0 ..< 24 {
                    let date = today.addingTimeInterval(-Double(month * 30 + 3) * 86_400 + 8 * 3_600)
                    let ester = month >= 12 ? "estradiol_valerate" : "estradiol_cypionate"
                    context.insert(LabMeasurement(date: date, analyteKey: "estradiol", value: Double.random(in: 110 ... 260, using: &rng), inputUnit: "pg/mL", esterID: ester))
                    context.insert(LabMeasurement(date: date, analyteKey: "testosterone", value: Double.random(in: 10 ... 60, using: &rng), inputUnit: "ng/dL", excludedFromCalibration: true))
                    summary.labs += 2
                }
                for name in ["Estradiol", "Spironolactone", "Progesterone"] {
                    context.insert(SubstanceColor(substance: name.lowercased(), tint: SubstanceColorStore.defaultTint(for: name), usesDefault: true))
                }
            }
        }
    }
#endif
