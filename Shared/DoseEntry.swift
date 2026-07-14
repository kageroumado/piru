import CoreLocation
import Foundation
import SwiftData

/// A single logged dose of a substance.
///
/// SwiftData `@Model` shared across the main Piru app, the Home Screen widget
/// (`PiruWidget`), and the Lock Screen Live Activity extension
/// (`PiruLiveActivityExtension`). Because the same store is opened from
/// extensions, schema changes here must remain compatible across all three
/// targets.
///
/// ## Storage Conventions
/// - ``route`` is a `RouteOfAdministration` enum that SwiftData persists via
///   its `String` `rawValue` (`"oral"`, `"insufflation"`, etc.), making the
///   column human-readable and stable across renames of the Swift type.
/// - ``tags`` is a computed view over ``tagsRaw``, a comma-separated string.
///   Tags are CSV-encoded rather than stored as a relationship because
///   SwiftData arrays of value types are awkward to query across targets
///   and the tag set is small and read-mostly. Whitespace is trimmed on read.
///
/// ## Invariants
/// - ``amount`` is clamped to be non-negative at construction time.
@Model
final class DoseEntry {
    // `timestamp` is the dominant sort/filter key across the app — the journal's reverse-chron
    // `@Query`, the tolerance replay's lookback windows, both dose-entry warning predicates
    // (`timestamp >= cutoff`), the widget, and session recovery all sort or range-filter on it — so an
    // index earns its (small, append-time) cost many times over at 3k+ rows. `id` is also indexed for
    // the exact-match lookups deep links / edits / dedup do (`#Predicate { $0.id == … }`, fetchLimit 1).
    #Index<DoseEntry>([\.timestamp], [\.id])

    /// Stable identity for cross-boundary references — route payloads, deep
    /// links, notification keys, and the Piru export format. `persistentModelID`
    /// can't serve this role: it isn't Codable-friendly across launches and
    /// changes on store rebuilds/restores.
    ///
    /// Defaulted so the V3→V4 schema migration stays additive. Deliberately NOT
    /// `@Attribute(.unique)` — unique constraints + migration have sharp edges;
    /// uniqueness is app-level instead (fresh value per insert, per-row
    /// reassignment in the V3→V4 migration stage, and
    /// `StoreRecovery.backfillDuplicateEntryIDs` as the post-open safety net,
    /// because a lightweight migration fills ONE shared default into every
    /// existing row). See `Specs/dose-entry-stable-id.md`.
    var id: UUID = UUID()

    /// The substance's canonical (non-normalized) display name as logged by the user.
    var substance: String
    /// Quantity of the dose in ``unit``. Clamped to be `>= 0` at init.
    var amount: Double
    /// Unit of measure for ``amount`` (e.g. `"mg"`, `"µg"`, `"g"`, `"mL"`).
    var unit: String
    /// Route of administration; persisted as `rawValue` (a `String`).
    var route: RouteOfAdministration
    /// The salt/ester form logged (Citrate, Glycinate, Carbonate…), for the
    /// handful of substances that offer a choice (Magnesium, Lithium). `nil` for
    /// every other dose — which keeps the V4→V5 migration lightweight, since nil
    /// is the correct value for every pre-existing row.
    var saltForm: String?

    /// The stereoisomer form logged (D/S/L/R), for the handful of substances that
    /// resolve to a distinct enantiomer (Focalin = `D`, Esketamine = `S`). `nil`
    /// = racemic/unspecified — the correct value for every pre-existing row, so the
    /// field-add stays a lightweight migration. Participates in the PSID form
    /// identity, so a Focalin dose is a distinct recent/favorite from a
    /// methylphenidate one. Populated at log time and by the PSID backfill.
    var isomer: String?

    /// The release form logged (IR/XR/…). Greenfield until Stage B — `nil` for
    /// every dose today, kept here so the schema change is a single additive step.
    var releaseForm: String?

    /// The PSID FAMILY (`substances.substance_uid`) this dose resolves to — the
    /// stable, collision-proof substance identity, superseding the fuzzy
    /// `substance` *name* match. `nil` for a dose whose name doesn't resolve
    /// (typo, deleted, or an exotic custom substance): such a dose stays
    /// fully functional via the retained ``substance`` string, per the
    /// never-drop migration posture. Populated by the once-only PSID backfill
    /// (``PSIDBackfillMigration``) and, going forward, at log time. Additive/
    /// optional, so the schema change is a free lightweight migration. See
    /// `Specs/stereoisomer-and-release-form-axes.md` and ``PSID``.
    var substanceUID: String?

