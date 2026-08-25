import Foundation
import GRDB
import Observation
import os

private nonisolated let logger = Logger(subsystem: "dev.yumeji.piru", category: "SubstanceStore")

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
    /// Browse-surfacing substance count per metadata tag — the tag cards'
    /// counterpart to `categorySummaryCache`, invalidated in lockstep.
    @ObservationIgnored private var tagSummaryCache: [String: Int]?
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
    /// Whether `init` fired the off-main batch prefill — the production
    /// configuration. Gates the cold-`all` tripwire below: a store built
    /// without the prewarm (tests) reaches the cold arm by design.
    private let prewarmsAllCache: Bool

    init(substancesDBURL: URL, userPrefsDBURL: URL, prewarmsAllCache: Bool = true) {
        self.prewarmsAllCache = prewarmsAllCache
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
        // Eager-prefill the `all` cache *off the main thread*: a synchronous
        // resolve of all 1700+ substances on the main actor costs ~660 ms,
        // which the first Library-tab tap — and, more visibly, the first
        // quick-log open — would otherwise pay. The batch loader is a
        // `nonisolated static` that does its SQL + struct building on this
        // background task; we only hop back to main to publish the finished
        // array into the cache.
        if prewarmsAllCache {
            // Read on the dedicated batch connection so this ~500 ms resolve
            // never blocks a foreground per-field read on `substancesDB`.
            let prewarmDB = substancesBatchDB
            let prewarmOrder = enabledSourceOrder
            prewarmTask = Task.detached(priority: .userInitiated) {
                let resolved = SubstanceReadModel.loadAllSubstancesBatch(db: prewarmDB, order: prewarmOrder)
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
        tagSummaryCache = nil
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
                       (pd.product_normalized IS NOT NULL) AS has_curve
                  FROM aliases a
                  JOIN substances s ON s.id = a.substance_id
                  LEFT JOIN product_durations pd ON pd.product_normalized = a.alias_normalized
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
        // Every production path must `await ensureAllLoaded()` before anything
        // that reads `all` — the cold arm below builds the whole batch
        // synchronously on the main actor (~500 ms) on the FOREGROUND
        // connection, blocking every other read behind it. The assertion turns
        // a missed await from a silent hang in the field into a caught bug in
        // development; release builds keep the fallback.
        if prewarmsAllCache {
            assertionFailure("Cold SubstanceStore.all on the main actor — await ensureAllLoaded() on this path first.")
        }
        let resolved = SubstanceReadModel.loadAllSubstancesBatch(db: substancesDB, order: order)
        allCache = resolved
        batchByName = nil
        batchByID = nil
        // Intentionally NOT writing to resolvedCache: the batch path omits
        // mechanism / subjective effects / tolerance (loaded by lookup() on
        // demand for the detail view). Poisoning the per-substance cache
        // with partial data would make detail views miss those fields.
        return resolved
    }

    /// Whether the batch cache is already published — the cheap check for a
    /// synchronous caller that must not reach the cold arm of `all` (defer and
    /// retry after ``ensureAllLoaded()`` instead).
    var isBatchCacheWarm: Bool {
        allCache != nil
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
            SubstanceReadModel.loadAllSubstancesBatch(db: db, order: order)
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

    /// Browse-surfacing substance count per metadata tag (`"common"`,
    /// `"research-chemical"`, …) — one bucketing sweep, so a tag card's count
    /// is a dict hit instead of an O(catalog) filter per body pass. Same
    /// warm-cache discipline as ``categorySummary()``.
    func tagSummary() -> [String: Int] {
        _ = enabledSourceOrder // observation dependency; see `categorySummary()`
        if let cached = tagSummaryCache { return cached }
        var counts: [String: Int] = [:]
        for substance in all where substance.displayClass.surfacesInBrowse {
            for tag in substance.tags {
                counts[tag, default: 0] += 1
            }
        }
        tagSummaryCache = counts
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
        let priorityCaseSQL = SubstanceReadModel.priorityCaseSQL(order)
        let enabledSourceListSQL = SubstanceReadModel.enabledSourceListSQL(order)
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
    /// the app's UI language (``SubstanceReadModel/contentLanguage``). Lets
    /// tests exercise the locale-first text resolution without changing the
    /// process locale.
    var languageOverride: ContentLanguage?

    /// The resolution engine bound to this store's current inputs: the
    /// foreground connection, the user's enabled-source order, and the content
    /// language (honoring ``languageOverride``). Constructing it reads
    /// ``enabledSourceOrder``, which registers the source-order observation
    /// dependency — a SwiftUI body that resolves through the reader re-renders
    /// when the user reorders sources.
    var reader: SubstanceReadModel {
        SubstanceReadModel(
            db: substancesDB,
            order: enabledSourceOrder,
            language: languageOverride ?? SubstanceReadModel.contentLanguage,
        )
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
        let reader = self.reader
        // Language is part of the cache key so a mid-session app-language change
        // re-resolves locale-first text instead of serving stale-language rows.
        let cacheKey = "\(id)|\(reader.language.rawValue)"
        if let cached = resolvedCache[cacheKey] { return cached }
        let resolved = reader.substance(id: id, editorialColumns: editorialColumns())
        if let resolved {
            resolvedCache[cacheKey] = resolved
        }
        return resolved
    }
}
