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

        // MARK: - Personas (-piruPersona <name>)

        /// User-archetype fixtures for UI-state testing, selected with the
        /// `-piruPersona <name>` launch argument:
        ///
        ///     xcrun simctl launch booted dev.yumeji.piru -piruPersona dailyMeds
        ///
        /// Unlike the showcase seed (which only fills an empty store), a
        /// persona **always wipes and reseeds**, so relaunching with a
        /// different name deterministically switches the whole UI state —
        /// the point is auditing the same screens under the data shapes real
        /// users actually have, not the dense dev journal we're blind to.
        enum Persona: String, CaseIterable {
            /// The archetypal real user (what TestFlight screenshots show):
            /// one scheduled stimulant med + one quiet supplement, taken
            /// consistently for 60 days; this morning's med is active now.
            case dailyMeds
            /// Same meds, ~60% adherence in streaks and multi-day gaps; the
            /// last dose was three days ago and late. Nothing active, today
            /// and yesterday untaken.
            case sporadicMeds
            /// Opens the app once every few weeks: a handful of as-needed
            /// clusters across 90 days, the latest ~3 weeks ago. No scheduled
            /// meds, nothing active — the Journal is mostly empty space.
            case rareOpener
            /// ``dailyMeds`` with the stimulant's tracked supply run down to
            /// the low-stock threshold — the "refill me" state the store
            /// screenshots need, which no adherence fixture reaches on its own.
            case medsLowStock
            /// Two psychedelic sessions with timestamped notes: an LSD evening
            /// twelve days ago fully annotated (ratings, mood, descriptors — the
            /// trip-report fixture), and a psilocybin session ~90 min in right
            /// now with its first notes (the check-in offer + live markers).
            case psychonaut
        }

        /// Seed the persona named by `-piruPersona`, if any. Returns `true`
        /// when a persona was seeded, so the caller skips the showcase seed.
        @MainActor
        static func insertPersonaData(container: ModelContainer) -> Bool {
            guard let name = UserDefaults.standard.string(forKey: "piruPersona") else { return false }
            guard let persona = Persona(rawValue: name) else {
                print("DemoData: unknown persona '\(name)' — known: \(Persona.allCases.map(\.rawValue).joined(separator: ", "))")
                return false
            }

            let context = container.mainContext
            wipeUserData(context: context)

            switch persona {
            case .dailyMeds: seedMedsPersona(context: context, sporadic: false)
            case .sporadicMeds: seedMedsPersona(context: context, sporadic: true)
            case .rareOpener: seedRareOpener(context: context)
            case .medsLowStock: seedMedsPersona(context: context, sporadic: false, lowStock: true)
            case .psychonaut: seedPsychonaut(context: context)
            }

            // Inventory caches are a replay over doses, so they can only be
            // filled once the doses above are in the context.
            InventoryService.recomputeAll(in: context, notify: false)

            try? context.save()
            SessionService.assignUnassignedDoses(in: context)
            // The launch recovery pass ran against the pre-wipe store; re-run
            // it so a persona's active dose opens the live session on this
            // launch instead of needing a second one.
            ActiveSessionManager.shared.clearSession()
            ActiveSessionManager.shared.recoverSession(container: container)
            return true
        }

        /// Wipe every model that surfaces in the UI — a fixture must not
        /// inherit the previous store's state. (QuickLogDose is the recents
        /// store behind the Log sheet's "Your Substances"; leaving it made
        /// a meds-only persona offer the dev store's research chemicals.)
        @MainActor
        static func wipeUserData(context: ModelContext) {
            try? context.delete(model: DoseEntry.self)
            try? context.delete(model: Session.self)
            try? context.delete(model: SubstanceColor.self)
            try? context.delete(model: UserColor.self)
            try? context.delete(model: FavoriteSubstance.self)
            try? context.delete(model: DailyDoseItem.self)
            try? context.delete(model: QuickLogDose.self)
            try? context.delete(model: DoseRoutine.self)
            try? context.delete(model: RoutineOccurrence.self)
            try? context.delete(model: InventoryItem.self)
            try? context.delete(model: ToleranceState.self)
            try? context.delete(model: CustomSubstanceRecord.self)
            try? context.delete(model: CustomDrinkPreset.self)
        }

        // MARK: - Import fixture (-piruImportFile <path>)

        /// `-piruImportFile <absolute path>` launch argument: wipe the store and
        /// import an exported JSON (Piru-native, PsyLog, or legacy), so a real
        /// user's export can be installed on the simulator in one launch instead
        /// of clicking through Settings ▸ Import Data:
        ///
        ///     xcrun simctl launch booted dev.yumeji.piru -piruImportFile /path/to/export.json
        ///
        /// Like personas, this always wipes first so relaunching is
        /// deterministic. Returns `true` when the argument was present (even on
        /// a failed import — the store was wiped, so the showcase seed must not
        /// fill it and mask the failure).
        @MainActor
        static func insertImportFileData(container: ModelContainer) -> Bool {
            guard let path = UserDefaults.standard.string(forKey: "piruImportFile") else { return false }
            let context = container.mainContext
            guard let data = FileManager.default.contents(atPath: path) else {
                print("DemoData: -piruImportFile could not read '\(path)'")
                return true
            }
            wipeUserData(context: context)
            do {
                try DataExportImport.importJSON(data: data, context: context)
                try context.save()
            } catch {
                print("DemoData: -piruImportFile import failed: \(DataExportImport.importErrorMessage(for: error))")
                return true
            }
            // The launch recovery pass ran against the pre-wipe store; re-run
            // it so an imported active dose opens the live session on this
            // launch instead of needing a second one.
            ActiveSessionManager.shared.clearSession()
            ActiveSessionManager.shared.recoverSession(container: container)
            print("DemoData: -piruImportFile imported '\(path)'")
            return true
        }

        /// The meds-user personas share one shape — a morning stimulant med
        /// and a quiet anytime supplement — and differ only in adherence.
        @MainActor
        private static func seedMedsPersona(context: ModelContext, sporadic: Bool, lowStock: Bool = false) {
            var rng = SeededRNG(seed: sporadic ? 20_260_722 : 20_260_721)
            let cal = Calendar.current
            let today = cal.startOfDay(for: .now)
            let now = Date.now

            context.insert(DailyDoseItem(
                substance: "Methylphenidate", amount: 10, unit: "mg", sortOrder: 0,
                reminderTimesMinutes: [8 * 60],
            ))
            context.insert(DailyDoseItem(
                substance: "Vitamin D", amount: 2_000, unit: "IU", sortOrder: 1,
                isBackgroundMed: true, isQuiet: true,
            ))
            context.insert(SubstanceColor(substance: "methylphenidate", hexColor: "2ca2f5"))
            context.insert(SubstanceColor(substance: "vitamin d", hexColor: "F9E2AF"))
            // Quick-log recents mirror what this user actually logs, so the
            // Log sheet's "Your Substances" shows their two meds — not the
            // empty state (chips are normally minted at log time; seeded
            // entries bypass that path).
            context.insert(QuickLogDose(substance: "Methylphenidate", route: .oral, amount: 10, unit: "mg", sortOrder: 0))
            context.insert(QuickLogDose(substance: "Vitamin D", route: .oral, amount: 2_000, unit: "IU", sortOrder: 1))

            // Tracked supply for the stimulant: one 250 mg fill, opened far
            // enough back that the logged doses have eaten most of it. Stock is
            // a replay over doses newer than `trackingStart`, so the fill date
            // is the only dial — 14 days back leaves a comfortable ~2 weeks,
            // 22 days back lands under the low-stock threshold.
            let fillDaysAgo = lowStock ? 22 : 14
            let fillDate = today.addingTimeInterval(-Double(fillDaysAgo) * 86_400 + 10 * 3_600)
            context.insert(InventoryItem(
                substance: "Methylphenidate",
                unit: "mg",
                trackingStart: fillDate,
                lowStockThreshold: 50,
                baselineQuantity: 250,
                doseSize: 10,
                manualEvents: [ManualEvent(kind: .initial, amount: 250, date: fillDate, note: "Pharmacy refill", setsBaseline: true)],
            ))

            // Sporadic misses cluster (forgot for a few days, then a good
            // streak) — a Markov step, not per-day coin flips. The sporadic
            // history also starts at day 3 so "today, yesterday, and the day
            // before are untaken" holds regardless of the RNG.
            var tookPreviousDay = true
            let oldestDay = 60
            let newestDay = sporadic ? 3 : 1
            for day in (newestDay ... oldestDay).reversed() {
                let dayStart = today.addingTimeInterval(-Double(day) * 86_400)
                let rate: Double = if !sporadic { 0.95 } else { tookPreviousDay ? 0.75 : 0.45 }
                let taken = Double.random(in: 0 ..< 1, using: &rng) < rate
                tookPreviousDay = taken
                guard taken else { continue }

                // The consistent user hits ~8:00; the sporadic one drifts as
                // late as 11:30.
                let lateness = sporadic
                    ? Double.random(in: 0 ... 3.5, using: &rng)
                    : Double.random(in: -0.2 ... 0.6, using: &rng)
                let medTime = dayStart.addingTimeInterval((8 + lateness) * 3_600)
                context.insert(DoseEntry(
                    substance: "Methylphenidate",
                    amount: 10, unit: "mg", route: .oral,
                    timestamp: medTime,
                    tags: ["meds"],
                ))
                if Double.random(in: 0 ..< 1, using: &rng) < (sporadic ? 0.5 : 0.85) {
                    context.insert(DoseEntry(
                        substance: "Vitamin D",
                        amount: 2_000, unit: "IU", route: .oral,
                        timestamp: medTime.addingTimeInterval(10 * 60),
                        tags: ["supplement"],
                        isBackgroundMed: true,
                    ))
                }
            }

            // Today: the consistent user took the med ~75 minutes ago (active
            // right now, supplement still pending); the sporadic user's today
            // is empty — the state the app must motivate, not celebrate.
            if !sporadic {
                let floor = cal.sessionDayStart(for: now).addingTimeInterval(5 * 60)
                context.insert(DoseEntry(
                    substance: "Methylphenidate",
                    amount: 10, unit: "mg", route: .oral,
                    timestamp: max(now.addingTimeInterval(-75 * 60), floor),
                    tags: ["meds"],
                ))
            }
        }

        @MainActor
        private static func seedRareOpener(context: ModelContext) {
            var rng = SeededRNG(seed: 20_260_723)
            let cal = Calendar.current
            let today = cal.startOfDay(for: .now)

            func at(_ daysAgo: Int, _ hour: Double) -> Date {
                let jitter = Double.random(in: -25 ... 25, using: &rng) * 60
                return today.addingTimeInterval(-Double(daysAgo) * 86_400 + hour * 3_600 + jitter)
            }

            // Sparse, self-contained episodes weeks apart — the newest ~3
            // weeks old so nothing is active and "today" is empty.
            for (daysAgo, kind) in [(21, "headache"), (24, "sleep"), (47, "party"), (52, "headache"), (78, "sleep"), (83, "party")] {
                switch kind {
                case "headache":
                    context.insert(DoseEntry(
                        substance: "Ibuprofen",
                        amount: 400, unit: "mg", route: .oral,
                        timestamp: at(daysAgo, 14.2),
                        notes: "Headache",
                        tags: ["as-needed"],
                    ))
                case "sleep":
                    context.insert(DoseEntry(
                        substance: "Melatonin",
                        amount: 0.5, unit: "mg", route: .sublingual,
                        timestamp: at(daysAgo, 23.1),
                        tags: ["sleep"],
                    ))
                default:
                    for round in 0 ..< 3 {
                        context.insert(DoseEntry(
                            substance: "Alcohol",
                            amount: round == 0 ? 2 : 1, unit: "units", route: .oral,
                            timestamp: at(daysAgo, 20.5 + Double(round) * 1.3),
                            notes: round == 0 ? "Birthday drinks" : nil,
                            tags: ["drinks", "social"],
                        ))
                    }
                }
            }

            for (name, hex) in [("ibuprofen", "f17395"), ("melatonin", "8394ff"), ("alcohol", "CBA6F7")] {
                context.insert(SubstanceColor(substance: name, hexColor: hex))
            }
            context.insert(QuickLogDose(substance: "Ibuprofen", route: .oral, amount: 400, unit: "mg", sortOrder: 0))
            context.insert(QuickLogDose(substance: "Melatonin", route: .sublingual, amount: 0.5, unit: "mg", sortOrder: 1))
        }

        /// Two psychedelic sessions with notes. Descriptor ids are SubFxOnEx
        /// concept ids from the bundled vocabulary (geometric imagery, euphoria,
        /// time dilation, nausea, awe, body load, introspection enhancement,
        /// jaw tension, color saturation enhancement).
        private static func seedPsychonaut(context: ModelContext) {
            let geometry = "5c5d671b-c0ea-5e67-8e09-9aecfc80a4b2"
            let euphoria = "43d66167-066c-575d-8ad3-16f95173a09f"
            let timeDilation = "a1fe306c-0b09-5031-8798-7740ac64165f"
            let nausea = "01bed144-1aa9-5c8d-9eec-2e353ef8f973"
            let awe = "2cca26d2-7717-58ef-bb2c-394b217cc39c"
            let bodyLoad = "f5f9b005-9ddb-52f7-bccb-cb2ae42f17dc"
            let introspection = "957f9432-9dac-50a5-9de7-696410f41058"
            let jawTension = "fc4d5df9-9d59-5860-baef-5d738b46cb5c"
            let colorSaturation = "a0b825ef-e144-5fb8-b6ca-16a2edef90d8"

            // An LSD evening twelve days ago, annotated end to end.
            let lsdStart = Calendar.current.startOfDay(for: .now).addingTimeInterval(-12 * 86_400 + 19 * 3_600)
            let lsdSession = Session(startDate: lsdStart, title: "Lake evening", note: "Gentle the whole way; the second half was the good part. Would keep the same dose.")
            context.insert(lsdSession)
            let lsd = DoseEntry(substance: "LSD", amount: 100, unit: "µg", route: .sublingual, timestamp: lsdStart)
            lsd.session = lsdSession
            context.insert(lsd)
            func lsdNote(_ minutes: Double, _ text: String, shulgin: Int? = nil, mood: Int? = nil, energy: Int? = nil, _ descriptors: [String] = [], hr: Double? = nil, kind: SessionNote.Kind = .observation) {
                context.insert(SessionNote(
                    timestamp: lsdStart.addingTimeInterval(minutes * 60), text: text,
                    shulgin: shulgin, mood: mood, energy: energy, descriptors: descriptors, heartRate: hr,
                    kind: kind, session: lsdSession,
                ))
            }
            lsdNote(35, "Slight nausea, a little restless. Nothing visual yet.", shulgin: 0, mood: 0, energy: 1, [nausea], hr: 78)
            lsdNote(65, "Edges of things breathing. Colors up. Laughing at the dog.", shulgin: 1, mood: 2, energy: 1, [colorSaturation, euphoria], hr: 86, kind: .checkIn)
            lsdNote(125, "Geometry behind closed eyes, ten minutes felt like an hour. Jaw a bit tight.", shulgin: 3, mood: 2, energy: 0, [geometry, timeDilation, jawTension], hr: 92)
            lsdNote(210, "Sat by the water. Quiet, very clear, kept thinking about my grandmother.", shulgin: 2, mood: 3, energy: -1, [awe, introspection], hr: 81, kind: .checkIn)
            lsdNote(330, "Mostly down. Tired in a good way.", shulgin: 1, mood: 1, energy: -2, [bodyLoad], hr: 72)
            SessionNoteService.ensureSummaryNote(for: lsdSession)
            lsdSession.refreshDoseBounds()

            // A psilocybin session ninety minutes in, still climbing.
            let mushroomStart = Date.now.addingTimeInterval(-90 * 60)
            let mushroomSession = Session(startDate: mushroomStart)
            context.insert(mushroomSession)
            let mushrooms = DoseEntry(substance: "Psilocybin mushrooms", amount: 2.5, unit: "g", route: .oral, timestamp: mushroomStart)
            mushrooms.session = mushroomSession
            context.insert(mushrooms)
            context.insert(SessionNote(
                timestamp: mushroomStart.addingTimeInterval(40 * 60), text: "Warm stomach, yawning. Music sounds wider.",
                shulgin: 1, mood: 1, energy: 0, descriptors: [bodyLoad], session: mushroomSession,
            ))
            context.insert(SessionNote(
                timestamp: mushroomStart.addingTimeInterval(75 * 60), text: "Patterns in the ceiling. Everything is a bit funny.",
                shulgin: 2, mood: 2, energy: 0, descriptors: [geometry, euphoria], session: mushroomSession,
            ))
            mushroomSession.refreshDoseBounds()

            for (name, hex) in [("lsd", "8394ff"), ("psilocybin mushrooms", "f17395")] {
                context.insert(SubstanceColor(substance: name, hexColor: hex))
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
    }

#endif
