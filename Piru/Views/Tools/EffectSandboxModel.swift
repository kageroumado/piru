import SwiftUI

/// Which substances the estimator is allowed to offer. The engine is calibrated
/// on five stimulants and can only *simulate* a curated handful beyond them;
/// offering the full 1100-substance library invites picking something that draws
/// a dose marker and no curve, which reads as a broken tool rather than an
/// unmodelable substance.
@MainActor
enum SandboxModelability {
    /// Both lists cost a `resolveFull` + pharmacology resolve per candidate and
    /// are read per keystroke by the picker's `searchable` filter, so they are
    /// cached, keyed on the source order every resolved value derives from.
    private static var cache: (order: [String], anchors: [Substance], adjuncts: [Substance])?

    private static func lists() -> (anchors: [Substance], adjuncts: [Substance]) {
        let order = SubstanceStore.shared.enabledSourceOrder
        if let cache, cache.order == order { return (cache.anchors, cache.adjuncts) }
        let anchors = resolve(SubstanceModelDatabase.calibratedTriggerSet.sorted()) {
            SubstanceModelDatabase.canAnchor(name: $0.name, pharmacology: pharmacology(for: $0))
        }
        let adjuncts = resolve(SubstanceModelDatabase.modelableCandidateNames) {
            !SubstanceModelDatabase.canAnchor(name: $0.name, pharmacology: pharmacology(for: $0))
                && SubstanceModelDatabase.canParticipate(name: $0.name, pharmacology: pharmacology(for: $0))
        }
        cache = (order, anchors, adjuncts)
        return (anchors, adjuncts)
    }

    /// Substances that can anchor a plan by themselves.
    static var anchors: [Substance] {
        lists().anchors
    }

    /// Substances the engine can simulate only alongside an anchor — they shape
    /// the curves but can't produce one on their own.
    static var adjuncts: [Substance] {
        lists().adjuncts
    }

    private static func pharmacology(for substance: Substance) -> PharmacologyParameters? {
        SubstanceStore.shared.pharmacologyParameters(forSubstanceName: substance.name)
    }

    /// Resolve canonical names through the library, drop anything that fails the
    /// test, and de-duplicate (several names alias onto one substance).
    private static func resolve(_ names: [String], keeping isIncluded: (Substance) -> Bool) -> [Substance] {
        var seen = Set<String>()
        return names.compactMap { SubstanceLibrary.resolveFull($0) }
            .filter { seen.insert($0.name).inserted }
            .filter(isIncluded)
            .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
    }
}

/// A set of doses modeled **together**, drawn as one curve. Two plans is the
/// comparison unit the tool needs: the doses inside a plan sum (a stack, a
/// redose schedule), and the plans themselves are held apart. "3 × 20 mg an hour
/// apart" versus "1 × 60 mg" is exactly two plans; so is "my amphetamine" versus
/// "my methylphenidate".
enum SandboxPlan: String, CaseIterable, Identifiable, Hashable {
    case a
    case b

    var id: String {
        rawValue
    }

    var label: LocalizedStringResource {
        switch self {
        case .a: "Plan A"
        case .b: "Plan B"
        }
    }

    var colorHex: String {
        switch self {
        case .a: "ED5787"
        case .b: "4C93E0"
        }
    }

    var color: Color {
        Color(hex: colorHex)
    }
}

/// A standalone "what-if" surface over the shipped effect engine: punch in
/// hypothetical doses (any substances, amounts, routes, relative timings) and see
/// the same Feeling / Energy / Compulsion / Strain curves a logged session draws —
/// **without touching the journal**. The engine (`MechanisticSessionModel.compute`)
/// already takes arbitrary `[DoseInput]`; this is the missing input surface.
/// See `Specs/effect-estimate-sandbox.md`.
@Observable
@MainActor
final class EffectSandboxModel {
    /// One hypothetical dose row.
    struct Row: Identifiable, Equatable {
        let id = UUID()
        var searchText = ""
        /// The resolved library substance; `nil` until one is picked.
        var substance: Substance?
        var amount: Double = 0
        var unit = "mg"
        var route: RouteOfAdministration = .oral
        /// Offset from t = 0 in hours — what makes redose/stagger scenarios expressible.
        var hours: Double = 0
        var plan: SandboxPlan = .a

