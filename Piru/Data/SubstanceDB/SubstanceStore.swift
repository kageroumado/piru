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
/// the bundled DB's own `.schema` output.
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

    #if DEBUG
        /// Close the user-prefs connection so a test can delete its temp directory
        /// without unlinking a file SQLite still holds open (`BUG IN CLIENT OF
        /// libsqlite3.dylib: vnode unlinked while in use`). Unusable afterwards —
        /// teardown only, last.
        func closeUserPrefsForTesting() {
            try? userPrefsDB.close()
        }
    #endif

    /// Ordered list of enabled source slugs (highest priority first). Re-read
    /// on every priority change. Bundled defaults seed the user DB on first
    /// launch.
    private(set) var enabledSourceOrder: [String] = []

    /// Cached resolved substances keyed by canonical name (case-insensitive).
    /// Cleared when the user changes source priority.
    ///
    /// `@ObservationIgnored`: this (and every cache below) is internal
    /// memoization, not observable UI state. It is filled *lazily inside a
    /// getter* (``resolveSubstance``), so without this a SwiftUI body that read
    /// the getter while the cache was cold would write an observed property
    /// mid-`body` — the AttributeGraph `precondition_failure` crash seen in the
    /// `HalfLifeCalculatorView` → `lookup` path. The sole *observable* input the
    /// resolved values derive from is ``enabledSourceOrder``; the body-reachable
    /// getters read it explicitly so source-priority changes still re-render.
    @ObservationIgnored private var resolvedCache: [String: Substance] = [:]

    /// Substance row id → resolved molar mass (`molecular_weight`). Backs the lean
    /// ``molarMass(forSubstanceName:)`` so the tolerance/PD engine can read one
    /// column without paying a full ``resolveSubstance`` (≈18 SQL + chem/effects
    /// decode) per dosed substance. Source-independent (the column is fixed for the
    /// DB's lifetime), so unlike `resolvedCache` it is *not* cleared on a source
    /// reorder; it is naturally discarded when the store is rebuilt for a DB update.
    @ObservationIgnored var molarMassByID: [Int64: Double?] = [:]

    /// Memoized ``pharmacologyParameters(forSubstanceName:)`` per substance name.
    /// The tolerance recompute resolves params for *every* unique dosed substance
    /// on the main actor each time the dose log changes; uncached, that re-ran a
    /// fresh `pk_routes` + `bindings` SQL fetch **and row decode** per substance
    /// (~50 for a heavy log) — a multi-second main-thread hang on every post-commit
    /// replay. Like ``molarMassByID`` the result is a pure function of the bundled
    /// DB row (by `substance_id`, no source-priority or overlay), stable for the
    /// DB's lifetime — so it is *not* cleared on a source reorder and is discarded
    /// naturally when the store is rebuilt for a DB update.
    @ObservationIgnored var pharmacologyParamsByName: [String: PharmacologyParameters] = [:]

    /// Cached `all`/`substances(in:)` results. Resolving 1600+ substances
    /// individually on every view body invalidation is what was making the
    /// Library tab feel laggy on entry. Cleared in lockstep with
    /// `resolvedCache`.
    @ObservationIgnored private var allCache: [Substance]?
    @ObservationIgnored private var substancesByCategoryCache: [SubstanceCategory: [Substance]] = [:]
    @ObservationIgnored private var nonEmptyCategoriesCache: [SubstanceCategory]?
    /// Browse-category histogram — every category (primary + curated
    /// `extraBrowseCategories`) a browse-surfacing substance lands in, with its
    /// count. Drives the Library cards' counts and the `nonEmptyCategories` /
    /// `browsable` gating without per-category `.filter` passes over `all`.
    /// Built in one bucketing sweep; invalidated in lockstep with `allCache`.
    @ObservationIgnored private var categorySummaryCache: [SubstanceCategory: Int]?
    /// Benzodiazepine diazepam-equivalences for the converter tool — one batched
    /// query, cached after first load. Cleared with the other source-derived caches.
    @ObservationIgnored private var benzoEquivalenceCache: [BenzoEquivalence]?

    /// Name/alias (lowercased) → lightweight batch row, derived from `allCache`.
    /// This is the journal/timeline resolution path: it carries everything
    /// `ActiveSubstanceState.from` and the category facet need (category,
    /// routes/dose-ranges, durations, half-life, aliases) **without** the heavy
    /// per-substance `resolveSubstance` SQL (mechanism, bindings, chem identity).
    /// Built lazily on first access; invalidated in lockstep with `allCache`.
    @ObservationIgnored private var batchByName: [String: Substance]?

    /// Row id → lightweight `Substance`, derived from the batch cache. Lets
    /// ``search(_:limit:)`` resolve its ranked ids from the warm cache instead of
    /// running the heavy per-substance ``resolveSubstance`` (≈21 SQL each) for
    /// every one of up to `limit` results — which made each settled keystroke
    /// fire ~1k SQL queries on the main actor. Invalidated with `batchByName`.
    @ObservationIgnored private var batchByID: [Int64: Substance]?

    /// The in-flight (or finished) off-main prefill of `allCache` started in
    /// `init`. ``ensureAllLoaded()`` awaits it so the journal derive resolves
    /// from the batch cache (dict hits) instead of paying ~50 cold heavy reads
    /// on the main actor at launch.
    @ObservationIgnored private var prewarmTask: Task<Void, Never>?

    /// All substance canonical names (lowercased) → row id. Built once at
    /// startup so `lookup` / `lookupByNameOrAlias` / `search` don't pay the
    /// full SQL scan tax.
    private(set) var nameIndex: [String: Int64] = [:]
    private(set) var aliasIndex: [String: Int64] = [:]
    /// Row ids the build flagged `is_stub` — no dose ranges at all. They stay in
    /// the library (their identifiers and aliases are still worth having) but
    /// lose name-resolution ties to a substance that actually carries data.
    private(set) var stubIDs: Set<Int64> = []
    /// Every substance owning a given normalized alias, in table order. Only the
    /// keys owned by more than one substance are kept — 123 of ~5.8k — so this is
    /// a small side table consulted purely to skip a stub that won first-wins.
    private(set) var aliasOwners: [String: [Int64]] = [:]
    /// Normalized alias → the alias in its display casing ("concerta" → "Concerta").
    /// `alias_normalized` is the *pipeline's* normalization — Greek-cap folding and
    /// all — which `lowercased()` does not reproduce, so a search hit recovers its
    /// display form through this map rather than by re-deriving it. Read by
    /// ``rankedSearch`` to title a row with the name the user actually typed.
    private(set) var aliasDisplayIndex: [String: String] = [:]
    /// Normalized alias → isomer code, for the facet-annotated aliases only
    /// ("focalin" → "D", "esketamine" → "S"). Lets a logged brand/enantiomer
    /// string recover its form during the PSID backfill. Built from `aliases.isomer`.
    private(set) var aliasIsomerIndex: [String: String] = [:]
    /// Normalized alias → release-form code ("concerta"/"adderall xr" → "XR",
    /// "vivitrol" → "DEP"). The release sibling of ``aliasIsomerIndex``, built from
    /// `aliases.release_form`; an alias can carry both ("focalin xr" → D + XR).
    ///
    /// Identity/label only: no source carries a distinct extended-release dose or
    /// duration, so this recovers *which form a logged string named* — it never
    /// selects a dose ladder, and there is deliberately no release picker.
    private(set) var aliasReleaseFormIndex: [String: String] = [:]
    /// Lowercased product name → the strengths it ships in (`product_strengths`).
    /// Lets a logged brand ("concerta") be entered as a *pill* by tapping a real
    /// strength. Display/entry only — see ``ProductStrengths``. Built at load by a
    /// small separate read so its absence in an older bundled DB degrades to "no
    /// chips" rather than failing the whole index build.
    private(set) var productStrengthIndex: [String: ProductStrengths] = [:]
    /// Lowercased product name → its duration-of-effect envelope
    /// (`product_durations`). Lets an extended-release brand ("concerta",
    /// "adderall xr") draw a curve of the labeled length instead of its parent's
    /// immediate-release curve. Keyed by the specific product, not the release-form
    /// umbrella. Built at load by a small separate read so its absence in an older
    /// bundled DB degrades to "base curve / marker" rather than failing the build.
    private(set) var productDurationIndex: [String: DurationProfile] = [:]
    /// Composed form titles from `substance_forms` — "Methylphenidate",
    /// "Methylphenidate XR", "Dexmethylphenidate XR" (the cross-axis Focalin XR
    /// form), "Naltrexone Depot". The build composes these once, so the app never
    /// re-implements title assembly (or duplicates the curated `titleSuffix`
    /// vocabulary) and can't drift from the DB.
    ///
    /// Keyed by **row id**, not uid: fold-family siblings that are co-familied but
    /// unfolded (Etiracetam/Levetiracetam) share a uid while having different
    /// titles, so a uid key would collide. Salt is excluded from the key — the
    /// index covers only `salt='0'` rows, which is exhaustive for name resolution
    /// since salt is deliberately never alias-annotated (see `aliases.salt_form`).
    private(set) var formTitleIndex: [FormKey: String] = [:]
    /// PSID FAMILY (`substance_uid`) → its branded products, flagships first. Feeds
    /// the QuickLog brand picker, whose selection sets `productName` (the key every
    /// downstream brand surface — curve, tablet chips, title — already reads).
    private(set) var brandProductsByUID: [String: [BrandProduct]] = [:]
    /// PSID FAMILY (`substances.substance_uid`) → member row ids. One-to-many:
    /// fold-family siblings (racemate + enantiomers, IR + XR) share a uid, so a
    /// FAMILY can map to several substance rows. Built once at init alongside
    /// ``nameIndex``. Drives ``substances(uid:)`` / ``substanceUID(forNameOrAlias:)``.
    private var uidIndex: [String: [Int64]] = [:]
    /// Reverse of ``uidIndex`` — row id → its FAMILY, for the O(1) name→uid path.
    private(set) var idToUIDIndex: [Int64: String] = [:]
    private(set) var allNames: [String] = []

    /// `source.slug` → `source.display_name`. Built once at init; consumed by
    /// the detail view's source-attribution rows so users see "TripSit
    /// factsheets" rather than the raw slug "tripsit".
    private var sourceDisplayNames: [String: String] = [:]

    /// The bundled substances DB the app shipped with. A missing resource is a
    /// build/packaging error — it is byte-identical for every install, so it
    /// can't be the device-specific launch crash; `fatalError` here asserts a
    /// true invariant (and would surface immediately in development).
    static func bundledSubstancesDBURL() -> URL {
        guard let bundleURL = Bundle.main.url(forResource: "piru-substances", withExtension: "sqlite") else {
            fatalError("Bundled piru-substances.sqlite missing from app bundle. Run `pipeline/build.sh` and add the result to the Piru target.")
        }
        return bundleURL
    }

    /// Picks the SQLite file to open at launch. Prefers an opt-in updated
    /// copy in `Documents/` (sha256-verified at install time by
    /// ``SubstanceDBUpdater``) and falls back to the bundled resource the app
    /// shipped with. The init recovers if the chosen file turns out to be
    /// unopenable (see ``init(substancesDBURL:userPrefsDBURL:prewarmsAllCache:)``).
    static func resolveSubstancesDBURL() -> URL {
        let applied = SubstanceDBUpdater.appliedSQLiteURL
        if FileManager.default.fileExists(atPath: applied.path) {
            return applied
        }
        return bundledSubstancesDBURL()
    }

    /// Open the writable user-prefs DB, recovering from on-disk corruption. The
    /// prefs DB holds only source priorities / profile / overrides — all
    /// re-seedable from bundled defaults — so a corrupt file or a bad leftover
    /// `-wal`/`-shm` (commonly left when the app is killed mid-write) is deleted
    /// and recreated rather than crashing the app at launch.
    ///
    /// If even a *fresh* on-disk store can't be created, fall back to an
    /// in-memory queue instead of crashing. The dominant reason an otherwise
    /// healthy sandbox refuses the open is Data Protection: when the app is
    /// launched into the background while the device is still locked (widget
    /// timeline refresh, background task), files with complete protection are
    /// unreadable and the create throws `EPERM`. That is transient — a plain
    /// foreground launch would have succeeded — so a persistent, launch-time
    /// crash is the wrong response. In-memory prefs are non-persisted (the user
    /// falls back to bundled-default source priorities for that session) but let
    /// the app run; the next disk open re-persists them.
    private static func openUserPrefs(at url: URL, configuration: Configuration) -> DatabaseQueue {
        do {
            return try DatabaseQueue(path: url.path, configuration: configuration)
        } catch {
            logger.error("user-prefs DB unopenable at \(url.path, privacy: .public) (\(error.localizedDescription, privacy: .public)); recreating from bundled defaults")
            let fm = FileManager.default
            let siblings = [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")]
            for sibling in siblings where fm.fileExists(atPath: sibling.path) {
                try? fm.removeItem(at: sibling)
            }
            do {
                return try DatabaseQueue(path: url.path, configuration: configuration)
            } catch {
                logger.error("user-prefs DB unrecreatable at \(url.path, privacy: .public) (\(error.localizedDescription, privacy: .public)); falling back to an in-memory prefs store")
                if let memory = try? DatabaseQueue(named: nil, configuration: configuration) {
                    return memory
                }
                fatalError("Failed to open even an in-memory user-prefs DB: \(error)")
            }
        }
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
        // Launch recovery: if the opt-in updated copy in Documents/ is corrupt
        // or half-applied (app killed mid-copy, truncated download past the
        // install-time sha256 check, …) the open throws. Rather than crash on
        // every launch — the dominant build-21/22 launch crash — quarantine the
        // bad applied DB and fall back to the bundled resource. A bundled-DB
        // failure stays fatal (see ``bundledSubstancesDBURL``).
        let openedSubstancesURL: URL
        do {
            self.substancesDB = try DatabaseQueue(path: substancesDBURL.path, configuration: bundleConfig)
            openedSubstancesURL = substancesDBURL
        } catch {
            let bundleURL = Self.bundledSubstancesDBURL()
            guard substancesDBURL != bundleURL else {
                fatalError("Failed to open bundled substances DB at \(substancesDBURL.path): \(error)")
            }
            logger.error("Substances DB unopenable at \(substancesDBURL.path, privacy: .public) (\(error.localizedDescription, privacy: .public)); falling back to bundled DB")
            if substancesDBURL == SubstanceDBUpdater.appliedSQLiteURL {
                logger.error("Quarantining the corrupt applied substance-DB update")
                SubstanceDBUpdater.quarantineAppliedDB()
            }
            do {
                self.substancesDB = try DatabaseQueue(path: bundleURL.path, configuration: bundleConfig)
            } catch {
                fatalError("Failed to open bundled substances DB at \(bundleURL.path): \(error)")
            }
            openedSubstancesURL = bundleURL
        }

        // Second read-only connection for off-main batch reads (see the property
        // doc). Same file, same read-only config; a distinct `label` so it's
        // identifiable in Instruments / GRDB logs. Opens the file we just
        // verified openable above.
        var batchConfig = bundleConfig
        batchConfig.label = "piru-substances-batch"
        do {
            self.substancesBatchDB = try DatabaseQueue(path: openedSubstancesURL.path, configuration: batchConfig)
        } catch {
            fatalError("Failed to open substances batch DB at \(openedSubstancesURL.path): \(error)")
        }

        var prefsConfig = Configuration()
        prefsConfig.label = "piru-user-prefs"
        self.userPrefsDB = Self.openUserPrefs(at: userPrefsDBURL, configuration: prefsConfig)

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

            // One-time source-order migration. Source priority was never surfaced
            // prominently, so existing installs carry whatever order they first
            // seeded — often stale after the bundled defaults were reprioritized
            // (e.g. drug.community promoted above PsychonautWiki, which left
            // methamphetamine's dose resolving from the wrong source). Re-apply the
            // bundled default order + enabled once per migration version, so
            // everyone lands on the current recommendation without resetting by
            // hand. Bump `currentSourceOrderMigration` whenever the default order
            // changes and you want it re-applied to existing installs.
            if UserDefaults.standard.integer(forKey: Self.sourceOrderMigrationKey) < Self.currentSourceOrderMigration {
                try userPrefsDB.write { db in
                    for row in bundledSources {
                        try db.execute(
                            sql: "UPDATE source_preferences SET priority = ?, enabled = ? WHERE source_slug = ?",
                            arguments: [row["default_priority"] as Int, row["default_enabled"] as Int, row["slug"] as String],
                        )
                    }
                }
                UserDefaults.standard.set(Self.currentSourceOrderMigration, forKey: Self.sourceOrderMigrationKey)
                logger.info("Applied source-order migration v\(Self.currentSourceOrderMigration)")
            }
        } catch {
            logger.error("Failed to seed user prefs: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static let sourceOrderMigrationKey = "piru.sourceOrderMigrationVersion"
    /// Bump this (and it re-applies bundled default source priority to every
    /// install on next launch) whenever the default `SOURCES` order changes.
    private static let currentSourceOrderMigration = 1

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

    /// The sources shown in the user-facing priority screen — the ones that
    /// actually compete for the fields on a substance card (dose, duration,
    /// effects, category, mechanism). Identifier-only and niche sources (PubChem,
    /// Wikidata, NPS Data Hub, PDSP, Erowid, DEA, pyrls, MedTAP, benzo-equivalency,
    /// FreeOD Wiki — the last floats up on its own in Chinese) still resolve at
    /// their bundled priority but aren't user-reorderable: they rarely or never
    /// win a displayed field, so surfacing them only adds noise.
    nonisolated static let reorderableSourceSlugs: Set<String> = [
        "piru-curated", "peer-review-primary", "drug.community",
        "psychonautwiki", "tripsit", "dailymed",
    ]

    /// ``sourceStates()`` limited to the reorderable primary sources, in the
    /// user's current priority order.
    func primarySourceStates() -> [SourceState] {
        sourceStates().filter { Self.reorderableSourceSlugs.contains($0.slug) }
    }

    /// Reorder just the primary sources; every other (hidden) source keeps its
    /// current relative order, slotted beneath the primaries. Keeps the priority
    /// space consistent without exposing the niche sources.
    func setPrimarySourcePriority(orderedPrimarySlugs: [String]) {
        let primary = Set(orderedPrimarySlugs)
        let others = sourceStates().map(\.slug).filter { !primary.contains($0) }
        setSourcePriority(orderedSlugs: orderedPrimarySlugs + others)
    }

    /// Reset every source to its bundled default priority + enabled state — the
    /// recommended order. Fixes prefs that went stale after a default changed
    /// (e.g. drug.community was promoted but existing installs kept the old rank).
    func resetSourcePriorityToDefaults() {
        do {
            let defaults = try substancesDB.read { db in
                try Row.fetchAll(db, sql: "SELECT slug, default_priority, default_enabled FROM sources")
            }
            try userPrefsDB.write { db in
                for row in defaults {
                    try db.execute(
                        sql: "UPDATE source_preferences SET priority = ?, enabled = ? WHERE source_slug = ?",
                        arguments: [row["default_priority"] as Int, row["default_enabled"] as Int, row["slug"] as String],
                    )
                }
            }
            reloadSourceOrder()
        } catch {
            logger.error("Failed to reset source priority: \(error.localizedDescription, privacy: .public)")
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
            let (names, aliases, aliasDisplay, aliasFacets, displayNames, uids, formTitles, stubs):
                ([(String, Int64, String)], [(String, Int64)], [(String, String)], [(String, String?, String?)], [(String, String)], [(Int64, String)], [(FormKey, String)], Set<Int64>) = try substancesDB.read { db in
                    let nameRows = try Row.fetchAll(db, sql: "SELECT id, canonical_name, substance_uid, is_stub FROM substances ORDER BY canonical_name COLLATE NOCASE")
                    let names = nameRows.map { ($0["canonical_name"] as String, $0["id"] as Int64, ($0["canonical_name"] as String).lowercased()) }
                    // Rows the build flagged as carrying no dose data at all. Kept
                    // so their identifiers/aliases stay reachable, but demoted in
                    // name resolution (see `substanceID(forNameOrAlias:)`).
                    let stubs = Set(nameRows.compactMap { row -> Int64? in
                        (row["is_stub"] as Int64? ?? 0) != 0 ? row["id"] as Int64 : nil
                    })
                    let uids = nameRows.compactMap { row -> (Int64, String)? in
                        guard let uid = row["substance_uid"] as String? else { return nil }
                        return (row["id"] as Int64, uid)
                    }
                    let aliasRows = try Row.fetchAll(db, sql: "SELECT substance_id, alias, alias_normalized, isomer, release_form FROM aliases")
                    let aliases = aliasRows.map { ($0["alias_normalized"] as String, $0["substance_id"] as Int64) }
                    let aliasDisplay = aliasRows.map { ($0["alias_normalized"] as String, $0["alias"] as String) }
                    // Only the facet-bearing rows — the vast majority of aliases name
                    // the plain/unspecified form and would just bloat both indexes.
                    let aliasFacets = aliasRows.compactMap { row -> (String, String?, String?)? in
                        let iso = row["isomer"] as String?
                        let release = row["release_form"] as String?
                        guard iso != nil || release != nil else { return nil }
                        return (row["alias_normalized"] as String, iso, release)
                    }
                    let sourceRows = try Row.fetchAll(db, sql: "SELECT slug, display_name FROM sources")
                    let displayNames = sourceRows.map { ($0["slug"] as String, $0["display_name"] as String) }
                    let formRows = try Row.fetchAll(db, sql: "SELECT substance_id, stereo, release, display_name FROM substance_forms WHERE salt = '0'")
                    let formTitles = formRows.map { row in
                        (
                            FormKey(
                                substanceID: row["substance_id"] as Int64,
                                stereo: row["stereo"] as String,
                                release: row["release"] as String,
                            ),
                            row["display_name"] as String,
                        )
                    }
                    return (names, aliases, aliasDisplay, aliasFacets, displayNames, uids, formTitles, stubs)
                }
            self.stubIDs = stubs
            self.allNames = names.map(\.0)
            // `uniquingKeysWith` (not `uniqueKeysWithValues:`) so a duplicate
            // lowercased canonical name (`MDMA`/`mdma` from an imported DB, or an
            // unmerged custom) collapses to the first row instead of *trapping* at
            // launch — a trap here is an uncatchable cold-start crash.
            self.nameIndex = Dictionary(names.map { ($0.2, $0.1) }, uniquingKeysWith: { first, _ in first })
            if self.nameIndex.count != names.count {
                logger.warning("buildIndexes: collapsed \(names.count - self.nameIndex.count) duplicate lowercased canonical name(s) in nameIndex")
            }
            var ax: [String: Int64] = [:]
            var owners: [String: [Int64]] = [:]
            for (alias, sid) in aliases {
                if ax[alias] == nil { ax[alias] = sid }
                owners[alias, default: []].append(sid)
            }
            self.aliasIndex = ax
            // Keep only the contested keys; a single-owner alias can never need
            // the stub-skipping fallback.
            self.aliasOwners = owners.filter { $0.value.count > 1 }
            // First-wins, matching `aliasIndex`: two aliases normalizing to the same
            // key ("Biphentin"/"biphentin") resolve to one substance, so they must
            // resolve to one display form too.
            var adx: [String: String] = [:]
            for (normalized, display) in aliasDisplay where adx[normalized] == nil {
                adx[normalized] = display
            }
            self.aliasDisplayIndex = adx
            // First-wins per facet, matching `aliasIndex` — an alias owned by >1
            // substance resolves to the first, and `audit_alias_collisions()` in the
            // build reports any such collision for triage.
            var aix: [String: String] = [:]
            var arx: [String: String] = [:]
            for (alias, iso, release) in aliasFacets {
                if let iso, aix[alias] == nil { aix[alias] = iso }
                if let release, arx[alias] == nil { arx[alias] = release }
            }
            self.aliasIsomerIndex = aix
            self.aliasReleaseFormIndex = arx
            // `substance_forms`' PK already makes these unique; uniquing defensively
            // rather than trapping at launch, matching `nameIndex` above.
            self.formTitleIndex = Dictionary(formTitles, uniquingKeysWith: { first, _ in first })
            // PSID FAMILY → its member row ids. One-to-many for co-familied-but-
            // unfolded rows (Etiracetam/Levetiracetam), else one row per uid.
            var ux: [String: [Int64]] = [:]
            var idux: [Int64: String] = [:]
            for (sid, uid) in uids {
                ux[uid, default: []].append(sid)
                idux[sid] = uid
            }
            self.uidIndex = ux
            self.idToUIDIndex = idux
            self.sourceDisplayNames = Dictionary(displayNames, uniquingKeysWith: { first, _ in first })
        } catch {
            logger.error("Failed to build indexes: \(error.localizedDescription, privacy: .public)")
        }

        // Per-product tablet/capsule strengths (`product_strengths`), read
        // separately: it's a small table used only when the pill editor opens, and
        // its own do/catch means an older bundled DB that predates the table
        // degrades to "no pill chips" instead of failing the whole index build.
        do {
            let rows = try substancesDB.read { db in
                try Row.fetchAll(db, sql: "SELECT product_normalized, form, strengths_mg FROM product_strengths")
            }
            var index: [String: ProductStrengths] = [:]
            for row in rows {
                let strengths = (row["strengths_mg"] as String)
                    .split(separator: ",")
                    .compactMap { Double($0) }
                guard !strengths.isEmpty else { continue }
                index[row["product_normalized"] as String] = ProductStrengths(
                    strengths: strengths, form: row["form"] as String,
                )
            }
            self.productStrengthIndex = index
        } catch {
            logger.warning("buildIndexes: product_strengths unavailable (\(error.localizedDescription, privacy: .public)) — pill chips disabled")
        }

        // Per-product duration envelopes (`product_durations`), read separately for
        // the same reason: an older bundled DB predating the table degrades to the
        // base curve / timestamp marker rather than failing the whole index build.
        do {
            let rows = try substancesDB.read { db in
                try Row.fetchAll(db, sql: """
                SELECT product_normalized, route,
                       onset_min, onset_max, comeup_min, comeup_max,
                       peak_min, peak_max, offset_min, offset_max,
                       afterglow_min, afterglow_max, total_min, total_max
                  FROM product_durations
                """)
            }
            func range(_ row: Row, _ phase: String) -> DurationRange? {
                guard let lo = row["\(phase)_min"] as Double?,
                      let hi = row["\(phase)_max"] as Double? else { return nil }
                return DurationRange(min: lo, max: hi)
            }
            var index: [String: DurationProfile] = [:]
            for row in rows {
                index[row["product_normalized"] as String] = DurationProfile(
                    onset: range(row, "onset"), comeup: range(row, "comeup"),
                    peak: range(row, "peak"), offset: range(row, "offset"),
                    afterglow: range(row, "afterglow"), total: range(row, "total"),
                )
            }
            self.productDurationIndex = index
        } catch {
            logger.warning("buildIndexes: product_durations unavailable (\(error.localizedDescription, privacy: .public)) — extended-release curves fall back")
        }

        // Branded products (`aliases` kind='brand') grouped by FAMILY uid for the
        // QuickLog brand picker, tagged with whether the build carries a curve /
        // tablet strengths so the menu can lead with the ones that draw a real
        // curve. Read separately for the same degrade-gracefully reason: a failure
        // drops to "no brand pill" rather than failing the whole index build.
        do {
            let rows = try substancesDB.read { db in
                try Row.fetchAll(db, sql: """
                SELECT s.substance_uid AS uid, a.alias, a.release_form AS rel, a.brand_rank AS rank,
                       (pd.product_normalized IS NOT NULL) AS has_curve,
                       (ps.product_normalized IS NOT NULL) AS has_strengths
                  FROM aliases a
                  JOIN substances s ON s.id = a.substance_id
                  LEFT JOIN product_durations pd ON pd.product_normalized = a.alias_normalized
                  LEFT JOIN product_strengths ps ON ps.product_normalized = a.alias_normalized
                 WHERE a.kind = 'brand' AND s.substance_uid IS NOT NULL
                """)
            }
            var index: [String: [BrandProduct]] = [:]
            for row in rows {
                let rel = row["rel"] as String?
                index[row["uid"] as String, default: []].append(BrandProduct(
                    name: row["alias"] as String,
                    releaseForm: (rel?.isEmpty == true) ? nil : rel,
                    brandRank: (row["rank"] as Int64?).map(Int.init),
                    hasCurve: (row["has_curve"] as Int64? ?? 0) != 0,
                    hasStrengths: (row["has_strengths"] as Int64? ?? 0) != 0,
                ))
            }
            // Flagships (curve/curated) first, then niche; each group alphabetical —
            // the order the picker menu renders top-to-bottom.
            for uid in index.keys {
                index[uid]?.sort { a, b in
                    if a.isFlagship != b.isFlagship { return a.isFlagship }
                    if a.hasCurve != b.hasCurve { return a.hasCurve }
                    if (a.brandRank ?? .max) != (b.brandRank ?? .max) { return (a.brandRank ?? .max) < (b.brandRank ?? .max) }
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
            }
            self.brandProductsByUID = index
        } catch {
            logger.warning("buildIndexes: brand aliases unavailable (\(error.localizedDescription, privacy: .public)) — brand pill disabled")
        }
    }

    /// Human-readable name for a source slug. Returns the slug itself as a
    /// safe fallback if the source is unknown (e.g. an applied DB has a slug
    /// our bundled `sources` table doesn't recognize).
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
    /// than `nameIndex` alone, so a substance dosed or queried by an alias
    /// (e.g. a dose logged as `"Lysergic Acid Diethylamide"`, now an alias of
    /// canonical `"LSD"`) still resolves its bindings / PK / molar-mass instead of
    /// returning empty. Without it the tolerance engine would see such a dose as
    /// having *no* pharmacology at all and silently drop it.
    func substanceID(forNameOrAlias name: String) -> Int64? {
        let key = name.lowercased()
        let byName = nameIndex[key]
        let byAlias = aliasIndex[key]
        // Canonical name wins — except when it names a data-less stub and the same
        // string also resolves, via the alias index, to a substance that has data.
        // `pyrls` ships "Dextroamphetamine-Amphetamine" as its own row with zero
        // dose, duration, PK and half-life rows; because `nameIndex` is consulted
        // first, logging that exact name resolved to the empty row and drew
        // nothing, while the alias "Adderall" resolved to Amphetamine and drew a
        // full curve.
        //
        // The preference runs both ways round: a *name* hit that is a stub yields
        // to a non-stub alias hit, and when there is no name hit at all the alias
        // index is asked for a non-stub owner before falling back to whichever
        // substance happens to be first. 817 of the 1912 rows are stubs and 123
        // alias keys are owned by more than one substance, so "first-wins landed
        // on the empty one" is not a rare shape.
        if let byName, !stubIDs.contains(byName) { return byName }
        if let byAlias, !stubIDs.contains(byAlias) { return byAlias }
        if let nonStub = nonStubAliasOwner(for: key) { return nonStub }
        return byName ?? byAlias
    }

    /// A substance owning `key` as an alias that actually carries data, when the
    /// first-wins ``aliasIndex`` entry is a stub. `nil` when every owner is a stub
    /// (then the stub is the honest answer).
    private func nonStubAliasOwner(for key: String) -> Int64? {
        guard let owners = aliasOwners[key] else { return nil }
        return owners.first { !stubIDs.contains($0) }
    }

    // MARK: - PSID resolution (see SubstanceStore+PSID.swift for the name→uid maps)

    /// The fully-resolved substances sharing the PSID FAMILY `uid`; empty when
    /// unknown. **Raw library rows** — bypass the custom overlay; app code resolves
    /// through ``SubstanceLibrary/substances(uid:)``.
    func substances(uid: String) -> [Substance] {
        substanceIDs(forUID: uid).compactMap { resolveSubstance(id: $0, canonicalName: nil) }
    }

    /// Test/diagnostic view over the FAMILY → ids index.
    var uidToID: [String: [Int64]] {
        uidIndex
    }

    /// All substances in the library. Lazily resolves on first access; the
    /// resolved array is *not* cached as a unit (resolvedCache caches per
    /// substance so partial fills still benefit from prior work).
    var all: [Substance] {
        // Register the observation dependency (on the reorder-able source order)
        // *before* the warm-cache early return — `allCache` is @ObservationIgnored,
        // so a body reading `all` would otherwise not re-render on a source reorder.
        let order = enabledSourceOrder
        if let cached = allCache { return cached }
        let resolved = Self.loadAllSubstancesBatch(db: substancesDB, order: order)
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
    func batchByIDIndex() -> [Int64: Substance] {
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
                    """
                    SELECT id, canonical_name, display_name, display_class, regulatory_status,
                           duration_implausible, popularity, is_stub, substance_uid,
                           -- Chemical identity travels with the shell. Without it a screen served
                           -- from this prewarm has no formula, mass, CAS, SMILES or InChIKey, and
                           -- the Chemistry card renders an empty grid.
                           cas, inchikey, formula, pubchem_cid, molecular_weight, smiles, iupac_name
                      FROM substances ORDER BY canonical_name COLLATE NOCASE
                    """,
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
                var substanceUIDByID: [Int64: String] = [:]
                // Chemical identity — see the SELECT above.
                var casByID: [Int64: String] = [:]
                var inchikeyByID: [Int64: String] = [:]
                var formulaByID: [Int64: String] = [:]
                var pubchemCIDByID: [Int64: Int] = [:]
                var molarMassByID: [Int64: Double] = [:]
                var smilesByID: [Int64: String] = [:]
                var iupacNameByID: [Int64: String] = [:]
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
                    if let uid: String = row["substance_uid"] { substanceUIDByID[sid] = uid }
                    if let v: String = row["cas"] { casByID[sid] = v }
                    if let v: String = row["inchikey"] { inchikeyByID[sid] = v }
                    if let v: String = row["formula"] { formulaByID[sid] = v }
                    if let v = row["pubchem_cid"] as Int64? { pubchemCIDByID[sid] = Int(v) }
                    if let v = row["molecular_weight"] as Double? { molarMassByID[sid] = v }
                    if let v: String = row["smiles"] { smilesByID[sid] = v }
                    if let v: String = row["iupac_name"] { iupacNameByID[sid] = v }
                }

                // Aliases — union across sources.
                var aliasesByID: [Int64: [String]] = [:]
                for row in try Row.fetchAll(
                    db,
                    sql:
                    // Brand names first (D.1.7), curated flagships (brand_rank 0,
                    // e.g. Ritalin) ahead of auto-derived form brands (rank 1, e.g.
                    // Concerta), then everything else alphabetical — so the "Also
                    // known as" subtitle leads with the names people know, not the
                    // alphabetically-first synonym. Findability is unaffected
                    // (search uses the normalized index).
                    "SELECT substance_id, alias FROM aliases ORDER BY COALESCE(brand_rank, 9), alias",
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
                        substanceUID: substanceUIDByID[sid],
                        cas: casByID[sid],
                        inchikey: inchikeyByID[sid],
                        formula: formulaByID[sid],
                        pubchemCID: pubchemCIDByID[sid],
                        popularity: popularityByID[sid] ?? 0,
                        isStub: isStubByID[sid] ?? false,
                        molarMass: molarMassByID[sid],
                        smiles: smilesByID[sid],
                        iupacName: iupacNameByID[sid],
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
        // Read the observed source-order input *before* the warm-cache early
        // return so a SwiftUI body that reads this `@ObservationIgnored` cache
        // still re-renders when the user reorders sources (which clears the
        // cache via `reloadSourceOrder`). The accessor call is what registers
        // the observation dependency; the value itself isn't needed here.
        _ = enabledSourceOrder
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
        _ = enabledSourceOrder // observation dependency; see `categorySummary()`
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
        _ = enabledSourceOrder // observation dependency; see `categorySummary()`
        if let cached = nonEmptyCategoriesCache { return cached }
        let summary = categorySummary()
        let result = SubstanceCategory.allCases.filter { (summary[$0] ?? 0) > 0 }
        nonEmptyCategoriesCache = result
        return result
    }

    // MARK: - Substance resolver (source-priority aware)

    /// Test-only override for the resolved content language. nil = derive from
    /// the app's UI language (``contentLanguage``). Lets tests exercise the
    /// locale-first text resolution without changing the process locale.
    var languageOverride: ContentLanguage?

    /// Decodes a curated JSON-blob TEXT column (e.g. `popular_aliases`,
    /// `misconceptions`) into a Codable type. Returns nil for a NULL/empty
    /// column or malformed JSON — a bad blob degrades the affected section to
    /// absent rather than failing the whole substance resolve.
    private static func decodeJSONBlob<T: Decodable>(_: T.Type, _ raw: String?) -> T? {
        guard let raw, let data = raw.data(using: .utf8), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Which additive editorial columns the opened `substances` table carries,
    /// probed once via `PRAGMA table_info` and cached. Checked per-column so a
    /// DB that has `popular_aliases`/`misconceptions` but predates
    /// `combinations`/`water_heat` still loads what it has.
    @ObservationIgnored private var editorialColumnSet: Set<String>?

    private func editorialColumns() -> Set<String> {
        if let editorialColumnSet { return editorialColumnSet }
        let all: Set = ["popular_aliases", "misconceptions", "combinations", "water_heat"]
        let present: Set<String> = (try? substancesDB.read { db -> Set<String> in
            let names = try Row.fetchAll(db, sql: "PRAGMA table_info(substances)")
                .compactMap { $0["name"] as String? }
            return all.intersection(names)
        }) ?? []
        editorialColumnSet = present
        return present
    }

    private func resolveSubstance(id: Int64, canonicalName _: String?) -> Substance? {
        _ = enabledSourceOrder // observation dependency; see `categorySummary()`
        let appLanguage = languageOverride ?? Self.contentLanguage
        // Language is part of the cache key so a mid-session app-language change
        // re-resolves locale-first text instead of serving stale-language rows.
        let cacheKey = "\(id)|\(appLanguage.rawValue)"
        if let cached = resolvedCache[cacheKey] { return cached }

        // Include each curated editorial column only when the opened DB actually
        // has it — an older OTA-applied copy may predate some of them.
        let ec = editorialColumns()
        let editorialColumns = ["popular_aliases", "misconceptions", "combinations", "water_heat"]
            .filter { ec.contains($0) }
            .map { ", \($0)" }
            .joined()

        do {
            let resolved = try substancesDB.read { db -> Substance? in
                guard let coreRow = try Row.fetchOne(db, sql: "SELECT canonical_name, display_name, display_class, regulatory_status, duration_implausible, substance_uid, cas, inchikey, formula, pubchem_cid, molecular_weight, popularity, is_stub, drug_community_slug, freeodwiki_slug, smiles, iupac_name, logp, logd, pka, tpsa, hba, hbd, ld50_oral_mg_per_kg, ld50_dermal_mg_per_kg, melting_point_c, boiling_point_c\(editorialColumns) FROM substances WHERE id = ?", arguments: [id]) else {
                    return nil
                }
                let name: String = coreRow["canonical_name"]
                let displayName: String? = coreRow["display_name"]
                let displayClass = (coreRow["display_class"] as String?).flatMap(CompoundDisplayClass.init(rawValue:)) ?? .recreational
                let regulatoryStatus: String? = coreRow["regulatory_status"]
                let durationImplausible = (coreRow["duration_implausible"] as Int64? ?? 0) != 0
                let substanceUID: String? = coreRow["substance_uid"]
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
                // Curated editorial JSON blobs (piru-curated, popular-substances
                // only; empty for the long tail). Decoded defensively — a
                // malformed blob degrades to absent, never a throw.
                //
                // NOTE (localization): these are stored English-only in a single
                // column, unlike `overview`/effects/mechanism which resolve by
                // `language:`. zh-Hans/zh-Hant users see English claim/correction
                // prose until translated. When authoring scales past English, move
                // to a language-keyed store (mirror `mechanisms_summary`'s
                // language PK) — a pipeline + reader change + wholesale rebuild,
                // not a user-data migration (the substance DB is a build artifact).
                let popularAliases = ec.contains("popular_aliases") ? Self.decodeJSONBlob([String].self, coreRow["popular_aliases"]) ?? [] : []
                let misconceptions = ec.contains("misconceptions") ? Self.decodeJSONBlob([MythBust].self, coreRow["misconceptions"]) ?? [] : []
                let combinations = ec.contains("combinations") ? Self.decodeJSONBlob([Combination].self, coreRow["combinations"]) ?? [] : []
                let waterHeat = ec.contains("water_heat") ? Self.decodeJSONBlob(WaterHeatGuidance.self, coreRow["water_heat"]) : nil
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

                // Brand names first, flagship brands ahead of form brands, then
                // alphabetical — see the batch path (D.1.7 + brand_rank).
                let aliases = try String.fetchAll(db, sql: "SELECT alias FROM aliases WHERE substance_id = ? ORDER BY COALESCE(brand_rank, 9), alias", arguments: [id])
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
                    substanceUID: substanceUID,
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
                    popularAliases: popularAliases,
                    misconceptions: misconceptions,
                    combinations: combinations,
                    waterHeat: waterHeat,
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
    ///
    /// Internal rather than `private` only so the same-type extension in
    /// `SubstanceStore+Provenance.swift` can mirror this ordering — Swift scopes
    /// `private` to the file, and provenance must resolve by the identical
    /// priority as the resolvers or the attributed slug would disagree with the
    /// value shown. Not part of the store's API; don't call from outside the type.
    var priorityCaseSQL: String {
        Self.priorityCaseSQL(enabledSourceOrder)
    }
    /// See ``priorityCaseSQL`` for why this isn't `private`.
    var enabledSourceListSQL: String {
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
        let rows: [(route: String, isomer: String?, common: Double?, strong: Double?, heavy: Double?)]
        do {
            rows = try queue.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT route, isomer, common_upper, strong_upper, heavy
                      FROM (
                        SELECT d.*, ROW_NUMBER() OVER (
                            PARTITION BY d.substance_id, d.route, d.salt_form, d.isomer
                            ORDER BY \(priorityCaseSQL) ASC) AS rn
                          FROM dose_ranges d
                          JOIN sources src ON src.id = d.source_id
                         WHERE d.substance_id = ?
                           AND src.slug IN (\(enabledSourceListSQL))
                    ) WHERE rn = 1
                """, arguments: [substanceID]).map {
                    (
                        route: $0["route"] ?? "",
                        isomer: $0["isomer"],
                        common: $0["common_upper"],
                        strong: $0["strong_upper"],
                        heavy: $0["heavy"],
                    )
                }
            }
        } catch {
            logger.error("referenceDoseMg failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        func reference(_ row: (route: String, isomer: String?, common: Double?, strong: Double?, heavy: Double?)) -> Double? {
            row.heavy ?? row.strong ?? row.common
        }
        /// Prefer the racemic form so a family's reference is the parent's, not an
        /// arbitrary enantiomer's; oral first, else the first route yielding a value.
        func firstReference(preferRacemic: Bool) -> Double? {
            let candidates = preferRacemic ? rows.filter { $0.isomer == nil } : rows
            if let oral = candidates.first(where: { RouteOfAdministration.from(string: $0.route) == .oral }),
               let value = reference(oral) {
                return value
            }
            return candidates.lazy.compactMap(reference).first
        }
        return firstReference(preferRacemic: true) ?? firstReference(preferRacemic: false)
    }

    /// `internal`, not `private`: the route resolver lives in
    /// `SubstanceStore+RouteResolution.swift` and a cross-file extension cannot
    /// see `private`.
    nonisolated static func priorityCaseSQL(_ order: [String]) -> String {
        sourceOrderSQL(order).priorityCase
    }

    nonisolated static func enabledSourceListSQL(_ order: [String]) -> String {
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

    /// The app's effective UI language, normalized to a content-language tag
    /// ('zh-Hans' | 'zh-Hant' | 'en'). Drives locale-first text resolution so a
    /// Chinese source (FreeOD Wiki) wins for descriptions/effects when the app
    /// runs in Chinese. Reads `preferredLocalizations` so it follows the app's
    /// per-app language override, not just the device language.
    nonisolated static var contentLanguage: ContentLanguage {
        .current
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
    ///
    /// Grouped by content, not by row. A compound with several manufacturers has
    /// a DailyMed label per manufacturer, and each repeats the same
    /// contraindication under its own citation — so methylphenidate listed
    /// "Glaucoma" twice and "Known allergy to it" twice. One citation of the
    /// several is kept; they say the same thing.
    private func resolvedContraindications(db: Database, substanceID: Int64) throws -> [Contraindication] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT c.text, c.flag, c.is_boxed_warning, MIN(ci.url) AS url
              FROM contraindications c
              JOIN sources src ON src.id = c.source_id
              LEFT JOIN citations ci ON ci.id = c.citation_id
             WHERE c.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
             GROUP BY COALESCE(c.flag, c.text), c.is_boxed_warning
             ORDER BY c.is_boxed_warning DESC, COALESCE(c.text, c.flag)
        """, arguments: [substanceID])
        return rows.map {
            Contraindication(
                flag: ($0["flag"] as String?).flatMap(ContraindicationFlag.init(rawValue:)),
                text: $0["text"],
                isBoxedWarning: ($0["is_boxed_warning"] as Int64? ?? 0) != 0,
                sourceURL: $0["url"],
            )
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
    ///
    /// Internal rather than `private` so `SubstanceStore+Provenance.swift` can
    /// attribute the same route set it resolves. Not part of the store's API.
    func resolvedRoutes(db: Database, substanceID: Int64) throws -> [SubstanceRoute] {
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
                        salt: sv.saltForm, isomer: sv.isomer, isomerDisplayName: sv.isomerDisplayName,
                        unit: sv.unit, doses: sv.doses, duration: sv.duration,
                        rank: idx, elementalFraction: sv.elementalFraction,
                    )
                }
            } else {
                [RouteVariant(
                    salt: nil, isomer: nil, isomerDisplayName: nil,
                    unit: route.unit, doses: route.doses, duration: route.duration,
                )]
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
            let duration = durationByKey[RouteSaltKey(sid: substanceID, route: routeStr, salt: nil, isomer: nil)]
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

    nonisolated static func rangeFrom(lower: Double?, upper: Double?) -> ClosedRange<Double>? {
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

    /// One locale-resolved prose row from a text table that
    /// `resolvedDescription`/`resolvedMechanism` share: matching-language text
    /// floats above source priority, English/`und` is the language fallback (see
    /// ``ContentLanguage/clauses(column:)``). Runs a strict enabled-source +
    /// preferred-language pass first, then a relaxed pass that keeps the same
    /// ORDER BY and language filter but drops the enabled-source filter, so a
    /// substance that only has prose from a deprioritized source shows it rather
    /// than a blank section. The table is aliased `t`; the returned row also carries
    /// `machine_translated` + `source_slug` so callers build their typed value.
    /// `table` is a fixed internal literal (no injection surface).
    private func resolvedTextRow(
        db: Database, from table: String, selecting columns: String,
        substanceID: Int64, language: ContentLanguage,
    ) throws -> Row? {
        let lang = language.clauses(column: "t.language")
        // Primary: the highest-priority enabled source, in the preferred language.
        if let row = try Row.fetchOne(db, sql: """
            SELECT \(columns), t.machine_translated, src.slug AS source_slug
              FROM \(table) t
              JOIN sources src ON src.id = t.source_id
             WHERE t.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
               \(lang.whereAnd)
             ORDER BY \(lang.orderPrefix)\(priorityCaseSQL) ASC
             LIMIT 1
        """, arguments: [substanceID]) {
            return row
        }
        // Fallback: prose exists, just not from an enabled source — show it
        // rather than a blank section. Only the enabled-source filter is dropped;
        // the language filter stays. Dropping it too let an English reader fall
        // through to raw zh prose whenever a compound had a Chinese row but no
        // English one (ketamine's mechanism, 137 others) — and a Chinese blob is
        // worse than a blank the bundled English template then fills. The ORDER BY
        // still floats the preferred language and the user's source priority. Also
        // covers the empty-source-order launch window (enabledSourceListSQL = ''
        // matches nothing), which would otherwise blank every overview until the
        // priority list finishes loading.
        return try Row.fetchOne(db, sql: """
            SELECT \(columns), t.machine_translated, src.slug AS source_slug
              FROM \(table) t
              JOIN sources src ON src.id = t.source_id
             WHERE t.substance_id = ?
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
        // (target, action).
        //
        // **A curated `affinity_tier` outranks the derived band.** The derived band is
        // absolute — Kᵢ < 100 nM strong, EC₅₀ < 1 µM strong — and an absolute band
        // cannot say which of *this* compound's targets is the weak one. Methamphetamine
        // is the case that proves it: SERT release EC₅₀ 736 nM lands under the 1 µM
        // cutoff and dots as "strong", beside DAT 24.5 and NET 12.3 nM on the same card
        // and a ternary reading SERT 1 %. The curator had already written the answer as
        // `affinity_tier = 1`; the query was discarding it. Do not restore measured-wins
        // — a hand-set tier is a claim about this drug's own balance, which is the
        // question the dots ask.
        //
        // The derived band still does all the work where nothing is curated. Binding
        // (Kᵢ) and functional (EC₅₀/IC₅₀) keep different cutoffs because a releaser's
        // EC₅₀ runs ~10× higher than a blocker's Kᵢ for the same strength. Keep these
        // identical to `ReceptorStrength` in Substance.swift.
        let bindingRows = try Row.fetchAll(db, sql: """
            SELECT target, action,
                   COALESCE(MAX(curated_tier), MAX(derived_tier), 1) AS affinity,
                   MAX(measured) AS measured, MIN(ki_nm) AS ki_nm FROM (
                SELECT b.target, b.action, b.ki_nm, b.affinity_tier AS curated_tier,
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
                            ELSE NULL END AS derived_tier
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
        // the cleanest name and the curated action label. Tier precedence is already settled per
        // (target, action) by the query above — curated first, derived band otherwise — so this pass
        // only picks between differently-*named* rows for the same receptor, preferring measured ones
        // when any exist. The full per-assay detail lives in the Receptor Literature disclosure.
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
        /// Study species (`human`, `rat`, `pig`, …), lowercased, or `nil` when unstated. Drives the
        /// resolver's interspecies allometric scaling (``SubstanceStore/scaledToHuman(_:)``): a
        /// non-human row keeps its species-invariant Vd/kg but has its confidence floored and its
        /// clearance/half-life allometrically scaled to a 70 kg human when no human value exists.
        let species: String?
        let sourceSlug: String
        let doi: String?
        let pmid: Int?
        let notes: String?
        /// Citation-verification grade for this route's values (`.unverified` when un-graded).
        var confidence: ConfidenceTier = .unverified
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
