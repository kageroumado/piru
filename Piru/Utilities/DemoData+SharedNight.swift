import Foundation
import SwiftData

#if DEBUG

    extension DemoData {
        /// One person's doses in the ``Persona/sharedNight`` fixture.
        private struct SeedDose {
            let substance: String
            let amount: Double
            let unit: String
            var route: RouteOfAdministration = .oral
            /// Hours after 21:00 last night.
            let at: Double
        }

        /// ``Persona/sharedNight``: last night shared by the owner, Alice and
        /// Bob, each in their own store, plus an unshared session each for the
        /// owner and Alice. Every store is wiped first.
        @MainActor
        static func seedSharedNight(now: Date) {
            let directory = ProfileDirectory.shared
            func profileID(named name: String, color: ProfileColor) -> UUID? {
                if let existing = directory.profiles.first(where: { $0.name == name }) { return existing.id }
                return try? directory.addProfile(name: name, color: color).id
            }
            guard let alice = profileID(named: "Alice", color: .ocean),
                  let bob = profileID(named: "Bob", color: .amber) else { return }

            let cal = Calendar.current
            let today = cal.startOfDay(for: now)
            let night = cal.date(byAdding: .day, value: -1, to: today)
                .flatMap { cal.date(bySettingHour: 21, minute: 0, second: 0, of: $0) } ?? today
            let experience = UUID()

            seedStore(directory.owner.id) { context in
                let session = sharedSession(
                    title: "Kitchen disco", at: night, experience: experience, context: context,
                    doses: [
                        SeedDose(substance: "2C-B", amount: 15, unit: "mg", at: 0.15),
                        SeedDose(substance: "2C-B", amount: 5, unit: "mg", at: 1.6),
                    ],
                )
                SessionNoteService.add(
                    to: session, timestamp: night.addingTimeInterval(1.1 * 3_600),
                    text: "Colors up, everyone dancing.",
                )
                unsharedSession(
                    at: cal.date(byAdding: .day, value: -2, to: night) ?? night, context: context,
                    doses: [SeedDose(substance: "Caffeine", amount: 100, unit: "mg", at: -12)],
                )
            }
            seedStore(alice) { context in
                let session = sharedSession(
                    title: "Kitchen disco", at: night, experience: experience, context: context,
                    doses: [
                        SeedDose(substance: "2C-B", amount: 20, unit: "mg", at: 0.25),
                        SeedDose(substance: "Alcohol", amount: 1, unit: "units", at: 2),
                    ],
                )
                SessionNoteService.add(
                    to: session, timestamp: night.addingTimeInterval(3 * 3_600),
                    text: "Danced until two.", kind: .summary,
                )
                unsharedSession(
                    at: cal.date(byAdding: .day, value: -3, to: night) ?? night, context: context,
                    doses: [SeedDose(substance: "Methylphenidate", amount: 10, unit: "mg", at: -12.5)],
                )
            }
            seedStore(bob) { context in
                sharedSession(
                    title: nil, at: night, experience: experience, context: context,
                    doses: [SeedDose(substance: "LSD", amount: 100, unit: "µg", route: .sublingual, at: -0.1)],
                )
            }
            SharedExperienceStore.shared.invalidate()
        }

        /// Wipe `profileID`'s store, fill it, save, and record the commit as
        /// that profile's.
        @MainActor
        private static func seedStore(_ profileID: UUID, fill: (ModelContext) -> Void) {
            guard let container = ProfileDirectory.shared.container(for: profileID, writable: true) else { return }
            ProfileScope.$pinned.withValue(profileID) {
                let context = container.mainContext
                wipeUserData(context: context)
                fill(context)
                try? context.save()
                DoseLogService.shared.changed()
            }
        }

        @discardableResult
        @MainActor
        private static func sharedSession(
            title: String?, at night: Date, experience: UUID, context: ModelContext, doses: [SeedDose],
        ) -> Session {
            let session = unsharedSession(at: night, context: context, doses: doses)
            session.title = title
            session.sharedExperienceID = experience
            return session
        }

        @discardableResult
        @MainActor
        private static func unsharedSession(at base: Date, context: ModelContext, doses: [SeedDose]) -> Session {
            let session = Session(startDate: base.addingTimeInterval((doses.map(\.at).min() ?? 0) * 3_600))
            context.insert(session)
            for dose in doses {
                let entry = DoseEntry(
                    substance: dose.substance, amount: dose.amount, unit: dose.unit, route: dose.route,
                    substanceUID: SubstanceLibrary.substanceUID(for: dose.substance),
                    timestamp: base.addingTimeInterval(dose.at * 3_600),
                )
                context.insert(entry)
                entry.session = session
                let key = dose.substance.lowercased()
                let existing = (try? context.fetchCount(FetchDescriptor<SubstanceColor>(predicate: #Predicate { $0.substance == key }))) ?? 0
                if existing == 0 {
                    context.insert(SubstanceColor(substance: key, tint: SubstanceColorStore.defaultTint(for: key), usesDefault: true))
                }
            }
            session.refreshDoseBounds()
            return session
        }
    }

#endif
