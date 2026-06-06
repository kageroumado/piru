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
    var colorHex: String?
    var librarySubstance: Substance?
    /// Staged from the Daily routine card. Daily items keep their own surface,
    /// so they don't mint quick-log chips on commit.
    var isFromDailySet = false
    /// Carried from `DailyDoseItem.isBackgroundMed` onto the committed entry.
    var isBackgroundMed = false

    var totalAmount: Double {
        amount * Double(count)
    }

    var color: Color {
        colorHex.map { Color(hex: $0) } ?? .gray
    }

    /// The library's reference dose for this item's route, in this item's
    /// unit — anchors stepper increments and draft prefills to what a person
    /// actually takes (LSD steps in 10 µg, not 0.25 µg).
    var referenceDose: Double? {
        Self.lookupReferenceDose(substance: librarySubstance, route: route, unit: unit)
    }

    static func lookupReferenceDose(substance: Substance?, route: RouteOfAdministration, unit: String) -> Double? {
        guard let substance,
              let routeInfo = substance.routes.first(where: { $0.route == route }),
              routeInfo.unit == unit
        else { return nil }
        let doses = routeInfo.doses
        return doses.common?.lowerBound
            ?? doses.light?.upperBound
            ?? doses.strong?.lowerBound
            ?? doses.threshold
            ?? doses.heavy
    }
}

// MARK: - Tray Time

/// The tray-wide "When" — the *only* time control in the quick-log flow,
/// applied to every staged dose. Offsets resolve at commit time, so a tray
/// left open doesn't drift. A staggered stack is two commits.
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

    /// Haptic triggers — bumped on discrete staging events so the view can
    /// attach `.sensoryFeedback` without coupling feedback to every tap.
    private(set) var stageTick = 0
    private(set) var incrementTick = 0

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

    /// Stage a chip; re-staging the same chip increments its count ("took two
    /// pills") — one entry of amount × count at commit, never two entries.
    func stage(
        substance: String,
        route: RouteOfAdministration,
        amount: Double,
        unit: String,
        colorHex: String?,
        librarySubstance: Substance?,
        isFromDailySet: Bool = false,
        isBackgroundMed: Bool = false,
    ) {
        if let index = stagedIndex(substance: substance, route: route, amount: amount, unit: unit) {
            staged[index].count += 1
            incrementTick += 1
        } else {
            staged.append(StagedDose(
                substanceName: substance,
                amount: amount,
                unit: unit,
                route: route,
                colorHex: colorHex,
                librarySubstance: librarySubstance,
                isFromDailySet: isFromDailySet,
                isBackgroundMed: isBackgroundMed,
            ))
            stageTick += 1
        }
    }

    /// Stage a draft (from search / the ⋯ chip) and open it for editing.
    /// Prefilled with the library's common dose when one is known — the
    /// editor focuses the amount field only when it opens empty.
    func stageDraft(substance: String, route: RouteOfAdministration, unit: String, colorHex: String?, librarySubstance: Substance?) {
        let draft = StagedDose(
            substanceName: substance,
            amount: StagedDose.lookupReferenceDose(substance: librarySubstance, route: route, unit: unit) ?? 0,
            unit: unit,
            route: route,
            colorHex: colorHex,
            librarySubstance: librarySubstance,
        )
        staged.append(draft)
        expandedItemID = draft.id
        stageTick += 1
    }

    func remove(_ item: StagedDose) {
        staged.removeAll { $0.id == item.id }
        if expandedItemID == item.id { expandedItemID = nil }
    }

    /// Amounts match on their *display* form — the user-perceived identity of
    /// a chip. Exact-double matching breaks when the editor round-trips an
    /// amount through its text field (31.700000000000003 → "31.7" → 31.7).
    private func stagedIndex(substance: String, route: RouteOfAdministration, amount: Double, unit: String) -> Int? {
        staged.firstIndex {
            $0.substanceName.lowercased() == substance.lowercased()
                && $0.route == route
                && $0.amount.doseFormatted == amount.doseFormatted
                && $0.unit == unit
        }
    }
}

// MARK: - Tray View

/// The commit surface for quick logging: staged doses, shared When/Tags/
/// Location controls, a live interaction check, and the Log button. Items
/// expand inline for per-dose enrichment — never a second sheet.
///
/// Renders content only; the dock in `QuickLogView` owns the glass surface,
/// so nothing here layers material on material.
struct DoseTrayView: View {
    @Bindable var model: DoseTrayModel
    let tagSuggestions: [String]
    let onAddMore: () -> Void
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
                    StagedDoseEditor(item: $item) {
                        withAnimation(.snappy) { model.expandedItemID = nil }
                    } onRemove: {
                        withAnimation(.snappy) { model.remove(item) }
                    }
                    .padding(.vertical, 6)
                } else {
                    TrayRow(dose: item) {
                        withAnimation(.snappy) { model.expandedItemID = item.id }
                    } onDelete: {
                        withAnimation(.snappy) { model.remove(item) }
                    }
                }
                Divider().padding(.leading, 20)
            }

            addMoreRow

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
        .sensoryFeedback(.selection, trigger: model.time)
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerView { picked in
                model.location = picked
            }
        }
    }

    // MARK: Rows

    /// Re-opens search inside the dock — staging never requires dismissing
    /// the tray. The plus is sized to the row dots so the labels align.
    private var addMoreRow: some View {
        Button(action: onAddMore) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 9)
                Text("Add another…")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(Theme.accent)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            Text(commitLabel)
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

    /// The CTA echoes a backdate ("Log 2 · 1h ago") so a stale time can't be
    /// committed blind.
    private var commitLabel: String {
        let base = model.staged.count == 1
            ? String(localized: "Log Dose")
            : String(localized: "Log \(model.staged.count) Doses")
        return model.time.isNow ? base : "\(base) · \(model.time.chipLabel)"
    }
}

