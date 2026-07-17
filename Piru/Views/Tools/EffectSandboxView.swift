import SwiftUI

// MARK: - Model

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
        var colorHex: String

        var displayName: String {
            substance?.displayTitle ?? ""
        }
    }

    var rows: [Row] = []
    private(set) var result: MechanisticSessionModel.Result?
    /// Whether the current rows contain a calibrated substance (the engine can anchor).
    private(set) var supported = false
    /// Whether any row has a resolved substance + positive amount (something to model).
    private(set) var hasInput = false

    /// A synthetic, stable anchor — the sandbox is relative-time, so the absolute
    /// value only sets the chart's clock labels.
    let startDate = Date()

    private var task: Task<Void, Never>?

    /// A small stable palette so overlaid doses read as distinct curves.
    private static let palette = ["ED5787", "4C93E0", "2FA06E", "E0912F", "8E7BE8", "D0453F"]

    /// A signature the view observes to trigger a debounced recompute on any edit.
    var signature: Int {
        var hasher = Hasher()
        for row in rows {
            hasher.combine(row.substance?.name)
            hasher.combine(row.amount)
            hasher.combine(row.route)
            hasher.combine(row.hours)
        }
        return hasher.finalize()
    }

    /// Dose event marks positioned on the time axis, one per modelable row.
    var doseMarks: [MechanisticSessionModel.DoseMark] {
        rows.compactMap { row in
            guard row.substance != nil, row.amount > 0 else { return nil }
            return MechanisticSessionModel.DoseMark(hours: row.hours, colorHex: row.colorHex)
        }
    }

    func addRow(substance: Substance? = nil, amount: Double = 0, route: RouteOfAdministration = .oral, hours: Double = 0) {
        let color = Self.palette[rows.count % Self.palette.count]
        var seeded = amount
        if seeded <= 0, let substance {
            seeded = StagedDose.lookupReferenceDose(substance: substance, route: route, unit: substance.defaultUnit) ?? 0
        }
        rows.append(Row(
            searchText: substance?.displayTitle ?? "",
            substance: substance, amount: seeded, unit: substance?.defaultUnit ?? "mg",
            route: route, hours: hours, colorHex: color,
        ))
    }

    /// Point an existing row at a newly-picked substance, seeding a reference dose
    /// when the row had none.
    func setSubstance(_ substance: Substance, forRow id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].substance = substance
        rows[index].searchText = substance.displayTitle
        rows[index].unit = substance.defaultUnit
        if rows[index].amount <= 0 {
            rows[index].amount = StagedDose.lookupReferenceDose(
                substance: substance, route: rows[index].route, unit: substance.defaultUnit,
            ) ?? 0
        }
    }

    func removeRow(_ id: UUID) {
        rows.removeAll { $0.id == id }
    }

    /// Seed the ADHD "compare my two meds" preset — two calibrated stimulants at a
    /// typical dose, overlaid. The whole point of the compare surface.
    func seedComparePreset() {
        rows.removeAll()
        if let amp = SubstanceLibrary.lookupByNameOrAlias("Amphetamine") {
            addRow(substance: amp, amount: 20, route: .oral, hours: 0)
        }
        if let mph = SubstanceLibrary.lookupByNameOrAlias("Methylphenidate") {
            addRow(substance: mph, amount: 20, route: .oral, hours: 0)
        }
        if rows.isEmpty { addRow() }
    }

    /// Recompute off-main, debounced — identical pipeline to the session screen,
    /// just fed by the rows instead of `DoseEntry`s.
    func scheduleRecompute() {
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            await self?.recompute()
        }
    }

    private func recompute() async {
        let doses: [MechanisticSessionModel.DoseInput] = rows.compactMap { row in
            guard let substance = row.substance, row.amount > 0 else { return nil }
            return MechanisticSessionModel.DoseInput(
                name: substance.name, amount: row.amount, route: row.route, hours: row.hours,
            )
        }
        hasInput = !doses.isEmpty
        guard !doses.isEmpty else {
            result = nil
            supported = false
            return
        }
        let pharmacology = resolvePharmacology(doses)
        let canModel = MechanisticSessionModel.supportsMechanisticView(doses, pharmacology: pharmacology)
        supported = canModel
        guard canModel else {
            result = nil
            return
        }
        let tMax = max((doses.map(\.hours).max() ?? 0) + 12, 12)
        let computed = await Task.detached {
            MechanisticSessionModel.compute(doses: doses, pharmacology: pharmacology, tMax: tMax)
        }.value
        result = computed
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

// MARK: - View

/// The Effect Estimator tool: an editable list of hypothetical doses feeding the
/// live effect model, with the same lens charts the session screen draws. A
/// decision/curiosity surface ("which of my two meds, and why") that writes
/// nothing to the journal.
struct EffectSandboxView: View {
    /// What a substance pick applies to — a brand-new dose, or replacing a row's.
    private enum PickTarget: Identifiable {
        case new
        case existing(UUID)
        var id: String {
            switch self {
            case .new: "new"
            case let .existing(rowID): rowID.uuidString
            }
        }
    }

    @State private var model = EffectSandboxModel()
    @State private var pickTarget: PickTarget?

    private let chartHeight: CGFloat = 200

    var body: some View {
        List {
            introSection
            dosesSection
            if model.supported, let result = model.result {
                resultsSections(result)
            } else {
                statusSection
            }
            honestySection
        }
        .scrollContentBackground(.hidden)
        .listSectionSpacing(16)
        .background(Theme.background)
        .navigationTitle("Effect Estimator")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if model.rows.isEmpty { model.seedComparePreset() }
            model.scheduleRecompute()
        }
        .onChange(of: model.signature) { model.scheduleRecompute() }
        .sheet(item: $pickTarget) { target in
            SandboxSubstancePicker { substance in
                switch target {
                case .new: model.addRow(substance: substance)
                case let .existing(rowID): model.setSubstance(substance, forRow: rowID)
                }
                pickTarget = nil
            }
        }
    }

    // MARK: Intro

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.2.square")
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    Text("Try a combination")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    ExperimentalTag()
                }
                Text("See how doses might feel over time — compare two meds, preview a stack, or change the timing — without logging anything. This is a scratch surface; nothing here touches your journal.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    model.seedComparePreset()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.on.rectangle")
                            .imageScale(.small)
                        Text("Compare two meds")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
            .listRowBackground(CardBackground())
        }
    }

    // MARK: Editable doses

    private var dosesSection: some View {
        Section {
            ForEach($model.rows) { $row in
                SandboxDoseRow(
                    row: $row,
                    onPickSubstance: { pickTarget = .existing(row.id) },
                    onRemove: { model.removeRow(row.id) },
                )
                .listRowBackground(CardBackground())
            }
            Button {
                pickTarget = .new
            } label: {
                Label("Add a dose", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }
            .listRowBackground(CardBackground())
        } header: {
            Text("Doses")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .textCase(nil)
        }
    }

    // MARK: Results (reuse the session's lens charts)

    private func resultsSections(_ result: MechanisticSessionModel.Result) -> some View {
        ForEach(EffectLens.mechanistic) { lens in
            Section {
                MechanisticChartView(
                    result: result,
                    lens: lens,
                    startDate: model.startDate,
                    // No "now" for a hypothetical — a value past the span hides the
                    // now-line; content framing comes from `startFramed`.
                    nowHours: 1_000_000,
                    doseMarks: model.doseMarks,
                    vitals: nil,
                    interactive: true,
                    startFramed: true,
                )
                .frame(height: chartHeight)
                .listRowInsets(EdgeInsets(top: 4, leading: 0.5, bottom: 4, trailing: 0.5))
                .listRowSeparator(.hidden)
                .listRowBackground(CardBackground())
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: lens.symbol)
                        .foregroundStyle(lens.color)
                        .imageScale(.small)
                        .accessibilityHidden(true)
                    Text(lens.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .textCase(nil)
                }
            } footer: {
                Text(footer(for: lens))
            }
        }
    }

    private func footer(for lens: EffectLens) -> LocalizedStringKey {
        switch lens {
        case .feeling: "Higher is better. Pleasure and warmth rise above the line; the comedown dips below."
        case .energy: "Higher is livelier. Drive rises above the line, sedation sits below."
        case .compulsion: "Lower is better. The pull to take another dose."
        case .strain: "Lower is better. Load on the body."
        case .timeline: ""
        }
    }

    // MARK: Status (nothing to model yet)

    private var statusSection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: model.hasInput ? "questionmark.circle" : "arrow.up")
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.hasInput ? "Add a calibrated substance" : "Add a dose to model it")
                        .font(.subheadline.weight(.semibold))
                    Text(
                        model.hasInput
                            ? "The model anchors on five stimulants — amphetamine, methylphenidate, mephedrone, 3-MMC, 2-MMC. Add one of those (or a brand of it) and the others will shape the curves around it."
                            : "Pick a substance and an amount above to see how it may feel over time.",
                    )
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 2)
            .listRowBackground(CardBackground())
        }
    }

    // MARK: Honesty

    private var honestySection: some View {
        Section {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    Text("This shows what the model predicts about the shape and sign of an effect — not what you should take. It is an estimate from typical pharmacology, never a recommendation or a safe-dose guide.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Calibrated on five stimulants; other substances shape the curves through how they interact with those. Compare the shape of a curve more than its exact height.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Your own response shifts with tolerance, body chemistry, and the day. Talk to a prescriber about your medication.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.top, 6)
            } label: {
                Label {
                    Text("Reading these estimates")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "checkmark.seal")
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.vertical, 2)
            .listRowBackground(CardBackground())
        } footer: {
            Text("A rough guide, not medical advice.")
        }
    }
}

