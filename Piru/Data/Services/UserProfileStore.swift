import Foundation
import GRDB
import Observation
import os
import SwiftData

/// Self-reported CYP2D6 metabolizer phenotype. The four clinical categories from CPIC guidelines;
/// `unknown` is the safe default (treated as extensive, the population majority).
enum CYP2D6Status: String, CaseIterable, Codable {
    case unknown
    case poor
    case intermediate
    case extensive
    case ultraRapid

    var label: LocalizedStringResource {
        switch self {
        case .unknown: "Unknown"
        case .poor: "Poor metabolizer"
        case .intermediate: "Intermediate metabolizer"
        case .extensive: "Extensive metabolizer"
        case .ultraRapid: "Ultra-rapid metabolizer"
        }
    }
}

/// Single home for user *profile / physiology* state, persisted via SwiftData.
///
/// Consolidates what used to be scattered: the disclosure tier lived in `SubstanceStore`'s GRDB prefs
/// DB, and body weight briefly lived in `UserDefaults`. Both are user data, not substance data, so
/// they belong in the same SwiftData store as doses/colors/favorites — one store, one backup and
/// recovery path, typed fields, and lightweight migration for the coming phenotype/context flags
/// (ALDH2, CYP2D6, smoking, grapefruit). SwiftData over GRDB here because this is durable, app-owned
/// user data and the rest of that layer is already SwiftData; the genuinely extension-shared feature
/// flags stay in the app-group `UserDefaults` where widgets can read them.
///
/// Wraps the app's shared `ModelContainer` (set once at launch via ``configure(container:)``) and a
/// single ``UserProfileRecord`` row, created lazily on first write. On first launch it migrates the
/// legacy disclosure tier out of the old GRDB `piru-user-prefs.sqlite` so existing users keep their
/// choice.
@Observable @MainActor
final class UserProfileStore {
    static let shared = UserProfileStore()

    // MARK: - Body-weight constants (Foundation A)

    /// Population-default adult body weight (kg), used when no real value is known.
    /// Every number derived from it is flagged "estimated" until a real value exists.
    static let defaultWeightKg = 60.0

    /// Plausible manual-entry bounds (kg). Input outside this range is rejected as a typo.
    static let weightRangeKg = 20.0 ... 300.0

    /// Provenance of the stored body weight — drives the "estimated" badge and Settings copy.
    enum WeightSource: String, Codable {
        case healthKit
        case manual
        /// No real value stored; ``effectiveWeightKg`` is the population default.
        case estimated
    }

    private let logger = Logger(subsystem: "dev.yumeji.piru", category: "UserProfileStore")

    // Persistence backing is deliberately `@ObservationIgnored`: a `ModelContext` / `@Model` stored as
    // an observation-tracked property of an `@Observable` type drags in SwiftData's SwiftUI observation
    // machinery, which traps (EXC_BREAKPOINT) when the graph is mutated outside a view update. View
    // observation is driven instead by the plain published value properties below; the record is just
    // the durable mirror.
    /// Retained so the context's coordinator stays alive for the store's lifetime. A `ModelContext`
    /// does not strongly own its container; dropping the container leaves an orphaned context that
    /// traps on the next mutation.
    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var record: UserProfileRecord?

    /// `internal` (not `private`) so tests can build isolated instances against an in-memory
    /// container; production code uses ``shared``.
    init() {}

    // MARK: - Published state (the observed source of truth for views)

    /// The user's chosen disclosure tier (drives progressive-disclosure defaults in detail views).
    private(set) var disclosureTier: UserProfile = .harmReduction

    /// The user's body weight in kg, or `nil` if never set (→ population default, estimated).
    private(set) var weightKg: Double?

    /// Provenance of ``weightKg`` (or `.estimated` when unset).
    private(set) var weightSource: WeightSource = .estimated

    /// Whether the user smokes tobacco regularly (chronic CYP1A2 induction — Stage 4c metabolic flag).
    private(set) var smokesTobacco: Bool = false

