import Foundation
import Testing
@testable import Piru

/// The tolerance curves assume nothing more is logged, which is wrong for a scheduled medication taken
/// every morning: that curve does not decay to baseline, it settles. The projection replays a My Meds
/// item's future doses forward across the chart window and draws that as the main curve, keeping the
/// no-further-doses decay as a secondary line.
@MainActor
@Suite("Tolerance — scheduled-med projection")
struct ToleranceScheduledProjectionTests {
    typealias Cal = ToleranceCalibrationTests
    static let now = Cal.now
    static let weightKg = 70.0
    static let horizon = ToleranceStore.projectionHorizonMinutes

    private static func stimulantParams() -> [String: PharmacologyParameters] {
        ["Stim": Cal.stimulant(referenceDoseMg: 60)]
    }

    private static func med(frequency: DoseFrequency, startDaysAgo: Double = 160) -> ToleranceStore.ScheduledMedSnapshot {
        .init(
            substance: "Stim", doseMg: 20, startDate: now.addingTimeInterval(-startDaysAgo * 86_400),
            frequency: frequency, frequencyDays: [], intervalDays: 2, reminderTimesMinutes: [9 * 60],
        )
    }

    // MARK: - 1. A daily med settles rather than decaying

    @Test
    func `A daily scheduled med settles well above where the no-dose curve decays`() throws {
        let params = Self.stimulantParams()
        let past = Cal.dailyDoses("Stim", mg: 20, days: 120, relativeTo: Self.now)
        let future = ToleranceStore.futureDoses([Self.med(frequency: .daily)], from: Self.now, horizonMinutes: Self.horizon)

        let projection = try #require(
            ToleranceStore.projection(past: past, future: future, params: params, now: Self.now, weightKg: Self.weightKg)[.catecholamineStimulant],
        )
        let projectedEnd = try #require(projection.points.last).percent

        let snapshot = try #require(ToleranceStore.simulate(doses: past, params: params, now: Self.now, weightKg: Self.weightKg)[.catecholamineStimulant])
        let decayRow = ToleranceRow(snapshot: snapshot, params: ReceptorClasses.parameters(for: .catecholamineStimulant))
        let decayEnd = decayRow.tolerancePercent(afterMinutes: Self.horizon)

