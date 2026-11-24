import Foundation
import SwiftData
import Testing
@testable import Piru

/// A substance's "alone" reading in the By-substance view is a *part* of the class it belongs to, so it
/// must never read above the whole (the diazepam-28%-over-GABA-24% bug). The fix puts each alone
/// snapshot on its class's shared gauge — the class reference occupancy, with each ln-shift layer capped
/// at the class's own — so the part sits at or below the whole at `now`, everywhere along the recovery
/// curve, and in its near-baseline date.
@MainActor
@Suite("Tolerance — a substance alone never exceeds its class")
struct TolerancePerSubstanceInvariantTests {
    typealias Cal = ToleranceCalibrationTests
    static let now = Cal.now
    static let weightKg = 70.0

    /// Sample offsets (minutes from now) across the chart window — now, and each round tick to 8 weeks.
    static let tickMinutes: [Double] = [0, 360, 1_440, 3 * 1_440, 7 * 1_440, 14 * 1_440, 28 * 1_440, 56 * 1_440]

    /// The engine's per-substance rescaling, reproduced: the alone replay put onto the joint class gauge.
    private func rescaledAlone(
        sub: [ToleranceStore.SimDose], all: [ToleranceStore.SimDose], params: [String: PharmacologyParameters],
        now: Date,
    ) -> (alone: [ReceptorClasses.ReceptorClass: ClassTolerance], joint: [ReceptorClasses.ReceptorClass: ClassTolerance]) {
        let joint = ToleranceStore.simulate(doses: all, params: params, now: now, weightKg: Self.weightKg)
        let alone = ToleranceStore.simulate(doses: sub, params: params, now: now, weightKg: Self.weightKg)
        return (alone.mapValues { joint[$0.receptorClass].map($0.rescaledToClass) ?? $0 }, joint)
    }

    private func expectPartLeqWhole(
        aloneCT: ClassTolerance, jointCT: ClassTolerance, label: String,
    ) {
        let eps = 0.02
        let aloneRow = ToleranceRow(snapshot: aloneCT, params: ReceptorClasses.parameters(for: aloneCT.receptorClass))
        let jointRow = ToleranceRow(snapshot: jointCT, params: ReceptorClasses.parameters(for: jointCT.receptorClass))
        #expect(aloneCT.severity <= jointCT.severity + eps / 100, "\(label): alone severity > class at now")
        for minutes in Self.tickMinutes {
            let alone = aloneRow.tolerancePercent(afterMinutes: minutes)
            let whole = jointRow.tolerancePercent(afterMinutes: minutes)
            #expect(alone <= whole + eps, "\(label): alone \(alone)% > class \(whole)% at \(minutes) min")
        }
        if let wholeNB = jointRow.minutesToNearBaseline {
            let aloneNB = aloneRow.minutesToNearBaseline
            #expect(aloneNB != nil, "\(label): class reaches near baseline but alone never does")
            if let aloneNB { #expect(aloneNB <= wholeNB + 60, "\(label): alone near-baseline date is after the class's") }
        }
    }

    @Test
    func `Diazepam alone never reads above the GABA class it shares with alprazolam`() throws {
        let params = ["Diazepam": Cal.diazepam(referenceDoseMg: 30), "Alprazolam": Cal.alprazolam(referenceDoseMg: 1)]
        let diazepam = Cal.dailyDoses("Diazepam", mg: 10, days: 20)
        let alprazolam = Cal.dailyDoses("Alprazolam", mg: 1, days: 6, endingHoursBeforeNow: 5 * 24)
        let all = diazepam + alprazolam

        for (name, doses) in [("Diazepam", diazepam), ("Alprazolam", alprazolam)] {
            let (alone, joint) = rescaledAlone(sub: doses, all: all, params: params, now: Self.now)
            for (cls, aloneCT) in alone {
                let jointCT = try #require(joint[cls])
                expectPartLeqWhole(aloneCT: aloneCT, jointCT: jointCT, label: name)
            }
        }
    }

    @Test
    func `A scheduled full agonist's projection never reads above its class's`() async throws {
        let params = [
            "Full": Cal.opioid(referenceDoseMg: 30),
            "Partial": Cal.opioid(referenceDoseMg: 30, intrinsicEfficacy: 0.3),
        ]
        let past = Cal.dailyDoses("Full", mg: 10, days: 30) + Cal.dailyDoses("Partial", mg: 20, days: 30, endingHoursBeforeNow: 7)
        let med = ToleranceStore.ScheduledMedSnapshot(
            substance: "Full", doseMg: 10, startDate: Self.now.addingTimeInterval(-60 * 86_400), frequency: .daily,
            frequencyDays: [], intervalDays: 2, reminderTimesMinutes: [9 * 60],
        )
        let future = ToleranceStore.futureDoses([med], from: Self.now, horizonMinutes: ToleranceStore.projectionHorizonMinutes)

        let projected = await ToleranceStore.projections(
            past: past, future: future, params: params, now: Self.now, weightKg: Self.weightKg,
        )
        let whole = try #require(projected.joint[.muOpioid])
        let part = try #require(projected.perSubstance["Full"]?[.muOpioid])
        #expect(part.points.count == whole.points.count)
        for (alone, joint) in zip(part.points, whole.points) {
            #expect(alone.minutesFromNow == joint.minutesFromNow)
            #expect(alone.percent <= joint.percent, "alone \(alone.percent)% > class \(joint.percent)% at \(alone.minutesFromNow) min")
        }
        if let alone = part.settlesPercent, let joint = whole.settlesPercent {
            #expect(alone <= joint)
        }
    }

    @Test
    func `Over the heavyLogging journal, no substance alone exceeds its class`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let container = try ModelContainer(
            for: Schema(PiruSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        let context = container.mainContext
        let noon = try #require(Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now))
        DemoData.seedHeavyLogging(context: context, now: noon)
        try context.save()
        let entries = try context.fetch(FetchDescriptor<DoseEntry>())

        let store = ToleranceStore()
        store.configure(container: container)
        await store.recompute(from: entries, now: noon)
        await store.recomputePerSubstance(from: entries, now: noon)
        #expect(!store.perSubstanceStates.isEmpty, "the per-substance replay produced nothing to check")

        for (name, aloneStates) in store.perSubstanceStates {
            for (cls, aloneCT) in aloneStates {
                let jointCT = try #require(store.states[cls], "\(name) drives \(cls) but it is absent from the joint snapshot")
                expectPartLeqWhole(aloneCT: aloneCT, jointCT: jointCT, label: "\(name)/\(cls)")
            }
        }
    }
}
