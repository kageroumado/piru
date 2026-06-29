import Foundation
import GRDB
import Observation
import os

private nonisolated let logger = Logger(subsystem: "dev.yumeji.piru", category: "SubstanceStore")

/// The app's resolved content language for substance text. The requested side
/// of locale resolution — stored rows may also be `und` (undetermined), which
/// the resolver treats as an English-tier fallback. Carries the SQL fragments
/// for locale-first text resolution so every text table resolves the same way.
nonisolated enum ContentLanguage: String {
    case en
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"

    var isChinese: Bool {
        self != .en
    }

    /// Derive from the app's preferred localization (follows a per-app language
    /// override, not just the device language).
    static var current: ContentLanguage {
        let pref = (Bundle.main.preferredLocalizations.first ?? "en").lowercased()
        guard pref.hasPrefix("zh") else { return .en }
        if pref.contains("hant") || pref.contains("tw") || pref.contains("hk") || pref.contains("mo") {
            return .zhHant
        }
        return .zhHans
    }

    /// Language-aware `WHERE`/`ORDER BY` fragments for a text table's `language`
    /// column. In Chinese, matching-language text floats above source priority
    /// (exact variant first, then any zh), falling back to English when no zh
    /// row exists. In English, raw zh is excluded — only English (and FreeOD's
    /// machine-translated en rows) show. `rawValue` is a fixed enum literal, so
    /// interpolating it carries no injection risk.
    func clauses(column col: String) -> (whereAnd: String, orderPrefix: String) {
        if isChinese {
            return ("", "(\(col) = '\(rawValue)') DESC, (\(col) LIKE 'zh%') DESC, ")
        }
        return (" AND \(col) IN ('en', 'und') ", "")
    }
}

/// The multi-source substance store. Replaces ``SubstanceLibrary``.
///
/// ## Two databases
///
/// **Bundled `piru-substances.sqlite`** — ships with the app, read-only,
/// replaced atomically on opt-in update. Holds every fact-bearing row from
/// every source with explicit `source_id` attribution. Schema documented in
/// `docs/sqlite-schema.md`.
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
/// Public API is `@MainActor`. Queries are **synchronous blocking reads** —
/// `DatabaseQueue.read` blocks the calling thread until the SQL completes;
/// there is no hop to GRDB's queue and back. The in-memory caches
/// (`resolvedCache`, `allCache`, …) and the off-main launch prewarm keep the
/// hot paths off SQLite, but an uncached query issued from the main actor
/// still pays its full cost there — don't add main-actor call sites assuming
/// reads are free.
@MainActor
@Observable
final class SubstanceStore {
    // MARK: - Lifecycle

    static let shared = SubstanceStore()

    /// Foreground (UI-interactive) connection. Per-field `resolveSubstance`
    /// reads, category counts, lookups — the queries a tap is waiting on — go
    /// here.
    let substancesDB: DatabaseQueue
    /// Second read-only connection to the **same** bundled file, reserved for
    /// the heavy off-main batch reads (the launch `prewarmTask`, the lazy
    /// `categorySummary`/`all` materialization). A `DatabaseQueue` serializes
    /// *all* access through one SQLite connection, so the ~500 ms batch resolve
    /// run on `substancesDB` would block every foreground read behind it — the
    /// tab-switch / detail-push hangs in the trace. The file is opened read-only
    /// and never written, so two independent connections read it concurrently
    /// (no WAL needed — DELETE-mode read-only allows multiple shared-lock
    /// readers). Keeping the batch on its own connection is what lets a detail
    /// push resolve immediately while the prewarm is still running.
    let substancesBatchDB: DatabaseQueue
    private let userPrefsDB: DatabaseQueue

    /// Ordered list of enabled source slugs (highest priority first). Re-read
    /// on every priority change. Bundled defaults seed the user DB on first
    /// launch.
    private(set) var enabledSourceOrder: [String] = []

    /// Cached resolved substances keyed by canonical name (case-insensitive).
    /// Cleared when the user changes source priority.
    private var resolvedCache: [String: Substance] = [:]

    /// Substance row id → resolved molar mass (`molecular_weight`). Backs the lean
    /// ``molarMass(forSubstanceName:)`` so the tolerance/PD engine can read one
    /// column without paying a full ``resolveSubstance`` (≈18 SQL + chem/effects
    /// decode) per dosed substance. Source-independent (the column is fixed for the
    /// DB's lifetime), so unlike `resolvedCache` it is *not* cleared on a source
    /// reorder; it is naturally discarded when the store is rebuilt for a DB update.
    var molarMassByID: [Int64: Double?] = [:]

    /// Memoized ``pharmacologyParameters(forSubstanceName:)`` per substance name.
    /// The tolerance recompute resolves params for *every* unique dosed substance
    /// on the main actor each time the dose log changes; uncached, that re-ran a
    /// fresh `pk_routes` + `bindings` SQL fetch **and row decode** per substance
    /// (~50 for a heavy log) — a multi-second main-thread hang on every post-commit
    /// replay. Like ``molarMassByID`` the result is a pure function of the bundled
    /// DB row (by `substance_id`, no source-priority or overlay), stable for the
    /// DB's lifetime — so it is *not* cleared on a source reorder and is discarded
    /// naturally when the store is rebuilt for a DB update.
    var pharmacologyParamsByName: [String: PharmacologyParameters] = [:]

    /// Cached `all`/`substances(in:)` results. Resolving 1600+ substances
    /// individually on every view body invalidation is what was making the
    /// Library tab feel laggy on entry. Cleared in lockstep with
    /// `resolvedCache`.
    private var allCache: [Substance]?
    private var substancesByCategoryCache: [SubstanceCategory: [Substance]] = [:]
    private var nonEmptyCategoriesCache: [SubstanceCategory]?
    /// Browse-category histogram — every category (primary + curated
    /// `extraBrowseCategories`) a browse-surfacing substance lands in, with its
    /// count. Drives the Library cards' counts and the `nonEmptyCategories` /
    /// `browsable` gating without per-category `.filter` passes over `all`.
    /// Built in one bucketing sweep; invalidated in lockstep with `allCache`.
    private var categorySummaryCache: [SubstanceCategory: Int]?
    /// Benzodiazepine diazepam-equivalences for the converter tool — one batched
    /// query, cached after first load. Cleared with the other source-derived caches.
    private var benzoEquivalenceCache: [BenzoEquivalence]?

    /// Name/alias (lowercased) → lightweight batch row, derived from `allCache`.
    /// This is the journal/timeline resolution path: it carries everything
    /// `ActiveSubstanceState.from` and the category facet need (category,
    /// routes/dose-ranges, durations, half-life, aliases) **without** the heavy
    /// per-substance `resolveSubstance` SQL (mechanism, bindings, chem identity).
    /// Built lazily on first access; invalidated in lockstep with `allCache`.
    private var batchByName: [String: Substance]?

    /// Row id → lightweight `Substance`, derived from the batch cache. Lets
    /// ``search(_:limit:)`` resolve its ranked ids from the warm cache instead of
    /// running the heavy per-substance ``resolveSubstance`` (≈21 SQL each) for
    /// every one of up to `limit` results — which made each settled keystroke
    /// fire ~1k SQL queries on the main actor. Invalidated with `batchByName`.
    private var batchByID: [Int64: Substance]?

    /// The in-flight (or finished) off-main prefill of `allCache` started in
    /// `init`. ``ensureAllLoaded()`` awaits it so the journal derive resolves
    /// from the batch cache (dict hits) instead of paying ~50 cold heavy reads
    /// on the main actor at launch.
    private var prewarmTask: Task<Void, Never>?

    /// All substance canonical names (lowercased) → row id. Built once at
    /// startup so `lookup` / `lookupByNameOrAlias` / `search` don't pay the
    /// full SQL scan tax.
    private(set) var nameIndex: [String: Int64] = [:]
    private var aliasIndex: [String: Int64] = [:]
    private(set) var allNames: [String] = []

