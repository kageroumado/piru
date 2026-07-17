import Foundation

/// Observable singleton recording the substances a user has tapped from search
/// results — the "Recently Searched" list on the Search landing. Stored as a
/// capped, most-recent-first list of canonical substance names in the App Group
/// UserDefaults (same suite as the other stores).
///
/// This is search *history*, deliberately distinct from the dose-log "Recent"
/// list: it remembers what you looked up, not what you took.
@Observable @MainActor
final class SearchHistoryStore {
    static let shared = SearchHistoryStore()

    private static let storageKey = "piru.searchHistory.v1"
    private static let appGroupID = "group.dev.yumeji.piru"
    private static let limit = 10

    /// Canonical substance names, most-recent first.
    private(set) var recent: [String] = []

    private let defaults: UserDefaults

    /// Designated init used by the shared singleton; tests use `forTesting`.
    private init(defaults: UserDefaults) {
        self.defaults = defaults
        load()
    }

    private convenience init() {
        let suite = UserDefaults(suiteName: Self.appGroupID) ?? .standard
        self.init(defaults: suite)
    }

    /// Test-only factory that takes an explicit UserDefaults instance.
    static func forTesting(defaults: UserDefaults) -> SearchHistoryStore {
        SearchHistoryStore(defaults: defaults)
    }

    // MARK: - Mutations

    /// Record a tapped substance by its canonical name. Moves an existing entry
    /// to the front (case-insensitive), caps the list, and persists.
    func record(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recent.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recent.insert(trimmed, at: 0)
        if recent.count > Self.limit {
            recent.removeLast(recent.count - Self.limit)
        }
        persist()
    }

    func clear() {
        recent.removeAll()
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else { return }
        recent = Array(decoded.prefix(Self.limit))
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(recent) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
