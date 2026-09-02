import SwiftData
import SwiftUI

// MARK: - Routes

/// Push targets inside the quick-log Edit sheet for the dock's pickers and
/// forms. `editLabel` carries the label's position in the list.
enum DockEditRoute: Hashable {
    case addShortcut
    case addLabel
    case editLabel(index: Int)
}

// MARK: - Sections

/// The Edit sheet's "Dock Shortcuts" section: the slots in order, reorderable
/// and deletable, plus an add row while a slot is free.
struct DockShortcutsSection: View {
    @Binding var path: NavigationPath
    @State private var preferences = DockPreferences.shared
    @State private var customStore = CustomSubstanceStore.shared

    var body: some View {
        Section {
            ForEach(preferences.shortcuts) { shortcut in
                Label {
                    Text(title(for: shortcut))
                } icon: {
                    Image(systemName: shortcut.systemImage)
                }
            }
            .onMove { source, destination in
                preferences.shortcuts.move(fromOffsets: source, toOffset: destination)
            }
            .onDelete { offsets in
                preferences.shortcuts.remove(atOffsets: offsets)
            }

            if preferences.canAddShortcut {
                Button {
                    path.append(DockEditRoute.addShortcut)
                } label: {
                    Label("Add Shortcut…", systemImage: "plus.circle")
                }
            }
        } header: {
            Text("Dock Shortcuts")
                .textCase(nil)
        } footer: {
            Text("Up to three, shown at the left of the dock.")
        }
    }

    private func title(for shortcut: DockShortcut) -> String {
        if let substance = shortcut.favoriteSubstance {
            return customStore.displayName(for: substance)
        }
        return shortcut.fixedTitle.map { String(localized: $0) } ?? ""
    }
}

/// The Edit sheet's "Dock Label" section: the fallback list in order — the
/// first label that applies is shown. Tap a row to edit it.
struct DockLabelsSection: View {
    @Binding var path: NavigationPath
    @State private var preferences = DockPreferences.shared

    var body: some View {
        Section {
            ForEach(Array(preferences.labels.enumerated()), id: \.element) { index, label in
                Button {
                    path.append(DockEditRoute.editLabel(index: index))
                } label: {
                    DockLabelRow(label: label)
                }
                .foregroundStyle(.primary)
            }
            .onMove { source, destination in
                preferences.labels.move(fromOffsets: source, toOffset: destination)
            }
            .onDelete { offsets in
                preferences.labels.remove(atOffsets: offsets)
            }

            Button {
                path.append(DockEditRoute.addLabel)
            } label: {
                Label("Add Label…", systemImage: "plus.circle")
            }
        } header: {
            Text("Dock Label")
                .textCase(nil)
        } footer: {
            Text("The first label that applies is shown. When none does, the dock shows “—”.")
        }
    }
}

/// One label row: its kind and, under it, what it says or when it applies.
private struct DockLabelRow: View {
    let label: DockLabel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label.kind.title)
            Text(detail)
                .captionSecondary()
        }
    }

    private var detail: String {
        switch label {
        case let .text(string):
            string
        case let .timed(string, startHour, endHour):
            "\(string) · \(DockHour.label(startHour))–\(DockHour.label(endHour))"
        case let .timer(timer):
            String(localized: timer.title)
        case .due:
            String(localized: "“2 due”, or the med’s name when one is due")
        }
    }
}

// MARK: - Shortcut Picker