    /// Whether the per-dose "had grapefruit" toggle is shown in the dose logger (off by default).
    private(set) var grapefruitLoggingEnabled: Bool = false

    /// Whether the user carries an ALDH2 loss-of-function variant ("alcohol flush"). Self-reported,
    /// off by default; gates the acetaldehyde readout in the alcohol vertical (Stage 5 / Foundation B).
    private(set) var aldh2Deficient: Bool = false

    /// Self-reported CYP2D6 metabolizer status. Affects PK for codeine, tramadol, MDMA, and others.
    /// `unknown` is the default (treated as extensive — the population majority). Surfaces educational
    /// notes on affected substances; a coarse PK multiplier is behind the Pharma Nerd tier.
    private(set) var cyp2d6Status: CYP2D6Status = .unknown

    // MARK: - Configuration

    /// Bind to the app's shared container. Call once at launch, before any view reads profile state.
    /// Idempotent. Loads the existing record (if any) and runs the one-time legacy-tier migration.
    func configure(container: ModelContainer, legacyPrefsDBURL: URL? = UserProfileStore.defaultLegacyPrefsDBURL) {
        self.container = container
        let ctx = container.mainContext
        context = ctx
        record = (try? ctx.fetch(FetchDescriptor<UserProfileRecord>()))?.first
        if record == nil {
            migrateLegacyTier(into: ctx, from: legacyPrefsDBURL)
        }
        publishFromRecord()
    }

    /// Mirror the durable record into the published value properties that views observe.
    private func publishFromRecord() {
        guard let record else {
            disclosureTier = .harmReduction
            weightKg = nil
            weightSource = .estimated
            smokesTobacco = false
            grapefruitLoggingEnabled = false
            aldh2Deficient = false
            cyp2d6Status = .unknown
            return
        }
        disclosureTier = UserProfile(rawValue: record.disclosureTierRaw) ?? .harmReduction
        weightKg = record.bodyWeightKg
        weightSource = WeightSource(rawValue: record.weightSourceRaw)
            ?? (record.bodyWeightKg == nil ? .estimated : .manual)
        smokesTobacco = record.smokesTobacco
        grapefruitLoggingEnabled = record.grapefruitLoggingEnabled
        aldh2Deficient = record.aldh2Deficient
        cyp2d6Status = CYP2D6Status(rawValue: record.cyp2d6StatusRaw) ?? .unknown
    }

    private static var defaultLegacyPrefsDBURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        return docs.appendingPathComponent("piru-user-prefs.sqlite")
    }

    // MARK: - Disclosure tier

    /// Persist a new disclosure tier. Immediate and `@Observable`, so detail views re-render with the
    /// new defaults.
    func setDisclosureTier(_ tier: UserProfile) {
        guard tier != disclosureTier else { return }
        disclosureTier = tier
        ensureRecord().disclosureTierRaw = tier.rawValue
        save()
    }

    // MARK: - Metabolic context flags (Stage 4c)

    /// Persist the "I smoke tobacco regularly" profile flag (chronic CYP1A2 induction).
    func setSmokesTobacco(_ value: Bool) {
        guard value != smokesTobacco else { return }
        smokesTobacco = value
        ensureRecord().smokesTobacco = value
        save()
    }

    /// Persist whether the per-dose grapefruit toggle is shown in the dose logger.
    func setGrapefruitLoggingEnabled(_ value: Bool) {
        guard value != grapefruitLoggingEnabled else { return }
        grapefruitLoggingEnabled = value
        ensureRecord().grapefruitLoggingEnabled = value
        save()
    }

    /// Persist the self-reported ALDH2 ("alcohol flush") phenotype flag.
    func setALDH2Deficient(_ value: Bool) {
        guard value != aldh2Deficient else { return }
        aldh2Deficient = value
        ensureRecord().aldh2Deficient = value
        save()
    }

    /// Persist the self-reported CYP2D6 metabolizer status.
    func setCYP2D6Status(_ value: CYP2D6Status) {
        guard value != cyp2d6Status else { return }
        cyp2d6Status = value
        ensureRecord().cyp2d6StatusRaw = value.rawValue
        save()
    }

    // MARK: - Body weight

    /// Weight to use in calculations — the user's value, or the population default when unset.
    var effectiveWeightKg: Double {
        weightKg ?? Self.defaultWeightKg
    }

    /// `true` when no real weight is known, so downstream numbers should carry an "estimated" badge.
    var isWeightEstimated: Bool {
        weightKg == nil
    }

    /// Record a weight the user typed in. Non-finite or out-of-range values are ignored.
    func setManualWeight(_ kg: Double) {
        guard kg.isFinite, Self.weightRangeKg.contains(kg) else { return }
        persistWeight(kg, source: .manual)
    }

    /// Record a weight read from HealthKit. Non-finite or out-of-range values are ignored.
    func setHealthKitWeight(_ kg: Double) {
        guard kg.isFinite, Self.weightRangeKg.contains(kg) else { return }
        persistWeight(kg, source: .healthKit)
    }

    /// Clear the stored weight, reverting to the population default (estimated).
    func clearWeight() {
        weightKg = nil
        weightSource = .estimated
        let r = ensureRecord()
        r.bodyWeightKg = nil
        r.weightSourceRaw = WeightSource.estimated.rawValue
        save()
    }

    private func persistWeight(_ kg: Double, source: WeightSource) {
        weightKg = kg
        weightSource = source
        let r = ensureRecord()
        r.bodyWeightKg = kg
        r.weightSourceRaw = source.rawValue
        save()
    }

    // MARK: - Record lifecycle

    private func ensureRecord() -> UserProfileRecord {
        if let record { return record }
        let r = UserProfileRecord()
        if let context {
            context.insert(r)
        } else {
            // A setter ran before configure(container:). The published value still updates so the UI
            // is correct this session, but nothing would persist — fail loudly in debug rather than
            // dropping the write silently. In production configure() runs at launch before any view.
            logger.fault("UserProfileStore mutated before configure(container:); write will not persist")
            assertionFailure("UserProfileStore.configure(container:) must run before any mutation")
        }
        record = r
        return r
    }

    private func save() {
        do {
            try context?.save()
        } catch {
            logger.error("Failed to save user profile: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Legacy migration

    /// One-time copy of the disclosure tier from the legacy GRDB `piru-user-prefs.sqlite`
    /// `user_profile` table into a fresh SwiftData record. Runs only when no record exists yet and the
    /// legacy file/table is present, so existing users keep their chosen tier across the storage move.
    ///
    /// LEGACY — plan to remove. Bridges installs still carrying a GRDB-stored disclosure tier to the
    /// SwiftData store exactly once on first launch. Once ASC confirms all installs have launched a
    /// SwiftData-tier build, delete this method and stop reading the GRDB prefs DB (the
    /// `legacyPrefsDBURL` plumbing in ``configure(container:)`` goes with it). See the legacy-removal
    /// tracking note.
    private func migrateLegacyTier(into ctx: ModelContext, from legacyURL: URL?) {
        guard let legacyURL, FileManager.default.fileExists(atPath: legacyURL.path) else { return }
        do {
            var config = Configuration()
            config.readonly = true
            config.label = "piru-user-prefs-legacy"
            let legacy = try DatabaseQueue(path: legacyURL.path, configuration: config)
            let raw = try legacy.read { db -> String? in
                let hasTable = try Int.fetchOne(
                    db,
                    sql: "SELECT 1 FROM sqlite_master WHERE type='table' AND name='user_profile'",
                ) != nil
                guard hasTable else { return nil }
                return try String.fetchOne(
                    db,
                    sql: "SELECT value FROM user_profile WHERE key = 'profile'",
                )
            }
            guard let raw, let tier = UserProfile(rawValue: raw) else { return }
            let migrated = UserProfileRecord(disclosureTierRaw: tier.rawValue)
            ctx.insert(migrated)
            record = migrated
            try ctx.save()
            logger.info("Migrated legacy disclosure tier '\(raw, privacy: .public)' into SwiftData")
        } catch {
            logger.error("Legacy disclosure-tier migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
