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
        /// A persona **always wipes and reseeds**, so relaunching with a
        /// different name deterministically switches the whole UI state —
        /// the point is auditing the same screens under the data shapes real
        /// users actually have. ``week`` is also what an empty DEBUG store
        /// fills with on launch (``insertDefaultData(container:)``).
        enum Persona: String, CaseIterable {
            /// One variable week ending today that lights up every surface:
            /// ADHD morning meds from My Meds with routine occurrences, a
            /// benzo at night, two titled psychedelic sessions with
            /// timestamped notes, a drinks evening logged from the beer
            /// preset, inventory, favorites, colors, and quick-log recents.
            case week
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
        /// when a persona was seeded, so the caller skips the default seed.
        @MainActor
        static func insertPersonaData(container: ModelContainer) -> Bool {
            guard let name = UserDefaults.standard.string(forKey: "piruPersona") else { return false }
            guard let persona = Persona(rawValue: name) else {
                print("DemoData: unknown persona '\(name)' — known: \(Persona.allCases.map(\.rawValue).joined(separator: ", "))")
                return false
            }
            seed(persona, container: container)
            return true
        }

        /// Fill an empty DEBUG store with ``Persona/week`` so a fresh
        /// simulator opens on a populated app. Launch with `-piruNoDemoData`
        /// to suppress it — needed when restoring a real export onto a wiped
        /// store, which would otherwise come up pre-seeded and merge the two
        /// histories.
        @MainActor
        static func insertDefaultData(container: ModelContainer) {
            guard !ProcessInfo.processInfo.arguments.contains("-piruNoDemoData") else { return }
            let count = (try? container.mainContext.fetchCount(FetchDescriptor<DoseEntry>())) ?? 0
            guard count == 0 else { return }
            seed(.week, container: container)
        }

        /// Wipe the store and seed `persona`, then run the launch-time passes
        /// that already ran against the pre-wipe store: session clustering,
        /// today's routine occurrences, and live-session recovery — so the
        /// persona's active dose opens the live session on this launch
        /// instead of needing a second one.
        @MainActor
        static func seed(_ persona: Persona, container: ModelContainer) {
            let context = container.mainContext
            wipeUserData(context: context)

            switch persona {
            case .week: seedWeek(context: context)
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
            RoutineOccurrenceService.reconcile(in: context)
            ActiveSessionManager.shared.clearSession()
            ActiveSessionManager.shared.recoverSession(container: container)
        }

        /// Wipe every model that surfaces in the UI — a fixture must not
        /// inherit the previous store's state. (QuickLogDose is the recents
        /// store behind the Log sheet's "Your Substances"; leaving it made
        /// a meds-only persona offer the dev store's research chemicals.)
        @MainActor
        static func wipeUserData(context: ModelContext) {
            try? context.delete(model: DoseEntry.self)
            try? context.delete(model: SessionNote.self)
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
        /// a failed import — the store was wiped, so the default seed must not
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

        // MARK: - The week (default seed)

        /// One realistic week ending today. Fixed hours and doses so
        /// screenshots reproduce; every substance resolves in the bundled DB
        /// and draws a timeline curve, except the quiet magnesium supplement,
        /// which stays off the graphs by design. Goes through the same
        /// services the UI uses (session notes, quick-log recents, drink
        /// presets) so relationships come out the way a logged week would.
        ///
        /// `now` is injectable so a test can pin the time of day: today's
        /// morning doses exist only once 08:05 has passed, so the morning
        /// tail is "Active Now" and nothing is ever seeded in the future.
        static func seedWeek(context: ModelContext, now: Date = .now) {
            let cal = Calendar.current
            let today = cal.startOfDay(for: now)

            func day(_ daysAgo: Int) -> Date {
                cal.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            }
            func at(_ daysAgo: Int, _ hour: Int, _ minute: Int = 0) -> Date {
                cal.date(bySettingHour: hour, minute: minute, second: 0, of: day(daysAgo)) ?? day(daysAgo)
            }
            func uid(_ name: String) -> String? {
                SubstanceLibrary.substanceUID(for: name)
            }
            @discardableResult
            func dose(
                _ name: String, _ amount: Double, _ unit: String, route: RouteOfAdministration = .oral,
                at timestamp: Date, notes: String? = nil, tags: [String] = [], background: Bool = false,
                volumeML: Double? = nil, abv: Double? = nil, drinkName: String? = nil,
            ) -> DoseEntry {
                let entry = DoseEntry(
                    substance: name, amount: amount, unit: unit, route: route, substanceUID: uid(name),
                    timestamp: timestamp, notes: notes, tags: tags, isBackgroundMed: background,
                    volumeML: volumeML, abv: abv, drinkName: drinkName,
                )
                context.insert(entry)
                return entry
            }
            /// A descriptor resolved by its vocabulary name at seed time, so the
            /// fixture never carries a concept id the bundled vocabulary might
            /// not know. An unmatched name is dropped and reported.
            func descriptor(_ name: String) -> String? {
                let want = SubjectiveEffectOntology.normalize(name)
                guard let hit = SubjectiveEffectOntology.shared.search(name, limit: 1).first,
                      SubjectiveEffectOntology.normalize(hit.concept.name) == want
                else {
                    print("DemoData: no subjective-effect concept named '\(name)'")
                    return nil
                }
                return hit.concept.id
            }
            func note(
                _ session: Session, plus minutes: Double, _ text: String,
                shulgin: Int? = nil, mood: Int? = nil, energy: Int? = nil,
                _ descriptors: [String] = [], heartRate: Double? = nil, kind: SessionNote.Kind = .observation,
            ) {
                SessionNoteService.add(
                    to: session, timestamp: session.startDate.addingTimeInterval(minutes * 60), text: text,
                    shulgin: shulgin, mood: mood, energy: energy,
                    descriptors: descriptors.compactMap(descriptor), heartRate: heartRate, kind: kind,
                )
            }
            func titledSession(_ title: String?, start: Date, checkIns: Bool = false) -> Session {
                let session = Session(startDate: start, title: title)
                if checkIns {
                    session.checkInIntervalMinutes = CheckInScheduler.Cadence.ladder.storedMinutes
                    session.checkInOffered = true
                }
                context.insert(session)
                return session
            }

            // ── My Meds ─────────────────────────────────────────
            let methylphenidate = DailyDoseItem(
                substance: "Methylphenidate", amount: 10, unit: "mg", sortOrder: 0,
                substanceUID: uid("Methylphenidate"), reminderTimesMinutes: [8 * 60],
            )
            let theanine = DailyDoseItem(
                substance: "L-Theanine", amount: 200, unit: "mg", sortOrder: 1,
                substanceUID: uid("L-Theanine"), reminderTimesMinutes: [8 * 60],
            )
            let magnesium = DailyDoseItem(
                substance: "Magnesium", amount: 350, unit: "mg", sortOrder: 2,
                isBackgroundMed: true, substanceUID: uid("Magnesium"), isQuiet: true, isAsNeeded: true,
            )
            for item in [methylphenidate, theanine, magnesium] {
                context.insert(item)
            }

            // ── Mornings ────────────────────────────────────────
            // The two scheduled meds plus a coffee. Past days also get their
            // routine occurrence rows, satisfied by the dose that was logged,
            // so adherence reads six of seven with today pending until 08:00.
            func morning(_ daysAgo: Int) {
                let med = dose("Methylphenidate", 10, "mg", at: at(daysAgo, 8, 0), tags: ["meds"])
                let supplement = dose("L-Theanine", 200, "mg", at: at(daysAgo, 8, 5), tags: ["meds"])
                dose("Caffeine", 90, "mg", at: at(daysAgo, 8, 5), notes: daysAgo == 0 ? "flat white" : nil, tags: ["coffee"])
                guard daysAgo > 0 else { return }
                for (item, entry) in [(methylphenidate, med), (theanine, supplement)] {
                    let occurrence = RoutineOccurrence(
                        substance: item.substance, substanceUID: item.substanceUID,
                        route: item.route, dueDay: day(daysAgo), slotMinutes: 8 * 60,
                    )
                    occurrence.state = .logged
                    occurrence.satisfyingEntryID = entry.id
                    context.insert(occurrence)
                }
            }
            for daysAgo in 1 ... 6 {
                morning(daysAgo)
            }
            if now >= at(0, 8, 6) {
                morning(0)
            }

            // ── Nights ──────────────────────────────────────────
            // Each benzo night is its own session: the clustering heuristic
            // would otherwise chain a 23:30 dose into the next morning's meds.
            for (daysAgo, hour, minute, amount) in [(1, 23, 10, 1.0), (3, 23, 30, 0.5)] {
                let night = titledSession(nil, start: at(daysAgo, hour, minute))
                dose("Lorazepam", amount, "mg", at: night.startDate, notes: "sleep", tags: ["sleep"]).session = night
                night.refreshDoseBounds()
            }
            dose("Magnesium", 350, "mg", at: at(6, 22, 0), tags: ["supplement"], background: true)

            // ── Lake evening (−2): psilocybin, notes end to end ──
            let lake = titledSession("Lake evening", start: at(2, 19, 30), checkIns: true)
            dose("Psilocybin mushrooms", 2.5, "g", at: lake.startDate, tags: ["trip"]).session = lake
            note(lake, plus: 40, "warm stomach, yawning. music sounds wider.",
                 shulgin: 1, mood: 1, energy: 0, ["warmth", "body load"])
            note(lake, plus: 80, "patterns in the wood grain, everything a bit funny. lake is very still.",
                 shulgin: 2, mood: 2, energy: 0, ["geometric imagery", "euphoria"], heartRate: 82, kind: .checkIn)
            note(lake, plus: 150, "peak. the water is breathing and I lost twenty minutes just looking at it. very happy, want to walk.",
                 shulgin: 3, mood: 2, energy: 1, ["geometric imagery", "euphoria", "time distortion"], heartRate: 88)
            note(lake, plus: 300, "mostly back. tired in the good way. tea, then bed.",
                 shulgin: 1, mood: 1, energy: -1, ["fatigue"], heartRate: 70, kind: .checkIn)
            SessionNoteService.setSummary("gentle the whole way. same dose next time, earlier start.", for: lake)
            lake.refreshDoseBounds()

            // ── Friday drinks (−4): three beers from the preset ──
            let alcohol = ByVolumeCatalog.capability(forAnyOf: ["Alcohol"])
            if let alcohol {
                CustomDrinkPreset.seedIfNeeded(for: "Alcohol", capability: alcohol, context: context)
            }
            let beer = (try? context.fetch(FetchDescriptor<CustomDrinkPreset>(
                predicate: #Predicate { $0.substanceName == "alcohol" },
                sortBy: [SortDescriptor(\.sortOrder)],
            )))?.first
            let beerML = beer?.volumeML ?? 330
            let beerABV = beer?.strengthABV ?? 5
            let beerGrams = alcohol?.canonicalAmount(volumeML: beerML, strength: beerABV)
                ?? ByVolumeDosing.grams(volumeML: beerML, abv: beerABV)
            let beerName = beer?.name ?? "Beer"
            let drinks = titledSession("Friday drinks", start: at(4, 19, 0))
            dose("Caffeine", 60, "mg", at: drinks.startDate, notes: "espresso before heading out", tags: ["coffee"]).session = drinks
            for (hour, minute) in [(20, 0), (21, 15), (22, 30)] {
                dose("Alcohol", beerGrams, alcohol?.canonicalUnit ?? "g", at: at(4, hour, minute), tags: ["drinks"],
                     volumeML: beerML, abv: beerABV, drinkName: beerName).session = drinks
            }
            drinks.refreshDoseBounds()

            // ── Forest walk (−5): LSD, three notes ──────────────
            let forest = titledSession("Forest walk", start: at(5, 14, 0), checkIns: true)
            dose("LSD", 100, "µg", route: .sublingual, at: forest.startDate, tags: ["trip"]).session = forest
            note(forest, plus: 50, "tab under the tongue for twenty minutes, now walking. slight jitter, colors a notch up.",
                 shulgin: 1, mood: 1, energy: 1, ["color saturation enhancement", "restlessness"])
            note(forest, plus: 120, "trees doing the thing. moss looks like it's breathing. laughed a full minute at a squirrel.",
                 shulgin: 3, mood: 3, energy: 1, ["drifting", "euphoria", "pattern recognition enhancement"], heartRate: 90, kind: .checkIn)
            note(forest, plus: 270, "sat on a log for an hour. thinking about work in a way that felt kind for once.",
                 shulgin: 2, mood: 2, energy: -1, ["introspection enhancement", "time dilation"])
            SessionNoteService.setSummary("long, clear, mostly kind. 100 µg is the right amount for a walk.", for: forest)
            forest.refreshDoseBounds()

            // ── Inventory ───────────────────────────────────────
            // Stock is a replay over doses newer than `trackingStart`, so the
            // fill sizes are chosen to land on round counts after the week's
            // consumption: 14 tablets of methylphenidate, 60 theanine caps, 8
            // lorazepam tablets, 40 caffeine tablets, 90 magnesium caps.
            let fill = at(7, 9, 0)
            let stock: [(name: String, doseSize: Double, initial: Double, threshold: Double, note: String)] = [
                ("Methylphenidate", 10, 210, 50, "pharmacy refill"),
                ("L-Theanine", 200, 67 * 200, 10 * 200, "new bottle"),
                ("Lorazepam", 1, 9.5, 2, "pharmacy refill"),
                ("Caffeine", 90, 47 * 90 + 60, 5 * 90, "new bottle"),
                ("Magnesium", 350, 91 * 350, 10 * 350, "new bottle"),
            ]
            for (order, item) in stock.enumerated() {
                context.insert(InventoryItem(
                    substance: item.name, unit: "mg", trackingStart: fill,
                    lowStockThreshold: item.threshold, baselineQuantity: item.initial, doseSize: item.doseSize,
                    manualEvents: [ManualEvent(kind: .initial, amount: item.initial, date: fill, note: item.note, setsBaseline: true)],
                    sortOrder: order,
                ))
            }

            // ── Favorites, colors, quick-log recents ────────────
            for (order, name) in ["Psilocybin mushrooms", "LSD", "Caffeine", "Lorazepam"].enumerated() {
                context.insert(FavoriteSubstance(substance: name, sortOrder: order, substanceUID: uid(name)))
            }
            let colors: [(String, String)] = [
                ("methylphenidate", "2ca2f5"), ("l-theanine", "00b3a2"), ("caffeine", "e08600"),
                ("lorazepam", "8394ff"), ("psilocybin mushrooms", "f17395"), ("lsd", "b885ef"),
                ("alcohol", "bb9900"), ("magnesium", "21b26a"),
            ]
            for (name, hex) in colors {
                context.insert(SubstanceColor(substance: name, hexColor: hex))
            }
            // Chips are normally minted at log time; seeded entries bypass
            // that path, so record the week's doses the way a log would.
            func recent(
                _ name: String, _ amount: Double, _ unit: String, route: RouteOfAdministration = .oral,
                volumeML: Double? = nil, abv: Double? = nil, drinkName: String? = nil, emoji: String? = nil,
            ) -> QuickLogManager.LoggedDose {
                QuickLogManager.LoggedDose(
                    substance: name, route: route, amount: amount, unit: unit,
                    volumeML: volumeML, abv: abv, drinkName: drinkName, emoji: emoji, substanceUID: uid(name),
                )
            }
            QuickLogManager.record([
                recent("Methylphenidate", 10, "mg"),
                recent("L-Theanine", 200, "mg"),
                recent("Caffeine", 90, "mg"),
                recent("Lorazepam", 1, "mg"),
                recent("Psilocybin mushrooms", 2.5, "g"),
                recent("LSD", 100, "µg", route: .sublingual),
                recent("Alcohol", beerGrams, alcohol?.canonicalUnit ?? "g",
                       volumeML: beerML, abv: beerABV, drinkName: beerName, emoji: beer?.emoji ?? "🍺"),
                recent("Magnesium", 350, "mg"),
            ], fixedOrder: true, context: context, save: false)
        }
    }

#endif
