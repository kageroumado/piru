import SwiftUI

// MARK: - Model

/// Which substances the estimator is allowed to offer. The engine is calibrated
/// on five stimulants and can only *simulate* a curated handful beyond them;
/// offering the full 1100-substance library invites picking something that draws
/// a dose marker and no curve, which reads as a broken tool rather than an
/// unmodelable substance.
@MainActor
enum SandboxModelability {
    /// Substances that can anchor a plan by themselves.
    static var anchors: [Substance] {
        resolve(SubstanceModelDatabase.calibratedTriggerSet.sorted()) {
            SubstanceModelDatabase.canAnchor(name: $0.name, pharmacology: pharmacology(for: $0))
        }
    }

    /// Substances the engine can simulate only alongside an anchor — they shape
    /// the curves but can't produce one on their own.
    static var adjuncts: [Substance] {
        resolve(SubstanceModelDatabase.modelableCandidateNames) {
            !SubstanceModelDatabase.canAnchor(name: $0.name, pharmacology: pharmacology(for: $0))
                && SubstanceModelDatabase.canParticipate(name: $0.name, pharmacology: pharmacology(for: $0))
        }
    }

    static func isAnchor(_ substance: Substance) -> Bool {
        SubstanceModelDatabase.canAnchor(name: substance.name, pharmacology: pharmacology(for: substance))
    }

