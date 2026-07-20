import Foundation
import SwiftData
import Testing
@testable import Piru

/// Regression coverage for ``ActiveSessionManager/recoverSession(container:)``.
///
/// The bug these guard: recovery consulted a running Live Activity *first* and
/// returned unconditionally, so a stale activity replaced the real session
/// wholesale and SwiftData was never read. Because ActivityKit keeps `.ended`
/// activities around — with a content state frozen at the moment they ended —
/// every cold launch resurrected the same long-dead dose list. A session with
/// five doses rendered as one: the single dose the activity had been started
/// with, hours earlier.
///
/// The ActivityKit half can't be exercised here (an `Activity` can't be
/// fabricated in a test process), so these cover the half that can be: SwiftData
/// is authoritative, recovers *every* still-active dose, and reaches back far
/// enough to prove it. The activity is now only consulted when the store yields
/// nothing — see `LiveActivityManager.recoverEntriesFromActivity()`.
///
/// Serialized: `ActiveSessionManager` is a `@MainActor` singleton, so parallel
/// cases would race on `activeEntries`.
@MainActor
@Suite("ActiveSessionManager — recovery", .serialized)
struct ActiveSessionRecoveryTests {
    /// Full schema, per the note in `DataExportImportTests`. Returned alongside
    /// its context: a bare context doesn't retain its container, and the
    /// container deallocating out from under it traps on the next insert.
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: Schema(StoreRecovery.models), configurations: config)
    }

    private func insert(_ entries: [DoseEntry], into container: ModelContainer) throws {
        let context = ModelContext(container)
        for entry in entries {
            context.insert(entry)
        }
        try context.save()
    }

    /// A substance whose acute oral curve is long enough to still be running
    /// well past the old 12 h lookback, but inside the 24 h modeling ceiling.
    /// Resolved from the bundled DB rather than hardcoded so a data refresh
    /// re-picks instead of silently invalidating the test.
    private func longActingOralSubstance() -> Substance? {
        SubstanceStore.shared.all
            .sorted { $0.name < $1.name }
            .first { substance in
                guard let minutes = substance.timelineDuration(for: .oral)?.estimatedTotalMinutes
                else { return false }
                return minutes > 13 * 60 && minutes <= Substance.maxAcuteTimelineMinutes
            }
    }

    @Test
    func `Recovery restores every active dose, not just the earliest`() throws {
        ActiveSessionManager.shared.clearSession()
        let container = try makeContainer()
        let now = Date.now

        try insert([
            DoseEntry(
                substance: "Kratom",
                amount: 1,
                unit: "g",
                route: .oral,
                timestamp: now.addingTimeInterval(-3 * 3_600),
            ),
            DoseEntry(
                substance: "Caffeine",
                amount: 250,
                unit: "mg",
                route: .oral,
                timestamp: now.addingTimeInterval(-90 * 60),
            ),
            DoseEntry(
                substance: "Kratom",
                amount: 2,
                unit: "g",
                route: .oral,
                timestamp: now.addingTimeInterval(-20 * 60),
            ),
        ], into: container)

        ActiveSessionManager.shared.recoverSession(container: container)

        // The reported bug collapsed this to 1 — the oldest dose alone, which is
        // what made the Journal hero fall into its single-dose layout.
        #expect(ActiveSessionManager.shared.activeEntries.count == 3)
        #expect(ActiveSessionManager.shared.hasActiveSession)
        #expect(ActiveSessionManager.shared.activeSubstanceStates.count == 3)
    }

    @Test
    func `A dose older than the previous 12h lookback is still recovered while active`() throws {
        ActiveSessionManager.shared.clearSession()
        let substance = try #require(
            longActingOralSubstance(),
            "bundled DB has no oral substance with a 13–24 h acute curve",
        )
        let container = try makeContainer()

        try insert([
            DoseEntry(
                substance: substance.name,
                amount: 100,
                unit: "mg",
                route: .oral,
                timestamp: Date.now.addingTimeInterval(-13 * 3_600),
            ),
        ], into: container)

        ActiveSessionManager.shared.recoverSession(container: container)

        #expect(ActiveSessionManager.shared.activeEntries.count == 1)
    }

    @Test
    func `Expired doses are dropped, active ones kept`() throws {
        ActiveSessionManager.shared.clearSession()
        let container = try makeContainer()

        try insert([
            // Kratom's acute curve is ~6.5 h — long finished.
            DoseEntry(
                substance: "Kratom",
                amount: 1,
                unit: "g",
                route: .oral,
                timestamp: Date.now.addingTimeInterval(-20 * 3_600),
            ),
            DoseEntry(
                substance: "Caffeine",
                amount: 200,
                unit: "mg",
                route: .oral,
                timestamp: Date.now.addingTimeInterval(-30 * 60),
            ),
        ], into: container)

        ActiveSessionManager.shared.recoverSession(container: container)

        #expect(ActiveSessionManager.shared.activeEntries.count == 1)
        #expect(ActiveSessionManager.shared.activeEntries.first?.snapshot.substance == "Caffeine")
    }

    /// Membership, not expiry: a dose with no acute curve on any route is one
    /// ``ActiveSessionManager/resolveDuration(substance:entry:)`` declined to
    /// model, and admitting it would open an "active session" counting down a
    /// curve the app deliberately refuses to draw. The journal still renders it
    /// (as a marker, or via the half-life tier) — the live session is a narrower
    /// claim than the timeline.
    ///
    /// Note this is *not* the same as "long-acting": Memantine resolves a real
    /// ~18 h acute profile from its winning source and legitimately joins the
    /// session. Only a substance with no duration rows at all is excluded.
    @Test
    func `A dose with no modeled curve never joins the live session`() throws {
        ActiveSessionManager.shared.clearSession()
        let durationless = try #require(SubstanceLibrary.lookupByNameOrAlias("Omega-3 Fatty Acids"))
        #expect(durationless.timelineDuration(for: .oral) == nil)

        let container = try makeContainer()
        try insert([
            DoseEntry(
                substance: durationless.name,
                amount: 2_000,
                unit: "mg",
                route: .oral,
                timestamp: Date.now.addingTimeInterval(-60 * 60),
            ),
            DoseEntry(
                substance: "Caffeine",
                amount: 200,
                unit: "mg",
                route: .oral,
                timestamp: Date.now.addingTimeInterval(-60 * 60),
            ),
        ], into: container)

        ActiveSessionManager.shared.recoverSession(container: container)

        #expect(ActiveSessionManager.shared.activeEntries.count == 1)
        #expect(ActiveSessionManager.shared.activeEntries.first?.snapshot.substance == "Caffeine")
    }

    /// The counterpart to the above, and the reason the `pruneCompleted` doc
    /// distinguishes the two: a long-acting med with a real (if long) acute
    /// profile *is* a live-session member. Memantine at ~18 h was in the
    /// reported session and should have been on the card.
    @Test
    func `A long-acting med with a real acute profile does join the live session`() throws {
        ActiveSessionManager.shared.clearSession()
        let container = try makeContainer()

        try insert([
            DoseEntry(
                substance: "Memantine",
                amount: 20,
                unit: "mg",
                route: .oral,
                timestamp: Date.now.addingTimeInterval(-60 * 60),
            ),
        ], into: container)

        ActiveSessionManager.shared.recoverSession(container: container)

        #expect(ActiveSessionManager.shared.activeEntries.count == 1)
        #expect(ActiveSessionManager.shared.hasActiveSession)
    }

    @Test
    func `Recovery is a no-op once a session is already tracked`() throws {
        ActiveSessionManager.shared.clearSession()
        let container = try makeContainer()

        let entry = DoseEntry(substance: "Caffeine", amount: 200, unit: "mg", route: .oral)
        try insert([entry], into: container)
        ActiveSessionManager.shared.addDose(
            entry: entry,
            substance: SubstanceLibrary.lookupByNameOrAlias("Caffeine"),
            colorHex: PresetColor.defaultHex,
            allColors: [],
        )
        #expect(ActiveSessionManager.shared.activeEntries.count == 1)

        ActiveSessionManager.shared.recoverSession(container: container)

        #expect(ActiveSessionManager.shared.activeEntries.count == 1)
        ActiveSessionManager.shared.clearSession()
    }
}
