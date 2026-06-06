import SwiftUI

// MARK: - Staged Dose

/// A dose staged in the quick-log tray, not yet committed. A staged chip is
/// already a complete dose (substance + amount + unit + route); everything
/// else here is optional enrichment.
struct StagedDose: Identifiable {
    let id = UUID()
    var substanceName: String
    var amount: Double
    var unit: String
    var route: RouteOfAdministration
    /// Repeat count for "two 150 mg capsules" — commits as one entry of
    /// `amount × count` (PK superposition is linear, so they're equivalent).
    var count: Int = 1
    var note: String = ""
    /// Per-dose timestamp override for staggered stacks; `nil` uses the
    /// tray-wide time.
    var timeOverride: Date?
    var colorHex: String?
    var librarySubstance: Substance?

    var totalAmount: Double {
        amount * Double(count)
    }

    var color: Color {
        colorHex.map { Color(hex: $0) } ?? .gray
    }
}

// MARK: - Tray Time

/// The tray-wide "When" — applied to every staged dose without an override.
/// Offsets resolve at commit time, so a tray left open doesn't drift.
enum TrayTime: Equatable {
    case now
    case offset(minutes: Int)
    case custom(Date)

    static let offsetChoices = [15, 30, 60, 120]

    var isNow: Bool {
        self == .now
    }

    var resolved: Date {
        switch self {
        case .now: .now
        case let .offset(minutes): .now.addingTimeInterval(-Double(minutes) * 60)
        case let .custom(date): date
        }
    }

    static func offsetLabel(minutes: Int) -> String {
        minutes < 60
            ? String(localized: "\(minutes) min ago")
            : String(localized: "\(minutes / 60)h ago")
    }

    /// Short label for the When chip.
    var chipLabel: String {
        switch self {
        case .now:
            String(localized: "Now")
        case let .offset(minutes):
            Self.offsetLabel(minutes: minutes)
        case let .custom(date):
            date.formatted(
                Calendar.current.isDateInToday(date)
                    ? .dateTime.hour().minute()
                    : .dateTime.month(.abbreviated).day().hour().minute(),
            )
        }
    }
}

// MARK: - Tray Model

/// Staging state for the quick-log tray. Owned by `QuickLogView` so dose chips
/// can reflect what's staged; rendered by `DoseTrayView`.
@Observable
final class DoseTrayModel {
    var staged: [StagedDose] = []
    var time: TrayTime = .now
    var tags: Set<String> = []
    var location: PickedLocation?
    var expandedItemID: UUID?
    var sharedDetailsExpanded = false

    var isEmpty: Bool {
        staged.isEmpty
    }

    var isCommittable: Bool {
        !staged.isEmpty && staged.allSatisfy { $0.amount > 0 }
    }

    /// How many of a given chip are staged (drives the chip's count badge).
    func quantity(substance: String, route: RouteOfAdministration, amount: Double, unit: String) -> Int {
        stagedIndex(substance: substance, route: route, amount: amount, unit: unit)
            .map { staged[$0].count } ?? 0
    }

    /// Stage a chip; re-staging the same chip increments its count.
    func stage(substance: String, route: RouteOfAdministration, amount: Double, unit: String, colorHex: String?, librarySubstance: Substance?) {
        if let index = stagedIndex(substance: substance, route: route, amount: amount, unit: unit) {
            staged[index].count += 1
        } else {
            staged.append(StagedDose(
                substanceName: substance,
                amount: amount,
                unit: unit,
                route: route,
                colorHex: colorHex,
                librarySubstance: librarySubstance,
            ))
        }
    }

    /// Stage an amount-less draft (from search / the ⋯ chip) and open it for
    /// editing so the amount field gets focus.
    func stageDraft(substance: String, route: RouteOfAdministration, unit: String, colorHex: String?, librarySubstance: Substance?) {
        let draft = StagedDose(
            substanceName: substance,
            amount: 0,
            unit: unit,
            route: route,
            colorHex: colorHex,
            librarySubstance: librarySubstance,
        )
        staged.append(draft)
        expandedItemID = draft.id
    }