        var displayName: String {
            substance?.displayTitle ?? ""
        }

        /// Color follows the *plan*, never the row. A per-row color would promise
        /// a per-row curve, and doses inside a plan are summed into one.
        var colorHex: String {
            plan.colorHex
        }
    }

    /// One plan's simulation, ready to draw.
    struct PlanResult: Identifiable {
        let plan: SandboxPlan
        let result: MechanisticSessionModel.Result
        var id: SandboxPlan {
            plan
        }
    }

    var rows: [Row] = []
    private(set) var planResults: [PlanResult] = []
    /// Whether any plan produced a curve (the engine could anchor on something).
    private(set) var supported = false
    /// Whether any row has a resolved substance + positive amount (something to model).
    private(set) var hasInput = false

    /// A synthetic, stable anchor — the sandbox is relative-time, so the absolute
    /// value only sets the chart's clock labels, which the estimator hides.
    let startDate = Date()

    private var task: Task<Void, Never>?

    /// Plans that hold at least one row, in A-then-B order.
    var activePlans: [SandboxPlan] {
        SandboxPlan.allCases.filter { plan in rows.contains { $0.plan == plan } }
    }

    /// `true` once a second plan exists — the point at which the panel grows plan
    /// headers and the charts start drawing one line per plan.
    var isComparing: Bool {
        activePlans.count > 1
    }

    func rows(in plan: SandboxPlan) -> [Row] {
        rows.filter { $0.plan == plan }
    }

    /// The widest simulation, supplying the shared time extent to every chart.
    var primaryResult: MechanisticSessionModel.Result? {
        planResults.map(\.result).max { $0.contentSpan < $1.contentSpan }
    }

    /// The union of active lenses across all plans — a lens appears if *any*
    /// plan's simulation produces meaningful signal on that channel.
    var activeLenses: [EffectLens] {
        var seen = Set<EffectLens>()
        for pr in planResults {
            seen.formUnion(pr.result.activeLenses)
        }
        guard !seen.isEmpty else { return EffectLens.mechanisticBase }
        return EffectLens.allCases.filter { seen.contains($0) && $0 != .timeline }
    }

    /// Curves for the chart, colored by plan. Empty when only one plan is active —
    /// a lone plan keeps the richer single-curve rendering (gradient fill, crash red).
    var comparisonSeries: [MechanisticComparisonSeries] {
        guard planResults.count > 1 else { return [] }
        return planResults.map {
            MechanisticComparisonSeries(id: $0.plan.rawValue, timeline: $0.result.timeline, color: $0.plan.color)
        }
    }

    /// The union of every plan's axis for a lens. Drawing plans against their own
    /// ranges would let two different doses render identically.
    func mergedRange(for lens: EffectLens) -> MechanisticSessionModel.AxisRange? {
        let ranges = planResults.compactMap { $0.result.ranges[lens.rawValue] }
        guard let first = ranges.first else { return nil }
        return ranges.dropFirst().reduce(first) {
            .init(hi: max($0.hi, $1.hi), lo: min($0.lo, $1.lo))
        }
    }

    /// A signature the view observes to trigger a debounced recompute on any edit.
    var signature: Int {
        var hasher = Hasher()
        for row in rows {
            hasher.combine(row.substance?.name)
            hasher.combine(row.amount)
            hasher.combine(row.route)
            hasher.combine(row.hours)
            hasher.combine(row.plan)
        }
        return hasher.finalize()
    }

    /// Dose marks for rows that actually made it into a curve. A row whose plan
    /// failed to model must not leave a marker behind — a dot with no curve reads
    /// as a broken chart rather than an unmodelable substance.
    var doseMarks: [MechanisticSessionModel.DoseMark] {
        let drawn = Set(planResults.map(\.plan))
        return rows.compactMap { row in
            guard row.substance != nil, row.amount > 0, drawn.contains(row.plan) else { return nil }
            return MechanisticSessionModel.DoseMark(hours: row.hours, colorHex: row.colorHex)
        }
    }

    /// Plans holding rows that produced no curve, so the UI can say which and why
    /// instead of silently dropping them.
    var unmodelablePlans: [SandboxPlan] {
        let drawn = Set(planResults.map(\.plan))
        return activePlans.filter { plan in
            !drawn.contains(plan) && rows(in: plan).contains { $0.substance != nil && $0.amount > 0 }
        }
    }

