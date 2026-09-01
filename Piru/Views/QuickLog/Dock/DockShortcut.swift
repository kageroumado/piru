import Foundation
import Observation

// MARK: - Shortcut

/// One of the idle dock's leading shortcut slots (`Specs/quick-dock-action-bar.md`).
/// Every case resolves to an existing route; `favorite` stages that substance
/// in the Log sheet at its reference dose and never logs on its own.
nonisolated enum DockShortcut: Hashable, Codable, Identifiable {
    case inventory
    case addNote
    case interactions
    case timeline
    case myMeds
    /// Carries the **canonical** substance name — the lookup key `.quickLog`'s
    /// prefill expects.
    case favorite(substance: String)

    /// The out-of-the-box dock: one Inventory slot.
    static let defaultShortcuts: [DockShortcut] = [.inventory]

    /// The fixed kinds a user can add, in picker order. Favorites come from
    /// the user's own list, so they are offered separately.
    static let fixedKinds: [DockShortcut] = [.inventory, .addNote, .interactions, .timeline, .myMeds]

    var id: String {
        switch self {
        case .inventory: "inventory"
        case .addNote: "addNote"
        case .interactions: "interactions"
        case .timeline: "timeline"
        case .myMeds: "myMeds"
        case let .favorite(substance): "favorite:\(substance.lowercased())"
        }
    }

    var systemImage: String {
        switch self {
        case .inventory: "shippingbox"
        case .addNote: "note.text.badge.plus"
        case .interactions: "exclamationmark.triangle"
        case .timeline: "calendar.day.timeline.left"
        case .myMeds: "pills"
        case .favorite: "star.fill"
        }
    }

    /// Title for the fixed kinds. A favorite is titled by its substance's
    /// display name, which only the main actor can resolve — callers handle
    /// that case themselves.
    var fixedTitle: LocalizedStringResource? {
        switch self {
        case .inventory: "Inventory"
        case .addNote: "Add Note"
        case .interactions: "Interactions"
        case .timeline: "Timeline"
        case .myMeds: "My Meds"
        case .favorite: nil
        }
    }

    /// Adding a note needs a session to attach it to.
    var requiresActiveSession: Bool {
        self == .addNote
    }

    var favoriteSubstance: String? {
        if case let .favorite(substance) = self { return substance }
        return nil
    }
}

// MARK: - Preferences

/// The dock's user configuration — shortcut slots and the label fallback
/// list — persisted as JSON in the app-group defaults beside the dock's other
/// prefs. Reads are observable, so the accessory and the Edit sheet stay in
/// step without a refresh hook.
@Observable @MainActor
final class DockPreferences {
    static let shared = DockPreferences()

    /// Slots in the leading area; beyond this the label has no room left.
    static let maxShortcuts = 3

    static let suiteName = "group.dev.yumeji.piru"
    private static let shortcutsKey = "dockShortcuts"
    private static let labelsKey = "dockLabels"

    private let defaults: UserDefaults

    var shortcuts: [DockShortcut] {
        didSet { Self.store(shortcuts, key: Self.shortcutsKey, in: defaults) }
    }

    var labels: [DockLabel] {
        didSet { Self.store(labels, key: Self.labelsKey, in: defaults) }
    }

    init(defaults: UserDefaults = UserDefaults(suiteName: DockPreferences.suiteName) ?? .standard) {
        self.defaults = defaults
        shortcuts = Self.load([DockShortcut].self, key: Self.shortcutsKey, from: defaults) ?? DockShortcut.defaultShortcuts
        labels = Self.load([DockLabel].self, key: Self.labelsKey, from: defaults) ?? DockLabel.defaultLabels
    }

    /// Whether another slot can be added.
    var canAddShortcut: Bool {
        shortcuts.count < Self.maxShortcuts
    }

    /// Appends a shortcut, ignoring duplicates and the slot cap.
    func addShortcut(_ shortcut: DockShortcut) {
        guard canAddShortcut, !shortcuts.contains(shortcut) else { return }
        shortcuts.append(shortcut)
    }

    /// Appends a label, ignoring an exact duplicate (it could never be reached).
    func addLabel(_ label: DockLabel) {
        guard !labels.contains(label) else { return }
        labels.append(label)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func store(_ value: some Encodable, key: String, in defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