    func remove(_ item: StagedDose) {
        staged.removeAll { $0.id == item.id }
        if expandedItemID == item.id { expandedItemID = nil }
    }

    private func stagedIndex(substance: String, route: RouteOfAdministration, amount: Double, unit: String) -> Int? {
        staged.firstIndex {
            $0.substanceName.lowercased() == substance.lowercased()
                && $0.route == route
                && $0.amount == amount
                && $0.unit == unit
        }
    }
}

// MARK: - Tray View

/// The commit surface for quick logging: staged doses, shared When/Tags/
/// Location controls, a live interaction check, and the Log button. Items
/// expand inline for per-dose enrichment — never a second sheet.
struct DoseTrayView: View {
    @Bindable var model: DoseTrayModel
    let tagSuggestions: [String]
    let onCommit: () -> Void

    @State private var showLocationPicker = false

    private var interactions: [InteractionResult] {
        let names = Array(Set(model.staged.map(\.substanceName)))
        guard names.count >= 2 else { return [] }
        return InteractionChecker.checkBatch(names, against: [])
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach($model.staged) { $item in
                if model.expandedItemID == item.id {
                    StagedDoseEditor(item: $item, trayTime: model.time) {
                        withAnimation(.snappy) { model.expandedItemID = nil }
                    } onRemove: {
                        withAnimation(.snappy) { model.remove(item) }
                    }
                    .padding(.vertical, 6)
                } else {
                    compactRow($item)
                }
                if item.id != model.staged.last?.id {
                    Divider().padding(.leading, 20)
                }
            }

            if !interactions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(interactions.enumerated()), id: \.offset) { _, warning in
                        InteractionWarningRow(warning: warning)
                    }
                }
                .padding(.top, 8)
            }

            if model.sharedDetailsExpanded {
                sharedDetails
                    .padding(.top, 10)
            }

            HStack(spacing: 8) {
                whenChip
                tagsChip
                locationChip
                Spacer(minLength: 0)
            }
            .padding(.top, 10)

            commitButton
                .padding(.top, 10)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(.quaternary, lineWidth: 0.5),
        )
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerView { picked in
                model.location = picked
            }
        }
    }

    // MARK: Rows

    private func compactRow(_ item: Binding<StagedDose>) -> some View {
        let dose = item.wrappedValue
        return HStack(spacing: 10) {
            Circle()
                .fill(dose.color)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "\(dose.substanceName) \(countPrefix(dose))\(dose.amount.doseFormatted) \(dose.unit)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Text(dose.route.localizedName)
                    if dose.timeOverride != nil {
                        Text(verbatim: "·")
                        Image(systemName: "clock")
                            .imageScale(.small)
                    }
                    if !dose.note.isEmpty {
                        Text(verbatim: "·")
                        Image(systemName: "note.text")
                            .imageScale(.small)
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Button {
                withAnimation(.snappy) { model.remove(dose) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove")
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy) { model.expandedItemID = dose.id }
        }
    }

    private func countPrefix(_ dose: StagedDose) -> String {
        dose.count > 1 ? "\(dose.count) × " : ""
    }

    // MARK: Shared controls

    private var whenChip: some View {
        Menu {
            Button {
                withAnimation(.snappy) { model.time = .now }
            } label: {
                if model.time.isNow {
                    Label("Now", systemImage: "checkmark")
                } else {
                    Text("Now")
                }
            }
            ForEach(TrayTime.offsetChoices, id: \.self) { minutes in
                Button {
                    withAnimation(.snappy) { model.time = .offset(minutes: minutes) }
                } label: {
                    if model.time == .offset(minutes: minutes) {
                        Label(TrayTime.offsetLabel(minutes: minutes), systemImage: "checkmark")
                    } else {
                        Text(TrayTime.offsetLabel(minutes: minutes))
                    }
                }
            }
            Button {
                withAnimation(.snappy) {
                    model.time = .custom(model.time.resolved)
                    model.sharedDetailsExpanded = true
                }
            } label: {
                Label("Pick date & time…", systemImage: "calendar")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .imageScale(.small)
                Text(model.time.chipLabel)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                model.time.isNow ? AnyShapeStyle(Color(.secondarySystemFill)) : AnyShapeStyle(Color.orange.opacity(0.18)),
                in: Capsule(),
            )
            .foregroundStyle(model.time.isNow ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.orange))
        }
        .buttonStyle(.plain)
    }

    private var tagsChip: some View {
        Button {
            withAnimation(.snappy) { model.sharedDetailsExpanded.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "tag")
                    .imageScale(.small)
                if model.tags.isEmpty {
                    Text("Tags")
                } else {
                    Text(verbatim: "\(model.tags.count)")
                }
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                model.tags.isEmpty ? AnyShapeStyle(Color(.secondarySystemFill)) : AnyShapeStyle(Theme.accent.opacity(0.15)),
                in: Capsule(),
            )
            .foregroundStyle(model.tags.isEmpty ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.accent))
        }
        .buttonStyle(.plain)
    }

    private var locationChip: some View {
        Button {
            if model.location == nil {
                showLocationPicker = true
            } else {
                withAnimation(.snappy) { model.location = nil }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: model.location == nil ? "mappin.and.ellipse" : "mappin.circle.fill")
                    .imageScale(.small)
                if let location = model.location {
                    Text(location.name)
                        .lineLimit(1)
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                } else {
                    Text("Location")
                }
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                model.location == nil ? AnyShapeStyle(Color(.secondarySystemFill)) : AnyShapeStyle(Theme.accent.opacity(0.15)),
                in: Capsule(),
            )
            .foregroundStyle(model.location == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.accent))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 180, alignment: .leading)
    }

    /// Expanded shared panel: custom time picker (when active) + tag chips.
    private var sharedDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            if case let .custom(date) = model.time {
                DatePicker(
                    "When",
                    selection: Binding(
                        get: { date },
                        set: { model.time = .custom($0) },
                    ),
                    in: ...Date.now,
                )
                .font(.footnote.weight(.semibold))
                .datePickerStyle(.compact)
            }

            FlowLayout(spacing: 6) {
                ForEach(allTagChoices, id: \.self) { tag in
                    let on = model.tags.contains(tag)
                    Button {
                        withAnimation(.snappy) {
                            if on { model.tags.remove(tag) } else { model.tags.insert(tag) }
                        }
                    } label: {
                        Text(verbatim: "#\(tag)")
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(
                                on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color(.secondarySystemFill)),
                                in: Capsule(),
                            )
                            .foregroundStyle(on ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var allTagChoices: [String] {
        tagSuggestions + model.tags.filter { !tagSuggestions.contains($0) }.sorted()
    }

    // MARK: Commit

    private var commitButton: some View {
        Button(action: onCommit) {
            Text(model.staged.count == 1 ? String(localized: "Log Dose") : String(localized: "Log \(model.staged.count) Doses"))
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Theme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!model.isCommittable)
        .opacity(model.isCommittable ? 1 : 0.5)
    }
}

// MARK: - Staged Dose Editor

/// Inline per-dose editor — Draft B's composer relocated into the tray.
/// Amount, unit, route, per-dose time override, and note; opened by tapping a
/// tray row, with the amount field focused automatically for drafts.
private struct StagedDoseEditor: View {
    @Binding var item: StagedDose
    let trayTime: TrayTime
    let onCollapse: () -> Void
    let onRemove: () -> Void

    @State private var amountText = ""
    @FocusState private var amountFocused: Bool

    private static let unitChoices = ["µg", "mg", "g", "mL"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            HStack(spacing: 8) {
                stepButton(systemImage: "minus") {
                    setAmount(max(0, item.amount - amountStep))
                }
                amountField
                stepButton(systemImage: "plus") {
                    setAmount(item.amount + amountStep)
                }
                if item.count > 1 {
                    Text(verbatim: "× \(item.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }

            HStack(spacing: 8) {
                routeMenu
                timeOverrideMenu
            }

            TextField("Add note…", text: $item.note, axis: .vertical)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: 12))

            if let override = item.timeOverride {
                DatePicker(
                    "Time",
                    selection: Binding(
                        get: { override },
                        set: { item.timeOverride = $0 },
                    ),
                    in: ...Date.now,
                )
                .font(.footnote.weight(.semibold))
                .datePickerStyle(.compact)
            }
        }
        .padding(12)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 18))
        .onAppear {
            amountText = item.amount > 0 ? item.amount.doseFormatted : ""
            if item.amount <= 0 { amountFocused = true }
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(item.color)
                .frame(width: 10, height: 10)
            Text(item.substanceName)
                .font(.headline)
            Spacer()
            Button(action: onCollapse) {
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse")
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove")
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onCollapse)
    }

    private var amountField: some View {
        HStack(spacing: 4) {
            TextField("0", text: $amountText)
                .keyboardType(.decimalPad)
                .focused($amountFocused)
                .multilineTextAlignment(.center)
                .font(.title3.weight(.semibold))
                .onChange(of: amountText) {
                    item.amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
                }
            Menu {
                ForEach(unitMenuChoices, id: \.self) { unit in
                    Button {
                        item.unit = unit
                    } label: {
                        if unit == item.unit {
                            Label(unit, systemImage: "checkmark")
                        } else {
                            Text(unit)
                        }
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Text(item.unit)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.secondaryLabel)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .frame(maxWidth: .infinity)
        .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private var unitMenuChoices: [String] {
        Self.unitChoices.contains(item.unit) ? Self.unitChoices : [item.unit] + Self.unitChoices
    }

    private func stepButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 42)
                .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    /// Magnitude-aware step so µg- and g-scale doses both nudge sensibly.
    private var amountStep: Double {
        switch item.amount {
        case ..<2: 0.25
        case ..<10: 1
        case ..<100: 5
        case ..<1_000: 25
        default: 100
        }
    }

    private func setAmount(_ value: Double) {
        item.amount = value
        amountText = value > 0 ? value.doseFormatted : ""
    }

    private var routeMenu: some View {
        Menu {
            ForEach(RouteOfAdministration.allCases) { route in
                Button {
                    item.route = route
                } label: {
                    if route == item.route {
                        Label(String(localized: route.localizedName), systemImage: "checkmark")
                    } else {
                        Text(route.localizedName)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.circle")
                    .imageScale(.small)
                Text(item.route.localizedName)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemFill), in: Capsule())
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    /// Per-dose time: shared tray time by default, overridable for staggered
    /// stacks ("the kratom was an hour before everything else").
    private var timeOverrideMenu: some View {
        Menu {
            Button {
                withAnimation(.snappy) { item.timeOverride = nil }
            } label: {
                if item.timeOverride == nil {
                    Label("Shared time", systemImage: "checkmark")
                } else {
                    Text("Shared time")
                }
            }
            Button {
                withAnimation(.snappy) { item.timeOverride = trayTime.resolved }
            } label: {
                Label("Custom…", systemImage: "clock")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .imageScale(.small)
                Text(item.timeOverride == nil ? trayTime.chipLabel : item.timeOverride!.formatted(.dateTime.hour().minute()))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                item.timeOverride == nil ? AnyShapeStyle(Color(.secondarySystemFill)) : AnyShapeStyle(Color.orange.opacity(0.18)),
                in: Capsule(),
            )
            .foregroundStyle(item.timeOverride == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.orange))
        }
        .buttonStyle(.plain)
    }
}