    func addRow(
        substance: Substance? = nil, amount: Double = 0, route: RouteOfAdministration = .oral,
        hours: Double = 0, plan: SandboxPlan = .a,
    ) {
        var seeded = amount
        if seeded <= 0, let substance {
            seeded = StagedDose.lookupReferenceDose(substance: substance, route: route, unit: substance.defaultUnit) ?? 0
        }
        rows.append(Row(
            searchText: substance?.displayTitle ?? "",
            substance: substance, amount: seeded, unit: substance?.defaultUnit ?? "mg",
            route: route, hours: hours, plan: plan,
        ))
    }

    func setPlan(_ plan: SandboxPlan, forRow id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].plan = plan
    }

    /// Point an existing row at a newly-picked substance, seeding a reference dose
    /// when the row had none.
    func setSubstance(_ substance: Substance, forRow id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].substance = substance
        rows[index].searchText = substance.displayTitle
        rows[index].route = substance.defaultRoute
        rows[index].unit = substance.unit(for: substance.defaultRoute)
        rows[index].amount = StagedDose.lookupReferenceDose(
            substance: substance, route: rows[index].route, unit: rows[index].unit,
        ) ?? rows[index].amount
    }

    /// Switch a row's route, following the route's unit and re-seeding the amount
    /// so the slider never lands outside the new route's ladder (10 mg oral and
    /// 10 mg insufflated are not the same dose).
    func setRoute(_ route: RouteOfAdministration, forRow id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let previous = rows[index].route
        guard previous != route else { return }
        rows[index].route = route
        guard let substance = rows[index].substance else { return }
        let unit = substance.unit(for: route)
        rows[index].unit = unit
        if let reference = StagedDose.lookupReferenceDose(substance: substance, route: route, unit: unit) {
            rows[index].amount = reference
        }
    }

    func removeRow(_ id: UUID) {
        rows.removeAll { $0.id == id }
    }

    /// Set once Clear is used, so re-entering the screen doesn't helpfully undo
    /// it by re-seeding the defaults.
    private(set) var hasBeenCleared = false

    func clearRows() {
        rows.removeAll()
        hasBeenCleared = true
    }

    /// Open on a real comparison — the two calibrated ADHD stimulants, one per
    /// plan — rather than an empty surface. Two curves teach what the tool does
    /// faster than a placeholder can.
    ///
    /// Both in a *single* plan would be the wrong lesson: the engine sums a
    /// plan's doses, so that models taking amphetamine and methylphenidate
    /// together, while reading as "A vs B" to anyone who opens the screen.
    func seedDefaultDoses() {
        rows.removeAll()
        if let amp = SubstanceLibrary.resolveFull("Amphetamine") {
            addRow(substance: amp, amount: 20, route: .oral, hours: 0, plan: .a)
        }
        if let mph = SubstanceLibrary.resolveFull("Methylphenidate") {
            addRow(substance: mph, amount: 20, route: .oral, hours: 0, plan: .b)
        }
        if rows.isEmpty { addRow() }
    }

    /// Recompute off-main, debounced — identical pipeline to the session screen,
    /// just fed by the rows instead of `DoseEntry`s.
    /// `immediate` skips the debounce, which exists to coalesce slider drags. On
    /// first appearance there is nothing to coalesce and the wait is just a blank
    /// chart.
    func scheduleRecompute(immediate: Bool = false) {
        task?.cancel()
        task = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled else { return }
            }
            await self?.recompute()
        }
    }

    private func recompute() async {
        var dosesByPlan: [SandboxPlan: [MechanisticSessionModel.DoseInput]] = [:]
        for row in rows {
            guard let substance = row.substance, row.amount > 0 else { continue }
            dosesByPlan[row.plan, default: []].append(MechanisticSessionModel.DoseInput(
                name: substance.name, amount: row.amount, route: row.route, hours: row.hours,
            ))
        }
        let allDoses = dosesByPlan.values.flatMap(\.self)
        hasInput = !allDoses.isEmpty
        guard !allDoses.isEmpty else {
            planResults = []
            supported = false
            return
        }
        // One tMax across every plan, so the curves share a time axis and can be
        // read against each other.
        let tMax = max((allDoses.map(\.hours).max() ?? 0) + 12, 12)
        let pharmacology = resolvePharmacology(allDoses)

        var computed: [PlanResult] = []
        for plan in SandboxPlan.allCases {
            guard let doses = dosesByPlan[plan], !doses.isEmpty else { continue }
            guard MechanisticSessionModel.supportsMechanisticView(doses, pharmacology: pharmacology) else { continue }
            let result = await Task.detached {
                MechanisticSessionModel.compute(doses: doses, pharmacology: pharmacology, tMax: tMax)
            }.value
            if let result { computed.append(PlanResult(plan: plan, result: result)) }
        }
        planResults = computed
        supported = !computed.isEmpty
    }

    /// Resolve each distinct substance's PK + binding from the bundled DB, keyed by
    /// normalized name — the same resolution the session performs, handed to the
    /// off-main compute.
    private func resolvePharmacology(_ doses: [MechanisticSessionModel.DoseInput]) -> [String: PharmacologyParameters] {
        var result: [String: PharmacologyParameters] = [:]
        for dose in doses {
            let key = SubstanceModelDatabase.normalize(dose.name)
            if result[key] == nil {
                result[key] = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: dose.name)
            }
        }
        return result
    }
}