// MARK: - Dose row

private struct SandboxDoseRow: View {
    @Binding var row: EffectSandboxModel.Row
    let onPickSubstance: () -> Void
    let onRemove: () -> Void

    @State private var amountText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: row.colorHex))
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Button(action: onPickSubstance) {
                    HStack(spacing: 4) {
                        Text(row.substance == nil ? String(localized: "Choose substance") : row.displayName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(row.substance == nil ? Theme.secondaryLabel : .primary)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove dose")
            }

            HStack(spacing: 8) {
                // Amount — steppers flank a tappable field, so you can nudge or type.
                stepButton("minus") { setAmount(max(0, row.amount - amountStep)) }
                    .accessibilityLabel("Decrease amount")
                HStack(spacing: 4) {
                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 52, height: 34)
                        .background(Color(.secondarySystemFill), in: Capsule())
                        .onChange(of: amountText) {
                            row.amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
                        }
                        .accessibilityLabel("Amount")
                    Text(row.unit)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                stepButton("plus") { setAmount(row.amount + amountStep) }
                    .accessibilityLabel("Increase amount")
                Spacer()
                // Route
                Menu {
                    ForEach(RouteOfAdministration.allCases) { route in
                        Button {
                            row.route = route
                        } label: {
                            if route == row.route {
                                Label(String(localized: route.localizedName), systemImage: "checkmark")
                            } else {
                                Text(route.localizedName)
                            }
                        }
                    }
                } label: {
                    routePill(row.route.localizedName)
                }
                .buttonStyle(.plain)
            }

            // Time offset on its own row, so the amount steppers + route never crowd it.
            HStack(spacing: 8) {
                Text("Time")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryLabel)
                Spacer()
                timeStepper
            }
        }
        .padding(.vertical, 4)
        .onAppear { amountText = row.amount > 0 ? row.amount.doseFormatted : "" }
        .onChange(of: row.amount) {
            // Keep the field in sync when the model fills a reference dose on pick.
            let formatted = row.amount > 0 ? row.amount.doseFormatted : ""
            if formatted != amountText { amountText = formatted }
        }
    }

    private func routePill(_ label: LocalizedStringResource) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.down.circle").imageScale(.small)
            Text(label).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(Color(.secondarySystemFill), in: Capsule())
        .foregroundStyle(.primary)
    }

    private var timeStepper: some View {
        HStack(spacing: 6) {
            Button { row.hours = max(0, row.hours - 0.5) } label: {
                Image(systemName: "minus")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .background(Color(.secondarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Earlier")
            Text(row.hours == 0 ? String(localized: "start") : String(localized: "+\(row.hours.doseFormatted)h"))
                .font(.footnote.weight(.medium))
                .monospacedDigit()
                .frame(minWidth: 44)
            Button { row.hours += 0.5 } label: {
                Image(systemName: "plus")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .background(Color(.secondarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Later")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Time offset")
        .accessibilityValue(row.hours == 0 ? Text("at start") : Text("plus \(row.hours.doseFormatted) hours"))
    }

    private func stepButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .background(Color(.secondarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
    }

    /// Step increment anchored to the substance's reference dose when known
    /// (LSD → 10 µg, pregabalin → 25 mg), else a magnitude table.
    private var amountStep: Double {
        if let substance = row.substance,
           let reference = StagedDose.lookupReferenceDose(substance: substance, route: row.route, unit: row.unit) {
            return DoseStepping.niceStep(for: reference)
        }
        return switch row.amount {
        case ..<2: 0.25
        case ..<10: 1
        case ..<100: 5
        case ..<1_000: 25
        default: 100
        }
    }

    private func setAmount(_ value: Double) {
        row.amount = value
        amountText = value > 0 ? value.doseFormatted : ""
    }
}

// MARK: - Substance picker sheet

/// A searchable substance picker that opens on a set of **common suggestions**
/// (the calibrated stimulants first) rather than a blank field — so a pick is one
/// tap, and typing narrows via the library's ranked search.
private struct SandboxSubstancePicker: View {
    let onPick: (Substance) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    /// The calibrated set the model anchors on, then a few common ones — the
    /// substances a compare/what-if user reaches for first.
    private var suggestions: [Substance] {
        [
            "Amphetamine",
            "Methylphenidate",
            "Lisdexamfetamine",
            "Mephedrone",
            "3-MMC",
            "MDMA",
            "Cocaine",
            "Methamphetamine",
            "Caffeine",
            "Modafinil",
        ]
        .compactMap { SubstanceLibrary.lookupByNameOrAlias($0) }
    }

    private var results: [Substance] {
        query.trimmingCharacters(in: .whitespaces).isEmpty
            ? suggestions
            : SubstanceLibrary.search(query, limit: 30)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(results) { substance in
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
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(query.trimmingCharacters(in: .whitespaces).isEmpty ? "Common" : "Results")
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search substances")
            .navigationTitle("Pick a substance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
