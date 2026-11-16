import Foundation
import SwiftData

#if DEBUG

    extension DemoData {
        /// The ``Persona/sharedStash`` fixture: the active profile ("you") with
        /// Alice and Bob beside it, created when absent.
        ///
        /// - Your 2C-B (150 mg) is shared with Alice; two of your doses and two of
        ///   hers draw it down to 80 mg.
        /// - Bob's ketamine (500 mg) is shared with you and Alice; his doses and
        ///   one of yours leave 350 mg. It shows in your Inventory as Bob's.
        /// - Methylphenidate (yours) and caffeine (Alice's) stay unshared.
        ///
        /// Every journal it touches is wiped first, the active one by the caller.
        @MainActor
        static func seedSharedStash(context: ModelContext, now: Date, directory: ProfileDirectory = .shared) {
            func person(_ name: String, _ color: ProfileColor) -> PiruProfile? {
                directory.profiles.first { $0.name == name && $0.id != directory.activeProfileID }
                    ?? (try? directory.addProfile(name: name, color: color))
            }
            guard let alice = person("Alice", .teal), let bob = person("Bob", .amber),
                  let aliceContext = directory.container(for: alice.id, writable: true)?.mainContext,
                  let bobContext = directory.container(for: bob.id, writable: true)?.mainContext
            else { return }
            let me = directory.activeProfileID
            let day: Double = 86_400
            func ago(_ days: Double, hour: Double = 21) -> Date {
                Calendar.current.startOfDay(for: now).addingTimeInterval(-days * day + hour * 3_600)
            }
            func dose(_ name: String, _ amount: Double, route: RouteOfAdministration = .oral, at date: Date) -> DoseEntry {
                DoseEntry(
                    substance: name, amount: amount, unit: "mg", route: route,
                    substanceUID: SubstanceLibrary.substanceUID(for: name), timestamp: date,
                )
            }
            func stock(
                _ name: String, amount: Double, since start: Date, doseSize: Double, threshold: Double? = nil, sharedWith: [UUID] = [],
            ) -> InventoryItem {
                let item = InventoryItem(
                    substance: name, unit: "mg", trackingStart: start, lowStockThreshold: threshold,
                    baselineQuantity: amount, doseSize: doseSize,
                    manualEvents: [ManualEvent(kind: .initial, amount: amount, date: start, setsBaseline: true)],
                    createdAt: start,
                )
                item.sharedWith = sharedWith
                return item
            }

            // Yours.
            context.insert(stock("2C-B", amount: 150, since: ago(10, hour: 18), doseSize: 15, threshold: 30, sharedWith: [alice.id]))
            context.insert(stock("Methylphenidate", amount: 300, since: ago(12, hour: 8), doseSize: 10))
            context.insert(dose("2C-B", 15, at: ago(8)))
            context.insert(dose("2C-B", 15, at: ago(3)))
            context.insert(dose("Ketamine", 50, route: .insufflation, at: ago(5, hour: 23)))
            for daysAgo in stride(from: 11.0, through: 1, by: -1) {
                context.insert(dose("Methylphenidate", 10, at: ago(daysAgo, hour: 8.5)))
            }

            // Alice's.
            wipeUserData(context: aliceContext)
            aliceContext.insert(stock("Caffeine", amount: 2_000, since: ago(9, hour: 7), doseSize: 100))
            aliceContext.insert(dose("2C-B", 20, at: ago(6)))
            aliceContext.insert(dose("2C-B", 20, at: ago(1)))
            aliceContext.insert(dose("Caffeine", 100, at: ago(1, hour: 9)))

            // Bob's.
            wipeUserData(context: bobContext)
            bobContext.insert(stock("Ketamine", amount: 500, since: ago(14, hour: 17), doseSize: 50, threshold: 100, sharedWith: [me, alice.id]))
            bobContext.insert(dose("Ketamine", 60, route: .insufflation, at: ago(10, hour: 22)))
            bobContext.insert(dose("Ketamine", 40, route: .insufflation, at: ago(2, hour: 22)))

            for other in [aliceContext, bobContext] {
                InventoryService.recomputeAll(in: other, notify: false)
                try? other.save()
                SessionService.assignUnassignedDoses(in: other)
                try? other.save()
            }
            Task(name: "Shared stash stock") {
                await SharedInventory.shared.refresh(notify: false)
            }
        }
    }

#endif
