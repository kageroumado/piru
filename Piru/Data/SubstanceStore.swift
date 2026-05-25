import Foundation
import GRDB
import Observation
import os

nonisolated private let logger = Logger(subsystem: "dev.yumeji.piru", category: "SubstanceStore")

/// The multi-source substance store. Replaces ``SubstanceLibrary``.
///
/// ## Two databases
///
/// **Bundled `piru-substances.sqlite`** — ships with the app, read-only,
/// replaced atomically on opt-in update. Holds every fact-bearing row from
/// every source with explicit `source_id` attribution. Schema documented in
/// `Exports/sqlite-schema.md`.
///
/// **User `piru-user-prefs.sqlite`** — lives in `Documents/`, writable, survives
/// bundled-DB updates. Holds the user's source-priority order, profile level
/// (casual/harm-reduction/pharma-nerd), and any per-field overrides.
///
/// ## Source-priority resolution
///
/// Most public methods return ``Substance`` values whose fields have been
/// resolved according to the user's enabled-source priority. The resolver runs
/// per-route / per-field SQL with `ORDER BY user.source_preferences.priority
/// ASC LIMIT 1`, so a single indexed query yields the highest-priority value
/// the user trusts for that field.
///
/// ## Concurrency
///
/// Public API is `@MainActor`. Internal queries hop to GRDB's serial queue and
/// hop back. Read-only bundled queries are cached in `resolvedCache`; the cache
/// invalidates on source-priority change.
@MainActor
@Observable
final class SubstanceStore {

    // MARK: - Lifecycle

    static let shared = SubstanceStore()

    private let substancesDB: DatabaseQueue
    private let userPrefsDB: DatabaseQueue

    /// Ordered list of enabled source slugs (highest priority first). Re-read
    /// on every priority change. Bundled defaults seed the user DB on first
    /// launch.
    private(set) var enabledSourceOrder: [String] = []

    /// The user's chosen disclosure tier. Drives default expanded state in
    /// progressive-disclosure surfaces. Defaults to ``UserProfile/harmReduction``
    /// when no value has been stored.
    private(set) var userProfile: UserProfile = .harmReduction

    /// Cached resolved substances keyed by canonical name (case-insensitive).
    /// Cleared when the user changes source priority.
    private var resolvedCache: [String: Substance] = [:]

    /// All substance canonical names (lowercased) → row id. Built once at
    /// startup so `lookup` / `lookupByNameOrAlias` / `search` don't pay the
    /// full SQL scan tax.
    private var nameIndex: [String: Int64] = [:]
    private var aliasIndex: [String: Int64] = [:]
    private(set) var allNames: [String] = []

    /// Picks the SQLite file to open at launch. Prefers an opt-in updated
    /// copy in `Documents/` (sha256-verified at install time by
    /// ``SubstanceDBUpdater``) and falls back to the bundled resource the app
    /// shipped with.
    static func resolveSubstancesDBURL() -> URL {
        let applied = SubstanceDBUpdater.appliedSQLiteURL
        if FileManager.default.fileExists(atPath: applied.path) {
            return applied
        }
        guard let bundleURL = Bundle.main.url(forResource: "piru-substances", withExtension: "sqlite") else {
            fatalError("Bundled piru-substances.sqlite missing from app bundle. Run `python3 Exports/build-sqlite-database.py` and add the result to the Piru target.")
        }
        return bundleURL
    }

    private init() {
        let dbURL = Self.resolveSubstancesDBURL()

        // The substances DB is opened read-only — both the bundled copy
        // (immutable resource bundle) and any opt-in update applied to
        // Documents/ (we never modify it after sha256-verified install).
        // readonly = true also allows multiple processes (app + extension)
        // to open the same file safely if we ever share it across targets.
        var bundleConfig = Configuration()
        bundleConfig.readonly = true
        bundleConfig.label = "piru-substances"
        do {
            self.substancesDB = try DatabaseQueue(path: dbURL.path, configuration: bundleConfig)
        } catch {
            fatalError("Failed to open substances DB at \(dbURL.path): \(error)")
        }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let prefsURL = docs.appendingPathComponent("piru-user-prefs.sqlite")
        var prefsConfig = Configuration()
        prefsConfig.label = "piru-user-prefs"
        do {
            self.userPrefsDB = try DatabaseQueue(path: prefsURL.path, configuration: prefsConfig)
        } catch {
            fatalError("Failed to open user-prefs DB at \(prefsURL.path): \(error)")
        }

        seedUserPrefsIfNeeded()
        reloadSourceOrder()
        reloadUserProfile()
        buildIndexes()
        logger.info("SubstanceStore opened: \(self.allNames.count) substances, \(self.enabledSourceOrder.count) enabled sources, profile=\(self.userProfile.rawValue, privacy: .public)")
    }

