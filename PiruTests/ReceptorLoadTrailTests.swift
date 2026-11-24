import Foundation
import Testing
@testable import Piru

/// Receptor Load's trails: every class from one replay preparation, matching the single-class trail
/// sample for sample, closing on `now`, and drawing a dose logged hours ago.
@Suite("Receptor Load trails")
@MainActor
struct ReceptorLoadTrailTests {
    typealias Cal = ToleranceCalibrationTests
    static let now = Cal.now
    static let weightKg = 70.0

    private var params: [String: PharmacologyParameters] {
        [
            "Alprazolam": Cal.alprazolam(referenceDoseMg: 1),
            "Morphine": Cal.morphine(referenceDoseMg: 30),
            "Ketamine": Cal.ketamine(referenceDoseMg: 100),
        ]
    }

    private var doses: [ToleranceStore.SimDose] {
        Cal.dailyDoses("Alprazolam", mg: 1, days: 20, endingHoursBeforeNow: 3, relativeTo: Self.now)
            + Cal.dailyDoses("Morphine", mg: 20, days: 10, endingHoursBeforeNow: 30, relativeTo: Self.now)
            + [ToleranceStore.SimDose(substance: "Ketamine", amountMg: 80, timestamp: Self.now.addingTimeInterval(-5 * 3_600))]
    }

    @Test
    func `Every class's trail matches the single-class trail sample for sample`() throws {
        let classes: Set<ReceptorClasses.ReceptorClass> = [.gaba, .muOpioid, .nmdaAntagonist]
        let past = 7.0 * 24 * 60
        let step = 3.0 * 60
        let trails = ToleranceStore.loadTrails(
            doses: doses, params: params, now: Self.now, weightKg: Self.weightKg,
            classes: classes, stepMinutes: step, pastHorizonMinutes: past,
        )
        #expect(Set(trails.keys) == classes)
        for receptorClass in classes {
            let single = ToleranceStore.loadTrail(
                doses: doses, params: params, now: Self.now, weightKg: Self.weightKg,
                receptorClass: receptorClass, horizonMinutes: 0, stepMinutes: step, pastHorizonMinutes: past,
            )
            let multi = try #require(trails[receptorClass])
            #expect(multi.count == single.count)
            for (lhs, rhs) in zip(multi, single) {
                #expect(lhs.date == rhs.date)
                #expect(lhs.load == rhs.load)
            }
        }
    }

    @Test
    func `A class no dose drives gets no trail`() {
        let trails = ToleranceStore.loadTrails(
            doses: doses, params: params, now: Self.now, weightKg: Self.weightKg,
            classes: [.adenosine, .gaba], stepMinutes: 180, pastHorizonMinutes: 7 * 24 * 60,
        )
        #expect(trails[.adenosine] == nil)
        #expect(trails[.gaba] != nil)
    }

    /// The first-day case: one dose two hours ago. A grid that starts at the dose and steps past now
    /// would hold only the dose's own instant, where nothing is absorbed yet, and read as no load.
    @Test
    func `A dose two hours old closes on now and draws a load`() throws {
        let fresh = [ToleranceStore.SimDose(substance: "Alprazolam", amountMg: 1, timestamp: Self.now.addingTimeInterval(-2 * 3_600))]
        let trails = ToleranceStore.loadTrails(
            doses: fresh, params: params, now: Self.now, weightKg: Self.weightKg,
            classes: [.gaba], stepMinutes: 180, pastHorizonMinutes: 7 * 24 * 60,
        )
        let trail = try #require(trails[.gaba])
        let last = try #require(trail.last)
        #expect(abs(last.date.timeIntervalSince(Self.now)) < 1)
        #expect(last.load > 0.5)
    }

    /// Opening Receptor Load replays the log for the snapshot, then for every class's trail; the
    /// pharmacology behind them is read from the database once.
    @Test
    func `The snapshot and every trail of one log share one pharmacology read`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let now = Date.now
        let entries = [
            DoseEntry(substance: "Caffeine", amount: 100, unit: "mg", route: .oral, timestamp: now.addingTimeInterval(-2 * 3_600)),
            DoseEntry(substance: "Alprazolam", amount: 1, unit: "mg", route: .oral, timestamp: now.addingTimeInterval(-26 * 3_600)),
            DoseEntry(substance: "Ketamine", amount: 50, unit: "mg", route: .insufflation, timestamp: now.addingTimeInterval(-50 * 3_600)),
        ]
        let store = ToleranceStore()
        await store.recompute(from: entries, now: now)
        let classes = Set(store.states.keys)
        #expect(classes.count >= 2)
        let trails = await store.loadTrails(for: classes, from: entries, now: now, pastHorizon: 7 * 86_400, step: 1_800)
        #expect(Set(trails.keys) == classes)
        _ = try await store.loadTrail(for: #require(classes.first), from: entries, now: now)
        #expect(store.parameterReadCount == 1)
    }
}

/// The span In Your Body and Receptor Load draw for a range.
@MainActor
@Suite("ModeledChartWindow")
struct ModeledChartWindowTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func `A log older than the range draws the whole range`() {
        let window = ModeledChartWindow(range: .thirtyDays, firstDose: now.addingTimeInterval(-90 * 86_400), now: now)
        #expect(window.start == now.addingTimeInterval(-30 * 86_400))
        #expect(window.end == now)
    }

    @Test
    func `A log two hours old starts half an hour before its first dose`() {
        let window = ModeledChartWindow(range: .thirtyDays, firstDose: now.addingTimeInterval(-2 * 3_600), now: now)
        #expect(window.length == 2.5 * 3_600)
        #expect(window.length < ModeledChartWindow.hourAxisLimit)
    }

    @Test
    func `A log ten days old in a thirty-day range starts a day before its first dose`() {
        let window = ModeledChartWindow(range: .thirtyDays, firstDose: now.addingTimeInterval(-10 * 86_400), now: now)
        #expect(window.length == 11 * 86_400)
    }

    @Test
    func `Receptor Load samples a week finely enough to keep a session's shape`() {
        let week = ModeledChartWindow(range: .sevenDays, firstDose: now.addingTimeInterval(-30 * 86_400), now: now)
        #expect(week.receptorLoadStep == 30 * 60)
        let month = ModeledChartWindow(range: .thirtyDays, firstDose: now.addingTimeInterval(-90 * 86_400), now: now)
        #expect(month.receptorLoadStep == 3 * 3_600)
    }
}
