import SwiftData
import SwiftUI

/// The add / edit sheet for one timestamped session note: the text first, then
/// the optional structure, then the moment it belongs to. Presented via
/// `SheetRoute.sessionNoteEditor` (the ⋯ menu, a note row, the dock shortcut,
/// a check-in notification).
///
/// **The structure is shaped by what the session carries** (``CheckInForm``).
/// A medication asks whether it worked; a psychedelic asks how strong it is;
/// a session carrying both asks each question once, with the substance named.
/// Someone mid-experience is not going to read a form — the front of the sheet
/// is a handful of taps, and everything that is only sometimes relevant sits
/// behind a disclosure.
struct SessionNoteEditor: View {
    let session: Session
    /// The note to edit; nil composes a new one.
    var note: SessionNote?
    /// Kind for a new note (ignored when editing).
    var kind: SessionNote.Kind = .observation
    /// Vitals the session screen already fetched, so the heart-rate snapshot
    /// needs no second HealthKit read. Nil when opened from elsewhere.
    var vitals: SessionVitals?

    @Environment(\.appNavigator) private var navigator
    @State private var draft: SessionNoteDraft
    @State private var showShulginInfo = false
    @State private var confirmDelete = false
    @State private var showSideEffects = false
    @State private var form = CheckInForm.unresolved
    @FocusState private var textFocused: Bool
    @AppStorage("showSessionVitals", store: UserDefaults(suiteName: "group.dev.yumeji.piru"))
    private var showSessionVitals = false

    init(session: Session, note: SessionNote? = nil, kind: SessionNote.Kind = .observation, vitals: SessionVitals? = nil) {
        self.session = session
        self.note = note
        self.kind = kind
        self.vitals = vitals
        _draft = State(initialValue: SessionNoteDraft(session: session, existing: note, kind: kind))
    }