    // MARK: - User prefs schema + seed

    private func seedUserPrefsIfNeeded() {
        do {
            try userPrefsDB.write { db in
                try db.execute(sql: """
                    CREATE TABLE IF NOT EXISTS source_preferences (
                        source_slug TEXT PRIMARY KEY,
                        priority    INTEGER NOT NULL,
                        enabled     INTEGER NOT NULL DEFAULT 1
                    );
                    CREATE TABLE IF NOT EXISTS user_profile (
                        key   TEXT PRIMARY KEY,
                        value TEXT NOT NULL
                    );
                    CREATE TABLE IF NOT EXISTS field_overrides (
                        id              INTEGER PRIMARY KEY,
                        substance_name  TEXT NOT NULL,
                        field_path      TEXT NOT NULL,
                        override_value  TEXT NOT NULL,
                        note            TEXT,
                        created_at      TEXT NOT NULL
                    );
                    CREATE INDEX IF NOT EXISTS idx_overrides_substance ON field_overrides(substance_name);
                """)
            }

            // Seed source_preferences from bundled defaults if empty.
            let needsSeed = try userPrefsDB.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM source_preferences") ?? 0
            } == 0

            if needsSeed {
                let defaults = try substancesDB.read { db in
                    try Row.fetchAll(db, sql: "SELECT slug, default_priority, default_enabled FROM sources ORDER BY default_priority")
                }
                try userPrefsDB.write { db in
                    for row in defaults {
                        try db.execute(
                            sql: "INSERT INTO source_preferences(source_slug, priority, enabled) VALUES (?, ?, ?)",
                            arguments: [row["slug"] as String, row["default_priority"] as Int, row["default_enabled"] as Int]
                        )
                    }
                }
                logger.info("Seeded source_preferences with \(defaults.count) defaults")
            }
        } catch {
            logger.error("Failed to seed user prefs: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Source priority

    private func reloadSourceOrder() {
        do {
            enabledSourceOrder = try userPrefsDB.read { db in
                try String.fetchAll(db, sql: "SELECT source_slug FROM source_preferences WHERE enabled = 1 ORDER BY priority ASC")
            }
        } catch {
            logger.error("Failed to read source priority: \(error.localizedDescription, privacy: .public)")
            enabledSourceOrder = []
        }
        resolvedCache.removeAll(keepingCapacity: true)
    }

    /// Set the user's source priority order (highest priority first). Cleared
    /// `resolvedCache` so the next lookup re-resolves with the new order.
    func setSourcePriority(orderedSlugs: [String]) {
        do {
            try userPrefsDB.write { db in
                for (idx, slug) in orderedSlugs.enumerated() {
                    try db.execute(
                        sql: "UPDATE source_preferences SET priority = ? WHERE source_slug = ?",
                        arguments: [idx + 1, slug]
                    )
                }
            }
            reloadSourceOrder()
        } catch {
            logger.error("Failed to update source priority: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Enable or disable a specific source. Disabled sources never appear in
    /// resolved values; advanced search can still surface them with an
    /// `includeDisabled: true` flag.
    func setSource(_ slug: String, enabled: Bool) {
        do {
            try userPrefsDB.write { db in
                try db.execute(
                    sql: "UPDATE source_preferences SET enabled = ? WHERE source_slug = ?",
                    arguments: [enabled ? 1 : 0, slug]
                )
            }
            reloadSourceOrder()
        } catch {
            logger.error("Failed to toggle source enabled state: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - User profile

    private static let userProfileKey = "profile"

    private func reloadUserProfile() {
        do {
            let raw = try userPrefsDB.read { db in
                try String.fetchOne(
                    db,
                    sql: "SELECT value FROM user_profile WHERE key = ?",
                    arguments: [Self.userProfileKey]
                )
            }
            if let raw, let parsed = UserProfile(rawValue: raw) {
                userProfile = parsed
            }
        } catch {
            logger.error("Failed to read user profile: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Persist a new disclosure tier. The change is immediate and triggers
    /// `@Observable` updates so detail views re-render with the new defaults.
    func setUserProfile(_ profile: UserProfile) {
        guard profile != userProfile else { return }
        do {
            try userPrefsDB.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO user_profile(key, value) VALUES (?, ?)
                        ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """,
                    arguments: [Self.userProfileKey, profile.rawValue]
                )
            }
            userProfile = profile
        } catch {
            logger.error("Failed to write user profile: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// All known sources (from the bundled DB) annotated with the user's
    /// current priority + enabled state. Settings UI uses this to render the
    /// reorderable list.
    struct SourceState: Identifiable, Hashable {
        let slug: String
        let displayName: String
        let description: String?
        let priority: Int
        let enabled: Bool
        var id: String { slug }
    }

    func sourceStates() -> [SourceState] {
        do {
            return try substancesDB.read { db -> [SourceState] in
                let rows = try Row.fetchAll(db, sql: "SELECT slug, display_name, description FROM sources")
                let prefs = try userPrefsDB.read { p in
                    try Row.fetchAll(p, sql: "SELECT source_slug, priority, enabled FROM source_preferences")
                }
                let prefBySlug = Dictionary(uniqueKeysWithValues: prefs.map { ($0["source_slug"] as String, ($0["priority"] as Int, ($0["enabled"] as Int) == 1)) })
                return rows.map { row in
                    let slug: String = row["slug"]
                    let (priority, enabled) = prefBySlug[slug] ?? (Int.max, true)
                    return SourceState(slug: slug, displayName: row["display_name"], description: row["description"], priority: priority, enabled: enabled)
                }.sorted { $0.priority < $1.priority }
            }
        } catch {
            logger.error("Failed to read source states: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Indexes

    private func buildIndexes() {
        do {
            let (names, aliases): ([(String, Int64, String)], [(String, Int64)]) = try substancesDB.read { db in
                let nameRows = try Row.fetchAll(db, sql: "SELECT id, canonical_name FROM substances ORDER BY canonical_name COLLATE NOCASE")
                let names = nameRows.map { ($0["canonical_name"] as String, $0["id"] as Int64, ($0["canonical_name"] as String).lowercased()) }
                let aliasRows = try Row.fetchAll(db, sql: "SELECT substance_id, alias_normalized FROM aliases")
                let aliases = aliasRows.map { ($0["alias_normalized"] as String, $0["substance_id"] as Int64) }
                return (names, aliases)
            }
            self.allNames = names.map(\.0)
            self.nameIndex = Dictionary(uniqueKeysWithValues: names.map { ($0.2, $0.1) })
            var ax: [String: Int64] = [:]
            for (alias, sid) in aliases where ax[alias] == nil { ax[alias] = sid }
            self.aliasIndex = ax
        } catch {
            logger.error("Failed to build indexes: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Public lookup API

    /// Look up by exact canonical name (case-insensitive).
    func lookup(_ name: String) -> Substance? {
        guard let id = nameIndex[name.lowercased()] else { return nil }
        return resolveSubstance(id: id, canonicalName: name)
    }

    /// Look up by canonical name OR any alias (case-insensitive).
    func lookupByNameOrAlias(_ nameOrAlias: String) -> Substance? {
        let key = nameOrAlias.lowercased()
        let id = nameIndex[key] ?? aliasIndex[key]
        guard let id else { return nil }
        return resolveSubstance(id: id, canonicalName: nameOrAlias)
    }

    /// All substances in the library. Lazily resolves on first access; the
    /// resolved array is *not* cached as a unit (resolvedCache caches per
    /// substance so partial fills still benefit from prior work).
    var all: [Substance] {
        allNames.compactMap { lookup($0) }
    }

    var count: Int { allNames.count }

    /// Substances in a single category. Uses the per-substance category
    /// resolver, so a substance whose categories differ across sources lands
    /// in whichever category the highest-priority enabled source assigns.
    func substances(in category: SubstanceCategory) -> [Substance] {
        all.filter { $0.category == category }
    }

    /// Categories that have at least one substance after source resolution.
    var nonEmptyCategories: [SubstanceCategory] {
        let cats = Set(all.map(\.category))
        return SubstanceCategory.allCases.filter(cats.contains)
    }

    // MARK: - Search

    /// Ranked search: exact name → alias → prefix → contains → fuzzy.
    func search(_ query: String, limit: Int = 50) -> [Substance] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        var exactIDs: [Int64] = []
        var prefixIDs: [Int64] = []
        var containsIDs: [Int64] = []
        var seen = Set<Int64>()

        if let id = nameIndex[q] ?? aliasIndex[q] {
            exactIDs.append(id); seen.insert(id)
        }
        for (key, id) in nameIndex {
            guard !seen.contains(id) else { continue }
            if key.hasPrefix(q) { prefixIDs.append(id); seen.insert(id) }
            else if key.contains(q) { containsIDs.append(id); seen.insert(id) }
        }
        for (key, id) in aliasIndex {
            guard !seen.contains(id) else { continue }
            if key.hasPrefix(q) { prefixIDs.append(id); seen.insert(id) }
            else if key.contains(q) { containsIDs.append(id); seen.insert(id) }
        }

        var ranked: [Int64] = exactIDs + prefixIDs + containsIDs
        if ranked.count > limit {
            ranked = Array(ranked.prefix(limit))
        }
        if ranked.count < limit && q.count >= 4 {
            let needed = limit - ranked.count
            ranked.append(contentsOf: fuzzyMatch(q, excluding: seen, limit: needed))
        }
        return ranked.prefix(limit).compactMap { id in
            resolveSubstance(id: id, canonicalName: nil)
        }
    }

    private func fuzzyMatch(_ query: String, excluding seen: Set<Int64>, limit: Int) -> [Int64] {
        let maxDist = max(1, Int(Double(query.count) * 0.3))
        var matches: [(Int64, Int)] = []
        for (key, id) in nameIndex where !seen.contains(id) {
            let d = levenshtein(query, key)
            if d <= maxDist { matches.append((id, d)) }
        }
        return matches.sorted { $0.1 < $1.1 }.prefix(limit).map(\.0)
    }

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var curr = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            curr[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[b.count]
    }

    // MARK: - Substance resolver (source-priority aware)

    private func resolveSubstance(id: Int64, canonicalName fallbackName: String?) -> Substance? {
        let cacheKey = "\(id)"
        if let cached = resolvedCache[cacheKey] { return cached }

        do {
            let resolved = try substancesDB.read { db -> Substance? in
                guard let coreRow = try Row.fetchOne(db, sql: "SELECT canonical_name FROM substances WHERE id = ?", arguments: [id]) else {
                    return nil
                }
                let name: String = coreRow["canonical_name"]

                let aliases = try String.fetchAll(db, sql: "SELECT alias FROM aliases WHERE substance_id = ? ORDER BY alias", arguments: [id])

                let category = try resolvedCategory(db: db, substanceID: id)
                let tags = try resolvedTags(db: db, substanceID: id)
                let routes = try resolvedRoutes(db: db, substanceID: id)
                let effects = try resolvedEffects(db: db, substanceID: id)
                let subjectiveEffects = try resolvedSubjectiveEffects(db: db, substanceID: id)
                let halfLifeMinutes = try resolvedHalfLife(db: db, substanceID: id)
                let mechanism = try resolvedMechanism(db: db, substanceID: id)
                let sources = try citedSources(db: db, substanceID: id)
                let toleranceInfo = try resolvedTolerance(db: db, substanceID: id)

                let defaultRoute = routes.first?.route
                    ?? RouteOfAdministration.from(string: tags.contains("inhalation") ? "inhalation" : "oral")

                return Substance(
                    name: name,
                    aliases: aliases,
                    category: category ?? .other,
                    defaultRoute: defaultRoute,
                    routes: routes,
                    effects: effects,
                    subjectiveEffects: subjectiveEffects,
                    toleranceInfo: toleranceInfo,
                    halfLifeMinutes: halfLifeMinutes,
                    sources: sources,
                    mechanismOfAction: mechanism,
                    tags: tags
                )
            }
            if let resolved {
                resolvedCache[cacheKey] = resolved
            }
            return resolved
        } catch {
            logger.error("resolveSubstance(\(id, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Per-field resolvers (source-priority aware)

    /// Builds a `CASE src.slug WHEN ... THEN ... END` expression that maps
    /// enabled source slugs to their priority rank. Used in `ORDER BY`.
    private var priorityCaseSQL: String {
        guard !enabledSourceOrder.isEmpty else {
            return "999"
        }
        let cases = enabledSourceOrder.enumerated().map { idx, slug in
            "WHEN '\(slug.replacingOccurrences(of: "'", with: "''"))' THEN \(idx)"
        }.joined(separator: " ")
        return "CASE src.slug \(cases) ELSE 999 END"
    }

    private var enabledSourceListSQL: String {
        if enabledSourceOrder.isEmpty { return "''" }
        return enabledSourceOrder.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }.joined(separator: ", ")
    }

    private func resolvedCategory(db: Database, substanceID: Int64) throws -> SubstanceCategory? {
        let row = try Row.fetchOne(db, sql: """
            SELECT c.category
              FROM categories c
              JOIN sources src ON src.id = c.source_id
             WHERE c.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
             ORDER BY \(priorityCaseSQL) ASC
             LIMIT 1
        """, arguments: [substanceID])
        guard let raw: String = row?["category"] else { return nil }
        return SubstanceCategory(rawValue: raw) ?? SubstanceCategory.from(tripSitCategory: raw)
    }

    private func resolvedTags(db: Database, substanceID: Int64) throws -> [String] {
        // Tags are additive — return the union across all enabled sources.
        try String.fetchAll(db, sql: """
            SELECT DISTINCT tag
              FROM tags t
              JOIN sources src ON src.id = t.source_id
             WHERE t.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
             ORDER BY tag
        """, arguments: [substanceID])
    }

    private func resolvedRoutes(db: Database, substanceID: Int64) throws -> [SubstanceRoute] {
        let routes = try String.fetchAll(db, sql: """
            SELECT DISTINCT route
              FROM dose_ranges d
              JOIN sources src ON src.id = d.source_id
             WHERE d.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
        """, arguments: [substanceID])

        var resolved: [SubstanceRoute] = []
        for route in routes {
            guard let r = try resolvedDoseForRoute(db: db, substanceID: substanceID, route: route) else { continue }
            resolved.append(r)
        }

        // Also surface routes that have duration data but no dose data
        let durationOnlyRoutes = try String.fetchAll(db, sql: """
            SELECT DISTINCT route
              FROM durations du
              JOIN sources src ON src.id = du.source_id
             WHERE du.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
               AND route NOT IN (SELECT DISTINCT route FROM dose_ranges WHERE substance_id = ?)
        """, arguments: [substanceID, substanceID])
        for route in durationOnlyRoutes {
            let duration = try resolvedDurationForRoute(db: db, substanceID: substanceID, route: route)
            let ra = RouteOfAdministration.from(string: route)
            resolved.append(SubstanceRoute(route: ra, unit: "mg", doses: DoseRange(), duration: duration))
        }
        return resolved
    }

    private func resolvedDoseForRoute(db: Database, substanceID: Int64, route: String) throws -> SubstanceRoute? {
        let row = try Row.fetchOne(db, sql: """
            SELECT d.unit, d.threshold, d.light_lower, d.light_upper,
                   d.common_lower, d.common_upper, d.strong_lower, d.strong_upper, d.heavy
              FROM dose_ranges d
              JOIN sources src ON src.id = d.source_id
             WHERE d.substance_id = ? AND d.route = ?
               AND src.slug IN (\(enabledSourceListSQL))
             ORDER BY \(priorityCaseSQL) ASC
             LIMIT 1
        """, arguments: [substanceID, route])
        guard let row else { return nil }

        let dose = DoseRange(
            threshold: row["threshold"],
            light: rangeFrom(lower: row["light_lower"], upper: row["light_upper"]),
            common: rangeFrom(lower: row["common_lower"], upper: row["common_upper"]),
            strong: rangeFrom(lower: row["strong_lower"], upper: row["strong_upper"]),
            heavy: row["heavy"]
        )

        let duration = try resolvedDurationForRoute(db: db, substanceID: substanceID, route: route)
        return SubstanceRoute(
            route: RouteOfAdministration.from(string: route),
            unit: row["unit"] ?? "mg",
            doses: dose,
            duration: duration
        )
    }

    private func resolvedDurationForRoute(db: Database, substanceID: Int64, route: String) throws -> DurationProfile? {
        let rows = try Row.fetchAll(db, sql: """
            SELECT du.phase, du.min_minutes, du.max_minutes
              FROM durations du
              JOIN sources src ON src.id = du.source_id
             WHERE du.substance_id = ? AND du.route = ?
               AND src.slug IN (\(enabledSourceListSQL))
               AND du.source_id = (
                   SELECT du2.source_id FROM durations du2
                   JOIN sources src2 ON src2.id = du2.source_id
                   WHERE du2.substance_id = ? AND du2.route = ?
                     AND src2.slug IN (\(enabledSourceListSQL))
                   ORDER BY CASE src2.slug
                       \(enabledSourceOrder.enumerated().map { "WHEN '\($1.replacingOccurrences(of: "'", with: "''"))' THEN \($0)" }.joined(separator: " "))
                       ELSE 999 END
                   LIMIT 1
               )
        """, arguments: [substanceID, route, substanceID, route])

        guard !rows.isEmpty else { return nil }

        var phases: [String: DurationRange] = [:]
        for row in rows {
            let phase: String = row["phase"]
            phases[phase] = DurationRange(min: row["min_minutes"], max: row["max_minutes"])
        }
        return DurationProfile(
            onset:     phases["onset"],
            comeup:    phases["comeup"],
            peak:      phases["peak"],
            offset:    phases["offset"],
            afterglow: phases["afterglow"],
            total:     phases["total"]
        )
    }

    private func rangeFrom(lower: Double?, upper: Double?) -> ClosedRange<Double>? {
        guard let lo = lower, let hi = upper, lo <= hi else { return nil }
        return lo...hi
    }

    private func resolvedHalfLife(db: Database, substanceID: Int64) throws -> Double? {
        try Double.fetchOne(db, sql: """
            SELECT h.half_life_minutes
              FROM half_lives h
              JOIN sources src ON src.id = h.source_id
             WHERE h.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
             ORDER BY \(priorityCaseSQL) ASC
             LIMIT 1
        """, arguments: [substanceID])
    }

    private func resolvedMechanism(db: Database, substanceID: Int64) throws -> MechanismOfAction? {
        guard let row = try Row.fetchOne(db, sql: """
            SELECT m.summary, m.description
              FROM mechanisms_summary m
              JOIN sources src ON src.id = m.source_id
             WHERE m.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
             ORDER BY \(priorityCaseSQL) ASC
             LIMIT 1
        """, arguments: [substanceID]) else { return nil }

        let bindingRows = try Row.fetchAll(db, sql: """
            SELECT b.target, b.action,
                   CASE WHEN b.ki_nm IS NOT NULL AND b.ki_nm < 100 THEN 3
                        WHEN b.ki_nm IS NOT NULL AND b.ki_nm < 1000 THEN 2
                        ELSE 1 END AS affinity
              FROM bindings b
              JOIN sources src ON src.id = b.source_id
             WHERE b.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
             ORDER BY b.ki_nm ASC NULLS LAST
             LIMIT 20
        """, arguments: [substanceID])

        let bindings: [ReceptorBinding] = bindingRows.compactMap { row in
            guard let target: String = row["target"],
                  let actionRaw: String = row["action"],
                  let action = BindingAction(rawValue: actionRaw) else { return nil }
            let affRaw: Int = row["affinity"]
            let affinity = BindingAffinity(rawValue: affRaw) ?? .significant
            return ReceptorBinding(target: target, action: action, affinity: affinity)
        }

        return MechanismOfAction(
            summary: row["summary"],
            description: row["description"] ?? "",
            primaryTargets: bindings.map(\.target),
            bindings: bindings,
            references: []
        )
    }

    private func resolvedEffects(db: Database, substanceID: Int64) throws -> [String] {
        try String.fetchAll(db, sql: """
            SELECT DISTINCT text
              FROM effects e
              JOIN sources src ON src.id = e.source_id
             WHERE e.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
             ORDER BY text
        """, arguments: [substanceID])
    }

    private func resolvedSubjectiveEffects(db: Database, substanceID: Int64) throws -> [SubjectiveEffect] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT DISTINCT se.name AS effect_name,
                            COALESCE(se.description, '') AS effect_description
              FROM subjective_effects se
              JOIN sources src ON src.id = se.source_id
             WHERE se.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
             ORDER BY se.name
        """, arguments: [substanceID])
        return rows.map { SubjectiveEffect(name: $0["effect_name"], description: $0["effect_description"]) }
    }

    private func resolvedTolerance(db: Database, substanceID: Int64) throws -> ToleranceInfo? {
        guard let row = try Row.fetchOne(db, sql: """
            SELECT t.half_life_days, t.full_reset_days, t.build_rate
              FROM tolerance t
              JOIN sources src ON src.id = t.source_id
             WHERE t.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
               AND t.half_life_days IS NOT NULL
               AND t.full_reset_days IS NOT NULL
               AND t.build_rate IS NOT NULL
             ORDER BY \(priorityCaseSQL) ASC
             LIMIT 1
        """, arguments: [substanceID]) else { return nil }
        return ToleranceInfo(
            halfLife: row["half_life_days"],
            fullResetDays: row["full_reset_days"],
            buildRate: row["build_rate"]
        )
    }

    private func citedSources(db: Database, substanceID: Int64) throws -> [String] {
        // Source attribution shown to the user: the set of source display
        // names that contributed any fact for this substance.
        let slugs = try String.fetchAll(db, sql: """
            SELECT DISTINCT src.slug FROM (
                SELECT source_id FROM categories WHERE substance_id = ?
                UNION SELECT source_id FROM dose_ranges WHERE substance_id = ?
                UNION SELECT source_id FROM durations WHERE substance_id = ?
                UNION SELECT source_id FROM half_lives WHERE substance_id = ?
                UNION SELECT source_id FROM mechanisms_summary WHERE substance_id = ?
                UNION SELECT source_id FROM bindings WHERE substance_id = ?
            ) AS uses
            JOIN sources src ON src.id = uses.source_id
            WHERE src.slug IN (\(enabledSourceListSQL))
            ORDER BY src.slug
        """, arguments: StatementArguments(Array(repeating: substanceID, count: 6) as [DatabaseValueConvertible]))
        return slugs
    }

    // MARK: - Advanced search (Pharma Nerd surface)

    /// One row from the bindings table joined to its substance + source +
    /// citation. Used by advanced-search results.
    struct BindingHit: Identifiable, Hashable {
        let id: Int64
        let substanceName: String
        let target: String
        let action: String
        let kiNm: Double?
        let ec50Nm: Double?
        let species: String?
        let sourceSlug: String
        let doi: String?
        let pmid: Int?
    }

    /// Returns every binding row matching the predicate, *across all sources*
    /// (including disabled) so pharma-nerd users can see the literature even
    /// for sources they've deprioritised. UI labels which source supplied each
    /// row so users can apply their own trust filter.
    func bindings(
        target: String? = nil,
        kiNmAtMost: Double? = nil,
        substanceContains: String? = nil,
        limit: Int = 200
    ) -> [BindingHit] {
        do {
            return try substancesDB.read { db in
                var sql = """
                    SELECT b.id, b.target, b.action, b.ki_nm, b.ec50_nm, b.species,
                           s.canonical_name AS substance_name,
                           src.slug AS source_slug,
                           c.doi, c.pmid
                      FROM bindings b
                      JOIN substances s ON s.id = b.substance_id
                      JOIN sources    src ON src.id = b.source_id
                      LEFT JOIN citations c ON c.id = b.citation_id
                     WHERE 1=1
                """
                var args: [DatabaseValueConvertible?] = []
                if let target {
                    sql += " AND b.target = ?"
                    args.append(target)
                }
                if let kiNmAtMost {
                    sql += " AND b.ki_nm IS NOT NULL AND b.ki_nm <= ?"
                    args.append(kiNmAtMost)
                }
                if let substanceContains, !substanceContains.isEmpty {
                    sql += " AND s.canonical_name LIKE ?"
                    args.append("%\(substanceContains)%")
                }
                sql += " ORDER BY b.ki_nm ASC NULLS LAST LIMIT ?"
                args.append(limit)

                let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    BindingHit(
                        id: row["id"],
                        substanceName: row["substance_name"],
                        target: row["target"],
                        action: row["action"],
                        kiNm: row["ki_nm"],
                        ec50Nm: row["ec50_nm"],
                        species: row["species"],
                        sourceSlug: row["source_slug"],
                        doi: row["doi"],
                        pmid: row["pmid"]
                    )
                }
            }
        } catch {
            logger.error("bindings query failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Provenance (per-field source attribution)

    /// Source attribution for the fields displayed in a substance detail
    /// view. Distinct from the substance-level `sources` list (which is just
    /// "every source that contributed anything") — this surfaces *which*
    /// source supplied a specific field after priority resolution.
    struct RouteProvenance: Hashable, Sendable {
        let route: RouteOfAdministration
        let doseSource: String?
        let durationSource: String?
    }

    struct SubstanceProvenance: Hashable, Sendable {
        let categorySource: String?
        let halfLifeSource: String?
        let mechanismSource: String?
        let routes: [RouteProvenance]
    }

    /// Resolves per-field source slugs for a substance using the same
    /// priority order as the field resolvers themselves, so the slug shown
    /// in the UI matches the source that actually won the field.
    func provenance(forSubstanceName name: String) -> SubstanceProvenance? {
        guard let substanceID = nameIndex[name.lowercased()] else { return nil }
        do {
            return try substancesDB.read { db in
                let categorySource = try fieldSource(
                    db: db,
                    sql: """
                        SELECT src.slug FROM categories c
                          JOIN sources src ON src.id = c.source_id
                         WHERE c.substance_id = ?
                           AND src.slug IN (\(enabledSourceListSQL))
                         ORDER BY \(priorityCaseSQL) ASC LIMIT 1
                    """,
                    substanceID: substanceID
                )
                let halfLifeSource = try fieldSource(
                    db: db,
                    sql: """
                        SELECT src.slug FROM half_lives h
                          JOIN sources src ON src.id = h.source_id
                         WHERE h.substance_id = ?
                           AND src.slug IN (\(enabledSourceListSQL))
                         ORDER BY \(priorityCaseSQL) ASC LIMIT 1
                    """,
                    substanceID: substanceID
                )
                let mechanismSource = try fieldSource(
                    db: db,
                    sql: """
                        SELECT src.slug FROM mechanisms_summary m
                          JOIN sources src ON src.id = m.source_id
                         WHERE m.substance_id = ?
                           AND src.slug IN (\(enabledSourceListSQL))
                         ORDER BY \(priorityCaseSQL) ASC LIMIT 1
                    """,
                    substanceID: substanceID
                )

                let routes = try resolvedRoutes(db: db, substanceID: substanceID).map(\.route)
                var routeProvenance: [RouteProvenance] = []
                for route in routes {
                    let doseSource = try fieldSource(
                        db: db,
                        sql: """
                            SELECT src.slug FROM dose_ranges d
                              JOIN sources src ON src.id = d.source_id
                             WHERE d.substance_id = ? AND d.route = ?
                               AND src.slug IN (\(enabledSourceListSQL))
                             ORDER BY \(priorityCaseSQL) ASC LIMIT 1
                        """,
                        substanceID: substanceID,
                        extra: [route.rawValue]
                    )
                    let durationSource = try fieldSource(
                        db: db,
                        sql: """
                            SELECT src.slug FROM durations du
                              JOIN sources src ON src.id = du.source_id
                             WHERE du.substance_id = ? AND du.route = ?
                               AND src.slug IN (\(enabledSourceListSQL))
                             ORDER BY \(priorityCaseSQL) ASC LIMIT 1
                        """,
                        substanceID: substanceID,
                        extra: [route.rawValue]
                    )
                    routeProvenance.append(RouteProvenance(
                        route: route,
                        doseSource: doseSource,
                        durationSource: durationSource
                    ))
                }

                return SubstanceProvenance(
                    categorySource: categorySource,
                    halfLifeSource: halfLifeSource,
                    mechanismSource: mechanismSource,
                    routes: routeProvenance
                )
            }
        } catch {
            logger.error("provenance(forSubstanceName:) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Helper: fetch a single source slug given a `SELECT src.slug …` query.
    private func fieldSource(db: Database, sql: String, substanceID: Int64, extra: [DatabaseValueConvertible] = []) throws -> String? {
        var values: [DatabaseValueConvertible] = [substanceID]
        values.append(contentsOf: extra)
        return try String.fetchOne(db, sql: sql, arguments: StatementArguments(values))
    }

    /// Every binding row associated with a specific substance, resolved by
    /// canonical name. Used by the detail view's "Receptor Literature"
    /// disclosure (pharma-nerd tier) to show the full Ki/EC50 table with
    /// per-row source attribution. Returns rows sorted by tightest Ki first.
    func bindings(forSubstanceName name: String) -> [BindingHit] {
        guard let substanceID = nameIndex[name.lowercased()] else { return [] }
        do {
            return try substancesDB.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT b.id, b.target, b.action, b.ki_nm, b.ec50_nm, b.species,
                           s.canonical_name AS substance_name,
                           src.slug AS source_slug,
                           c.doi, c.pmid
                      FROM bindings b
                      JOIN substances s ON s.id = b.substance_id
                      JOIN sources    src ON src.id = b.source_id
                      LEFT JOIN citations c ON c.id = b.citation_id
                     WHERE b.substance_id = ?
                     ORDER BY b.ki_nm ASC NULLS LAST, b.ec50_nm ASC NULLS LAST
                """, arguments: [substanceID])
                return rows.map { row in
                    BindingHit(
                        id: row["id"],
                        substanceName: row["substance_name"],
                        target: row["target"],
                        action: row["action"],
                        kiNm: row["ki_nm"],
                        ec50Nm: row["ec50_nm"],
                        species: row["species"],
                        sourceSlug: row["source_slug"],
                        doi: row["doi"],
                        pmid: row["pmid"]
                    )
                }
            }
        } catch {
            logger.error("bindings(forSubstanceName:) failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Distinct binding targets sorted by how many substances hit them.
    /// Powers an autocomplete / chip picker in the advanced-search UI.
    func availableBindingTargets() -> [(target: String, substanceCount: Int)] {
        do {
            return try substancesDB.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT target, COUNT(DISTINCT substance_id) AS n
                      FROM bindings
                     WHERE target IS NOT NULL AND target <> ''
                     GROUP BY target
                     ORDER BY n DESC, target ASC
                """)
                return rows.map { ($0["target"], $0["n"]) }
            }
        } catch { return [] }
    }

}

// MARK: - Static façade

/// Static façade matching the legacy `SubstanceLibrary` API. Lets every call
/// site keep working with a stable shape while the store underneath is
/// GRDB-backed. Inlined into call sites would be the long-term cleanup, but
/// the façade is zero-cost so a one-line `enum` is the right level of
/// abstraction for the migration to land cleanly.
@MainActor
enum SubstanceLibrary {
    static var all: [Substance] { SubstanceStore.shared.all }
    static var count: Int { SubstanceStore.shared.count }
    static var nonEmptyCategories: [SubstanceCategory] { SubstanceStore.shared.nonEmptyCategories }
    static func substances(in category: SubstanceCategory) -> [Substance] { SubstanceStore.shared.substances(in: category) }
    static func lookup(_ name: String) -> Substance? { SubstanceStore.shared.lookup(name) }
    static func lookupByNameOrAlias(_ nameOrAlias: String) -> Substance? { SubstanceStore.shared.lookupByNameOrAlias(nameOrAlias) }
    static func search(_ query: String, limit: Int = 50) -> [Substance] { SubstanceStore.shared.search(query, limit: limit) }
}