    static func canParticipate(_ substance: Substance) -> Bool {
        SubstanceModelDatabase.canParticipate(name: substance.name, pharmacology: pharmacology(for: substance))
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

// MARK: - View

// The Effect Estimator tool: an editable list of hypothetical doses feeding the
// live effect model, with the same lens charts the session screen draws. A
// decision/curiosity surface ("which of my two meds, and why") that writes
// nothing to the journal.

struct EffectSandboxView: View {
    /// What a substance pick applies to — a new dose in a given plan, or a
    /// replacement for an existing row's.
    private enum PickTarget: Identifiable {
        case new(SandboxPlan)
        case existing(UUID)
        var id: String {
            switch self {
            case let .new(plan): "new-\(plan.rawValue)"
            case let .existing(rowID): rowID.uuidString
            }
        }
    }

    @State private var model = EffectSandboxModel()
    @State private var pickTarget: PickTarget?
    @State private var showsGuide = false
    /// True while a dose slider's thumb is held — see ``BackSwipeSuspender``.
    @State private var isAdjustingDose = false

    var body: some View {
        Group {
            if model.rows.isEmpty {
                emptyState
            } else {
                doseList
            }
        }
        .background(Theme.background)
        .background { BackSwipeSuspender(isSuspended: isAdjustingDose) }
        // The charts are pinned and the doses scroll under them — the inverse of
        // the old layout. You are always editing against a visible curve, and the
        // doses get the full width of a standard list instead of a cramped strip.
        .safeAreaInset(edge: .top, spacing: 0) {
            // Shown as soon as there are rows, not once the first result lands:
            // the simulation runs off-main, so gating on it made the whole list
            // jump down a moment after opening. The pager keeps its height and
            // fills in the curves when they arrive.
            if !model.rows.isEmpty {
                SandboxChartPager(model: model)
            }
        }
        .navigationTitle("Effect Estimator")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear {
            if model.rows.isEmpty, !model.hasBeenCleared { model.seedDefaultDoses() }
            model.scheduleRecompute(immediate: true)
        }
        .onChange(of: model.signature) { model.scheduleRecompute() }
        .sheet(item: $pickTarget) { target in
            SandboxSubstancePicker { substance in
                switch target {
                case let .new(plan): model.addRow(substance: substance, plan: plan)
                case let .existing(rowID): model.setSubstance(substance, forRow: rowID)
                }
                pickTarget = nil
            }
        }
        .sheet(isPresented: $showsGuide) { SandboxGuideSheet(model: model) }
    }

    // MARK: Toolbar

    /// One button, always relevant. Everything else that used to live in an
    /// overflow menu is now a row in the list where it applies — a menu that
    /// degrades to a single "Clear" item is not worth the tap.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showsGuide = true
            } label: {
                Image(systemName: "info.circle")
            }
            .accessibilityLabel("Reading these estimates")
        }
    }

    // MARK: Doses

    /// Plans are plain list sections, which is what they always were: a titled
    /// group with an "Add" row at the end. That makes "add to *this* plan"
    /// self-evident instead of needing a tiny glyph in a floating strip.
    private var doseList: some View {
        List {
            ForEach(model.activePlans) { plan in
                planSection(plan)
            }
            if !model.isComparing {
                Section {
                    Button {
                        pickTarget = .new(.b)
                    } label: {
                        Label("Compare with another plan", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    .listRowBackground(CardBackground())
                } footer: {
                    Text("A second plan is drawn as its own curve, so you can hold two ideas side by side — two meds, or a split dose against a single one.")
                }
            }
            Section {
                Button(role: .destructive) {
                    model.clearRows()
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
                .listRowBackground(CardBackground())
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func planSection(_ plan: SandboxPlan) -> some View {
        Section {
            ForEach(model.rows(in: plan)) { row in
                SandboxDoseRow(
                    row: bindingForRow(row.id),
                    onPickSubstance: { pickTarget = .existing(row.id) },
                    onSetRoute: { model.setRoute($0, forRow: row.id) },
                    onThumbHeldChange: { isAdjustingDose = $0 },
                )
                .contextMenu {
                    if model.isComparing {
                        ForEach(SandboxPlan.allCases) { target in
                            Button {
                                model.setPlan(target, forRow: row.id)
                            } label: {
                                if target == row.plan {
                                    Label(String(localized: target.label), systemImage: "checkmark")
                                } else {
                                    Text(target.label)
                                }
                            }
                        }
                        Divider()
                    }
                    Button(role: .destructive) {
                        model.removeRow(row.id)
                    } label: {
                        Label("Remove dose", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        model.removeRow(row.id)
                    } label: {
                        Label("Remove dose", systemImage: "trash")
                    }
                }
                .listRowBackground(CardBackground())
            }
            Button {
                pickTarget = .new(plan)
            } label: {
                Label("Add a Dose", systemImage: "plus.circle.fill")
            }
            .listRowBackground(CardBackground())
        } header: {
            if model.isComparing {
                HStack(spacing: 6) {
                    Capsule()
                        .fill(plan.color)
                        .frame(width: 14, height: 3)
                        .accessibilityHidden(true)
                    Text(plan.label)
                }
            } else {
                Text("Doses")
            }
        } footer: {
            if model.unmodelablePlans.contains(plan) {
                Label(
                    "Nothing here can anchor a curve. Add a calibrated substance — amphetamine, methylphenidate, mephedrone, 3-MMC, or 2-MMC.",
                    systemImage: "exclamationmark.triangle",
                )
            }
        }
    }

    /// A binding into the model's array by row id, so a reordered or filtered
    /// `ForEach` can still drive edits without index math.
    private func bindingForRow(_ id: UUID) -> Binding<EffectSandboxModel.Row> {
        Binding(
            get: { model.rows.first { $0.id == id } ?? EffectSandboxModel.Row() },
            set: { updated in
                guard let index = model.rows.firstIndex(where: { $0.id == id }) else { return }
                model.rows[index] = updated
            },
        )
    }

    // MARK: Empty (no rows at all)

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Add a dose to model it", systemImage: "chart.xyaxis.line")
        } description: {
            Text("Pick a substance and an amount to see how it may feel over time.")
        } actions: {
            Button("Add a dose") { pickTarget = .new(.a) }
                .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Pinned charts

/// The four lenses as a paged strip: swipe between them, or read the overview
/// page that shows all four at once. Pinned above the doses so every slider drag
/// is visible against the curve it changes.
private struct SandboxChartPager: View {
    let model: EffectSandboxModel

    @State private var page = 0

    private var height: CGFloat {
        252
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.isComparing { legend }
            TabView(selection: $page) {
                overviewPage.tag(0)
                ForEach(Array(model.activeLenses.enumerated()), id: \.element) { index, lens in
                    singlePage(lens).tag(index + 1)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .frame(height: height)
        }
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(model.activePlans) { plan in
                HStack(spacing: 5) {
                    Capsule()
                        .fill(plan.color)
                        .frame(width: 14, height: 3)
                    Text(plan.label)
                        .font(.caption.weight(.medium))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    /// All four at once — the relationship between channels is often the answer
    /// ("Feeling flat, Strain doubled"), and a paged view alone would hide it.
    private var overviewPage: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 6) {
            ForEach(model.activeLenses) { lens in
                VStack(alignment: .leading, spacing: 0) {
                    label(lens, font: .caption2)
                    chart(lens, height: 76)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        // Clear of the paging dots, which the TabView pins to the frame's bottom.
        .padding(.bottom, 26)
        .accessibilityLabel("All four lenses")
    }

    private func singlePage(_ lens: EffectLens) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            label(lens, font: .subheadline)
            chart(lens, height: 150)
            Text(footer(for: lens))
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 26)
    }

    private func label(_ lens: EffectLens, font: Font) -> some View {
        HStack(spacing: 5) {
            Image(systemName: lens.symbol)
                .foregroundStyle(lens.color)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(lens.label)
                .font(font.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.leading, 4)
    }

    private func chart(_ lens: EffectLens, height: CGFloat) -> some View {
        Group {
            if let result = model.primaryResult {
                MechanisticChartView(
                    result: result,
                    lens: lens,
                    startDate: model.startDate,
                    // No "now" for a hypothetical — a value past the span hides the
                    // now-line; content framing comes from `startFramed`.
                    nowHours: 1_000_000,
                    doseMarks: model.doseMarks,
                    vitals: nil,
                    // Non-interactive: a pan gesture here would fight the pager's swipe.
                    interactive: false,
                    startFramed: true,
                    comparison: model.comparisonSeries,
                    axisOverride: model.mergedRange(for: lens),
                    // A hypothetical has no wall clock — its start date is synthetic.
                    showsClockAxis: false,
                )
            }
        }
        .frame(height: height)
    }

    private func footer(for lens: EffectLens) -> LocalizedStringKey {
        switch lens {
        case .feeling: "Higher is better. Pleasure and warmth rise above the line; the comedown dips below."
        case .wanting: "Higher is more pull. The rush and craving signal."
        case .liking: "Higher is more pleasure. The opioid warmth signal."
        case .energy: "Higher is livelier. Drive rises above the line, sedation sits below."
        case .compulsion: "Lower is better. The pull to take another dose."
        case .strain: "Lower is better. Load on the body."
        case .timeline: ""
        }
    }
}

// MARK: - Back-swipe arbitration

/// Suspends the navigation stack's interactive back-swipe while a slider thumb is
/// held.
///
/// A `Slider` in a pushed view loses its drag to the pop gesture: grabbing the
/// thumb and moving horizontally pops the screen instead of changing the value.
/// UIKit's recognizer claims the pan first, and SwiftUI's `Slider` has no way to
/// require it to fail. Suspending it for exactly as long as the thumb is held is
/// narrower than disabling back-swipe for the whole screen — anywhere you are not
/// touching a slider, the gesture still works.
private struct BackSwipeSuspender: UIViewRepresentable {
    let isSuspended: Bool

    func makeUIView(context _: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context _: Context) {
        let suspended = isSuspended
        // Deferred: on the first update the view is not yet in the hierarchy, so
        // the navigation controller can't be found synchronously.
        DispatchQueue.main.async {
            uiView.enclosingNavigationController?.interactivePopGestureRecognizer?.isEnabled = !suspended
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator _: ()) {
        // Never leave the gesture disabled behind us if the view goes away
        // mid-drag (a dismissal, a cancelled touch).
        uiView.enclosingNavigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }
}

private extension UIView {
    var enclosingNavigationController: UINavigationController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let nav = current as? UINavigationController { return nav }
            if let controller = current as? UIViewController, let nav = controller.navigationController { return nav }
            responder = current.next
        }
        return nil
    }
}

// MARK: - Dose row

/// One dose as a standard list row: a full-width name button, a labeled slider,
/// and system `Picker`/`Stepper` controls. Every target clears the 44pt minimum,
/// and each control says what it does rather than relying on a bare glyph.
/// Removing and re-planning live in the row's context menu and swipe actions,
/// where iOS users already look for them.
private struct SandboxDoseRow: View {
    @Binding var row: EffectSandboxModel.Row
    let onPickSubstance: () -> Void
    let onSetRoute: (RouteOfAdministration) -> Void
    /// Reports whether the dose thumb is currently held, so the screen can
    /// suspend the back-swipe for the duration.
    let onThumbHeldChange: (Bool) -> Void

    private var scale: SandboxDoseScale {
        SandboxDoseScale(substance: row.substance, route: row.route, unit: row.unit, amount: row.amount)
    }

    /// Slider writes go through the scale so a drag lands on a clean detent — the
    /// engine gets 22.5 mg, never 22.499999999999996.
    private var amountBinding: Binding<Double> {
        let scale = scale
        return Binding(
            get: { min(row.amount, scale.upperBound) },
            set: { row.amount = scale.snap($0) },
        )
    }

    private var routeBinding: Binding<RouteOfAdministration> {
        Binding(get: { row.route }, set: { onSetRoute($0) })
    }

    private var readout: String {
        "\(row.amount.doseFormatted) \(row.unit)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            nameButton
            if row.substance != nil {
                doseControl
                Picker(selection: routeBinding) {
                    ForEach(RouteOfAdministration.allCases) { route in
                        Text(route.localizedName).tag(route)
                    }
                } label: {
                    Text("Route")
                }
                .pickerStyle(.menu)
                Stepper(value: $row.hours, in: 0 ... 24, step: 0.5) {
                    LabeledContent {
                        Text(SandboxDoseRow.timeText(row.hours))
                            .monospacedDigit()
                    } label: {
                        Text("Taken")
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var nameButton: some View {
        Button(action: onPickSubstance) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: row.colorHex))
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(row.substance == nil ? String(localized: "Choose substance") : row.displayName)
                    .font(.headline)
                    .foregroundStyle(row.substance == nil ? Theme.secondaryLabel : .primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .frame(minHeight: 32)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Substance")
        .accessibilityValue(row.substance == nil ? Text("None") : Text(verbatim: row.displayName))
        .accessibilityHint("Choose a different substance")
    }

    private var doseControl: some View {
        let scale = scale
        let level = scale.level(for: row.amount)
        return VStack(spacing: 2) {
            HStack(spacing: 6) {
                Text("Dose")
                    .foregroundStyle(Theme.secondaryLabel)
                Spacer(minLength: 4)
                Text(readout)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(level?.labelColor ?? .primary)
                if let level {
                    Text(level.displayName)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            Slider(value: amountBinding, in: 0 ... scale.upperBound, step: scale.step) { editing in
                onThumbHeldChange(editing)
            }
            .tint(Color(hex: row.colorHex))
            .background(alignment: .leading) { tierTicks(scale) }
            // `minimumDistance: 0` fires on touch-down, before any movement — the
            // back-swipe has to be suspended *before* the pan is recognized, so
            // `onEditingChanged` alone is too late.
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onThumbHeldChange(true) }
                    .onEnded { _ in onThumbHeldChange(false) },
            )
            .accessibilityLabel("Dose")
            .accessibilityValue(readout)
        }
    }

    /// Faint marks where the ladder's tiers fall, each in its tier's color, so the
    /// track reads as the substance's own ladder rather than an arbitrary 0-to-max.
    private func tierTicks(_ scale: SandboxDoseScale) -> some View {
        GeometryReader { proxy in
            ForEach(scale.tierMarks) { mark in
                Capsule()
                    .fill(mark.level.labelColor.opacity(0.75))
                    .frame(width: 2, height: 7)
                    .offset(x: proxy.size.width * mark.fraction, y: proxy.size.height / 2 + 8)
            }
        }
        // The track is inset by roughly the thumb's half-width, so the ticks must
        // be too or they drift off the tier boundaries they mark.
        .padding(.horizontal, 11)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// "At start" / "30 min later" / "1 h 30 m later" — a bare "start" said
    /// nothing about what the number meant.
    static func timeText(_ hours: Double) -> String {
        guard hours > 0 else { return String(localized: "At start") }
        let totalMinutes = Int((hours * 60).rounded())
        let wholeHours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if wholeHours == 0 { return String(localized: "\(minutes) min later") }
        if minutes == 0 { return String(localized: "\(wholeHours) h later") }
        return String(localized: "\(wholeHours) h \(minutes) m later")
    }
}

// MARK: - Guide sheet

/// The tool's reasoning, laid open: how to read the curves, the mechanism story
/// the session screen already tells, and — per substance actually in play — the
/// measured pharmacology and the derived engine inputs built from it.
///
/// Showing the numbers matters even for a reader who can't evaluate them. A curve
/// with no visible provenance is an oracle; the same curve with its half-life,
/// Tmax, transporter weights and confidence grades attached is a claim you can
/// follow, check, and disagree with.
private struct SandboxGuideSheet: View {
    let model: EffectSandboxModel

    @Environment(\.dismiss) private var dismiss
    @State private var glossaryTopic: PharmacologyGlossarySheet.Topic?

    /// Distinct (substance, route) pairs currently feeding a curve — the exact set
    /// the engine resolved parameters for.
    private var substancesInPlay: [EffectSandboxModel.Row] {
        var seen = Set<String>()
        return model.rows.filter { row in
            guard let substance = row.substance, row.amount > 0 else { return false }
            return seen.insert("\(substance.name)|\(row.route.rawValue)").inserted
        }
    }

    var body: some View {
        NavigationStack {
            List {
                readingSection
                mechanismSection
                coverageSection
                ForEach(substancesInPlay) { row in
                    ParameterSection(row: row, onGlossary: { glossaryTopic = $0 })
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("How this is estimated")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark").font(.body.weight(.semibold))
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accent)
                    .accessibilityLabel(Text("Done"))
                }
            }
            .sheet(item: $glossaryTopic) { PharmacologyGlossarySheet(topic: $0) }
        }
    }

    private var readingSection: some View {
        Section {
            Text("See how doses might feel over time — compare two meds, preview a stack, or change the timing — without logging anything. This is a scratch surface; nothing here touches your journal.")
            Text("This shows what the model predicts about the shape and sign of an effect — not what you should take. It is an estimate from typical pharmacology, never a recommendation or a safe-dose guide.")
            Text("Compare the shape of a curve more than its exact height.")
            Text("Your own response shifts with tolerance, body chemistry, and the day. Talk to a prescriber about your medication.")
        } header: {
            Text("Reading these estimates")
        } footer: {
            Text("A rough guide, not medical advice.")
        }
        .listRowBackground(CardBackground())
    }

    /// Two depths, in order: the intuition (the session screen's own explainer, so
    /// there is one account of the model rather than two that drift), then the
    /// full pipeline for anyone who wants to check the reasoning.
    private var mechanismSection: some View {
        Section {
            NavigationLink {
                EffectModelExplainerView()
            } label: {
                Label("How this works", systemImage: "function")
            }
            NavigationLink {
                EffectPipelineExplainerView()
            } label: {
                Label("The calculation, step by step", systemImage: "list.number")
            }
        } footer: {
            Text("The idea first, then every stage from your dose to the line on the chart.")
        }
        .listRowBackground(CardBackground())
    }

    private var coverageSection: some View {
        Section {
            Text("The model is calibrated on five stimulants: amphetamine, methylphenidate, mephedrone, 3-MMC, and 2-MMC. Other substances shape the curves through how they interact with these. Opioids are read through their dopamine activity, mostly to show those interactions.")
            Text("Confidence varies by substance. Well-studied ones like amphetamine and methylphenidate rest on firmer data than newer compounds.")
        } header: {
            Text("What these curves cover")
        }
        .listRowBackground(CardBackground())
    }
}

/// One substance's inputs: what was measured, and what the engine derived from it.
private struct ParameterSection: View {
    let row: EffectSandboxModel.Row
    let onGlossary: (PharmacologyGlossarySheet.Topic) -> Void

    private var pharmacology: PharmacologyParameters? {
        guard let substance = row.substance else { return nil }
        return SubstanceStore.shared.pharmacologyParameters(forSubstanceName: substance.name)
    }

    private var engineParams: SubstanceModelParams? {
        guard let substance = row.substance else { return nil }
        return SubstanceModelDatabase.params(name: substance.name, pharmacology: pharmacology)
    }

    var body: some View {
        Section {
            if let pharmacology {
                measuredRows(pharmacology)
            }
            if let engineParams {
                derivedRows(engineParams)
            }
            if let targets = pharmacology?.targets, !targets.isEmpty {
                bindingRows(targets)
            }
            if pharmacology == nil, engineParams == nil {
                Text("No resolved pharmacology for this substance.")
                    .foregroundStyle(Theme.secondaryLabel)
            }
        } header: {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: row.colorHex))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(verbatim: row.displayName)
                Text(row.route.localizedName)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .textCase(nil)
        } footer: {
            if let tier = pharmacology?.occupancyConfidence {
                HStack(spacing: 6) {
                    Text("Weakest input")
                    ConfidenceBadge(tier: tier)
                }
            }
        }
        .listRowBackground(CardBackground())
    }

    // MARK: Measured

    @ViewBuilder
    private func measuredRows(_ parameters: PharmacologyParameters) -> some View {
        Button {
            onGlossary(.pharmacokinetics)
        } label: {
            LabeledContent {
                Image(systemName: "info.circle")
                    .foregroundStyle(Theme.accent)
            } label: {
                Text("Measured pharmacokinetics")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        if let halfLife = parameters.halfLifeMinutes {
            LabeledContent("Half-life (t½)", value: Self.duration(minutes: halfLife))
        }
        if let tmax = parameters.tmaxMinutes {
            LabeledContent("Time to peak (Tmax)", value: Self.duration(minutes: tmax))
        }
        if let bioavailability = parameters.bioavailabilityFraction {
            LabeledContent("Bioavailability (F)", value: "\(Int((bioavailability * 100).rounded()))%")
        }
        if let vd = parameters.vdLPerKg {
            LabeledContent("Distribution (Vd)", value: "\(vd.doseFormatted) L/kg")
        }
        if let reference = parameters.referenceDoseMg {
            LabeledContent("Reference dose", value: "\(reference.doseFormatted) mg")
        }
        if let species = parameters.pkSpecies, species.lowercased() != "human" {
            LabeledContent("Species", value: species.capitalized)
        }
    }

    // MARK: Derived

    /// The literal values handed to the simulation. `ka` in particular is derived,
    /// not measured — from Tmax when there is one, else a fixed multiple of `ke` —
    /// and saying so is the difference between a figure and a guess.
    @ViewBuilder
    private func derivedRows(_ params: SubstanceModelParams) -> some View {
        Text("What the engine uses")
            .font(.subheadline.weight(.semibold))
        LabeledContent("Elimination rate (ke)", value: "\(params.ke.doseFormatted) /h")
        LabeledContent("Absorption rate (ka)", value: "\(params.ka.doseFormatted) /h")
        // Distinct from the DB's measured reference above: this is the curated
        // anchor the calibrated magnitudes were fitted against.
        LabeledContent("Model anchor dose", value: "\(params.refUnit.doseFormatted) \(row.unit)")
        if params.wDAT > 0 || params.wNET > 0 || params.wSERT > 0 {
            LabeledContent("Transporter weights", value: "DAT \(params.wDAT.doseFormatted) · NET \(params.wNET.doseFormatted) · SERT \(params.wSERT.doseFormatted)")
            LabeledContent("Mechanism", value: params.releaser ? String(localized: "Releaser") : String(localized: "Reuptake blocker"))
        }
        if params.mu > 0 {
            LabeledContent("µ-opioid drive", value: params.mu.doseFormatted)
        }
        if params.gaba > 0 {
            LabeledContent("GABA-A drive", value: params.gaba.doseFormatted)
        }
    }

    // MARK: Binding

    @ViewBuilder
    private func bindingRows(_ targets: [PharmacologyParameters.TargetEngagement]) -> some View {
        Button {
            onGlossary(.receptor)
        } label: {
            LabeledContent {
                Image(systemName: "info.circle")
                    .foregroundStyle(Theme.accent)
            } label: {
                Text("Binding used")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        // The tightest few only: the whole table lives on the substance's own
        // Pharmacology card, and this is the subset that shaped these curves.
        ForEach(targets.prefix(5)) { target in
            LabeledContent {
                Text(verbatim: concentrationLabel(target))
                    .monospacedDigit()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: target.target)
                    ProvenanceBadge(
                        confidence: target.confidence,
                        species: target.species,
                        sourceSlug: target.sourceSlug,
                    )
                }
            }
        }
    }

    private func concentrationLabel(_ target: PharmacologyParameters.TargetEngagement) -> String {
        switch target.kind {
        case .ki: concLabel(kiNm: target.halfMaxNanomolar, ec50Nm: nil, ic50Nm: nil)
        case .ec50: concLabel(kiNm: nil, ec50Nm: target.halfMaxNanomolar, ic50Nm: nil)
        case .ic50: concLabel(kiNm: nil, ec50Nm: nil, ic50Nm: target.halfMaxNanomolar)
        }
    }

    private static func duration(minutes: Double) -> String {
        minutes < 90
            ? String(localized: "\(Int(minutes.rounded())) min")
            : String(localized: "\((minutes / 60).doseFormatted) h")
    }
}

// MARK: - Substance picker sheet

/// The picker offers only what the engine can simulate, split into what can
/// anchor a plan and what merely shapes one. Searching the whole library let you
/// pick, say, lisdexamfetamine and get a dose marker with no curve.
private struct SandboxSubstancePicker: View {
    let onPick: (Substance) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    private func matches(_ substance: Substance) -> Bool {
        guard !trimmedQuery.isEmpty else { return true }
        return substance.displayTitle.localizedCaseInsensitiveContains(trimmedQuery)
            || substance.name.localizedCaseInsensitiveContains(trimmedQuery)
    }

    private var anchors: [Substance] {
        SandboxModelability.anchors.filter(matches)
    }

    private var adjuncts: [Substance] {
        SandboxModelability.adjuncts.filter(matches)
    }

    var body: some View {
        NavigationStack {
            List {
                if !anchors.isEmpty {
                    Section {
                        ForEach(anchors) { row($0) }
                    } header: {
                        Text("Calibrated")
                    } footer: {
                        Text("The model was calibrated on these. Each one can be modeled on its own.")
                    }
                }
                if !adjuncts.isEmpty {
                    Section {
                        ForEach(adjuncts) { row($0) }
                    } header: {
                        Text("Modeled alongside")
                    } footer: {
                        Text("The engine can simulate these as part of a plan, but they need a calibrated substance in the same plan to anchor the curve.")
                    }
                }
                if anchors.isEmpty, adjuncts.isEmpty {
                    ContentUnavailableView.search(text: trimmedQuery)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search substances")
            .navigationTitle("Pick a substance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                }
            }
        }
    }

    private func row(_ substance: Substance) -> some View {
        Button {
            onPick(substance)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(substance.displayTitle)
                        .foregroundStyle(.primary)
                    Text(substance.category.displayName)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