    /// `source.slug` → `source.display_name`. Built once at init; consumed by
    /// the detail view's source-attribution rows so users see "TripSit
    /// factsheets" rather than the raw slug "tripsit".
    private var sourceDisplayNames: [String: String] = [:]

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
            fatalError("Bundled piru-substances.sqlite missing from app bundle. Run `python3 pipeline/build/sqlite.py` and add the result to the Piru target.")
        }
        return bundleURL
    }

    /// Designated initializer — the testability seam. Tests construct an
    /// isolated store pointing at the (read-only) bundled substances DB and a
    /// temp-directory user-prefs DB so priority/profile mutations never touch
    /// the shared singleton or the real `Documents/piru-user-prefs.sqlite`.
    /// Production goes through the `private convenience init()` below, which
    /// resolves the real paths and keeps the prewarm enabled.
    ///
    /// - Parameters:
    ///   - substancesDBURL: SQLite file holding the substance facts. Opened
    ///     read-only; must exist.
    ///   - userPrefsDBURL: Writable SQLite file for source priorities, profile
    ///     and overrides. Created (schema + bundled-default seed) if missing.
    ///   - prewarmsAllCache: Whether to fire the detached background task that
    ///     prefills `allCache`. Defaults to `true` (production behavior); tests
    ///     pass `false` so short-lived instances don't pay a ~600 ms batch
    ///     resolve they never read.
    init(substancesDBURL: URL, userPrefsDBURL: URL, prewarmsAllCache: Bool = true) {
        // The substances DB is opened read-only — both the bundled copy
        // (immutable resource bundle) and any opt-in update applied to
        // Documents/ (we never modify it after sha256-verified install).
        // readonly = true also allows multiple processes (app + extension)
        // to open the same file safely if we ever share it across targets.
        var bundleConfig = Configuration()
        bundleConfig.readonly = true
        bundleConfig.label = "piru-substances"
        do {
            self.substancesDB = try DatabaseQueue(path: substancesDBURL.path, configuration: bundleConfig)
        } catch {
            fatalError("Failed to open substances DB at \(substancesDBURL.path): \(error)")
        }

        // Second read-only connection for off-main batch reads (see the property
        // doc). Same file, same read-only config; a distinct `label` so it's
        // identifiable in Instruments / GRDB logs.
        var batchConfig = bundleConfig
        batchConfig.label = "piru-substances-batch"
        do {
            self.substancesBatchDB = try DatabaseQueue(path: substancesDBURL.path, configuration: batchConfig)
        } catch {
            fatalError("Failed to open substances batch DB at \(substancesDBURL.path): \(error)")
        }

        var prefsConfig = Configuration()
        prefsConfig.label = "piru-user-prefs"
        do {
            self.userPrefsDB = try DatabaseQueue(path: userPrefsDBURL.path, configuration: prefsConfig)
        } catch {
            fatalError("Failed to open user-prefs DB at \(userPrefsDBURL.path): \(error)")
        }

        seedUserPrefsIfNeeded()
        reloadSourceOrder()
        buildIndexes()
        logger.info("SubstanceStore opened: \(self.allNames.count) substances, \(self.enabledSourceOrder.count) enabled sources")
        // Eager-prefill the `all` cache *off the main thread*. The first
        // Library-tab tap — and, more visibly, the first quick-log open — was
        // paying a ~660 ms synchronous resolve of all 1700+ substances on the
        // main actor (the old prefill hopped to `MainActor.run` to build the
        // batch, so it blocked the main thread whenever it happened to run).
        // The batch loader is now a `nonisolated static` that does its SQL +
        // struct building on this background task; we only hop back to main to
        // publish the finished array into the cache.
        if prewarmsAllCache {
            // Read on the dedicated batch connection so this ~500 ms resolve
            // never blocks a foreground per-field read on `substancesDB`.
            let prewarmDB = substancesBatchDB
            let prewarmOrder = enabledSourceOrder
            prewarmTask = Task.detached(priority: .userInitiated) {
                let resolved = Self.loadAllSubstancesBatch(db: prewarmDB, order: prewarmOrder)
                await MainActor.run { [weak self] in
                    // Drop the prefill if the user reordered/toggled sources while
                    // it ran — `reloadSourceOrder()` nils `allCache`, so the nil
                    // check alone would publish a batch resolved with stale order.
                    guard let self, self.allCache == nil, self.enabledSourceOrder == prewarmOrder else { return }
                    self.allCache = resolved
                    self.batchByName = nil
                    self.batchByID = nil
                }
            }
        }
    }

    private convenience init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        self.init(
            substancesDBURL: Self.resolveSubstancesDBURL(),
            userPrefsDBURL: docs.appendingPathComponent("piru-user-prefs.sqlite"),
        )
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
                            arguments: [row["slug"] as String, row["default_priority"] as Int, row["default_enabled"] as Int],
                        )
                    }
                }
                logger.info("Seeded source_preferences with \(defaults.count) defaults")
            }

            // Reconcile: a bundled-DB upgrade can introduce new sources (e.g.
            // pyrls/medtap/benzos-cited/nps-datahub) that an existing user's
            // already-seeded prefs table lacks. Insert any missing slugs at
            // their bundled default priority/enabled so their data resolves.
            let bundledSources = try substancesDB.read { db in
                try Row.fetchAll(db, sql: "SELECT slug, default_priority, default_enabled FROM sources ORDER BY default_priority")
            }
            try userPrefsDB.write { db in
                let known = try String.fetchAll(db, sql: "SELECT source_slug FROM source_preferences")
                let knownSet = Set(known)
                for row in bundledSources where !knownSet.contains(row["slug"] as String) {
                    try db.execute(
                        sql: "INSERT OR IGNORE INTO source_preferences(source_slug, priority, enabled) VALUES (?, ?, ?)",
                        arguments: [row["slug"] as String, row["default_priority"] as Int, row["default_enabled"] as Int],
                    )
                }
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
        allCache = nil
        batchByName = nil
        batchByID = nil
        substancesByCategoryCache.removeAll(keepingCapacity: true)
        nonEmptyCategoriesCache = nil
        categorySummaryCache = nil
        benzoEquivalenceCache = nil
    }

    /// Set the user's source priority order (highest priority first). Cleared
    /// `resolvedCache` so the next lookup re-resolves with the new order.
    func setSourcePriority(orderedSlugs: [String]) {
        do {
            try userPrefsDB.write { db in
                for (idx, slug) in orderedSlugs.enumerated() {
                    try db.execute(
                        sql: "UPDATE source_preferences SET priority = ? WHERE source_slug = ?",
                        arguments: [idx + 1, slug],
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
                    arguments: [enabled ? 1 : 0, slug],
                )
            }
            reloadSourceOrder()
        } catch {
            logger.error("Failed to toggle source enabled state: \(error.localizedDescription, privacy: .public)")
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
        var id: String {
            slug
        }
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
            let (names, aliases, displayNames): ([(String, Int64, String)], [(String, Int64)], [(String, String)]) = try substancesDB.read { db in
                let nameRows = try Row.fetchAll(db, sql: "SELECT id, canonical_name FROM substances ORDER BY canonical_name COLLATE NOCASE")
                let names = nameRows.map { ($0["canonical_name"] as String, $0["id"] as Int64, ($0["canonical_name"] as String).lowercased()) }
                let aliasRows = try Row.fetchAll(db, sql: "SELECT substance_id, alias_normalized FROM aliases")
                let aliases = aliasRows.map { ($0["alias_normalized"] as String, $0["substance_id"] as Int64) }
                let sourceRows = try Row.fetchAll(db, sql: "SELECT slug, display_name FROM sources")
                let displayNames = sourceRows.map { ($0["slug"] as String, $0["display_name"] as String) }
                return (names, aliases, displayNames)
            }
            self.allNames = names.map(\.0)
            // `uniquingKeysWith` (not `uniqueKeysWithValues:`) so a duplicate
            // lowercased canonical name — e.g. an opt-in updated or imported DB
            // carrying both `MDMA` and `mdma`, or a custom substance that failed
            // to merge — collapses to the first row instead of *trapping* at
            // launch. This runs eagerly on every cold start, and a trap here is
            // an unrecoverable launch crash (the enclosing do/catch can't catch
            // a precondition failure).
            self.nameIndex = Dictionary(names.map { ($0.2, $0.1) }, uniquingKeysWith: { first, _ in first })
            if self.nameIndex.count != names.count {
                logger.warning("buildIndexes: collapsed \(names.count - self.nameIndex.count) duplicate lowercased canonical name(s) in nameIndex")
            }
            var ax: [String: Int64] = [:]
            for (alias, sid) in aliases where ax[alias] == nil {
                ax[alias] = sid
            }
            self.aliasIndex = ax
            self.sourceDisplayNames = Dictionary(displayNames, uniquingKeysWith: { first, _ in first })
        } catch {
            logger.error("Failed to build indexes: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Human-readable name for a source slug. Returns the slug itself as a
    /// safe fallback if the source is unknown (e.g. an applied DB has a slug
    /// our bundled `sources` table doesn't recognise).
    func sourceDisplayName(forSlug slug: String) -> String {
        sourceDisplayNames[slug] ?? slug
    }

    // MARK: - Public lookup API

    /// Look up by exact canonical name (case-insensitive).
    ///
    /// **Raw library row — bypasses the user's custom-substance overlay.**
    /// App code must resolve through ``SubstanceLibrary/lookup(_:)`` instead;
    /// this stays `internal` (not `fileprivate`) only because
    /// `MechanismOfActionTests` exercises the raw store directly.
    func lookup(_ name: String) -> Substance? {
        guard let id = nameIndex[name.lowercased()] else { return nil }
        return resolveSubstance(id: id, canonicalName: name)
    }

    /// Look up by canonical name OR any alias (case-insensitive).
    ///
    /// **Raw library row — bypasses the user's custom-substance overlay.**
    /// App code must resolve through the overlay-aware ``SubstanceLibrary``
    /// façade (now in its own file, so this is `internal` rather than
    /// `fileprivate`); the façade remains the only intended resolution path.
    func lookupByNameOrAlias(_ nameOrAlias: String) -> Substance? {
        guard let id = substanceID(forNameOrAlias: nameOrAlias) else { return nil }
        return resolveSubstance(id: id, canonicalName: nameOrAlias)
    }

    /// Resolve a substance *name or alias* to its library id, mirroring
    /// ``lookupByNameOrAlias(_:)``'s canonical-then-alias precedence.
    ///
    /// The per-field pharmacology and detail accessors resolve through this rather
    /// than `nameIndex` alone, so a substance dosed or queried by a common alias
    /// (e.g. `"LSD"` → canonical `"Lysergic Acid Diethylamide"`) still resolves its
    /// bindings / PK / molar-mass instead of returning empty. Without it the
    /// tolerance engine saw LSD as having *no* pharmacology at all and silently
    /// dropped it.
    func substanceID(forNameOrAlias name: String) -> Int64? {
        let key = name.lowercased()
        return nameIndex[key] ?? aliasIndex[key]
    }

    /// All substances in the library. Lazily resolves on first access; the
    /// resolved array is *not* cached as a unit (resolvedCache caches per
    /// substance so partial fills still benefit from prior work).
    var all: [Substance] {
        if let cached = allCache { return cached }
        let resolved = Self.loadAllSubstancesBatch(db: substancesDB, order: enabledSourceOrder)
        allCache = resolved
        batchByName = nil
        batchByID = nil
        // Intentionally NOT writing to resolvedCache: the batch path omits
        // mechanism / subjective effects / tolerance (loaded by lookup() on
        // demand for the detail view). Poisoning the per-substance cache
        // with partial data would make detail views miss those fields.
        return resolved
    }

    /// Await the off-main `allCache` prefill started in `init` (or, if the
    /// prewarm was disabled or already nilled, resolve it synchronously now).
    /// The journal calls this before deriving so its per-entry resolution lands
    /// on the batch cache (``timelineRow(_:)``) rather than ~50 cold heavy
    /// `resolveSubstance` reads on the main actor at launch.
    func ensureAllLoaded() async {
        if allCache != nil { return }
        if let prewarmTask {
            await prewarmTask.value
            if allCache != nil { return }
        }
        // Cold path — the prewarm was disabled, or it published under a source
        // order that's since changed (`reloadSourceOrder` nils `allCache`).
        // Resolve off-main on the batch connection and publish; never pay the
        // ~500 ms batch build synchronously on the main actor.
        let db = substancesBatchDB
        let order = enabledSourceOrder
        let resolved = await Task.detached(priority: .userInitiated) {
            Self.loadAllSubstancesBatch(db: db, order: order)
        }.value
        guard allCache == nil, enabledSourceOrder == order else { return }
        allCache = resolved
        batchByName = nil
        batchByID = nil
    }

    /// The name/alias-keyed view over the batch cache, built lazily on first
    /// use and reused until `allCache` is invalidated.
    private func batchIndex() -> [String: Substance] {
        if let batchByName { return batchByName }
        let rows = all
        var index: [String: Substance] = [:]
        index.reserveCapacity(rows.count * 2)
        for row in rows {
            // Canonical name wins ties; aliases only fill gaps so a shared alias
            // never shadows a real substance's own row.
            index[row.name.lowercased()] = row
            for alias in row.aliases {
                let key = alias.lowercased()
                if index[key] == nil { index[key] = row }
            }
        }
        batchByName = index
        return index
    }

    /// Row id → lightweight `Substance`, built once from the batch cache and the
    /// `nameIndex` (canonical name → id). Lets ``search`` resolve ranked ids
    /// without SQL. Warms `all` via ``batchIndex()`` on first use.
    private func batchByIDIndex() -> [Int64: Substance] {
        if let batchByID { return batchByID }
        let byName = batchIndex()
        var map: [Int64: Substance] = [:]
        map.reserveCapacity(nameIndex.count)
        for (key, id) in nameIndex where map[id] == nil {
            if let substance = byName[key] { map[id] = substance }
        }
        batchByID = map
        return map
    }

    /// Lightweight library row for the journal/timeline path — category, routes,
    /// dose-ranges, durations, half-life, aliases — resolved from the batch
    /// cache without the heavy per-substance SQL. Returns `nil` only when the
    /// name matches no library substance (the caller then falls back to the full
    /// overlay-aware lookup, which also covers custom-only substances).
    func timelineRow(_ nameOrAlias: String) -> Substance? {
        batchIndex()[nameOrAlias.lowercased()]
    }

    /// Exact-canonical lightweight projection for the **detail shell** — the hot
    /// header/dose/duration fields from the warm batch cache, with **no** heavy
    /// per-field resolve. Returns `nil` unless the batch cache is already warm
    /// **and** the name is a canonical substance (same exactness as ``lookup``),
    /// so a detail push renders its header instantly from cache when it can, and
    /// the caller cleanly falls back to the full resolve otherwise. Never
    /// triggers a cold `all` build on the calling (main) actor.
    func shellRow(_ name: String) -> Substance? {
        guard allCache != nil, nameIndex[name.lowercased()] != nil else { return nil }
        return batchIndex()[name.lowercased()]
    }

    /// Batch-load every substance with ~12 SQL queries instead of ~21k
    /// (12 per-substance × 1785). Uses `ROW_NUMBER() OVER (PARTITION BY …)`
    /// to pick the highest-priority source per (substance, field) in a
    /// single query, then groups the rows in memory.
    /// Rank routes by `RouteOfAdministration.allCases` order — oral first,
    /// sublingual second, intravenous mid-list, etc. — so substances default
    /// to the route a typical user would log first.
    private nonisolated static let routeRanks: [RouteOfAdministration: Int] = Dictionary(
        uniqueKeysWithValues: RouteOfAdministration.allCases.enumerated().map { ($1, $0) },
    )
    nonisolated static func routeRank(_ r: RouteOfAdministration) -> Int {
        routeRanks[r] ?? Int.max
    }

    /// One resolved (salt-tagged or unspecified) dose/duration row for a route,
    /// before it's folded into a ``SubstanceRoute``. `salt == nil` is the
    /// unspecified/base form that the vast majority of substances use.
    struct RouteVariant {
        let salt: String?
        let unit: String
        let doses: DoseRange
        let duration: DurationProfile?
        /// Curated ordering rank (0 = the default salt); `nil` sorts last.
        var rank: Int?
        /// Mass fraction of the elemental active for this salt, if known.
        var elementalFraction: Double?
    }

    /// Fold the per-salt dose/duration variants of a single route into one
    /// ``SubstanceRoute``. When salt-tagged variants exist they become
    /// ``SubstanceRoute/saltForms`` (ordered by label, default = first), and the
    /// route's top-level `unit`/`doses`/`duration` mirror that default so
    /// salt-unaware code transparently gets the default form. With no salt tags
    /// the single base variant populates the route directly (`saltForms == nil`).
    private nonisolated static func makeRoute(
        route: RouteOfAdministration,
        variants: [RouteVariant],
        protocolDosing: ProtocolDosing? = nil,
        durationOfAction: DurationOfAction? = nil,
    ) -> SubstanceRoute {
        // Order by curated `salt_rank` (0 = default); fall back to label for ties
        // or when no rank is set (older DBs), so the default is data-driven, not
        // alphabetical-by-accident.
        let tagged = variants.filter { $0.salt != nil }.sorted {
            ($0.rank ?? Int.max, $0.salt!) < ($1.rank ?? Int.max, $1.salt!)
        }
        guard let first = tagged.first else {
            // No salt dimension — use the base (unspecified) variant.
            let base = variants.first
            return SubstanceRoute(
                route: route, unit: base?.unit ?? "mg",
                doses: base?.doses ?? DoseRange(), duration: base?.duration,
                protocolDosing: protocolDosing, durationOfAction: durationOfAction,
            )
        }
        let saltForms = tagged.map {
            SaltVariant(
                saltForm: $0.salt!, unit: $0.unit, doses: $0.doses,
                duration: $0.duration, elementalFraction: $0.elementalFraction,
            )
        }
        return SubstanceRoute(
            route: route, unit: first.unit, doses: first.doses, duration: first.duration,
            protocolDosing: protocolDosing, durationOfAction: durationOfAction, saltForms: saltForms,
        )
    }

    /// Identifies a (substance, route, salt) tuple in the set-based route
    /// resolver. `salt == nil` is the unspecified/base form the vast majority
    /// of substances use; a handful (Magnesium, Lithium) carry per-salt rows.
    ///
    /// `nonisolated` so its synthesized `Hashable` conformance is usable from
    /// the `nonisolated static` resolver (which runs off-main during the
    /// library prewarm) — without it the default `MainActor` isolation would
    /// taint the conformance and reject the off-main dictionary keying.
    private nonisolated struct RouteSaltKey: Hashable { let sid: Int64; let route: String; let salt: String? }

    /// The **single** set-based dose/duration route resolver, shared by the
    /// batch loader and the per-substance detail/`lookup` path. Given a set of
    /// substance ids it runs **one windowed query per table** (`dose_ranges`,
    /// `durations`) — partitioned by `(substance_id, route, salt_form)`
    /// (durations also by `phase`) and restricted to `substance_id IN (…)` —
    /// then groups the rows in Swift and assembles each substance's dose-bearing
    /// `[SubstanceRoute]` via ``makeRoute`` (the single salt-fold point).
    ///
    /// This collapses the former detail-path N+1 — one dose query per substance,
    /// then a `resolvedDoseForRoute` per route and a per-salt
    /// `resolvedDurationForRoute` under it (~10-15 tiny queries) — into a
    /// constant two queries regardless of id-set size, and removes the
    /// string-built `salt_form IS NULL` vs `= ?` branch: a row's `salt_form` is
    /// read as `String?` and grouped in Swift.
    ///
    /// `nonisolated` so it runs off-main during the library prewarm; every model
    /// it builds (`DoseRange`, `DurationProfile`, `SubstanceRoute`,
    /// `SaltVariant`) has a `nonisolated init`. Protocol-dosing and
    /// duration-of-action — whose model initializers are `MainActor`-isolated,
    /// and which never appeared in the browse path — are folded in afterward by
    /// the MainActor ``attachAuxiliaryRoutes(db:substanceID:doseRoutes:)`` on the
    /// detail path only.
    ///
    /// The returned arrays are **not** route-rank sorted — callers sort, exactly
    /// as they did before.
    private nonisolated static func resolveRoutes(
        db: Database,
        substanceIDs: Set<Int64>,
        order: [String],
    ) throws -> [Int64: [SubstanceRoute]] {
        guard !substanceIDs.isEmpty, !order.isEmpty else { return [:] }
        let priorityCaseSQL = priorityCaseSQL(order)
        let enabledSourceListSQL = enabledSourceListSQL(order)
        // `substance_id IN (…)` over the id set. The ids are our own Int64 row
        // ids (never user input), so interpolation is safe and lets one
        // statement serve any id-set size without a parameter blowup.
        let idListSQL = substanceIDs.map(String.init).joined(separator: ", ")

        // 1. Dose ladders — highest-priority source per (substance, route, salt).
        var dosesByKey: [RouteSaltKey: (unit: String, doses: DoseRange, rank: Int?, elemental: Double?)] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT substance_id, route, salt_form, salt_rank, elemental_fraction, unit, threshold,
                   light_lower, light_upper, common_lower, common_upper,
                   strong_lower, strong_upper, heavy
              FROM (
                SELECT d.*, ROW_NUMBER() OVER (
                    PARTITION BY d.substance_id, d.route, d.salt_form
                    ORDER BY \(priorityCaseSQL) ASC) AS rn
                  FROM dose_ranges d
                  JOIN sources src ON src.id = d.source_id
                 WHERE d.substance_id IN (\(idListSQL))
                   AND src.slug IN (\(enabledSourceListSQL))
            ) WHERE rn = 1
        """) {
            let key = RouteSaltKey(sid: row["substance_id"], route: row["route"], salt: row["salt_form"])
            let dose = DoseRange(
                threshold: row["threshold"],
                light: rangeFrom(lower: row["light_lower"], upper: row["light_upper"]),
                common: rangeFrom(lower: row["common_lower"], upper: row["common_upper"]),
                strong: rangeFrom(lower: row["strong_lower"], upper: row["strong_upper"]),
                heavy: row["heavy"],
            )
            dosesByKey[key] = (
                row["unit"] ?? "mg", dose,
                (row["salt_rank"] as Int64?).map(Int.init), row["elemental_fraction"],
            )
        }

        // 2. Durations — highest-priority source *per phase* so different
        // sources can contribute different phases (curated supplies onset/peak/
        // offset while PsychonautWiki fills comeup/afterglow). Keyed by
        // (substance, route, salt); a salt-tagged dose variant takes its own
        // salt's duration, the unspecified base takes the NULL-salt rows.
        let durationByKey = try resolveDurations(
            db: db, idListSQL: idListSQL,
            priorityCaseSQL: priorityCaseSQL, enabledSourceListSQL: enabledSourceListSQL,
        )

        // Assemble dose-bearing routes. Per-salt variants of a route fold into
        // one SubstanceRoute (default salt mirrored at top level by makeRoute).
        var result: [Int64: [SubstanceRoute]] = [:]
        result.reserveCapacity(substanceIDs.count)
        var variantsByID: [Int64: [String: [RouteVariant]]] = [:]
        for (key, value) in dosesByKey {
            variantsByID[key.sid, default: [:]][key.route, default: []].append(
                RouteVariant(
                    salt: key.salt, unit: value.unit, doses: value.doses,
                    duration: durationByKey[key],
                    rank: value.rank, elementalFraction: value.elemental,
                ),
            )
        }
        for (sid, variantsByRoute) in variantsByID {
            let routes = variantsByRoute.map { routeStr, variants in
                makeRoute(route: RouteOfAdministration.from(string: routeStr), variants: variants)
            }
            if !routes.isEmpty { result[sid] = routes }
        }
        return result
    }

    /// Windowed per-(substance, route, salt, phase) duration resolution shared
    /// by ``resolveRoutes`` and the detail path's auxiliary route fill, so the
    /// phase-merge logic lives in exactly one place.
    private nonisolated static func resolveDurations(
        db: Database, idListSQL: String,
        priorityCaseSQL: String, enabledSourceListSQL: String,
    ) throws -> [RouteSaltKey: DurationProfile] {
        var phasesByKey: [RouteSaltKey: [String: DurationRange]] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT substance_id, route, salt_form, phase, min_minutes, max_minutes
              FROM (
                SELECT du.substance_id, du.route, du.salt_form, du.phase,
                       du.min_minutes, du.max_minutes,
                       ROW_NUMBER() OVER (
                           PARTITION BY du.substance_id, du.route, du.phase, du.salt_form
                           ORDER BY \(priorityCaseSQL) ASC) AS rn
                  FROM durations du
                  JOIN sources src ON src.id = du.source_id
                 WHERE du.substance_id IN (\(idListSQL))
                   AND src.slug IN (\(enabledSourceListSQL))
            ) WHERE rn = 1
        """) {
            let key = RouteSaltKey(sid: row["substance_id"], route: row["route"], salt: row["salt_form"])
            phasesByKey[key, default: [:]][row["phase"]] = DurationRange(
                min: row["min_minutes"], max: row["max_minutes"],
            )
        }
        var durationByKey: [RouteSaltKey: DurationProfile] = [:]
        for (key, phases) in phasesByKey {
            durationByKey[key] = DurationProfile(
                onset: phases["onset"], comeup: phases["comeup"],
                peak: phases["peak"], offset: phases["offset"],
                afterglow: phases["afterglow"], total: phases["total"],
            )
        }
        return durationByKey
    }

    private nonisolated static func loadAllSubstancesBatch(db queue: DatabaseQueue, order: [String]) -> [Substance] {
        guard !order.isEmpty else { return [] }
        // Build the priority/source SQL fragments once up front so the read
        // closure captures plain strings (and statics) instead of `self` —
        // that's what lets the whole resolve run off the main actor.
        let priorityCaseSQL = priorityCaseSQL(order)
        let enabledSourceListSQL = enabledSourceListSQL(order)
        do {
            return try queue.read { db in
                let allRows = try Row.fetchAll(
                    db,
                    sql:
                    "SELECT id, canonical_name, display_name, display_class, regulatory_status, duration_implausible, popularity, is_stub FROM substances ORDER BY canonical_name COLLATE NOCASE",
                )
                let ids: [Int64] = allRows.map { $0["id"] }
                let names: [Int64: String] = Dictionary(
                    uniqueKeysWithValues:
                    allRows.map { ($0["id"], $0["canonical_name"] as String) },
                )
                // Display-name overrides — browse rows show this as the title when set.
                var displayNameByID: [Int64: String] = [:]
                // Curated popularity scores — drives the category-browse sort.
                var popularityByID: [Int64: Double] = [:]
                // Display-policy fields — loaded in the cheap batch path because
                // every browse row needs the class for filtering + dose gating.
                var displayClassByID: [Int64: CompoundDisplayClass] = [:]
                var regulatoryByID: [Int64: String] = [:]
                var durationImplausibleByID: [Int64: Bool] = [:]
                var isStubByID: [Int64: Bool] = [:]
                for row in allRows {
                    let sid: Int64 = row["id"]
                    if let raw: String = row["display_class"], let cls = CompoundDisplayClass(rawValue: raw) {
                        displayClassByID[sid] = cls
                    }
                    if let reg: String = row["regulatory_status"] { regulatoryByID[sid] = reg }
                    durationImplausibleByID[sid] = (row["duration_implausible"] as Int64? ?? 0) != 0
                    if let dn: String = row["display_name"] { displayNameByID[sid] = dn }
                    popularityByID[sid] = row["popularity"] as Double? ?? 0
                    isStubByID[sid] = (row["is_stub"] as Int64? ?? 0) != 0
                }

                // Aliases — union across sources.
                var aliasesByID: [Int64: [String]] = [:]
                for row in try Row.fetchAll(
                    db,
                    sql:
                    "SELECT substance_id, alias FROM aliases ORDER BY alias",
                ) {
                    let sid: Int64 = row["substance_id"]
                    aliasesByID[sid, default: []].append(row["alias"])
                }

                // Category — priority-resolved, with the non-informative "Other"
                // sunk below any specific category (mirrors `resolvedCategory`).
                let categoryRows = try Row.fetchAll(db, sql: """
                    SELECT substance_id, category FROM (
                        SELECT c.substance_id, c.category,
                               ROW_NUMBER() OVER (PARTITION BY c.substance_id
                                                  ORDER BY (c.category = 'Other'
                                                            AND src.slug != 'piru-curated') ASC,
                                                           \(priorityCaseSQL) ASC) AS rn
                          FROM categories c
                          JOIN sources src ON src.id = c.source_id
                         WHERE src.slug IN (\(enabledSourceListSQL))
                    ) WHERE rn = 1
                """)
                var categoryByID: [Int64: SubstanceCategory] = [:]
                for row in categoryRows {
                    let raw: String = row["category"]
                    let cat = SubstanceCategory(rawValue: raw) ?? SubstanceCategory.from(tripSitCategory: raw)
                    categoryByID[row["substance_id"]] = cat
                }

                // Additional browse homes (curated multi-class compounds).
                var extraCategoriesByID: [Int64: [SubstanceCategory]] = [:]
                for row in try Row.fetchAll(
                    db, sql: "SELECT substance_id, category FROM browse_extra_categories",
                ) {
                    let raw: String = row["category"]
                    guard let cat = SubstanceCategory(rawValue: raw) else { continue }
                    extraCategoriesByID[row["substance_id"], default: []].append(cat)
                }

                // Tags — union across enabled sources.
                var tagsByID: [Int64: [String]] = [:]
                for row in try Row.fetchAll(db, sql: """
                    SELECT DISTINCT t.substance_id, t.tag
                      FROM tags t
                      JOIN sources src ON src.id = t.source_id
                     WHERE src.slug IN (\(enabledSourceListSQL))
                     ORDER BY t.tag
                """) {
                    tagsByID[row["substance_id"], default: []].append(row["tag"])
                }

                // Routes (dose / duration / protocol / duration-of-action) —
                // resolved set-based through the single shared resolver. One
                // windowed query per table over the full id set; per-salt
                // ladders fold into `SubstanceRoute.saltForms`, and duration-/
                // protocol-/DOA-only routes are surfaced too.
                let routesByID = try Self.resolveRoutes(db: db, substanceIDs: Set(ids), order: order)

                // Half-life — priority-resolved.
                var halfLifeByID: [Int64: Double] = [:]
                for row in try Row.fetchAll(db, sql: """
                    SELECT substance_id, half_life_minutes FROM (
                        SELECT h.substance_id, h.half_life_minutes,
                               ROW_NUMBER() OVER (PARTITION BY h.substance_id
                                                  ORDER BY \(priorityCaseSQL) ASC) AS rn
                          FROM half_lives h
                          JOIN sources src ON src.id = h.source_id
                         WHERE src.slug IN (\(enabledSourceListSQL))
                    ) WHERE rn = 1
                """) {
                    halfLifeByID[row["substance_id"]] = row["half_life_minutes"]
                }

                // Effects — union, localized via the controlled vocabulary so a
                // zh user sees translated labels even on English-only-source
                // substances. DISTINCT on the resolved label folds orthography
                // variants that share a vocab_id into one entry.
                var effectsByID: [Int64: [String]] = [:]
                let effectLabelSQL = Self.localizedEffectLabelSQL(Self.contentLanguage)
                for row in try Row.fetchAll(db, sql: """
                    SELECT DISTINCT e.substance_id, \(effectLabelSQL) AS text
                      FROM effects e
                      JOIN sources src ON src.id = e.source_id
                     WHERE src.slug IN (\(enabledSourceListSQL))
                     ORDER BY text
                """) {
                    effectsByID[row["substance_id"], default: []].append(row["text"])
                }

                // Cited sources — distinct slugs touching any per-substance row.
                var sourcesByID: [Int64: [String]] = [:]
                for row in try Row.fetchAll(db, sql: """
                    SELECT DISTINCT uses.substance_id, src.slug FROM (
                        SELECT substance_id, source_id FROM categories
                        UNION SELECT substance_id, source_id FROM dose_ranges
                        UNION SELECT substance_id, source_id FROM durations
                        UNION SELECT substance_id, source_id FROM half_lives
                        UNION SELECT substance_id, source_id FROM mechanisms_summary
                        UNION SELECT substance_id, source_id FROM bindings
                    ) uses
                    JOIN sources src ON src.id = uses.source_id
                    WHERE src.slug IN (\(enabledSourceListSQL))
                    ORDER BY src.slug
                """) {
                    sourcesByID[row["substance_id"], default: []].append(row["slug"])
                }

                // Assemble. Mechanism / subjective effects / tolerance are
                // lazily resolved on detail-view open via `lookup()` — they
                // pull in 20-row binding lists and are too heavy to load for
                // every substance in the library.
                return ids.compactMap { sid in
                    guard let name = names[sid] else { return nil }
                    let aliases = aliasesByID[sid] ?? []
                    let tags = tagsByID[sid] ?? []
                    var routes = routesByID[sid] ?? []
                    // Sort by RouteOfAdministration.allCases order so the
                    // default route is the most-common ROA (oral first,
                    // then sublingual / insufflation / inhalation /
                    // intravenous / etc.). Without this the dict iteration
                    // is undefined and substances like Diazepam would
                    // default to IV instead of oral.
                    routes.sort { Self.routeRank($0.route) < Self.routeRank($1.route) }
                    let defaultRoute = routes.first?.route
                        ?? RouteOfAdministration.from(string: tags.contains("inhalation") ? "inhalation" : "oral")
                    return Substance(
                        name: name, displayName: displayNameByID[sid], aliases: aliases,
                        category: categoryByID[sid] ?? .other,
                        extraBrowseCategories: extraCategoriesByID[sid] ?? [],
                        defaultRoute: defaultRoute, routes: routes,
                        effects: effectsByID[sid] ?? [],
                        subjectiveEffects: [],
                        toleranceInfo: nil,
                        halfLifeMinutes: halfLifeByID[sid],
                        sources: sourcesByID[sid] ?? [],
                        mechanismOfAction: nil,
                        tags: tags,
                        displayClass: displayClassByID[sid] ?? .recreational,
                        regulatoryStatus: regulatoryByID[sid],
                        durationImplausible: durationImplausibleByID[sid] ?? false,
                        popularity: popularityByID[sid] ?? 0,
                        isStub: isStubByID[sid] ?? false,
                    )
                }
            }
        } catch {
            logger.error("loadAllSubstancesBatch failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    var count: Int {
        allNames.count
    }

    /// Browse-category histogram: for every category a card might show, the
    /// count of browse-surfacing substances that land in it (under their
    /// primary `category` **or** any curated `extraBrowseCategories`). This is
    /// exactly `substances(in: c).count` for each `c`, computed in **one**
    /// bucketing sweep over the batch projection instead of one `.filter` pass
    /// per category — so the Library cards' counts are a single dict lookup.
    ///
    /// Cheap on its own (no per-substance `resolveSubstance`), but it does read
    /// `all`. Call it after ``ensureAllLoaded()`` so the underlying batch cache
    /// is warm and this stays a pure in-memory bucketing — never a cold
    /// main-thread resolve.
    func categorySummary() -> [SubstanceCategory: Int] {
        if let cached = categorySummaryCache { return cached }
        var counts: [SubstanceCategory: Int] = [:]
        for substance in all where substance.displayClass.surfacesInBrowse {
            counts[substance.category, default: 0] += 1
            for extra in substance.extraBrowseCategories where extra != substance.category {
                counts[extra, default: 0] += 1
            }
        }
        categorySummaryCache = counts
        return counts
    }

    /// Substances in a single category. Uses the per-substance category
    /// resolver, so a substance whose categories differ across sources lands
    /// in whichever category the highest-priority enabled source assigns.
    func substances(in category: SubstanceCategory) -> [Substance] {
        if let cached = substancesByCategoryCache[category] { return cached }
        // Non-recreational compounds (antibiotics, …) stay searchable for
        // medication tracking but are hidden from recreational category browse.
        // A substance lands here under its primary `category` OR any curated
        // `extraBrowseCategories` (intentional multi-class homes).
        let filtered = all.filter {
            ($0.category == category || $0.extraBrowseCategories.contains(category))
                && $0.displayClass.surfacesInBrowse
        }
        substancesByCategoryCache[category] = filtered
        return filtered
    }

    /// Every benzodiazepine carrying a cited diazepam-equivalence, name-sorted,
    /// for the equivalence converter tool. One batched window query picks the
    /// highest-priority enabled source per substance — the same resolution
    /// ``resolvedDiazepamEquivalent(db:substanceID:)`` does per detail, but
    /// without N+1-resolving every benzo's full record. Cached after first load.
    func benzoEquivalences() -> [BenzoEquivalence] {
        if let cached = benzoEquivalenceCache { return cached }
        let order = enabledSourceOrder
        guard !order.isEmpty else { return [] }
        let priorityCaseSQL = Self.priorityCaseSQL(order)
        let enabledSourceListSQL = Self.enabledSourceListSQL(order)
        let result: [BenzoEquivalence] = (try? substancesDB.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT s.canonical_name AS name, s.display_name AS display_name,
                       d.dose_mg AS dose_mg, d.equivalent_diazepam_mg AS eq_mg,
                       d.display_text AS display_text
                  FROM (
                    SELECT de.*, ROW_NUMBER() OVER (
                        PARTITION BY de.substance_id
                        ORDER BY \(priorityCaseSQL) ASC) AS rn
                      FROM diazepam_equivalents de
                      JOIN sources src ON src.id = de.source_id
                     WHERE src.slug IN (\(enabledSourceListSQL))
                  ) d
                  JOIN substances s ON s.id = d.substance_id
                 WHERE d.rn = 1
                 ORDER BY s.canonical_name COLLATE NOCASE
            """)
            return rows.map { row in
                BenzoEquivalence(
                    name: row["name"],
                    displayName: (row["display_name"] as String?) ?? row["name"],
                    equivalent: DiazepamEquivalent(
                        doseMg: row["dose_mg"],
                        equivalentDiazepamMg: row["eq_mg"],
                        displayText: row["display_text"],
                    ),
                )
            }
        }) ?? []
        benzoEquivalenceCache = result
        return result
    }

    /// Categories that have at least one browsable substance after resolution.
    /// Derived from the ``categorySummary()`` histogram so it can never disagree
    /// with the cards' counts.
    var nonEmptyCategories: [SubstanceCategory] {
        if let cached = nonEmptyCategoriesCache { return cached }
        let summary = categorySummary()
        let result = SubstanceCategory.allCases.filter { (summary[$0] ?? 0) > 0 }
        nonEmptyCategoriesCache = result
        return result
    }

    // MARK: - Search

    /// Ranked search: exact name → alias → prefix → contains → fuzzy.
    ///
    /// Resolves from the warm batch cache (no per-result SQL). Synchronous entry
    /// kept for tests and non-interactive callers; the interactive search field
    /// uses ``searchAsync(_:limit:)`` so the ranking never runs on the main thread.
    func search(_ query: String, limit: Int = 50) -> [Substance] {
        Self.rankedSearch(
            query, nameIndex: nameIndex, aliasIndex: aliasIndex,
            idToSubstance: batchByIDIndex(), limit: limit,
        )
    }

    /// Off-main ranked search: snapshot the (Sendable) indexes on the main actor,
    /// then rank + resolve on a background task. The keystroke handler awaits this
    /// instead of calling `search` directly, so neither the index scan / fuzzy
    /// pass nor result resolution stalls the keyboard. The snapshots are
    /// copy-on-write dictionaries, so handing them to the detached task is cheap.
    func searchAsync(_ query: String, limit: Int = 50) async -> [Substance] {
        await ensureAllLoaded()
        let names = nameIndex
        let aliases = aliasIndex
        let byID = batchByIDIndex()
        return await Task.detached(priority: .userInitiated) {
            Self.rankedSearch(query, nameIndex: names, aliasIndex: aliases, idToSubstance: byID, limit: limit)
        }.value
    }

    /// Pure ranking over the index snapshots — runnable on any thread. Order is
    /// identical to the original (exact → prefix → contains → fuzzy); only the
    /// resolution changed from per-id SQL to a batch-cache dict hit.
    nonisolated static func rankedSearch(
        _ query: String,
        nameIndex: [String: Int64],
        aliasIndex: [String: Int64],
        idToSubstance: [Int64: Substance],
        limit: Int,
    ) -> [Substance] {
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
            if key.hasPrefix(q) { prefixIDs.append(id); seen.insert(id) } else if key.contains(q) { containsIDs.append(id); seen.insert(id) }
        }
        for (key, id) in aliasIndex {
            guard !seen.contains(id) else { continue }
            if key.hasPrefix(q) { prefixIDs.append(id); seen.insert(id) } else if key.contains(q) { containsIDs.append(id); seen.insert(id) }
        }

        var ranked: [Int64] = exactIDs + prefixIDs + containsIDs
        if ranked.count > limit {
            ranked = Array(ranked.prefix(limit))
        }
        if ranked.count < limit, q.count >= 4 {
            let needed = limit - ranked.count
            ranked.append(contentsOf: fuzzyMatch(q, nameIndex: nameIndex, excluding: seen, limit: needed))
        }
        return ranked.prefix(limit).compactMap { idToSubstance[$0] }
    }

    private nonisolated static func fuzzyMatch(_ query: String, nameIndex: [String: Int64], excluding seen: Set<Int64>, limit: Int) -> [Int64] {
        let maxDist = max(1, Int(Double(query.count) * 0.3))
        var matches: [(Int64, Int)] = []
        for (key, id) in nameIndex where !seen.contains(id) {
            let d = levenshtein(query, key)
            if d <= maxDist { matches.append((id, d)) }
        }
        return matches.sorted { $0.1 < $1.1 }.prefix(limit).map(\.0)
    }

    private nonisolated static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0 ... b.count)
        var curr = [Int](repeating: 0, count: b.count + 1)
        for i in 1 ... a.count {
            curr[0] = i
            for j in 1 ... b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[b.count]
    }

    // MARK: - Substance resolver (source-priority aware)

    /// Test-only override for the resolved content language. nil = derive from
    /// the app's UI language (``contentLanguage``). Lets tests exercise the
    /// locale-first text resolution without changing the process locale.
    var languageOverride: ContentLanguage?

    private func resolveSubstance(id: Int64, canonicalName _: String?) -> Substance? {
        let appLanguage = languageOverride ?? Self.contentLanguage
        // Language is part of the cache key so a mid-session app-language change
        // re-resolves locale-first text instead of serving stale-language rows.
        let cacheKey = "\(id)|\(appLanguage.rawValue)"
        if let cached = resolvedCache[cacheKey] { return cached }

        do {
            let resolved = try substancesDB.read { db -> Substance? in
                guard let coreRow = try Row.fetchOne(db, sql: "SELECT canonical_name, display_name, display_class, regulatory_status, duration_implausible, cas, inchikey, formula, pubchem_cid, molecular_weight, popularity, is_stub, drug_community_slug, freeodwiki_slug, smiles, iupac_name, logp, logd, pka, tpsa, hba, hbd, ld50_oral_mg_per_kg, ld50_dermal_mg_per_kg, melting_point_c, boiling_point_c FROM substances WHERE id = ?", arguments: [id]) else {
                    return nil
                }
                let name: String = coreRow["canonical_name"]
                let displayName: String? = coreRow["display_name"]
                let displayClass = (coreRow["display_class"] as String?).flatMap(CompoundDisplayClass.init(rawValue:)) ?? .recreational
                let regulatoryStatus: String? = coreRow["regulatory_status"]
                let durationImplausible = (coreRow["duration_implausible"] as Int64? ?? 0) != 0
                let cas: String? = coreRow["cas"]
                let inchikey: String? = coreRow["inchikey"]
                let formula: String? = coreRow["formula"]
                let pubchemCID = (coreRow["pubchem_cid"] as Int64?).map(Int.init)
                let molarMass = coreRow["molecular_weight"] as Double?
                let popularity = coreRow["popularity"] as Double? ?? 0
                let isStub = (coreRow["is_stub"] as Int64? ?? 0) != 0
                let drugCommunitySlug: String? = coreRow["drug_community_slug"]
                let freeodwikiSlug: String? = coreRow["freeodwiki_slug"]
                let smiles: String? = coreRow["smiles"]
                let iupacName: String? = coreRow["iupac_name"]
                let physicochemical = Physicochemical(
                    logP: coreRow["logp"] as Double?,
                    logD: coreRow["logd"] as Double?,
                    pKa: coreRow["pka"] as Double?,
                    tpsa: coreRow["tpsa"] as Double?,
                    hba: (coreRow["hba"] as Int64?).map(Int.init),
                    hbd: (coreRow["hbd"] as Int64?).map(Int.init),
                    ld50OralMgPerKg: coreRow["ld50_oral_mg_per_kg"] as Double?,
                    ld50DermalMgPerKg: coreRow["ld50_dermal_mg_per_kg"] as Double?,
                    meltingPointC: coreRow["melting_point_c"] as Double?,
                    boilingPointC: coreRow["boiling_point_c"] as Double?,
                )

                let aliases = try String.fetchAll(db, sql: "SELECT alias FROM aliases WHERE substance_id = ? ORDER BY alias", arguments: [id])
                let peptideProfile = try resolvedPeptideProfile(db: db, substanceID: id)
                let references = try resolvedReferences(db: db, substanceID: id)

                let category = try resolvedCategory(db: db, substanceID: id)
                let tags = try resolvedTags(db: db, substanceID: id)
                var routes = try resolvedRoutes(db: db, substanceID: id)
                let effects = try resolvedEffects(db: db, substanceID: id, language: appLanguage)
                let subjectiveEffects = try resolvedSubjectiveEffects(db: db, substanceID: id, language: appLanguage)
                let halfLifeMinutes = try resolvedHalfLife(db: db, substanceID: id)
                let mechanism = try resolvedMechanism(db: db, substanceID: id, language: appLanguage)
                let overview = try resolvedDescription(db: db, substanceID: id, language: appLanguage)
                let sources = try citedSources(db: db, substanceID: id)
                let toleranceInfo = try resolvedTolerance(db: db, substanceID: id)
                let indications = try self.resolvedIndications(db: db, substanceID: id)
                let contraindications = try self.resolvedContraindications(db: db, substanceID: id)
                let diazepamEquivalent = try self.resolvedDiazepamEquivalent(db: db, substanceID: id)

                routes.sort { Self.routeRank($0.route) < Self.routeRank($1.route) }
                let defaultRoute = routes.first?.route
                    ?? RouteOfAdministration.from(string: tags.contains("inhalation") ? "inhalation" : "oral")

                return Substance(
                    name: name,
                    displayName: displayName,
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
                    tags: tags,
                    displayClass: displayClass,
                    regulatoryStatus: regulatoryStatus,
                    durationImplausible: durationImplausible,
                    indications: indications,
                    contraindications: contraindications,
                    diazepamEquivalent: diazepamEquivalent,
                    cas: cas,
                    inchikey: inchikey,
                    formula: formula,
                    pubchemCID: pubchemCID,
                    popularity: popularity,
                    isStub: isStub,
                    molarMass: molarMass,
                    peptideProfile: peptideProfile,
                    references: references,
                    drugCommunitySlug: drugCommunitySlug,
                    freeodwikiSlug: freeodwikiSlug,
                    overview: overview,
                    smiles: smiles,
                    iupacName: iupacName,
                    physicochemical: physicochemical.hasAnyValue ? physicochemical : nil,
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
        Self.priorityCaseSQL(enabledSourceOrder)
    }
    private var enabledSourceListSQL: String {
        Self.enabledSourceListSQL(enabledSourceOrder)
    }

    /// Pure SQL builders, parameterised by the enabled-source order so they can
    /// run on a background thread during the off-main batch prewarm (see
    /// ``loadAllSubstancesBatch(db:order:)``) as well as from the main-actor
    /// per-substance resolvers.
    ///
    /// These are rebuilt on *every* `resolveSubstance`/`resolveRoutes` call (and
    /// several times within each), yet the enabled-source order changes only
    /// when the user reorders sources — so the string-building (per-slug escape +
    /// join) showed up in launch profiles. A single-entry memo keyed by the
    /// order (value-compared, cheaper than rebuilding) collapses the repeats.
    /// The lock keeps it correct across the main-actor resolvers and the
    /// off-main batch prewarm sharing the same `static`.
    private struct SourceOrderSQL {
        let order: [String]
        let priorityCase: String
        let enabledList: String
    }

    private nonisolated static let sourceOrderSQLMemo = OSAllocatedUnfairLock<SourceOrderSQL?>(initialState: nil)

    private nonisolated static func sourceOrderSQL(_ order: [String]) -> SourceOrderSQL {
        sourceOrderSQLMemo.withLock { memo in
            if let memo, memo.order == order { return memo }
            let built = SourceOrderSQL(
                order: order,
                priorityCase: buildPriorityCaseSQL(order),
                enabledList: buildEnabledSourceListSQL(order),
            )
            memo = built
            return built
        }
    }

    /// The substance's **reference "heavy" dose** in mg — the escalation denominator for the deep
    /// tolerance gate (`dose ÷ reference`). Resolved from the substance's primary dose ladder: the
    /// **oral** route when it has one, else the first route that carries a usable range; within that
    /// route, `heavy ?? strong.upperBound ?? common.upperBound`. Returns `nil` when no ladder exists,
    /// so the deep gate stays closed (the conservative fallback).
    ///
    /// `nonisolated static` so both the cached instance path and the off-main batch resolve can call
    /// it on their own connection. Source priority mirrors ``resolveRoutes`` — the highest-priority
    /// enabled source per `(route, salt)` — so the reference matches the dose ladder the detail view
    /// shows.
    nonisolated static func referenceDoseMg(substanceID: Int64, db queue: DatabaseQueue, order: [String]) -> Double? {
        guard !order.isEmpty else { return nil }
        let priorityCaseSQL = priorityCaseSQL(order)
        let enabledSourceListSQL = enabledSourceListSQL(order)
        let rows: [(route: String, common: Double?, strong: Double?, heavy: Double?)]
        do {
            rows = try queue.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT route, common_upper, strong_upper, heavy
                      FROM (
                        SELECT d.*, ROW_NUMBER() OVER (
                            PARTITION BY d.substance_id, d.route, d.salt_form
                            ORDER BY \(priorityCaseSQL) ASC) AS rn
                          FROM dose_ranges d
                          JOIN sources src ON src.id = d.source_id
                         WHERE d.substance_id = ?
                           AND src.slug IN (\(enabledSourceListSQL))
                    ) WHERE rn = 1
                """, arguments: [substanceID]).map {
                    (route: $0["route"] ?? "", common: $0["common_upper"], strong: $0["strong_upper"], heavy: $0["heavy"])
                }
            }
        } catch {
            logger.error("referenceDoseMg failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        func reference(_ row: (route: String, common: Double?, strong: Double?, heavy: Double?)) -> Double? {
            row.heavy ?? row.strong ?? row.common
        }
        // Oral first (the dose-ladder primary route), else the first route that yields a value.
        if let oral = rows.first(where: { RouteOfAdministration.from(string: $0.route) == .oral }),
           let value = reference(oral) {
            return value
        }
        for row in rows where reference(row) != nil { return reference(row) }
        return nil
    }

    private nonisolated static func priorityCaseSQL(_ order: [String]) -> String {
        sourceOrderSQL(order).priorityCase
    }

    private nonisolated static func enabledSourceListSQL(_ order: [String]) -> String {
        sourceOrderSQL(order).enabledList
    }

    private nonisolated static func buildPriorityCaseSQL(_ order: [String]) -> String {
        guard !order.isEmpty else {
            return "999"
        }
        let cases = order.enumerated().map { idx, slug in
            "WHEN '\(slug.replacingOccurrences(of: "'", with: "''"))' THEN \(idx)"
        }.joined(separator: " ")
        return "CASE src.slug \(cases) ELSE 999 END"
    }

    private nonisolated static func buildEnabledSourceListSQL(_ order: [String]) -> String {
        if order.isEmpty { return "''" }
        return order.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }.joined(separator: ", ")
    }

    /// The app's effective UI language, normalised to a content-language tag
    /// ('zh-Hans' | 'zh-Hant' | 'en'). Drives locale-first text resolution so a
    /// Chinese source (FreeOD Wiki) wins for descriptions/effects when the app
    /// runs in Chinese. Reads `preferredLocalizations` so it follows the app's
    /// per-app language override, not just the device language.
    nonisolated static var contentLanguage: ContentLanguage {
        .current
    }

    /// SQL scalar resolving a row of `effects` (table aliased `e`) to its
    /// localized label via the controlled vocabulary (Track 1). For Chinese it
    /// returns the `effect_vocab_labels` label for the exact variant, then any
    /// broader zh label, then the raw English `e.text` fallback — so a zh user
    /// sees translated effects on *every* substance, even ones whose source data
    /// was English-only, because the label was translated once at the vocabulary
    /// level. For English it is simply `e.text` (already the canonical PW name).
    private nonisolated static func localizedEffectLabelSQL(_ language: ContentLanguage) -> String {
        guard language.isChinese else { return "e.text" }
        return """
        COALESCE(
            (SELECT lbl.label FROM effect_vocab_labels lbl
              WHERE lbl.vocab_id = e.vocab_id AND lbl.language = '\(language.rawValue)'),
            (SELECT lbl.label FROM effect_vocab_labels lbl
              WHERE lbl.vocab_id = e.vocab_id AND lbl.language LIKE 'zh%' LIMIT 1),
            e.text)
        """
    }

    private func resolvedCategory(db: Database, substanceID: Int64) throws -> SubstanceCategory? {
        let row = try Row.fetchOne(db, sql: """
            SELECT c.category
              FROM categories c
              JOIN sources src ON src.id = c.source_id
             WHERE c.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
             ORDER BY (c.category = 'Other' AND src.slug != 'piru-curated') ASC,
                      \(priorityCaseSQL) ASC
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

    /// Clinical indications — additive union across enabled sources.
    private func resolvedIndications(db: Database, substanceID: Int64) throws -> [String] {
        try String.fetchAll(db, sql: """
            SELECT DISTINCT text
              FROM indications i
              JOIN sources src ON src.id = i.source_id
             WHERE i.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
             ORDER BY text
        """, arguments: [substanceID])
    }

    /// Contraindications + boxed warnings — boxed warnings sorted first.
    private func resolvedContraindications(db: Database, substanceID: Int64) throws -> [Contraindication] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT DISTINCT text, is_boxed_warning
              FROM contraindications c
              JOIN sources src ON src.id = c.source_id
             WHERE c.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
             ORDER BY is_boxed_warning DESC, text
        """, arguments: [substanceID])
        return rows.map {
            Contraindication(text: $0["text"], isBoxedWarning: ($0["is_boxed_warning"] as Int64? ?? 0) != 0)
        }
    }

    /// Diazepam-equivalency (benzodiazepines only) — highest-priority source.
    private func resolvedDiazepamEquivalent(db: Database, substanceID: Int64) throws -> DiazepamEquivalent? {
        guard let row = try Row.fetchOne(db, sql: """
            SELECT dose_mg, equivalent_diazepam_mg, display_text
              FROM diazepam_equivalents d
              JOIN sources src ON src.id = d.source_id
             WHERE d.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
             ORDER BY \(priorityCaseSQL) ASC
             LIMIT 1
        """, arguments: [substanceID]) else { return nil }
        return DiazepamEquivalent(
            doseMg: row["dose_mg"],
            equivalentDiazepamMg: row["equivalent_diazepam_mg"],
            displayText: row["display_text"],
        )
    }

    /// Detail-path routes for one substance.
    ///
    /// The dose/duration ladders (and the per-salt fold) come from the **single**
    /// set-based ``resolveRoutes(db:substanceIDs:order:)`` — the same code path
    /// the batch loader uses, run with a one-element id set — which is what
    /// collapses the former per-route `resolvedDoseForRoute` + per-salt
    /// `resolvedDurationForRoute` N+1 into two windowed queries.
    ///
    /// The protocol-dosing and duration-of-action layers (whose model
    /// initializers are `MainActor`-isolated, so the off-main resolver can't
    /// build them — and which the browse path never surfaced) are folded in here
    /// on the main actor: attached to the dose routes, then any
    /// protocol-/DOA-/duration-only routes are appended, matching the legacy
    /// resolver's surfacing order. Still set-based — three queries for the id,
    /// not per-route.
    private func resolvedRoutes(db: Database, substanceID: Int64) throws -> [SubstanceRoute] {
        let doseRoutes = try Self.resolveRoutes(db: db, substanceIDs: [substanceID], order: enabledSourceOrder)[substanceID] ?? []
        return try attachAuxiliaryRoutes(db: db, substanceID: substanceID, doseRoutes: doseRoutes)
    }

    /// Folds protocol-dosing and duration-of-action data into a substance's
    /// dose routes and surfaces routes whose *only* data is a duration profile,
    /// a clinical schedule, or a long-acting release window. MainActor-isolated
    /// because `ProtocolDosing` / `DurationOfAction` carry MainActor-isolated
    /// initializers; the detail path is already on the main actor, and the
    /// browse path deliberately omits these (it always has).
    private func attachAuxiliaryRoutes(
        db: Database, substanceID: Int64, doseRoutes: [SubstanceRoute],
    ) throws -> [SubstanceRoute] {
        let order = enabledSourceOrder
        let priorityCaseSQL = Self.priorityCaseSQL(order)
        let enabledSourceListSQL = Self.enabledSourceListSQL(order)
        let idListSQL = String(substanceID)

        // Protocol dosing — highest-priority source per route, keyed by the
        // parsed `RouteOfAdministration` so it lines up with the dose routes'
        // enum (DB route strings like `intranasal`/`oral_er` normalize).
        var protocolByRoute: [RouteOfAdministration: (unit: String, dosing: ProtocolDosing)] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT route, unit, low_amount, high_amount, frequency,
                   titration_json, course_duration, notes
              FROM (
                SELECT p.*, ROW_NUMBER() OVER (
                    PARTITION BY p.route
                    ORDER BY \(priorityCaseSQL) ASC) AS rn
                  FROM protocol_dosing p
                  JOIN sources src ON src.id = p.source_id
                 WHERE p.substance_id = \(idListSQL)
                   AND src.slug IN (\(enabledSourceListSQL))
            ) WHERE rn = 1
        """) {
            guard let frequency = row["frequency"] as String? else { continue }
            var titration: [TitrationStep]? = nil
            if let json = row["titration_json"] as String?, let data = json.data(using: .utf8) {
                titration = try? JSONDecoder().decode([TitrationStep].self, from: data)
            }
            let dosing = ProtocolDosing(
                lowAmount: row["low_amount"],
                highAmount: row["high_amount"],
                frequency: frequency,
                titration: titration,
                courseDuration: row["course_duration"],
                notes: row["notes"],
            )
            protocolByRoute[RouteOfAdministration.from(string: row["route"])] = (row["unit"] ?? "mg", dosing)
        }

        // Duration-of-action — highest-priority source per route.
        var doaByRoute: [RouteOfAdministration: DurationOfAction] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT route, min_minutes, max_minutes
              FROM (
                SELECT da.route, da.min_minutes, da.max_minutes,
                       ROW_NUMBER() OVER (
                           PARTITION BY da.route
                           ORDER BY \(priorityCaseSQL) ASC) AS rn
                  FROM durations_of_action da
                  JOIN sources src ON src.id = da.source_id
                 WHERE da.substance_id = \(idListSQL)
                   AND src.slug IN (\(enabledSourceListSQL))
            ) WHERE rn = 1
        """) {
            guard let mn = row["min_minutes"] as Double?, let mx = row["max_minutes"] as Double? else { continue }
            doaByRoute[RouteOfAdministration.from(string: row["route"])] = DurationOfAction(minMinutes: mn, maxMinutes: mx)
        }

        // Attach protocol/DOA to the existing dose routes (re-using makeRoute so
        // the salt fold and default-mirror invariant stay single-sourced).
        var resolved: [SubstanceRoute] = doseRoutes.map { route in
            let proto = protocolByRoute[route.route]?.dosing
            let doa = doaByRoute[route.route]
            guard proto != nil || doa != nil else { return route }
            let variants: [RouteVariant] = if let saltForms = route.saltForms {
                // `saltForms` is already in curated (rank) order — preserve it by
                // feeding the index as the rank, and carry the elemental fraction,
                // so re-folding through makeRoute is order-preserving and lossless.
                saltForms.enumerated().map { idx, sv in
                    RouteVariant(
                        salt: sv.saltForm, unit: sv.unit, doses: sv.doses, duration: sv.duration,
                        rank: idx, elementalFraction: sv.elementalFraction,
                    )
                }
            } else {
                [RouteVariant(salt: nil, unit: route.unit, doses: route.doses, duration: route.duration)]
            }
            return Self.makeRoute(
                route: route.route, variants: variants,
                protocolDosing: proto, durationOfAction: doa,
            )
        }
        var haveRoutes = Set(resolved.map(\.route))

        // Duration-only routes — durations but no dose ladder. Take the NULL-salt
        // (base) duration, matching the legacy `resolvedDurationForRoute` default.
        let durationByKey = try Self.resolveDurations(
            db: db, idListSQL: idListSQL,
            priorityCaseSQL: priorityCaseSQL, enabledSourceListSQL: enabledSourceListSQL,
        )
        let durationRoutes = Set(durationByKey.keys.map(\.route))
        for routeStr in durationRoutes.sorted() {
            let ra = RouteOfAdministration.from(string: routeStr)
            guard !haveRoutes.contains(ra) else { continue }
            let duration = durationByKey[RouteSaltKey(sid: substanceID, route: routeStr, salt: nil)]
            resolved.append(SubstanceRoute(
                route: ra, unit: "mg", doses: DoseRange(), duration: duration,
                protocolDosing: protocolByRoute[ra]?.dosing,
                durationOfAction: doaByRoute[ra],
            ))
            haveRoutes.insert(ra)
        }

        // Protocol-only routes — a clinical schedule with no ladder/phases.
        for (ra, value) in protocolByRoute {
            guard !haveRoutes.contains(ra) else { continue }
            resolved.append(SubstanceRoute(
                route: ra, unit: value.unit, doses: DoseRange(), duration: nil,
                protocolDosing: value.dosing, durationOfAction: doaByRoute[ra],
            ))
            haveRoutes.insert(ra)
        }

        // Duration-of-action-only routes — long-acting depot window only.
        for (ra, value) in doaByRoute {
            guard !haveRoutes.contains(ra) else { continue }
            resolved.append(SubstanceRoute(
                route: ra, unit: "mg", doses: DoseRange(), duration: nil,
                protocolDosing: nil, durationOfAction: value,
            ))
            haveRoutes.insert(ra)
        }

        return resolved
    }

    /// Distinct primary references for a compound: the substance-level curated
    /// `sources` plus the citations attached to its dose / duration / half-life /
    /// mechanism / protocol facts. Binding citations are excluded — they have a
    /// dedicated Receptor Literature card and would swamp the list.
    private func resolvedReferences(db: Database, substanceID: Int64) throws -> [Citation] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT DISTINCT c.doi, c.pmid, c.url, c.title FROM citations c
             WHERE c.id IN (
                SELECT citation_id FROM substance_citations WHERE substance_id = :id
                UNION SELECT citation_id FROM dose_ranges        WHERE substance_id = :id
                UNION SELECT citation_id FROM durations          WHERE substance_id = :id
                UNION SELECT citation_id FROM half_lives         WHERE substance_id = :id
                UNION SELECT citation_id FROM mechanisms_summary WHERE substance_id = :id
                UNION SELECT citation_id FROM protocol_dosing    WHERE substance_id = :id
             )
             ORDER BY c.title, c.url, c.doi
             LIMIT 60
        """, arguments: ["id": substanceID])
        return rows.map { r in
            Citation(
                doi: r["doi"],
                pmid: (r["pmid"] as Int64?).map(Int.init),
                url: r["url"],
                title: r["title"],
            )
        }
    }

    private func resolvedPeptideProfile(db: Database, substanceID: Int64) throws -> PeptideProfile? {
        guard let row = try Row.fetchOne(db, sql: """
            SELECT sequence, supplied_form, typical_vial_mg, reconstitution_solvent,
                   storage_temperature, storage_light_sensitive, reconstituted_stability_days, iu_per_mg
              FROM peptide_profiles WHERE substance_id = ?
        """, arguments: [substanceID]) else { return nil }

        var storage: StorageRequirement? = nil
        if let temp = (row["storage_temperature"] as String?).flatMap(StorageRequirement.Temperature.init(rawValue:)) {
            storage = StorageRequirement(
                temperature: temp,
                lightSensitive: (row["storage_light_sensitive"] as Int64? ?? 0) != 0,
                reconstitutedStabilityDays: row["reconstituted_stability_days"],
            )
        }
        let profile = PeptideProfile(
            sequence: row["sequence"],
            suppliedForm: (row["supplied_form"] as String?).flatMap(SuppliedForm.init(rawValue:)),
            typicalVialMg: row["typical_vial_mg"],
            reconstitutionSolvent: row["reconstitution_solvent"],
            storage: storage,
            iuPerMg: row["iu_per_mg"],
        )
        return profile.hasAnyValue ? profile : nil
    }

    private nonisolated static func rangeFrom(lower: Double?, upper: Double?) -> ClosedRange<Double>? {
        guard let lo = lower, let hi = upper, lo <= hi else { return nil }
        return lo ... hi
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

    /// One locale-resolved prose row from a text table, the single definitive
    /// `LIMIT 1` pass that `resolvedDescription`/`resolvedMechanism` share:
    /// matching-language text floats above source priority, English/`und` is the
    /// fallback (see ``ContentLanguage/clauses(column:)``). The table is aliased
    /// `t`; the returned row also carries `machine_translated` + `source_slug` so
    /// callers build their typed value. `table` is a fixed internal literal (no
    /// injection surface).
    private func resolvedTextRow(
        db: Database, from table: String, selecting columns: String,
        substanceID: Int64, language: ContentLanguage,
    ) throws -> Row? {
        let lang = language.clauses(column: "t.language")
        return try Row.fetchOne(db, sql: """
            SELECT \(columns), t.machine_translated, src.slug AS source_slug
              FROM \(table) t
              JOIN sources src ON src.id = t.source_id
             WHERE t.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
               \(lang.whereAnd)
             ORDER BY \(lang.orderPrefix)\(priorityCaseSQL) ASC
             LIMIT 1
        """, arguments: [substanceID])
    }

    /// Substance overview prose (descriptions table), resolved locale-first.
    private func resolvedDescription(db: Database, substanceID: Int64, language: ContentLanguage) throws -> SubstanceOverview? {
        guard let row = try resolvedTextRow(
            db: db, from: "descriptions", selecting: "t.text",
            substanceID: substanceID, language: language,
        ) else { return nil }
        let text: String = row["text"]
        guard !text.isEmpty else { return nil }
        return SubstanceOverview(
            text: text,
            machineTranslated: (row["machine_translated"] as Int64? ?? 0) != 0,
            sourceSlug: (row["source_slug"] as String?) ?? "freeodwiki",
        )
    }

    /// Canonical key for collapsing near-synonymous binding targets in the
    /// mechanism *summary* — "NMDA receptor" → "nmda", so a measured row doesn't
    /// double-list a curated target. Strips a trailing "receptor(s)" word,
    /// lowercases, and collapses whitespace. Subunit-specific names
    /// ("GABA-A α4β3δ (extrasynaptic)") stay distinct from the coarse target.
    static func normalizedBindingTarget(_ target: String) -> String {
        var t = target.lowercased().trimmingCharacters(in: .whitespaces)
        // Drop a trailing assay/qualifier parenthetical so a measured row stated
        // under a wordier name ("DAT (release, [3H]-DA …)", "α2δ-1 (porcine
        // cortex)", "NMDA receptor (PCP site)") collapses onto its clean canonical
        // target ("dat", "α2δ-1", "nmda") — the graded flagship rows use the bare
        // target name, the enrichment layer often appends the assay in parens.
        if let paren = t.firstIndex(of: "(") {
            t = String(t[..<paren]).trimmingCharacters(in: .whitespaces)
        }
        for suffix in [" receptors", " receptor"] where t.hasSuffix(suffix) {
            t = String(t.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        return t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func resolvedMechanism(db: Database, substanceID: Int64, language: ContentLanguage) throws -> MechanismOfAction? {
        let row = try resolvedTextRow(
            db: db, from: "mechanisms_summary", selecting: "t.summary, t.description",
            substanceID: substanceID, language: language,
        )

        // Union-merge bindings across sources (curated ∪ measured) into ONE row per
        // (target, action), taking the STRONGEST tier any source attests. Each row's
        // tier is the **measurement-aware potency band** (`ReceptorStrength`): measured
        // affinity/potency WINS, with the curated `affinity_tier` only a fallback for
        // tier-only rows that carry no Kᵢ/EC₅₀/IC₅₀ (e.g. mitragynine). Measured-wins is
        // what keeps this card in lock-step with the Receptor Literature card, which
        // computes the same bands from the same values. Binding (Kᵢ) and functional
        // (EC₅₀/IC₅₀) get different cutoffs because a releaser's EC₅₀ runs ~10× higher
        // than a blocker's Kᵢ for the same strength. We GROUP BY and take MAX(tier) so a
        // potent assay never loses to a weaker sibling. Keep these cutoffs identical to
        // `ReceptorStrength` in Substance.swift.
        let bindingRows = try Row.fetchAll(db, sql: """
            SELECT target, action, MAX(tier) AS affinity, MAX(measured) AS measured, MIN(ki_nm) AS ki_nm FROM (
                SELECT b.target, b.action, b.ki_nm,
                       CASE WHEN b.ki_nm IS NOT NULL OR b.ec50_nm IS NOT NULL OR b.ic50_nm IS NOT NULL
                            THEN 1 ELSE 0 END AS measured,
                       CASE WHEN b.ki_nm   IS NOT NULL AND b.ki_nm   <   100 THEN 3
                            WHEN b.ki_nm   IS NOT NULL AND b.ki_nm   <  1000 THEN 2
                            WHEN b.ki_nm   IS NOT NULL                        THEN 1
                            WHEN b.ec50_nm IS NOT NULL AND b.ec50_nm <  1000 THEN 3
                            WHEN b.ec50_nm IS NOT NULL AND b.ec50_nm < 10000 THEN 2
                            WHEN b.ec50_nm IS NOT NULL                        THEN 1
                            WHEN b.ic50_nm IS NOT NULL AND b.ic50_nm <  1000 THEN 3
                            WHEN b.ic50_nm IS NOT NULL AND b.ic50_nm < 10000 THEN 2
                            WHEN b.ic50_nm IS NOT NULL                        THEN 1
                            ELSE COALESCE(b.affinity_tier, 1) END AS tier
                  FROM bindings b
                  JOIN sources src ON src.id = b.source_id
                 WHERE b.substance_id = ?
                   AND src.slug IN (\(enabledSourceListSQL))
            )
             GROUP BY target, action
             ORDER BY affinity DESC, ki_nm ASC NULLS LAST, LENGTH(target) ASC
             LIMIT 40
        """, arguments: [substanceID])

        struct RawHit {
            let target: String
            let action: BindingAction
            let tier: Int
            let measured: Bool
        }
        let rawHits: [RawHit] = bindingRows.compactMap { row in
            guard let target: String = row["target"],
                  let actionRaw: String = row["action"],
                  let action = BindingAction(rawValue: actionRaw) else { return nil }
            return RawHit(target: target, action: action, tier: row["affinity"], measured: (row["measured"] as Int) == 1)
        }
        // Collapse one row per receptor for the *summary* table: a measured row often restates a curated
        // target under a wordier name ("NMDA (MK-801 site, S-enantiomer)" vs the curated "NMDA"). We keep
        // the cleanest name and the curated action label, but take the **measured tier** when any measured
        // assay exists — so the summary's dots match the Receptor Literature card's (which also computes
        // `ReceptorStrength` from the same measured values) instead of showing the editorial tier. The full
        // per-assay detail still lives in the Receptor Literature disclosure.
        var groupOrder: [String] = []
        var groups: [String: [RawHit]] = [:]
        for hit in rawHits {
            let key = Self.normalizedBindingTarget(hit.target)
            if groups[key] == nil { groupOrder.append(key) }
            groups[key, default: []].append(hit)
        }
        let bindings: [ReceptorBinding] = groupOrder.compactMap { key in
            guard let hits = groups[key], !hits.isEmpty else { return nil }
            let measured = hits.filter(\.measured)
            let tier = (measured.isEmpty ? hits : measured).map(\.tier).max() ?? 1
            // Prefer a curated (clean, editorial) action label; else the strongest measured row's action.
            let action = hits.first { !$0.measured }?.action
                ?? measured.max(by: { $0.tier < $1.tier })?.action
                ?? hits[0].action
            let name = hits.map(\.target).min { $0.count < $1.count } ?? hits[0].target
            return ReceptorBinding(target: name, action: action, affinity: BindingAffinity(rawValue: tier) ?? .significant)
        }
        .sorted { $0.affinity > $1.affinity }

        // Surface measured bindings even when no curated summary row exists —
        // the detail view's mechanism composer fills missing summary text from
        // the per-name / category fallback, so substances with real receptor
        // data (e.g. mephedrone: DAT/NET/SERT releasingAgent) no longer fall
        // through to a generic "Modulator" placeholder. Return nil only when we
        // have neither a summary nor any binding.
        guard row != nil || !bindings.isEmpty else { return nil }

        return MechanismOfAction(
            summary: row?["summary"] ?? "",
            description: row?["description"] ?? "",
            primaryTargets: bindings.map(\.target),
            bindings: bindings,
        )
    }

    private func resolvedEffects(db: Database, substanceID: Int64, language: ContentLanguage) throws -> [String] {
        try String.fetchAll(db, sql: """
            SELECT DISTINCT \(Self.localizedEffectLabelSQL(language)) AS text
              FROM effects e
              JOIN sources src ON src.id = e.source_id
             WHERE e.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
             ORDER BY text
        """, arguments: [substanceID])
    }

    private func resolvedSubjectiveEffects(db: Database, substanceID: Int64, language: ContentLanguage) throws -> [SubjectiveEffect] {
        func fetch(_ langFilter: String) throws -> [SubjectiveEffect] {
            let rows = try Row.fetchAll(db, sql: """
                SELECT DISTINCT se.name AS effect_name,
                                COALESCE(se.description, '') AS effect_description
                  FROM subjective_effects se
                  JOIN sources src ON src.id = se.source_id
                 WHERE se.substance_id = ?
                   AND src.slug IN (\(enabledSourceListSQL))
                   \(langFilter)
                 ORDER BY se.name
            """, arguments: [substanceID])
            return rows.map { SubjectiveEffect(name: $0["effect_name"], description: $0["effect_description"]) }
        }
        // Chinese: show the zh set if the substance has one, else fall back to
        // English (don't blank the section). English: never show raw zh.
        if language.isChinese {
            let zh = try fetch("AND se.language LIKE 'zh%'")
            return zh.isEmpty ? try fetch("AND se.language IN ('en', 'und')") : zh
        }
        return try fetch("AND se.language IN ('en', 'und')")
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
            buildRate: row["build_rate"],
        )
    }

    private func citedSources(db: Database, substanceID: Int64) throws -> [String] {
        // Source attribution shown to the user: the set of source display
        // names that contributed any fact for this substance.
        try String.fetchAll(db, sql: """
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
    }

    // MARK: - Advanced search (Pharma Nerd surface)

    /// One per-route pharmacokinetic row joined to its source + citation.
    /// Surfaced in the detail view's Pharmacokinetics disclosure (pharma-nerd
    /// tier). Every numeric is from primary literature with explicit attribution;
    /// fields are optional because most rows populate only a subset.
    struct PKRouteHit: Identifiable, Hashable {
        let id: Int64
        let route: String
        let bioavailabilityPct: Double?
        let cmaxNgPerMl: Double?
        let tmaxMin: Double?
        let halfLifeMin: Double?
        let vdLPerKg: Double?
        let clearanceMlPerMinPerKg: Double?
        let proteinBindingPct: Double?
        let doseInStudyMg: Double?
        let subjectN: Int?
        let demographics: String?
        let sourceSlug: String
        let doi: String?
        let pmid: Int?
        let notes: String?
        /// Citation-verification grade for this route's values (`.unverified` when un-graded).
        var confidence: ConfidenceTier = .unverified
    }

    /// One metabolism row — an enzyme/pathway and (optionally) the metabolite it
    /// produces — joined to its source + citation. Surfaced alongside
    /// ``PKRouteHit`` in the Pharmacokinetics disclosure.
    struct MetabolismHit: Identifiable, Hashable {
        let id: Int64
        let enzyme: String
        let fractionOfClearancePct: Double?
        let metaboliteName: String?
        let metaboliteActive: Bool?
        let metabolitePotencyVsParentPct: Double?
        let sourceSlug: String
        let doi: String?
        let pmid: Int?
        let notes: String?
    }

    /// One row from the bindings table joined to its substance + source +
    /// citation. Used by advanced-search results.
    struct BindingHit: Identifiable, Hashable {
        let id: Int64
        let substanceName: String
        let target: String
        let action: String
        let kiNm: Double?
        let ec50Nm: Double?
        let ic50Nm: Double?
        let species: String?
        let sourceSlug: String
        let doi: String?
        let pmid: Int?
        /// Citation-verification grade for this binding (`.unverified` when un-graded).
        var confidence: ConfidenceTier = .unverified
    }

    /// Returns every binding row matching the predicate, *across all sources*
    /// (including disabled) so pharma-nerd users can see the literature even
    /// for sources they've deprioritised. UI labels which source supplied each
    /// row so users can apply their own trust filter.
    func bindings(
        target: String? = nil,
        kiNmAtMost: Double? = nil,
        substanceContains: String? = nil,
        limit: Int = 200,
    ) -> [BindingHit] {
        do {
            return try substancesDB.read { db in
                var sql = """
                    SELECT b.id, b.target, b.action, b.ki_nm, b.ec50_nm, b.ic50_nm, b.species, b.confidence,
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
                        ic50Nm: row["ic50_nm"],
                        species: row["species"],
                        sourceSlug: row["source_slug"],
                        doi: row["doi"],
                        pmid: row["pmid"],
                        confidence: ConfidenceTier(grade: row["confidence"]),
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
    struct RouteProvenance: Hashable {
        let doseSource: String?
        let durationSource: String?
    }

    struct SubstanceProvenance: Hashable {
        let categorySource: String?
        let halfLifeSource: String?
        let mechanismSource: String?
        /// Keyed by route for O(1) lookup from per-route UI rows. Routes
        /// without any source data (e.g. the route is in `dose_ranges` but no
        /// enabled source has it after priority resolution) are simply absent.
        let routesBySource: [RouteOfAdministration: RouteProvenance]
    }

    /// Resolves per-field source slugs for a substance using the same
    /// priority order as the field resolvers themselves, so the slug shown
    /// in the UI matches the source that actually won the field.
    func provenance(forSubstanceName name: String) -> SubstanceProvenance? {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return nil }
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
                    substanceID: substanceID,
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
                    substanceID: substanceID,
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
                    substanceID: substanceID,
                )

                let routes = try resolvedRoutes(db: db, substanceID: substanceID).map(\.route)
                var routesBySource: [RouteOfAdministration: RouteProvenance] = [:]
                routesBySource.reserveCapacity(routes.count)
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
                        extra: [route.rawValue],
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
                        extra: [route.rawValue],
                    )
                    routesBySource[route] = RouteProvenance(
                        doseSource: doseSource,
                        durationSource: durationSource,
                    )
                }

                return SubstanceProvenance(
                    categorySource: categorySource,
                    halfLifeSource: halfLifeSource,
                    mechanismSource: mechanismSource,
                    routesBySource: routesBySource,
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

    /// A group of effects sharing one PsychonautWiki category, for the
    /// "All effects" screen.
    struct EffectGroup: Identifiable, Hashable {
        let category: String
        let effects: [String]
        var id: String {
            category
        }
    }

    /// Canonical display order for PW effect categories. Mirrors
    /// `CATEGORY_ORDER` in `pipeline/build/pw_effect_categories.py`. Unknown
    /// categories (including the `Other` bucket for uncategorized survivors)
    /// sort last, alphabetically.
    private static let effectCategoryOrder = [
        "Physical", "Cognitive", "Visual", "Auditory", "Tactile",
        "Multisensory", "Sensory", "Smell and taste", "Transpersonal", "Disconnective",
    ]

    /// The substance's effects grouped by PsychonautWiki category, ordered for
    /// display. Lazily resolved on the "All effects" screen — the flat
    /// `Substance.effects` union drives the browse/search paths; this is the
    /// grouped view used only when a user drills into the full taxonomy.
    func effectsByCategory(forSubstanceName name: String) -> [EffectGroup] {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return [] }
        let language = languageOverride ?? Self.contentLanguage
        do {
            let rows = try substancesDB.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT DISTINCT \(Self.localizedEffectLabelSQL(language)) AS text,
                                    COALESCE(e.effect_category, '') AS category
                      FROM effects e
                      JOIN sources src ON src.id = e.source_id
                     WHERE e.substance_id = ?
                       AND src.slug IN (\(enabledSourceListSQL))
                     ORDER BY text COLLATE NOCASE
                """, arguments: [substanceID])
            }
            var byCategory: [String: [String]] = [:]
            for row in rows {
                let raw = (row["category"] as String?) ?? ""
                let category = raw.isEmpty ? "Other" : raw
                byCategory[category, default: []].append(row["text"])
            }
            let order = Self.effectCategoryOrder
            return byCategory.keys
                .sorted { a, b in
                    let ia = order.firstIndex(of: a) ?? order.count
                    let ib = order.firstIndex(of: b) ?? order.count
                    return ia != ib ? ia < ib : a < b
                }
                .map { EffectGroup(category: $0, effects: byCategory[$0] ?? []) }
        } catch {
            logger.error("effectsByCategory(forSubstanceName:) failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