/// Pushed from "Add Shortcut…": the fixed kinds not yet in the dock, then the
/// user's favorites and recent substances as one-tap staging shortcuts.
struct DockShortcutPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var preferences = DockPreferences.shared
    @State private var customStore = CustomSubstanceStore.shared
    @Query(sort: [SortDescriptor(\FavoriteSubstance.sortOrder), SortDescriptor(\FavoriteSubstance.createdAt, order: .reverse)])
    private var favorites: [FavoriteSubstance]
    @Query(sort: \QuickLogDose.lastUsedAt, order: .reverse) private var recentDoses: [QuickLogDose]

    /// How many recent substances to offer under the favorites.
    private static let recentLimit = 8

    var body: some View {
        List {
            Section {
                ForEach(availableKinds) { shortcut in
                    Button {
                        add(shortcut)
                    } label: {
                        Label {
                            Text(shortcut.fixedTitle ?? "")
                        } icon: {
                            Image(systemName: shortcut.systemImage)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }

            if !substanceChoices.isEmpty {
                Section {
                    ForEach(substanceChoices, id: \.self) { substance in
                        Button {
                            add(.favorite(substance: substance))
                        } label: {
                            Label {
                                Text(customStore.displayName(for: substance))
                            } icon: {
                                Image(systemName: "star")
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("Stage a Substance")
                        .textCase(nil)
                } footer: {
                    Text("Opens Log with that substance staged at its usual dose. Nothing is logged until you commit.")
                }
            }
        }
        .navigationTitle("Add Shortcut")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var availableKinds: [DockShortcut] {
        DockShortcut.fixedKinds.filter { !preferences.shortcuts.contains($0) }
    }

    /// Favorites first, then recents, deduplicated by canonical name and
    /// excluding substances already in a slot.
    private var substanceChoices: [String] {
        var seen = Set<String>()
        var names: [String] = []
        let taken = Set(preferences.shortcuts.compactMap { $0.favoriteSubstance?.lowercased() })
        for name in favorites.map(\.substance) + recentDoses.prefix(Self.recentLimit * 4).map(\.substance) {
            let key = name.lowercased()
            guard !taken.contains(key), seen.insert(key).inserted else { continue }
            names.append(name)
            if names.count >= favorites.count + Self.recentLimit { break }
        }
        return names
    }

    private func add(_ shortcut: DockShortcut) {
        preferences.addShortcut(shortcut)
        dismiss()
    }
}

// MARK: - Label Form

/// Pushed from "Add Label…" and from a label row: one form for every kind,
/// with the kind picker on top. Saving appends a new label or replaces the
/// edited one in place.
struct DockLabelForm: View {
    /// The list position being edited, or `nil` when adding.
    let index: Int?

    @Environment(\.dismiss) private var dismiss
    @State private var preferences = DockPreferences.shared
    @State private var kind: DockLabel.Kind
    @State private var text: String
    @State private var startHour: Int
    @State private var endHour: Int
    @State private var timer: DockTimer

    init(index: Int?, existing: DockLabel?) {
        self.index = index
        _kind = State(initialValue: existing?.kind ?? .text)
        var text = ""
        var startHour = 7
        var endHour = 10
        var timer = DockTimer.sinceLastDose
        switch existing {
        case let .text(string): text = string
        case let .timed(string, start, end): (text, startHour, endHour) = (string, start, end)
        case let .timer(kind): timer = kind
        case .due, nil: break
        }
        _text = State(initialValue: text)
        _startHour = State(initialValue: startHour)
        _endHour = State(initialValue: endHour)
        _timer = State(initialValue: timer)
    }

    var body: some View {
        Form {
            Section {
                Picker("Kind", selection: $kind) {
                    ForEach(DockLabel.Kind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
            }

            switch kind {
            case .text:
                textSection
            case .timed:
                textSection
                hoursSection
            case .timer:
                Section {
                    Picker("Timer", selection: $timer) {
                        ForEach(DockTimer.allCases, id: \.self) { timer in
                            Text(timer.title).tag(timer)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            case .due:
                Section {
                    Text("Shows “2 due”, or the med’s name when exactly one is due. Falls through to the next label otherwise.")
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
        .navigationTitle(index == nil ? "Add Label" : "Edit Label")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    save()
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.glassProminent)
                .disabled(!isValid)
                .accessibilityLabel("Save")
            }
        }
    }

    private var textSection: some View {
        Section {
            TextField("Log a dose", text: $text)
                .onChange(of: text) {
                    if text.count > DockLabel.maxTextLength {
                        text = String(text.prefix(DockLabel.maxTextLength))
                    }
                }
        } footer: {
            Text("Up to \(DockLabel.maxTextLength) characters.")
        }
    }

    private var hoursSection: some View {
        Section {
            Picker("From", selection: $startHour) {
                ForEach(0 ..< 24, id: \.self) { hour in
                    Text(DockHour.label(hour)).tag(hour)
                }
            }
            Picker("Until", selection: $endHour) {
                ForEach(0 ..< 24, id: \.self) { hour in
                    Text(DockHour.label(hour)).tag(hour)
                }
            }
        } footer: {
            Text("Shown while the time is inside this range. A range ending before it starts wraps past midnight.")
        }
    }

    private var isValid: Bool {
        switch kind {
        case .text, .timed: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .timer, .due: true
        }
    }

    private var composed: DockLabel {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return switch kind {
        case .text: .text(trimmed)
        case .timed: .timed(trimmed, startHour: startHour, endHour: endHour)
        case .timer: .timer(timer)
        case .due: .due
        }
    }

    private func save() {
        if let index, preferences.labels.indices.contains(index) {
            preferences.labels[index] = composed
        } else {
            preferences.addLabel(composed)
        }
        dismiss()
    }
}

// MARK: - Presentation helpers

extension DockLabel {
    /// The label kinds as the form offers them.
    enum Kind: String, CaseIterable, Identifiable {
        case text
        case timed
        case timer
        case due

        var id: String {
            rawValue
        }

        var title: LocalizedStringResource {
            switch self {
            case .text: "Text"
            case .timed: "Timed Text"
            case .timer: "Timer"
            case .due: "Meds Due"
            }
        }
    }

    var kind: Kind {
        switch self {
        case .text: .text
        case .timed: .timed
        case .timer: .timer
        case .due: .due
        }
    }
}

extension DockTimer {
    var title: LocalizedStringResource {
        switch self {
        case .sinceLastDose: "Since last dose"
        case .untilNextMed: "Until next med"
        }
    }
}

/// Locale-aware hour labels for the timed-range pickers ("7 AM", "19:00").
enum DockHour {
    static func label(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(.dateTime.hour())
    }
}
