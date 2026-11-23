#if DEBUG
    import Foundation
    import SwiftData

    extension PerfFixtures {
        /// One substance the journal generator logs, with how it is usually taken.
        struct Spec {
            let name: String
            let unit: String
            let amounts: [Double]
            var route: RouteOfAdministration = .oral
            var altRoute: RouteOfAdministration?
            /// Relative frequency among episodes.
            var weight: Double = 1
            /// Most doses in one episode (1 = never redosed).
            var redoses = 1
            /// Hour of day episodes start around.
            var hour: Double = 20
            var products: [String] = []
            var salt: String?
            var drink = false
        }

        static let catalog: [Spec] = [
            Spec(name: "Caffeine", unit: "mg", amounts: [60, 90, 120, 200], weight: 12, redoses: 3, hour: 8.5),
            Spec(name: "Alcohol", unit: "g", amounts: [14, 16.5, 20], weight: 6, redoses: 6, hour: 20, drink: true),
            Spec(name: "Nicotine", unit: "mg", amounts: [1, 2, 4], weight: 3, redoses: 5, hour: 14),
            Spec(name: "Cannabis", unit: "mg", amounts: [100, 200, 300], route: .inhalation, altRoute: .oral, weight: 4, redoses: 3, hour: 21),
            Spec(name: "Methylphenidate", unit: "mg", amounts: [18, 36, 54], weight: 5, hour: 8, products: ["Concerta", "Ritalin"]),
            Spec(name: "Amphetamine", unit: "mg", amounts: [10, 20], weight: 2, hour: 8, products: ["Adderall"], salt: "Sulfate"),
            Spec(name: "Lisdexamfetamine", unit: "mg", amounts: [30, 50, 70], weight: 2, hour: 7.5, products: ["Vyvanse"]),
            Spec(name: "Modafinil", unit: "mg", amounts: [100, 200], weight: 1, hour: 8),
            Spec(name: "L-Theanine", unit: "mg", amounts: [100, 200], weight: 2, hour: 8),
            Spec(name: "Magnesium", unit: "mg", amounts: [200, 350], weight: 2, hour: 22),
            Spec(name: "Vitamin D", unit: "IU", amounts: [1_000, 2_000, 4_000], weight: 2, hour: 9),
            Spec(name: "Melatonin", unit: "mg", amounts: [0.3, 0.5, 1, 3], route: .sublingual, weight: 3, hour: 23),
            Spec(name: "Ibuprofen", unit: "mg", amounts: [200, 400, 600], weight: 3, redoses: 3, hour: 13),
            Spec(name: "Paracetamol", unit: "mg", amounts: [500, 1_000], weight: 3, redoses: 3, hour: 13),
            Spec(name: "Codeine", unit: "mg", amounts: [15, 30, 60], weight: 0.6, redoses: 2, hour: 21),
            Spec(name: "Tramadol", unit: "mg", amounts: [50, 100], weight: 0.5, redoses: 2, hour: 20),
            Spec(name: "Oxycodone", unit: "mg", amounts: [5, 10], weight: 0.3, redoses: 2, hour: 21),
            Spec(name: "Kratom", unit: "g", amounts: [2, 3, 5], weight: 1, redoses: 3, hour: 15),
            Spec(name: "Alprazolam", unit: "mg", amounts: [0.25, 0.5, 1], weight: 1, hour: 22, products: ["Xanax"]),
            Spec(name: "Lorazepam", unit: "mg", amounts: [0.5, 1], weight: 1, hour: 23),
            Spec(name: "Diazepam", unit: "mg", amounts: [2, 5, 10], weight: 0.8, hour: 22, products: ["Valium"]),
            Spec(name: "Clonazepam", unit: "mg", amounts: [0.25, 0.5], weight: 0.8, hour: 22),
            Spec(name: "Etizolam", unit: "mg", amounts: [0.5, 1], weight: 0.4, hour: 22),
            Spec(name: "Zolpidem", unit: "mg", amounts: [5, 10], weight: 0.8, hour: 23.5),
            Spec(name: "Gabapentin", unit: "mg", amounts: [300, 600], weight: 0.8, redoses: 2, hour: 19),
            Spec(name: "Pregabalin", unit: "mg", amounts: [75, 150], weight: 0.6, redoses: 2, hour: 19),
            Spec(name: "Phenibut", unit: "g", amounts: [0.5, 1, 1.5], weight: 0.4, hour: 18),
            Spec(name: "GHB", unit: "mL", amounts: [1, 1.5, 2], weight: 0.5, redoses: 5, hour: 23),
            Spec(name: "MDMA", unit: "mg", amounts: [80, 100, 120], weight: 2, redoses: 3, hour: 22),
            Spec(name: "MDA", unit: "mg", amounts: [60, 90], weight: 0.3, redoses: 2, hour: 22),
            Spec(name: "Cocaine", unit: "mg", amounts: [20, 30, 50], route: .insufflation, weight: 1.5, redoses: 8, hour: 23),
            Spec(name: "Ketamine", unit: "mg", amounts: [20, 30, 50], route: .insufflation, weight: 2, redoses: 6, hour: 23, salt: "Hydrochloride"),
            Spec(name: "Methamphetamine", unit: "mg", amounts: [10, 20], weight: 0.2, redoses: 3, hour: 22),
            Spec(name: "3-MMC", unit: "mg", amounts: [100, 150], route: .insufflation, altRoute: .oral, weight: 0.5, redoses: 5, hour: 23),
            Spec(name: "4-FA", unit: "mg", amounts: [80, 100], weight: 0.4, redoses: 2, hour: 21),
            Spec(name: "LSD", unit: "µg", amounts: [75, 100, 150], route: .sublingual, weight: 1.5, redoses: 2, hour: 15),
            Spec(name: "Psilocybin mushrooms", unit: "g", amounts: [1, 2, 3.5], weight: 1.5, redoses: 2, hour: 17),
            Spec(name: "DMT", unit: "mg", amounts: [20, 40], route: .inhalation, weight: 0.4, redoses: 3, hour: 21),
            Spec(name: "Mescaline", unit: "mg", amounts: [200, 300], weight: 0.2, hour: 14),
            Spec(name: "2C-B", unit: "mg", amounts: [10, 15, 20], weight: 0.8, redoses: 2, hour: 22),
            Spec(name: "4-AcO-DMT", unit: "mg", amounts: [15, 20], weight: 0.3, hour: 16),
            Spec(name: "Nitrous oxide", unit: "g", amounts: [8, 16], route: .inhalation, weight: 0.8, redoses: 10, hour: 23),
            Spec(name: "Dextromethorphan", unit: "mg", amounts: [150, 300], weight: 0.3, hour: 20),
            Spec(name: "Diphenhydramine", unit: "mg", amounts: [25, 50], weight: 0.8, hour: 23),
            Spec(name: "Hydroxyzine", unit: "mg", amounts: [25, 50], weight: 0.5, hour: 22),
            Spec(name: "Sertraline", unit: "mg", amounts: [50, 100], weight: 1, hour: 9),
            Spec(name: "Escitalopram", unit: "mg", amounts: [10, 20], weight: 1, hour: 9),
            Spec(name: "Fluoxetine", unit: "mg", amounts: [20, 40], weight: 0.6, hour: 9),
            Spec(name: "Bupropion", unit: "mg", amounts: [150, 300], weight: 0.6, hour: 8),
            Spec(name: "Venlafaxine", unit: "mg", amounts: [75, 150], weight: 0.4, hour: 9),
            Spec(name: "Mirtazapine", unit: "mg", amounts: [15, 30], weight: 0.4, hour: 23),
            Spec(name: "Quetiapine", unit: "mg", amounts: [25, 50], weight: 0.4, hour: 23),
            Spec(name: "Trazodone", unit: "mg", amounts: [50, 100], weight: 0.4, hour: 23),
            Spec(name: "Propranolol", unit: "mg", amounts: [10, 20, 40], weight: 0.5, hour: 10),
            Spec(name: "Guanfacine", unit: "mg", amounts: [1, 2], weight: 0.3, hour: 21),
            Spec(name: "Memantine", unit: "mg", amounts: [5, 10], weight: 0.2, hour: 9),
            Spec(name: "Buprenorphine", unit: "mg", amounts: [2, 4, 8], route: .sublingual, weight: 0.3, hour: 9),
            Spec(name: "Methadone", unit: "mg", amounts: [20, 40], weight: 0.2, hour: 9),
            Spec(name: "Kava", unit: "g", amounts: [5, 10], weight: 0.3, redoses: 2, hour: 19),
            Spec(name: "Salvia divinorum", unit: "mg", amounts: [500, 1_000], route: .inhalation, weight: 0.1, hour: 21),
            Spec(name: "Ashwagandha", unit: "mg", amounts: [300, 600], weight: 0.5, hour: 9),
            Spec(name: "Creatine", unit: "g", amounts: [3, 5], weight: 1, hour: 10),
            Spec(name: "Omega-3", unit: "mg", amounts: [1_000], weight: 0.6, hour: 9),
        ]

        static let places: [(name: String, latitude: Double, longitude: Double)] = [
            ("Home", 48.8566, 2.3522), ("Studio", 48.8606, 2.3376), ("Parc des Buttes-Chaumont", 48.8809, 2.3828),
            ("Rex Club", 48.8708, 2.3478), ("Concrete", 48.8399, 2.3708), ("Lake cabin", 46.2044, 6.1432),
            ("Berghain", 52.5112, 13.4430), ("Office", 48.8738, 2.2950), ("Festival grounds", 51.0897, 4.3891),
            ("Alex's flat", 48.8530, 2.3690), ("Beach house", 43.2965, 5.3698), ("Forest trail", 48.4049, 2.7016),
        ]

        static let tagPool = [
            "work", "party", "sleep", "focus", "social", "pain", "trip", "meds", "weekend", "festival",
            "solo", "date", "gym", "anxiety", "travel", "study",
        ]

        static let notePool = [
            "Felt it faster than usual, probably the empty stomach.",
            "Smooth, no anxiety. Same again next time.",
            "Headache earlier, took this and it settled within the hour.",
            "Redosed because the first one barely landed.",
            "Ate a big dinner first; slower onset, gentler peak.",
            "Long day at work. Tired but wired.",
            "Great music, great people. Drank water every hour.",
            "Slept badly afterwards. Note to self: earlier next time.",
            "Grapefruit juice at breakfast — worth watching.",
            "Mild nausea for twenty minutes, then fine.",
        ]

        /// A journal of `target` doses spread over `days`, grouped into
        /// episodes: one substance taken one to several times within hours,
        /// filed as one session.
        struct Journal {
            var rng: PerfRNG
            let now: Date
            let days: Int
            let target: Int
            /// Names logged alongside the catalog (custom substances).
            var extraSubstances: [String] = []

            init(seed: UInt64, now: Date, days: Int, target: Int) {
                rng = PerfRNG(seed: seed)
                self.now = now
                self.days = days
                self.target = target
            }

            mutating func insert(into context: ModelContext, summary: inout Summary) {
                let specs = PerfFixtures.catalog + extraSubstances.map {
                    Spec(name: $0, unit: "mg", amounts: [5, 10, 20], weight: 1.5, redoses: 2, hour: 19)
                }
                let weights = specs.map(\.weight)
                var identities: [String: String?] = [:]
                let colored = Set(((try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? []).map(\.substance))
                for spec in specs {
                    let uid = SubstanceLibrary.substanceUID(for: spec.name)
                    identities[spec.name] = uid
                    if uid == nil, !extraSubstances.contains(spec.name) { summary.unresolvedSubstances.append(spec.name) }
                    guard !colored.contains(spec.name.lowercased()) else { continue }
                    context.insert(SubstanceColor(
                        substance: spec.name.lowercased(), tint: SubstanceColorStore.defaultTint(for: spec.name), usesDefault: true,
                    ))
                }
                let earliest = now.addingTimeInterval(-Double(days) * 86_400)
                var inserted = 0
                while inserted < target {
                    let spec = specs[rng.weighted(weights)]
                    let dayOffset = Double.random(in: 0 ..< Double(days), using: &rng)
                    let day = Calendar.current.startOfDay(for: earliest.addingTimeInterval(dayOffset * 86_400))
                    let hour = min(max(spec.hour + Double.random(in: -2 ... 2, using: &rng), 0), 23.9)
                    var time = day.addingTimeInterval(hour * 3_600)
                    guard time < now else { continue }
                    let count = min(Int.random(in: 1 ... spec.redoses, using: &rng), target - inserted)
                    let session = Session(startDate: time, title: rng.chance(0.08) ? rng.pick(["Friday out", "Lake evening", "Birthday", "Studio night", "Rainy Sunday"]) : nil)
                    context.insert(session)
                    let place = rng.chance(0.4) ? rng.pick(PerfFixtures.places) : nil
                    let tags = rng.chance(0.5) ? [rng.pick(PerfFixtures.tagPool)] : []
                    for index in 0 ..< count where time < now {
                        let entry = dose(spec, at: time, uid: identities[spec.name] ?? nil, place: place, tags: tags, first: index == 0)
                        context.insert(entry)
                        entry.session = session
                        inserted += 1
                        time = time.addingTimeInterval(Double.random(in: 25 ... 110, using: &rng) * 60)
                    }
                    if rng.chance(0.12) {
                        let note = SessionNote(
                            timestamp: session.startDate.addingTimeInterval(45 * 60), text: rng.pick(PerfFixtures.notePool),
                            shulgin: Int.random(in: 0 ... 3, using: &rng), mood: Int.random(in: -2 ... 3, using: &rng),
                            energy: Int.random(in: -2 ... 2, using: &rng), kind: rng.chance(0.5) ? .checkIn : .observation,
                            session: session,
                        )
                        context.insert(note)
                        summary.notes += 1
                    }
                    session.refreshDoseBounds()
                    summary.sessions += 1
                }
                summary.doses += inserted
                insertCustomUnits(into: context, summary: &summary)
            }

            private mutating func dose(
                _ spec: Spec, at time: Date, uid: String?, place: (name: String, latitude: Double, longitude: Double)?,
                tags: [String], first: Bool,
            ) -> DoseEntry {
                let product = !spec.products.isEmpty && rng.chance(0.6) ? rng.pick(spec.products) : nil
                let isomer = product.flatMap(SubstanceLibrary.isomer(for:))
                let release = product.flatMap(SubstanceLibrary.releaseForm(for:))
                let route = spec.altRoute != nil && rng.chance(0.25) ? spec.altRoute ?? spec.route : spec.route
                let amount = rng.pick(spec.amounts)
                let customUnit = spec.name == "Ketamine" && rng.chance(0.3)
                return DoseEntry(
                    substance: spec.name, amount: customUnit ? 1 : amount, unit: customUnit ? "bump" : spec.unit, route: route,
                    saltForm: spec.salt, isomer: isomer, releaseForm: release, productName: product, substanceUID: uid,
                    displayNameSnapshot: product == nil ? nil : DoseTitle.snapshot(canonicalName: spec.name, isomer: isomer, releaseForm: release),
                    timestamp: time,
                    notes: first && rng.chance(0.15) ? rng.pick(PerfFixtures.notePool) : nil,
                    tags: tags,
                    locationName: place?.name, latitude: place?.latitude, longitude: place?.longitude,
                    hadGrapefruit: rng.chance(0.03) ? true : nil,
                    meal: rng.chance(0.3) ? rng.pick(MealState.allCases) : nil,
                    isApproximate: rng.chance(0.1),
                    volumeML: spec.drink ? 330 : nil, abv: spec.drink ? 5 : nil,
                    drinkName: spec.drink ? rng.pick(["Beer", "IPA", "Wine", "Gin tonic"]) : nil,
                )
            }

            private func insertCustomUnits(into _: ModelContext, summary: inout Summary) {
                let store = CustomUnitStore.shared
                for (substance, label, amount, unit) in [
                    ("Ketamine", "bump", 20.0, "mg"), ("Cannabis", "joint", 300.0, "mg"),
                    ("Caffeine", "espresso", 63.0, "mg"), ("Kratom", "spoon", 2.5, "g"),
                ] where !store.hasLabel(label, forSubstanceNamed: substance) {
                    store.add(substanceName: substance, label: label, amountPerUnit: amount, unit: unit)
                    summary.customUnits += 1
                }
            }
        }
    }
#endif
