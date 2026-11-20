import Foundation
import SwiftData
import Testing
@testable import Piru

/// Dose delete, retime and edit through ``SessionEditingService``: what each
/// writes to the store, and that each refreshes its session's bounds and bumps
/// ``DoseLogService/revision`` exactly once.
@MainActor
@Suite("SessionEditingService")
struct SessionEditingServiceTests {
    /// An in-memory store with the full current schema. A `ModelContext` holds
    /// its container weakly, so the store carries both for the test's duration.
    private struct Store {
        let container: ModelContainer
        let context: ModelContext
    }

    private func makeStore() throws -> Store {
        let container = try ModelContainer(
            for: Schema(PiruSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        return Store(container: container, context: ModelContext(container))
    }

    /// Absent from the substance library, so the tests are independent of
    /// bundled data.
    private let unknown = "ZZEditingTestSubstance"

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func time(_ hours: Double) -> Date {
        base.addingTimeInterval(hours * 3_600)
    }

    /// One session holding a dose at each of `hours`, saved.
    private func session(in context: ModelContext, dosesAt hours: [Double]) throws -> (session: Session, doses: [DoseEntry]) {
        let session = Session(startDate: time(hours.min() ?? 0))
        context.insert(session)
        let doses = hours.map { hour in
            let dose = DoseEntry(substance: unknown, amount: 100, timestamp: time(hour))
            context.insert(dose)
            dose.session = session
            return dose
        }
        session.refreshDoseBounds()
        try context.save()
        return (session, doses)
    }

    /// A library-shaped record for ``unknown`` with one user-defined unit.
    private var substanceWithCapsules: Substance {
        var substance = Substance(
            name: unknown,
            aliases: [],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [],
            effects: [],
            substanceUID: "PS-TEST",
        )
        substance.customUnitAliases = [UnitAlias(label: "capsule", amountPerUnit: 30, unit: "mg")]
        return substance
    }

    private func draft(for entry: DoseEntry) -> EntryDraft {
        let draft = EntryDraft()
        draft.begin(from: entry, hasByVolumeCapability: false)
        return draft
    }

    // MARK: - Delete

    @Test
    func `Delete removes the dose, pulls the session's bounds in and signals once`() throws {
        let store = try makeStore()
        let (session, doses) = try session(in: store.context, dosesAt: [0, 2])
        #expect(session.lastDoseDate == time(2))
        let before = DoseLogService.shared.revision

        SessionEditingService.shared.delete(doses[1], in: store.context)

        let remaining = try store.context.fetch(FetchDescriptor<DoseEntry>())
        #expect(remaining.map(\.id) == [doses[0].id])
        #expect(session.startDate == time(0))
        #expect(session.lastDoseDate == time(0))
        #expect(DoseLogService.shared.revision == before + 1)
    }

    // MARK: - Retime

    @Test
    func `Retime moves the session's bounds with the dose and signals once`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let store = try makeStore()
        let (session, doses) = try session(in: store.context, dosesAt: [0, 2])
        let before = DoseLogService.shared.revision

        doses[1].timestamp = time(5)
        SessionEditingService.shared.retimed(doses[1], from: time(2), in: store.context)

        #expect(session.startDate == time(0))
        #expect(session.lastDoseDate == time(5))
        #expect(DoseLogService.shared.revision == before + 1)

        doses[0].timestamp = time(-1)
        SessionEditingService.shared.retimed(doses[0], from: time(0), in: store.context)

        #expect(session.startDate == time(-1))
        #expect(session.lastDoseDate == time(5))
        #expect(DoseLogService.shared.revision == before + 2)
    }

    @Test
    func `Retime to the same time changes nothing and stays silent`() throws {
        let store = try makeStore()
        let (session, doses) = try session(in: store.context, dosesAt: [0, 2])
        // Bounds left stale on purpose: an untouched session proves the early return.
        session.lastDoseDate = time(9)
        let before = DoseLogService.shared.revision

        SessionEditingService.shared.retimed(doses[1], from: time(2), in: store.context)

        #expect(session.lastDoseDate == time(9))
        #expect(DoseLogService.shared.revision == before)
    }

    // MARK: - Edit

    @Test
    func `Commit stores an alias unit as its canonical amount and unit`() throws {
        let store = try makeStore()
        let (_, doses) = try session(in: store.context, dosesAt: [0])
        let draft = draft(for: doses[0])
        draft.amount = "2"
        draft.unit = "capsule"
        let before = DoseLogService.shared.revision

        let committed = SessionEditingService.shared.commit(draft, to: doses[0], substance: substanceWithCapsules, in: store.context)

        #expect(committed)
        #expect(doses[0].amount == 60)
        #expect(doses[0].unit == "mg")
        #expect(doses[0].substanceUID == "PS-TEST")
        #expect(DoseLogService.shared.revision == before + 1)
    }

    @Test
    func `Commit keeps a unit the substance has no alias for`() throws {
        let store = try makeStore()
        let (_, doses) = try session(in: store.context, dosesAt: [0])
        let draft = draft(for: doses[0])
        draft.amount = "2"
        draft.unit = "g"

        #expect(SessionEditingService.shared.commit(draft, to: doses[0], substance: substanceWithCapsules, in: store.context))

        #expect(doses[0].amount == 2)
        #expect(doses[0].unit == "g")
    }

    @Test
    func `Commit moves the session's bounds to an edited time`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let store = try makeStore()
        let (session, doses) = try session(in: store.context, dosesAt: [0, 2])
        let draft = draft(for: doses[1])
        draft.timestamp = time(6)
        let before = DoseLogService.shared.revision

        #expect(SessionEditingService.shared.commit(draft, to: doses[1], substance: nil, in: store.context))

        #expect(doses[1].timestamp == time(6))
        #expect(session.startDate == time(0))
        #expect(session.lastDoseDate == time(6))
        #expect(DoseLogService.shared.revision == before + 1)
    }