// MARK: - Tray Row

/// A staged dose as a compact row: chevron-only affordance — tap expands the
/// inline editor, swipe left reveals delete (with full-swipe to remove).
private struct TrayRow: View {
    let dose: StagedDose
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0

    private static let revealWidth: CGFloat = 64
    private static let fullSwipeThreshold: CGFloat = 180

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteBackdrop
            rowContent
                .offset(x: offset)
        }
        // The delete backdrop fills the row height — without this the
        // greedy frame stretches every row to fill the dock's safe area.
        .fixedSize(horizontal: false, vertical: true)
        .clipped()
        .gesture(swipeGesture)
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dose.color)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "\(dose.substanceName) \(countPrefix)\(dose.amount.doseFormatted) \(dose.unit)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Text(dose.route.localizedName)
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
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture {
            if offset != 0 {
                withAnimation(.snappy) { offset = 0 }
            } else {
                onTap()
            }
        }
    }

    private var deleteBackdrop: some View {
        Button(action: onDelete) {
            Image(systemName: "trash.fill")
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: Self.revealWidth)
                .frame(maxHeight: .infinity)
                .background(.red)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove")
        .opacity(offset < -1 ? 1 : 0)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                offset = min(0, value.translation.width)
            }
            .onEnded { value in
                if offset < -Self.fullSwipeThreshold || value.predictedEndTranslation.width < -Self.fullSwipeThreshold * 1.5 {
                    onDelete()
                } else if offset < -Self.revealWidth / 2 {
                    withAnimation(.snappy) { offset = -Self.revealWidth }
                } else {
                    withAnimation(.snappy) { offset = 0 }
                }
            }
    }

    private var countPrefix: String {
        dose.count > 1 ? "\(dose.count) × " : ""
    }
}

// MARK: - Staged Dose Editor

/// Inline per-dose editor: rows directly on the tray surface — fields use
/// fills, never their own card, so the dock stays a single material. Amount,
/// unit, route, and note; time lives only on the tray's shared When chip.
private struct StagedDoseEditor: View {
    @Binding var item: StagedDose
    let onCollapse: () -> Void
    let onRemove: () -> Void

    @State private var amountText = ""
    /// Suppresses the text→amount sync when `amountText` is being set *from*
    /// the model (onAppear / stepper), so opening the editor never rewrites
    /// the staged amount through display rounding.
    @State private var suppressAmountSync = false
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
                noteField
            }
        }
        .onAppear {
            if item.amount > 0 {
                suppressAmountSync = true
                amountText = item.amount.doseFormatted
            }
            if item.amount <= 0 { amountFocused = true }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(item.color)
                .frame(width: 9, height: 9)
            Text(item.substanceName)
                .font(.headline)
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove")
            Button(action: onCollapse) {
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse")
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onCollapse)
    }

    /// Styled like every other control pill in the tray.
    private var noteField: some View {
        TextField("Add note…", text: $item.note)
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemFill), in: Capsule())
    }

    private var amountField: some View {
        HStack(spacing: 4) {
            TextField("0", text: $amountText)
                .keyboardType(.decimalPad)
                .focused($amountFocused)
                .multilineTextAlignment(.center)
                .font(.title3.weight(.semibold))
                .onChange(of: amountText) {
                    if suppressAmountSync {
                        suppressAmountSync = false
                        return
                    }
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

    /// Stepper increment anchored to the substance's reference dose when the
    /// library knows one (LSD → 10 µg, pregabalin → 25 mg), falling back to a
    /// magnitude table for unknowns.
    private var amountStep: Double {
        if let reference = item.referenceDose {
            return Self.niceStep(for: reference)
        }
        return switch item.amount {
        case ..<2: 0.25
        case ..<10: 1
        case ..<100: 5
        case ..<1_000: 25
        default: 100
        }
    }

    /// ≈10% of the reference dose, snapped to a 1 / 2.5 / 5 × 10ᵏ series.
    static func niceStep(for reference: Double) -> Double {
        guard reference > 0 else { return 1 }
        let raw = reference / 10
        let magnitude = pow(10, floor(log10(raw)))
        let normalized = raw / magnitude
        let snapped: Double = normalized < 1.75 ? 1 : normalized < 3.75 ? 2.5 : normalized < 7.5 ? 5 : 10
        return snapped * magnitude
    }

    private func setAmount(_ value: Double) {
        item.amount = value
        let newText = value > 0 ? value.doseFormatted : ""
        // Only arm the suppress flag when onChange will actually fire,
        // otherwise it would stay latched and swallow the next keystroke.
        if newText != amountText {
            suppressAmountSync = true
            amountText = newText
        }
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
}
