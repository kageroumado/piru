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
}