    @Test
    func `Commit refuses a draft with no amount and writes nothing`() throws {
        let store = try makeStore()
        let (_, doses) = try session(in: store.context, dosesAt: [0])
        let draft = draft(for: doses[0])
        draft.amount = ""
        draft.notes = "never written"
        let before = DoseLogService.shared.revision

        #expect(!SessionEditingService.shared.commit(draft, to: doses[0], substance: nil, in: store.context))

        #expect(doses[0].amount == 100)
        #expect(doses[0].notes == nil)
        #expect(DoseLogService.shared.revision == before)
    }

    @Test
    func `Commit of an unknown dose stores zero in the draft unit and drops its estimate and volume`() throws {
        let store = try makeStore()
        let (_, doses) = try session(in: store.context, dosesAt: [0])
        doses[0].volumeML = 250
        doses[0].abv = 5
        let draft = draft(for: doses[0])
        draft.unit = "capsule"
        draft.isUnknownDose = true
        draft.isApproximate = true

        #expect(SessionEditingService.shared.commit(draft, to: doses[0], substance: substanceWithCapsules, in: store.context))

        #expect(doses[0].isUnknownDose)
        #expect(doses[0].amount == 0)
        #expect(doses[0].unit == "capsule")
        #expect(!doses[0].isApproximate)
        #expect(doses[0].volumeML == nil)
        #expect(doses[0].abv == nil)
    }

    @Test
    func `Commit keeps a recorded volume while the amount stands and drops it once the amount changes`() throws {
        let store = try makeStore()
        let (_, doses) = try session(in: store.context, dosesAt: [0])
        doses[0].volumeML = 10
        doses[0].abv = 4
        doses[0].combinationName = "Test Mixture"

        let unchanged = draft(for: doses[0])
        unchanged.notes = "same amount"
        #expect(SessionEditingService.shared.commit(unchanged, to: doses[0], substance: nil, in: store.context))
        #expect(doses[0].volumeML == 10)
        #expect(doses[0].abv == 4)

        let changed = draft(for: doses[0])
        changed.amount = "50"
        #expect(SessionEditingService.shared.commit(changed, to: doses[0], substance: nil, in: store.context))
        #expect(doses[0].amount == 50)
        #expect(doses[0].volumeML == nil)
        #expect(doses[0].abv == nil)
    }

    @Test
    func `Commit merges the draft's tags with hashtags in its notes`() throws {
        let store = try makeStore()
        let (_, doses) = try session(in: store.context, dosesAt: [0])
        let draft = draft(for: doses[0])
        draft.tags = ["home", "calm"]
        draft.notes = "quiet evening #calm #music"

        #expect(SessionEditingService.shared.commit(draft, to: doses[0], substance: nil, in: store.context))

        #expect(Set(doses[0].tags) == ["home", "calm", "music"])
        #expect(doses[0].tags.count == 3)
        #expect(doses[0].notes == "quiet evening #calm #music")
    }

    @Test
    func `Commit keeps a meal only for an oral dose`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let store = try makeStore()
        let (_, doses) = try session(in: store.context, dosesAt: [0])
        let meal = try #require(MealState.allCases.first)
        let draft = draft(for: doses[0])
        draft.meal = meal

        draft.route = .oral
        #expect(SessionEditingService.shared.commit(draft, to: doses[0], substance: nil, in: store.context))
        #expect(doses[0].meal == meal)

        draft.route = .insufflation
        #expect(SessionEditingService.shared.commit(draft, to: doses[0], substance: nil, in: store.context))
        #expect(doses[0].meal == nil)
    }
}
