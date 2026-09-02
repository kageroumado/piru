import SwiftUI

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
                HStack(spacing: Spacing.sm) {
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
        .padding(.top, Spacing.md)
        .accessibilityElement(children: .combine)
    }

    /// All four at once — the relationship between channels is often the answer
    /// ("Feeling flat, Strain doubled"), and a paged view alone would hide it.
    private var overviewPage: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.lg), GridItem(.flexible(), spacing: Spacing.lg)], spacing: Spacing.sm) {
            ForEach(model.activeLenses) { lens in
                VStack(alignment: .leading, spacing: 0) {
                    label(lens, font: .caption2)
                    chart(lens, height: 76)
                }
            }
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.top, Spacing.xs)
        // Clear of the paging dots, which the TabView pins to the frame's bottom.
        .padding(.bottom, 26)
        .accessibilityLabel("All four lenses")
    }

    private func singlePage(_ lens: EffectLens) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            label(lens, font: .subheadline)
            chart(lens, height: 150)
            Text(footer(for: lens))
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Spacing.xs)
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.top, Spacing.xs)
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
        .padding(.leading, Spacing.xs)
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