        #expect(decayEnd < ToleranceRow.nearBaselineSeverity * 100 + 3, "with no further doses the curve is near baseline by the horizon")
        #expect(projectedEnd > decayEnd + 10, "the schedule keeps tolerance up; it does not fall to baseline")
        #expect(projection.settlesPercent != nil, "an established daily med reaches a steady level inside the window")
    }

    // MARK: - 2. An as-needed med does not project

    @Test
    func `An as-needed item yields no schedule to project`() {
        let asNeeded = DailyDoseItem(substance: "Stim", amount: 20, unit: "mg", isAsNeeded: true)
        #expect(ToleranceStore.scheduledMed(from: asNeeded) == nil)

        let nonMass = DailyDoseItem(substance: "Vitamin D", amount: 2_000, unit: "IU")
        #expect(ToleranceStore.scheduledMed(from: nonMass) == nil, "a unit that is not a mass can't drive an occupancy curve")

        let scheduled = DailyDoseItem(substance: "Stim", amount: 20, unit: "mg")
        #expect(ToleranceStore.scheduledMed(from: scheduled) != nil)
    }

    @Test
    func `No scheduled contributor means no projection`() {
        let params = Self.stimulantParams()
        let past = Cal.dailyDoses("Stim", mg: 20, days: 120, relativeTo: Self.now)
        let projection = ToleranceStore.projection(past: past, future: [], params: params, now: Self.now, weightKg: Self.weightKg)
        #expect(projection.isEmpty)
    }

    // MARK: - 3. Every-other-day projects on the right days

    @Test
    func `An every-other-day med falls on alternating days and a daily one twice as often`() {
        let window = 14.0 * 1_440
        let start = Self.now.addingTimeInterval(-10 * 86_400)
        let everyOther = ToleranceStore.ScheduledMedSnapshot(
            substance: "X", doseMg: 10, startDate: start, frequency: .everyOtherDay,
            frequencyDays: [], intervalDays: 2, reminderTimesMinutes: [12 * 60],
        )
        let future = ToleranceStore.futureDoses([everyOther], from: Self.now, horizonMinutes: window)
        #expect(!future.isEmpty)

        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        for dose in future {
            let days = calendar.dateComponents([.day], from: startDay, to: calendar.startOfDay(for: dose.timestamp)).day ?? 0
            #expect(days % 2 == 0, "an every-other-day dose landed on an odd offset from the start date")
        }

        var daily = everyOther
        daily = ToleranceStore.ScheduledMedSnapshot(
            substance: "X", doseMg: 10, startDate: start, frequency: .daily,
            frequencyDays: [], intervalDays: 2, reminderTimesMinutes: [12 * 60],
        )
        let dailyFuture = ToleranceStore.futureDoses([daily], from: Self.now, horizonMinutes: window)
        #expect(dailyFuture.count > future.count)
    }

    // MARK: - 4. The projection ends at the window's end

    @Test
    func `No projected dose lands after the window, and the curve reaches it`() throws {
        let window = 7.0 * 1_440
        let future = ToleranceStore.futureDoses([Self.med(frequency: .daily)], from: Self.now, horizonMinutes: window)
        #expect(!future.isEmpty)
        let end = Self.now.addingTimeInterval(window * 60)
        #expect(future.allSatisfy { $0.timestamp > Self.now && $0.timestamp <= end })

        let params = Self.stimulantParams()
        let past = Cal.dailyDoses("Stim", mg: 20, days: 60, relativeTo: Self.now)
        let full = ToleranceStore.futureDoses([Self.med(frequency: .daily)], from: Self.now, horizonMinutes: Self.horizon)
        let projection = try #require(
            ToleranceStore.projection(past: past, future: full, params: params, now: Self.now, weightKg: Self.weightKg)[.catecholamineStimulant],
        )
        let lastMinutes = try #require(projection.points.last).minutesFromNow
        #expect(lastMinutes <= Self.horizon + ToleranceStore.defaultTimestepMinutes)
        #expect(lastMinutes > Self.horizon - 2 * 1_440, "the projection reaches the end of its horizon")
    }

    // MARK: - 5. Editing the schedule changes the result

    @Test
    func `A daily schedule settles higher than every-other-day`() throws {
        let params = Self.stimulantParams()
        let past = Cal.dailyDoses("Stim", mg: 20, days: 120, relativeTo: Self.now)
        let daily = ToleranceStore.futureDoses([Self.med(frequency: .daily)], from: Self.now, horizonMinutes: Self.horizon)
        let everyOther = ToleranceStore.futureDoses([Self.med(frequency: .everyOtherDay)], from: Self.now, horizonMinutes: Self.horizon)

        let dailyEnd = try #require(ToleranceStore.projection(past: past, future: daily, params: params, now: Self.now, weightKg: Self.weightKg)[.catecholamineStimulant]?.points.last).percent
        let everyOtherEnd = try #require(ToleranceStore.projection(past: past, future: everyOther, params: params, now: Self.now, weightKg: Self.weightKg)[.catecholamineStimulant]?.points.last).percent
        #expect(dailyEnd > everyOtherEnd + 1, "halving the schedule must lower where the curve settles")
    }

    // MARK: - 6. Settled means steady over several cycles

    private static let step = ToleranceStore.defaultTimestepMinutes
    private static let stepCount = Int(horizon / step)

    /// Levels every step across the horizon from `level(minutes)`.
    private static func levels(_ level: (Double) -> Double) -> [Double] {
        (0 ... stepCount).map { level(Double($0) * step) }
    }

    /// A daily ripple of ±`amplitude` points, its peak `phaseMinutes` after midnight of day 0.
    private static func ripple(_ minutes: Double, amplitude: Double = 4, phaseMinutes: Double = 0) -> Double {
        amplitude * cos(2 * .pi * (minutes - phaseMinutes) / 1_440)
    }

    @Test
    func `A curve rising steadily to the end of the window is still rising`() {
        let rising = Self.levels { 80 * $0 / Self.horizon }
        #expect(ToleranceStore.projectionOutcome(levels: rising, stepMinutes: Self.step, cycleMinutes: 1_440) == .rising)

        let slowRise = Self.levels { 40 + 6 * $0 / Self.horizon + Self.ripple($0) }
        #expect(
            ToleranceStore.projectionOutcome(levels: slowRise, stepMinutes: Self.step, cycleMinutes: 1_440) == .rising,
            "six points over eight weeks still climbs ~3 points a month",
        )
    }

    @Test
    func `A curve coming down to the end of the window is still falling`() {
        let falling = Self.levels { 60 - 20 * $0 / Self.horizon + Self.ripple($0) }
        #expect(ToleranceStore.projectionOutcome(levels: falling, stepMinutes: Self.step, cycleMinutes: 1_440) == .falling)

        let slowDecay = Self.levels { 30 + 30 * exp(-$0 / (40 * 1_440)) }
        #expect(ToleranceStore.projectionOutcome(levels: slowDecay, stepMinutes: Self.step, cycleMinutes: 1_440) == .falling)
    }

    @Test
    func `A rippling curve that levels off settles at its mean, whatever the ripple's phase`() {
        var settled: [Double] = []
        for phase in stride(from: 0.0, to: 1_440, by: 180) {
            let curve = Self.levels { 40 - 25 * exp(-$0 / (4 * 1_440)) + Self.ripple($0, phaseMinutes: phase) }
            let outcome = ToleranceStore.projectionOutcome(levels: curve, stepMinutes: Self.step, cycleMinutes: 1_440)
            guard case let .settles(percent, minutes) = outcome else {
                Issue.record("phase \(phase): expected a settled curve, got \(outcome)")
                continue
            }
            #expect(minutes > 5 * 1_440 && minutes < 25 * 1_440, "settles once the approach is within the band")
            settled.append(percent)
        }
        #expect(settled.allSatisfy { $0 == 40 }, "the settle level is the cycle mean at every phase: \(settled)")
    }

    @Test
    func `A weekly schedule needs three steady weeks, not three steady days`() {
        // Steady for the last ten days only: enough for a daily schedule, short of three weekly cycles.
        let curve = Self.levels { $0 < 46 * 1_440 ? 10 + 30 * $0 / (46 * 1_440) : 40 }
        let daily = ToleranceStore.projectionOutcome(levels: curve, stepMinutes: Self.step, cycleMinutes: 1_440)
        #expect(ToleranceStore.ToleranceProjection(points: [], outcome: daily).settlesPercent == 40)
        #expect(ToleranceStore.projectionOutcome(levels: curve, stepMinutes: Self.step, cycleMinutes: 7 * 1_440) == .rising)
    }

    @Test
    func `The settle level does not move with the hour the projection starts`() throws {
        let params = Self.stimulantParams()
        var settled: [Double] = []
        for hours in [0.0, 3, 8, 13, 19] {
            let now = Self.now.addingTimeInterval(hours * 3_600)
            let past = Cal.dailyDoses("Stim", mg: 20, days: 120, endingHoursBeforeNow: 1 + hours, relativeTo: now)
            let future = ToleranceStore.futureDoses([Self.med(frequency: .daily)], from: now, horizonMinutes: Self.horizon)
            let projection = try #require(
                ToleranceStore.projection(past: past, future: future, params: params, now: now, weightKg: Self.weightKg)[.catecholamineStimulant],
            )
            try settled.append(#require(projection.settlesPercent, "opened \(hours) h later, the curve did not settle"))
        }
        let spread = (settled.max() ?? 0) - (settled.min() ?? 0)
        #expect(spread <= 1, "settle levels by opening hour: \(settled)")
    }

    // MARK: - 7. Schedule enumeration

    @Test
    func `A slot a dose logged today already satisfies is not dosed again`() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Self.now)
        let eight = today.addingTimeInterval(8 * 3_600)
        let med = ToleranceStore.ScheduledMedSnapshot(
            substance: "Stim", doseMg: 20, startDate: today.addingTimeInterval(-30 * 86_400), frequency: .daily,
            frequencyDays: [], intervalDays: 2, reminderTimesMinutes: [9 * 60, 21 * 60],
            takenTodaySlots: ToleranceStore.takenSlots([9 * 60, 21 * 60], doses: [(minutes: 7 * 60 + 30, slot: nil)]),
        )
        #expect(med.takenTodaySlots == [9 * 60], "a 07:30 dose claims the nearest slot, 09:00")

        let future = ToleranceStore.futureDoses([med], from: eight, horizonMinutes: 2 * 1_440)
        let first = try #require(future.map(\.timestamp).min())
        #expect(first == today.addingTimeInterval(21 * 3_600), "today's 09:00 dose was logged at 07:30; the next is 21:00")
    }

    @Test
    func `A dose checked off for a slot claims that slot`() {
        let slots = [8 * 60, 20 * 60]
        #expect(ToleranceStore.takenSlots(slots, doses: [(minutes: 15 * 60, slot: 8 * 60)]) == [8 * 60])
        #expect(ToleranceStore.takenSlots(slots, doses: [(minutes: 15 * 60, slot: nil)]) == [20 * 60])
        #expect(ToleranceStore.takenSlots(slots, doses: [(minutes: 9 * 60, slot: nil), (minutes: 10 * 60, slot: nil)]) == Set(slots))
        #expect(ToleranceStore.takenSlots(slots, doses: []).isEmpty)
    }

    @Test
    func `An undated every-other-day med counts its days from its first logged dose`() throws {
        let calendar = Calendar.current
        let now = try #require(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: .now))
        let today = calendar.startOfDay(for: now)
        let distantStart = calendar.startOfDay(for: .distantPast)
        // A first dose on a day an odd number of days after `distantPast`, so counting from year 1 lands
        // on the other phase.
        var firstDay = try #require(calendar.date(byAdding: .day, value: -5, to: today))
        if (calendar.dateComponents([.day], from: distantStart, to: firstDay).day ?? 0).isMultiple(of: 2) {
            firstDay = try #require(calendar.date(byAdding: .day, value: -1, to: firstDay))
        }
        let item = DailyDoseItem(substance: "Stim", amount: 20, unit: "mg", frequency: .everyOtherDay, reminderTimesMinutes: [9 * 60])
        let entry = DoseEntry(substance: "Stim", amount: 20, timestamp: firstDay.addingTimeInterval(9 * 3_600))

        let meds = ToleranceStore.scheduledMeds(from: [item], entries: [entry], now: now)
        let med = try #require(meds.first)
        #expect(calendar.startOfDay(for: med.startDate) == firstDay)

        let future = ToleranceStore.futureDoses(meds, from: now, horizonMinutes: 14 * 1_440)
        #expect(!future.isEmpty)
        for dose in future {
            let days = calendar.dateComponents([.day], from: firstDay, to: calendar.startOfDay(for: dose.timestamp)).day ?? 0
            #expect(days.isMultiple(of: 2), "a dose fell on an odd day after the first logged one")
        }
    }

    @Test
    func `Two identical items do not cancel out of the schedule signature`() {
        let a = Self.med(frequency: .daily)
        let b = Self.med(frequency: .everyOtherDay)
        #expect(ToleranceStore.scheduleSignature([a, a]) != ToleranceStore.scheduleSignature([b, b]))
        #expect(ToleranceStore.scheduleSignature([a, b]) == ToleranceStore.scheduleSignature([b, a]))
    }

    // MARK: - 8. The store projects from seeds of the same log

    @Test
    func `A scheduled med logged after the By-substance replay gets its own projection`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let noon = try #require(Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now))
        let stimulant = DailyDoseItem(substance: "Methylphenidate", amount: 20, unit: "mg", startDate: noon.addingTimeInterval(-60 * 86_400))
        let benzo = DailyDoseItem(substance: "Clonazepam", amount: 1, unit: "mg", startDate: noon.addingTimeInterval(-60 * 86_400))
        let meds = [stimulant, benzo].compactMap { ToleranceStore.scheduledMed(from: $0) }
        let before = (1 ... 30).map {
            DoseEntry(substance: "Methylphenidate", amount: 20, timestamp: noon.addingTimeInterval(-Double($0) * 86_400 - 3 * 3_600))
        }
        let after = before + (1 ... 10).map {
            DoseEntry(substance: "Clonazepam", amount: 1, timestamp: noon.addingTimeInterval(-Double($0) * 86_400 - 2 * 3_600))
        }

        let store = ToleranceStore()
        // The By-substance view is opened on the first log.
        await store.recompute(from: before, now: noon)
        await store.recomputePerSubstance(from: before, now: noon)
        await store.recomputeProjections(from: before, scheduledMeds: meds, now: noon)
        #expect(store.perSubstanceProjections["Methylphenidate"] != nil)
        #expect(store.perSubstanceProjections["Clonazepam"] == nil, "not logged yet, so it has no alone snapshot")

        // The log changes; the mechanism task projects before the By-substance replay has caught up.
        await store.recompute(from: after, now: noon)
        await store.recomputeProjections(from: after, scheduledMeds: meds, now: noon)
        await store.recomputePerSubstance(from: after, now: noon)
        await store.recomputeProjections(from: after, scheduledMeds: meds, now: noon)
        #expect(store.perSubstanceProjections["Clonazepam"] != nil, "the By-substance projection was left on the previous log")
    }

    @Test
    func `Projecting before the joint replay of the same log leaves the projection to the call after it`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let noon = try #require(Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now))
        let item = DailyDoseItem(substance: "Methylphenidate", amount: 20, unit: "mg", startDate: noon.addingTimeInterval(-60 * 86_400))
        let meds = [item].compactMap { ToleranceStore.scheduledMed(from: $0) }
        let entries = (1 ... 30).map {
            DoseEntry(substance: "Methylphenidate", amount: 20, timestamp: noon.addingTimeInterval(-Double($0) * 86_400 - 3 * 3_600))
        }

        let store = ToleranceStore()
        await store.recomputeProjections(from: entries, scheduledMeds: meds, now: noon)
        #expect(store.projections.isEmpty, "nothing to seed from yet")
        await store.recompute(from: entries, now: noon)
        await store.recomputeProjections(from: entries, scheduledMeds: meds, now: noon)
        #expect(!store.projections.isEmpty)
    }

    // MARK: - 9. One pharmacology read per log

    @Test
    func `The projection of a logged med reads no pharmacology beyond its replay's`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let noon = try #require(Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now))
        let item = DailyDoseItem(substance: "Methylphenidate", amount: 20, unit: "mg", startDate: noon.addingTimeInterval(-60 * 86_400))
        let meds = [item].compactMap { ToleranceStore.scheduledMed(from: $0) }
        let entries = (1 ... 30).map {
            DoseEntry(substance: "Methylphenidate", amount: 20, timestamp: noon.addingTimeInterval(-Double($0) * 86_400 - 3 * 3_600))
        }

        let store = ToleranceStore()
        await store.recompute(from: entries, now: noon)
        await store.recomputeProjections(from: entries, scheduledMeds: meds, now: noon)
        #expect(!store.projections.isEmpty)
        #expect(store.parameterReadCount == 1)
    }

    @Test
    func `A projection of a med not yet logged reads it`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let noon = try #require(Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now))
        let item = DailyDoseItem(substance: "Clonazepam", amount: 1, unit: "mg", startDate: noon.addingTimeInterval(-60 * 86_400))
        let meds = [item].compactMap { ToleranceStore.scheduledMed(from: $0) }
        let entries = (1 ... 30).map {
            DoseEntry(substance: "Methylphenidate", amount: 20, timestamp: noon.addingTimeInterval(-Double($0) * 86_400 - 3 * 3_600))
        }

        let store = ToleranceStore()
        await store.recompute(from: entries, now: noon)
        await store.recomputeProjections(from: entries, scheduledMeds: meds, now: noon)
        #expect(store.parameterReadCount == 2)
    }

    @Test
    func `Replays of one log started together share one pharmacology read`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let noon = try #require(Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now))
        let entries = (1 ... 30).map {
            DoseEntry(substance: "Methylphenidate", amount: 20, timestamp: noon.addingTimeInterval(-Double($0) * 86_400 - 3 * 3_600))
        }

        let store = ToleranceStore()
        let replay = Task { await store.recompute(from: entries, now: noon) }
        let trail = Task { await store.loadTrail(for: .catecholamineStimulant, from: entries, now: noon) }
        await replay.value
        _ = await trail.value
        #expect(store.parameterReadCount == 1)
    }
}
