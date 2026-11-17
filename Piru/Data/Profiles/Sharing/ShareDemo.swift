import Foundation
import SwiftData

#if DEBUG

    /// `-piruShareDemo`: a share from "Bob", sealed to the active profile and
    /// opened the way an AirDropped file is, for simulator checks of the
    /// receive flow. Bob's side overlaps the newest session in the journal.
    @MainActor
    enum ShareDemo {
        static let argument = "-piruShareDemo"

        static func run(directory: ProfileDirectory = .shared) async {
            await SubstanceStore.shared.ensureAllLoaded()
            guard let me = try? ShareIdentityStore.shared.identity(for: directory.activeProfileID) else { return }
            let bob = ShareIdentity.make()

            var newest = FetchDescriptor<Session>(
                predicate: #Predicate { $0.lastDoseDate != nil },
                sortBy: [SortDescriptor(\.startDate, order: .reverse)],
            )
            newest.fetchLimit = 1
            // A `-piruPersona` seed lands a moment after launch; wait for it.
            var mine: Session?
            for _ in 0 ..< 20 {
                mine = try? directory.activeContainer.mainContext.fetch(newest).first
                if mine != nil { break }
                try? await Task.sleep(for: .milliseconds(250))
            }
            let start = mine.map { $0.startDate.addingTimeInterval(900) } ?? Date.now.addingTimeInterval(-3 * 3_600)

            let doses = [("2C-B", 20.0, "mg", 0.0), ("Alcohol", 1.0, "units", 1.5)].map { substance, amount, unit, hours in
                let entry = DoseEntry(
                    substance: substance, amount: amount, unit: unit,
                    substanceUID: SubstanceLibrary.substanceUID(for: substance),
                    timestamp: start.addingTimeInterval(hours * 3_600),
                )
                return SharedDoseSnapshot(entry, tint: SubstanceColorStore.defaultTint(for: substance.lowercased()))
            }
            let side = SessionShare.Side(
                experienceID: mine?.sharedExperienceID ?? UUID(),
                sessionID: UUID(),
                title: "Kitchen disco",
                summary: nil,
                startDate: start,
                doses: doses,
                notes: [SharedNoteSnapshot(id: UUID(), timestamp: start.addingTimeInterval(3_600), text: "Colors up.")],
                weightKg: 72,
            )
            let share = SessionShare(sender: .init(name: "Bob", avatar: .monogram(for: "Bob")), side: side)
            guard let envelope = try? ShareEnvelope.seal(share.encoded(), from: bob, to: [(me.personID, me.publicKey)]),
                  let data = try? envelope.encoded()
            else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Demo.pirushare")
            try? data.write(to: url)
            _ = ShareInbox.shared.handle(url, directory: directory)
        }
    }

#endif