// MARK: - Dose scale

/// The slider's domain for one row, derived from the substance's own dose ladder
/// rather than a fixed range — so amphetamine sweeps 0–60 mg in 2.5 mg detents
/// while LSD sweeps 0–300 µg in 10 µg ones, and the slider's midpoint always sits
/// somewhere useful instead of at an absurd multiple of a real dose.
struct SandboxDoseScale {
    let upperBound: Double
    let step: Double
    let ladder: DoseRange?

    /// A tier boundary on the track: where it falls, and the tier it closes.
    struct TierMark: Identifiable {
        let fraction: Double
        let level: DoseLevel
        var id: Double {
            fraction
        }
    }

    /// Boundaries of the ladder along the track, each carrying its tier's color —
    /// so the marks read as the substance's own ladder (matching the tier word in
    /// the readout) instead of anonymous decoration.
    var tierMarks: [TierMark] {
        guard let ladder, upperBound > 0 else { return [] }
        let boundaries: [(Double?, DoseLevel)] = [
            (ladder.threshold, .threshold),
            (ladder.light?.upperBound, .light),
            (ladder.common?.upperBound, .common),
            (ladder.strong?.upperBound, .strong),
        ]
        return boundaries.compactMap { value, level in
            guard let value, value > 0, value < upperBound else { return nil }
            return TierMark(fraction: value / upperBound, level: level)
        }
    }

    /// The track runs to twice the top of the ladder. Ending it *at* heavy makes
    /// the ladder partition the slider neatly but caps the tool below what it's
    /// for — you can't model an overshoot if the slider won't go there. The tier
    /// ticks keep the scale readable at the cost of a common dose sitting left of
    /// center.
    init(substance: Substance?, route: RouteOfAdministration, unit: String, amount: Double) {
        let ladder = substance?.doseRange(for: route)
        self.ladder = ladder?.hasAnyValue == true ? ladder : nil
        let reference = StagedDose.lookupReferenceDose(substance: substance, route: route, unit: unit)
        let ceiling: Double = if let heavy = ladder?.heavy {
            heavy * 2
        } else if let strong = ladder?.strong?.upperBound {
            strong * 2
        } else if let common = ladder?.common?.upperBound {
            common * 3
        } else if let light = ladder?.light?.upperBound {
            light * 5
        } else if let reference {
            reference * 4
        } else {
            100
        }
        let step = DoseStepping.niceStep(for: reference ?? ceiling / 6)
        self.step = step
        // Snap the ceiling up to a whole number of steps, and never below what the
        // row already holds (a seeded or previously-typed amount stays reachable).
        let wanted = max(ceiling, amount)
        upperBound = max(step, (wanted / step).rounded(.up) * step)
    }

    /// Round an arbitrary value onto the detent grid, killing the float dust a
    /// slider drag leaves behind (2.5000000000000004 mg).
    func snap(_ value: Double) -> Double {
        let snapped = (value / step).rounded() * step
        return min(max(0, snapped), upperBound)
    }

    func level(for amount: Double) -> DoseLevel? {
        guard let ladder, amount > 0 else { return nil }
        return ladder.level(for: amount)
    }
}