    /// The composite display title captured at resolve time — "Methylphenidate",
    /// "Esketamine", later "Methylphenidate XR" once facets exist — so the
    /// journal can title a dose from its resolved identity without re-deriving,
    /// and so the title is stable even if the catalog later relabels. `nil` until
    /// the dose resolves to a ``substanceUID``. Additive/optional.
    var displayNameSnapshot: String?
    /// When the dose was taken.
    var timestamp: Date
    /// Optional free-form note attached to the dose.
    var notes: String?
    /// CSV-encoded backing storage for ``tags``. Prefer reading/writing ``tags``.
    var tagsRaw: String?

    /// The session this dose belongs to, assigned at log time by
    /// ``SessionClustering`` and persisted. Optional so the V1→V2 migration stays
    /// lightweight and `nil` for any not-yet-populated entry; ``Session`` owns
    /// the inverse with a `.nullify` delete rule.
    var session: Session?

    /// Whether this dose was logged as a *background* medication (a daily med
    /// flagged "background"). Background doses never open or extend a recreational
    /// session — they fold into the current one if active, else form a quiet
    /// maintenance session. Stamped at log time from the ``DailyDoseItem`` so it
    /// survives later edits to the template. Defaults `false`.
    var isBackgroundMed: Bool = false

    /// Optional place where the dose was taken — a human-readable name (an Apple
    /// Maps POI, an address, or a reverse-geocoded current location). Stored
    /// alongside ``latitude``/``longitude`` so the journal can show the spot on a
    /// map. All three are optional and default `nil`, keeping the migration
    /// lightweight and leaving every existing dose location-less.
    var locationName: String?
    /// Latitude of ``locationName`` in degrees, or `nil` if no location is set.
    var latitude: Double?
    /// Longitude of ``locationName`` in degrees, or `nil` if no location is set.
    var longitude: Double?

    /// Whether grapefruit was taken with this dose — a per-dose CYP3A4-inhibition
    /// context flag (Stage 4c). Only ever set for grapefruit-sensitive (3A4-heavy)
    /// substrates when the user has enabled grapefruit logging; `nil`/`false` for
    /// every other dose, which keeps the migration additive and lightweight.
    var hadGrapefruit: Bool?

    /// By-volume input metadata for drinks logged by concentration × volume
    /// (alcohol). ``amount`` remains the canonical grams the PK/ladder run on;
    /// these record *how it was measured* so the dose round-trips as a drink on
    /// edit and can be shown in its natural terms. All `nil` for every dose not
    /// logged by volume, keeping the migration additive and lightweight.
    var volumeML: Double?
    /// Strength as percent alcohol-by-volume, paired with ``volumeML``.
    var abv: Double?
    /// Optional user-given drink name (e.g. "IPA"), shown in place of the bare
    /// substance where present.
    var drinkName: String?

    /// The dose's location as a coordinate, or `nil` unless both ``latitude`` and
    /// ``longitude`` are set. A named place may have no coordinate (e.g. a
    /// free-typed label), so a non-nil ``locationName`` does not imply this.
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Free-form labels attached to the dose, decoded from ``tagsRaw``.
    ///
    /// Backed by a comma-separated string for portable SwiftData storage across
    /// the app, widget, and Live Activity extensions. Whitespace around each
    /// tag is trimmed on read; setting an empty array writes `nil`.
    var tags: [String] {
        get {
            guard let raw = tagsRaw, !raw.isEmpty else { return [] }
            return raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        set {
            tagsRaw = newValue.isEmpty ? nil : newValue.joined(separator: ",")
        }
    }

    init(
        substance: String,
        amount: Double,
        unit: String = "mg",
        route: RouteOfAdministration = .oral,
        saltForm: String? = nil,
        isomer: String? = nil,
        releaseForm: String? = nil,
        substanceUID: String? = nil,
        displayNameSnapshot: String? = nil,
        timestamp: Date = .now,
        notes: String? = nil,
        tags: [String] = [],
        isBackgroundMed: Bool = false,
        locationName: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        hadGrapefruit: Bool? = nil,
        volumeML: Double? = nil,
        abv: Double? = nil,
        drinkName: String? = nil,
    ) {
        self.substance = substance
        self.amount = max(0, amount)
        self.unit = unit
        self.route = route
        self.saltForm = saltForm
        self.isomer = isomer
        self.releaseForm = releaseForm
        self.substanceUID = substanceUID
        self.displayNameSnapshot = displayNameSnapshot
        self.timestamp = timestamp
        self.notes = notes
        self.tagsRaw = tags.isEmpty ? nil : tags.joined(separator: ",")
        self.isBackgroundMed = isBackgroundMed
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
        self.hadGrapefruit = hadGrapefruit
        self.volumeML = volumeML
        self.abv = abv
        self.drinkName = drinkName
    }
}