    private var title: LocalizedStringKey {
        switch (draft.isEditing, draft.kind) {
        case (true, .summary): "Summary"
        case (true, _): "Edit Note"
        case (false, .summary): "Summary"
        case (false, .checkIn): "How is it going?"
        case (false, .observation): "Add Note"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                textSection
                if draft.kind != .summary {
                    if form.asksWorked { workedSection }
                    if form.asksIntensity { shulginSection }
                    moodEnergySection
                    if !form.highlights.isEmpty { highlightsSection }
                    if !form.sideEffects.isEmpty { sideEffectsSection }
                    descriptorSection
                }
                timeSection
                if draft.isEditing {
                    Section {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Delete Note", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { navigator.dismiss() } label: {
                        Image(systemName: "xmark").font(.body.weight(.semibold))
                    }
                    .accessibilityLabel(Text("Cancel"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        draft.save()
                        navigator.dismiss()
                    } label: {
                        Image(systemName: "checkmark").font(.body.weight(.semibold))
                    }
                    .skinButtonStyle(.prominent)
                    .tint(Theme.accent)
                    .disabled(!draft.hasContent)
                    .accessibilityLabel(Text("Save"))
                }
            }
            .confirmationDialog("Delete this note?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Note", role: .destructive) {
                    draft.delete()
                    navigator.dismiss()
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            await SubstanceStore.shared.ensureAllLoaded()
            form = CheckInForm.build(for: session)
            await draft.loadHeartRate(showSessionVitals: showSessionVitals, provided: vitals)
        }
        .onChange(of: draft.timestamp) { _, _ in
            if !draft.isEditing { draft.refreshHeartRate() }
        }
        .onAppear { textFocused = true }
    }

    // MARK: - Sections

    private var textSection: some View {
        Section {
            TextEditor(text: $draft.text)
                .focused($textFocused)
                .frame(minHeight: 96)
                .overlay(alignment: .topLeading) {
                    if draft.text.isEmpty {
                        Text(draft.kind == .summary ? "How was it, overall?" : "What do you notice?")
                            .foregroundStyle(.tertiary)
                            .padding(.top, Spacing.md)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    /// "Did it work?" — the reference point is this person's own usual result,
    /// which is why the words are comparative and there is no scale to read.
    private var workedSection: some View {
        Section {
            Picker("Did it work?", selection: $draft.worked) {
                Text("—").tag(Int?.none)
                ForEach(WorkedScale.levels, id: \.self) { level in
                    if let label = WorkedScale.shortLabel(level) {
                        Text(label).tag(Int?.some(level))
                    }
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            sectionHeader("Did it work?", tag: form.tag(form.workedNames))
        }
    }

    /// The effects this class is taken for, one tap each. They are ordinary
    /// descriptors — the same vocabulary the picker below offers in full.
    private var highlightsSection: some View {
        Section {
            DescriptorToggleChips(slugs: form.highlights, draft: draft)
        } header: {
            Text("Noticing")
        }
    }

    /// Collapsed by default: the list is long, most of it is absent most of the
    /// time, and an open one would be the first thing between someone and Save.
    private var sideEffectsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showSideEffects) {
                DescriptorToggleChips(slugs: form.sideEffects, draft: draft)
                ForEach(draft.selected(among: form.sideEffects), id: \.self) { slug in
                    if let line = CheckInLenses.reassurance(for: slug) {
                        Label {
                            Text(line)
                        } icon: {
                            Image(systemName: "info.circle")
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                        .padding(.top, Spacing.xs)
                    }
                }
            } label: {
                HStack {
                    Text("Any side effects?")
                    Spacer()
                    let count = draft.selected(among: form.sideEffects).count
                    if count > 0 {
                        Text("\(count)")
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
            }
        }
    }

    /// A section header with an optional trailing substance name — present only
    /// when the session carries more than one substance and the question would
    /// otherwise be ambiguous about which.
    private func sectionHeader(_ title: LocalizedStringKey, tag: String?) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let tag {
                Text(tag)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
                    .textCase(nil)
            }
        }
    }

    private var shulginSection: some View {
        Section {
            Picker("Intensity", selection: $draft.shulgin) {
                Text("—").tag(Int?.none)
                ForEach(Array(ShulginScale.levels), id: \.self) { level in
                    Text(verbatim: ShulginScale.glyph(level) ?? "").tag(Int?.some(level))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            HStack {
                Text("Shulgin scale")
                if let tag = form.tag(form.intensityNames) {
                    Text(tag)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryLabel)
                        .textCase(nil)
                }
                Spacer()
                Button {
                    showShulginInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .accessibilityLabel(Text("About the Shulgin scale"))
                .popover(isPresented: $showShulginInfo) {
                    ShulginInfoView()
                        .presentationCompactAdaptation(.popover)
                }
            }
        }
    }

    @ViewBuilder
    private var moodEnergySection: some View {
        if form.showsMood || form.showsEnergy {
            Section {
                if form.showsMood {
                    SevenStepRow(title: "Mood", low: "Low", high: "High", value: $draft.mood)
                }
                if form.showsEnergy {
                    SevenStepRow(title: "Energy", low: "Sedated", high: "Stimulated", value: $draft.energy)
                }
            } footer: {
                Text("Optional — leave them where they are to record nothing.")
            }
        }
    }

    private var descriptorSection: some View {
        Section {
            NavigationLink {
                DescriptorPickerView(selection: $draft.descriptors)
            } label: {
                HStack {
                    Text("Descriptors")
                    Spacer()
                    if !draft.descriptors.isEmpty {
                        Text("\(draft.descriptors.count)")
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
            }
            if !draft.descriptors.isEmpty {
                DescriptorChips(ids: draft.descriptors) { id in
                    draft.descriptors.removeAll { $0 == id }
                }
            }
        } footer: {
            Text("What you noticed, in a shared vocabulary — so a later you can search for the moment the geometry started.")
        }
    }

    private var timeSection: some View {
        Section {
            DatePicker("Time", selection: $draft.timestamp, displayedComponents: [.date, .hourAndMinute])
            if let bpm = draft.heartRate {
                LabeledContent("Heart rate") {
                    Text("\(Int(bpm.rounded())) bpm")
                        .foregroundStyle(VitalsPalette.heart)
                        .monospacedDigit()
                }
            }
        } footer: {
            if draft.heartRate != nil {
                Text("The Apple Health sample nearest this time.")
            }
        }
    }
}

// MARK: - Seven-step slider row

/// A −3…+3 slider that records nothing until it is moved: nil renders at the
/// center, dimmed; a value shows as a signed number with a clear button.
private struct SevenStepRow: View {
    let title: LocalizedStringKey
    let low: LocalizedStringKey
    let high: LocalizedStringKey
    @Binding var value: Int?

    private var sliderValue: Binding<Double> {
        Binding(
            get: { Double(value ?? 0) },
            set: { value = Int($0.rounded()) },
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(title)
                Spacer()
                if let value {
                    Text(verbatim: TripReport.signed(value))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                    Button {
                        self.value = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear"))
                } else {
                    Text("Not recorded")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Slider(value: sliderValue, in: -3 ... 3, step: 1) {
                Text(title)
            } minimumValueLabel: {
                Text(low).font(.caption2).foregroundStyle(Theme.secondaryLabel)
            } maximumValueLabel: {
                Text(high).font(.caption2).foregroundStyle(Theme.secondaryLabel)
            }
            .tint(value == nil ? Color.secondary.opacity(Theme.Opacity.muted) : Theme.accent)
        }
        .padding(.vertical, Spacing.xxs)
    }
}

// MARK: - Shulgin info

/// The scale as PiHKAL states it — cited by name, quoted in substance.
private struct ShulginInfoView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("The Shulgin Rating Scale")
                .cardTitle()
            Group {
                row("±", "Threshold — a real effect, its nature not yet clear.")
                row("+", "Definite, but the nature or duration not yet clear; ordinary activity possible.")
                row("++", "Unmistakable effect and duration; ordinary activity possible but disinclined.")
                row("+++", "Full effect; the experience is the thing, ordinary activity set aside.")
                row("++++", "A rare, peak, transcendental state — a serene and all-encompassing experience; the person, and the rating, are describing something outside the ordinary scale.")
            }
            Text("Shulgin & Shulgin, PiHKAL: A Chemical Love Story (1991), \"The Shulgin Rating Scale\".")
                .captionSecondary()
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: 340)
    }

    private func row(_ glyph: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.lg) {
            Text(verbatim: glyph)
                .font(.subheadline.weight(.bold).monospaced())
                .frame(width: 44, alignment: .trailing)
                .foregroundStyle(Theme.accent)
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Toggle chips

/// A row of one-tap descriptor chips built from curated slugs: filled when the
/// note carries that concept, outlined when it does not.
///
/// A slug the loaded vocabulary cannot resolve draws nothing, so a database
/// older than a curated list degrades to a shorter row rather than a dead chip.
private struct DescriptorToggleChips: View {
    let slugs: [String]
    @Bindable var draft: SessionNoteDraft
    @State private var ontology = SubjectiveEffectOntology.shared

    private var resolved: [(slug: String, name: String)] {
        slugs.compactMap { slug in ontology.concept(slug: slug).map { (slug: slug, name: $0.name) } }
    }

    var body: some View {
        FlowLayout(spacing: Spacing.sm) {
            ForEach(resolved, id: \.slug) { slug, name in
                let isOn = draft.hasDescriptor(slug: slug)
                Button {
                    draft.toggleDescriptor(slug: slug)
                } label: {
                    Text(name)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            Theme.accent.opacity(isOn ? Theme.Opacity.tint : 0),
                            in: skinChipShape(),
                        )
                        .overlay {
                            skinChipShape()
                                .stroke(
                                    isOn ? Theme.accent : Color.secondary.opacity(Theme.Opacity.muted),
                                    lineWidth: 1,
                                )
                        }
                        .foregroundStyle(isOn ? Theme.accent : Theme.secondaryLabel)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, Spacing.xs)
        .animation(.smooth(duration: 0.15), value: draft.descriptors)
    }
}

// MARK: - Chips

/// The chosen descriptors as removable chips (ids resolved through the
/// vocabulary; an id it no longer resolves draws no chip).
struct DescriptorChips: View {
    let ids: [String]
    var onRemove: ((String) -> Void)?
    @State private var ontology = SubjectiveEffectOntology.shared

    private var resolved: [(id: String, name: String)] {
        ids.compactMap { id in ontology.name(for: id).map { (id: id, name: $0) } }
    }

    var body: some View {
        FlowLayout(spacing: Spacing.sm) {
            ForEach(resolved, id: \.id) { id, name in
                HStack(spacing: Spacing.xs) {
                    Text(name)
                        .font(.caption.weight(.medium))
                    if onRemove != nil {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(Theme.accent.opacity(Theme.Opacity.tint), in: skinChipShape())
                .foregroundStyle(Theme.accent)
                .contentShape(Capsule())
                .onTapGesture { onRemove?(id) }
                .accessibilityAddTraits(onRemove == nil ? [] : .isButton)
                .accessibilityHint(onRemove == nil ? Text("") : Text("Removes the descriptor"))
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}
