#if DEBUG
    import Foundation
    import os
    import SwiftData

    /// Large, varied stores for `pipeline/perf/`, selected by
    /// `-piruPerfFixture <name>`. Every generator is seeded, so a fixture is the
    /// same rows on every run, and every date is relative to `DebugClock.now`,
    /// so a run pinned with `-piruNow` reproduces exactly.
    ///
    /// Rows are inserted directly with their sessions already assigned, so
    /// seeding 12,000 doses is one save rather than a clustering pass per dose.
    @MainActor
    enum PerfFixtures {
        enum Fixture: String, CaseIterable {
            /// 5,000 doses over two years: 60+ substances, redosed sessions,
            /// notes, tags, locations, food state, brands, salts, custom units,
            /// three meds with stock.
            case heavy
            /// Ten scheduled meds over 18 months with their routine occurrences,
            /// stock with refills and corrections, two items low.
            case dailyMeds
            /// Custom substances, relabels, duration overrides, picked colors and
            /// custom units, over a 2,000-dose journal that uses them.
            case customData
            /// Four profiles of 1,500 doses each and 20 nights shared between them.
            case profiles
            /// Two years of injected estradiol (an ester switch), daily
            /// spironolactone and progesterone, and 24 blood draws.
            case hormones
            /// 12,000 doses over three years, plus the meds and custom layers.
            case stress
            /// No rows: the target of the import flow.
            case empty
        }

        /// The fixture named by `-piruPerfFixture`, if any.
        static var requested: Fixture? {
            UserDefaults.standard.string(forKey: "piruPerfFixture").flatMap(Fixture.init(rawValue:))
        }

        struct Summary: Codable {
            let fixture: String
            var doses = 0
            var sessions = 0
            var notes = 0
            var meds = 0
            var occurrences = 0
            var inventory = 0
            var labs = 0
            var customSubstances = 0
            var customUnits = 0
            var profiles = 1
            var unresolvedSubstances: [String] = []
            var seconds: Double = 0
        }

        /// Wipes the active store (and any perf profiles) and seeds `fixture`.
        static func seed(_ fixture: Fixture, container: ModelContainer) -> Summary {
            let started = Date.now
            let state = PerfProbe.signposter.beginInterval("seed", "\(fixture.rawValue, privacy: .public)")
            defer { PerfProbe.signposter.endInterval("seed", state) }
            let context = container.mainContext
            removePerfProfiles()
            DemoData.wipeUserData(context: context)
            CustomSubstanceStore.shared.resetAfterDeletion()
            var summary = Summary(fixture: fixture.rawValue)
            let now = DebugClock.now
            switch fixture {
            case .heavy:
                var journal = Journal(seed: 5001, now: now, days: 730, target: 5_000)
                journal.insert(into: context, summary: &summary)
                var meds = Meds(seed: 5002, now: now, days: 120, items: 3)
                meds.insert(into: context, summary: &summary)
            case .dailyMeds:
                var meds = Meds(seed: 6001, now: now, days: 548, items: 10)
                meds.insert(into: context, summary: &summary)
            case .customData:
                var custom = CustomLayer(seed: 7001)
                custom.insert(into: context, summary: &summary)
                var journal = Journal(seed: 7002, now: now, days: 365, target: 2_000)
                journal.extraSubstances = CustomLayer.customNames
                journal.insert(into: context, summary: &summary)
            case .profiles:
                var journal = Journal(seed: 8001, now: now, days: 365, target: 1_500)
                journal.insert(into: context, summary: &summary)
                Profiles(seed: 8002, now: now).insert(owner: context, summary: &summary)
            case .hormones:
                var hormones = Hormones(seed: 9001, now: now)
                hormones.insert(into: context, summary: &summary)
            case .stress:
                var journal = Journal(seed: 10001, now: now, days: 1_095, target: 12_000)
                journal.insert(into: context, summary: &summary)
                var meds = Meds(seed: 10002, now: now, days: 365, items: 6)
                meds.insert(into: context, summary: &summary)
                var custom = CustomLayer(seed: 10003)
                custom.insert(into: context, summary: &summary)
            case .empty:
                break
            }
            InventoryService.recomputeAll(in: context, notify: false)
            try? context.save()
            // Meds and hormone doses are inserted without a session, the way a
            // fresh import arrives; the clustering pass files them.
            SessionService.assignUnassignedDoses(in: context)
            RoutineOccurrenceService.reconcile(in: context)
            try? context.save()
            DoseLogService.shared.changed()
            ActiveSessionManager.shared.clearSession()
            ActiveSessionManager.shared.recoverSession(container: container)
            summary.seconds = Date.now.timeIntervalSince(started)
            return summary
        }

        /// Profiles a previous profiles fixture added; their journals go with them.
        private static func removePerfProfiles() {
            let directory = ProfileDirectory.shared
            for profile in directory.profiles where profile.name.hasPrefix(Profiles.namePrefix) {
                try? directory.deleteProfile(id: profile.id)
            }
        }
    }

    // MARK: - Randomness

    /// SplitMix64: small, fast and the same sequence on every platform.
    struct PerfRNG: RandomNumberGenerator {
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

        mutating func chance(_ probability: Double) -> Bool {
            Double.random(in: 0 ..< 1, using: &self) < probability
        }

        mutating func pick<T>(_ items: [T]) -> T {
            items[Int.random(in: 0 ..< items.count, using: &self)]
        }

        /// An index drawn with the given relative weights.
        mutating func weighted(_ weights: [Double]) -> Int {
            let total = weights.reduce(0, +)
            var roll = Double.random(in: 0 ..< total, using: &self)
            for (index, weight) in weights.enumerated() {
                roll -= weight
                if roll < 0 { return index }
            }
            return weights.count - 1
        }
    }
#endif
