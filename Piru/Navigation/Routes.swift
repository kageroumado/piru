import Foundation

// MARK: - Tabs

/// The five top-level tabs of the app. Replaces `selectedTab: Int` storage.
nonisolated enum AppTab: String, Hashable, Codable, CaseIterable {
    case journal
    case library
    case tools
    case insights
    case search
}

// MARK: - Push Routes

/// A value pushed onto a `NavigationStack`. Resolution from value → view lives
/// in `View.withAppDestinations()` so push destinations are registered exactly
/// once per stack.
///
/// Entry references carry the entry's stable `id` (so the route survives
/// timestamp edits) plus its `timestamp` as a resolution fallback: routes
/// decoded from pre-V4 payloads and from id-less deep links (the Live Activity
/// emits `piru://entry/<timestamp>` URLs) arrive with `id == nil` and resolve
/// through the legacy ±2 s window instead. The synthesized `Codable` decodes a
/// missing `id` key as `nil`, so old persisted snapshots keep decoding.
nonisolated enum PushRoute: Hashable, Codable {
    case session(id: UUID)
    case entry(timestamp: Date, id: UUID?)
    /// Comedown-alert screen for a dose, identified like `.entry`; the
    /// duration profile is re-derived from the resolved entry.
    case rampDown(timestamp: Date, id: UUID?)
    case comedownGuide
    case substance(name: String)
    case libraryCategory(SubstanceCategory)
    /// Substances flagged with a metadata tag (the Library's Common card).
    case libraryTag(String)
    case libraryFavorites
    case tool(Tool)
    /// One pharmacological class's write-up, by `class_contexts.slug`. Reached
    /// from Tools ▸ Education ▸ Drug Classes and from a substance's own class
    /// row.
    case drugClass(slug: String)
    /// The classes under one Library family — pushed from that family's list.
    case drugClassGroup(SubstanceCategory)
    case insight(Insight)
    /// A group of related insight graphs — the middle level of the Insights
    /// two-level push (`Specs/insights-stats-architecture.md`). Only groups with
    /// more than one graph route here; a lone graph is pushed directly.
    case insightGroup(InsightGroup)
    /// The My Meds hub — a *place*, so it pushes (Specs/meds-ux-review.md §2);
    /// `SheetRoute.dailyDoseSettings` remains for deep links and contexts
    /// without a bound stack.
    case myMeds
    /// One med's detail screen. `DailyDoseItem` has no stable id field (see
    /// `RoutineOccurrence`), so the route carries an identity snapshot:
    /// `identityKey` plus `sortOrder` to disambiguate two schedules of the
    /// same substance (e.g. oral + injected MPH).
    case medDetail(identityKey: String, sortOrder: Int)
    /// A deep-data page for a substance — the redesigned detail view's "Show
    /// all" destination. One route parameterized by `section` so Mechanism's
    /// "Show all", the per-section links, and the single "For the curious"
    /// launcher all resolve to one place. The page renders the substance's
    /// **full** data for that section regardless of the user's disclosure tier.
    case substanceData(name: String, section: DataSection)
}

/// A deep-data section reachable from a substance's detail. Excludes Effects —
/// that keeps its existing in-view "Show all" sheet (`showAllEffects`); only the
/// reference sections push a page.
///
/// `pharmacology` is deliberately one section, not separate
/// receptor-literature / pharmacokinetics pages: the deep page reuses the whole
/// `PharmacologySections` cluster (mechanism · monoamine · receptor literature ·
/// PK · metabolism), so a single honest title beats two identical pages
/// promising a subset. The inline placement of those subsections still differs
/// (see `DetailSection`); this enum is only the deep-page routing target.
nonisolated enum DataSection: String, Hashable, Codable, CaseIterable {
    case chemistry
    case pharmacology
    case sources

    /// The pushed page's navigation title.
    var pageTitle: LocalizedStringResource {
        switch self {
        case .chemistry: "Chemistry"
        case .pharmacology: "Pharmacology"
        case .sources: "Sources"
        }
    }
}

/// A detail screen reachable from the Insights overview.
nonisolated enum Insight: String, Hashable, Codable, CaseIterable, Identifiable {
    case adherence
    case usage
    /// Predicted per-mechanism tolerance and recovery — usage statistics derived from the user's own
    /// logged history (like Adherence and Usage), so it lives in Insights, not Tools
    /// (`Specs/tolerance-faithful-model-improvements.md` §7).
    case tolerance
    /// What's currently active in the body — the read-only "in your system" view.
    /// Split out from the Half-Life Calculator (`Tool.calculator`) so each screen
    /// has a single responsibility; the two cross-link to each other.
    case inSystem
    /// The historic counterpart to `inSystem`: per-substance body-load traced
    /// across a time range (`Specs/insights-stats-architecture.md`), fed by
    /// `BodyLevelsManager`.
    case bodyLoad
    /// The historic counterpart to `tolerance`: per-mechanism receptor load
    /// traced across a time range, off `ToleranceStore.loadTrail`.
    case receptorLoad
    /// Where a regularly-dosed substance settles: steady-state plateau projected
    /// from the log's own inferred median dose + interval, off `SteadyStateModel`.
    case steadyStateProjection
    /// Record-and-model patterns for self or a clinician: days used, cumulative
    /// exposure (clinical equivalents where they exist), dose trend, and
    /// co-exposure. Off the shared `ClinicalStats` layer the PDF report also uses.
    case patterns

    var id: String {
        rawValue
    }
}

/// A named cluster of related insight graphs — the middle tier of the Insights
/// two-level push. The landing shows one card per group; tapping a group with
/// several graphs pushes its list screen, while a single-graph group is pushed
/// straight to the graph (no pointless one-row list).
nonisolated enum InsightGroup: String, Hashable, Codable, CaseIterable, Identifiable {
    /// What's circulating now + how it has moved over time.
    case inYourBody
    /// Predicted tolerance now + receptor load over time.
    case toleranceReceptors

    var id: String {
        rawValue
    }

    /// The graphs in the group, in display order.
    var insights: [Insight] {
        switch self {
        case .inYourBody: [.inSystem, .bodyLoad, .steadyStateProjection]
        case .toleranceReceptors: [.tolerance, .receptorLoad]
        }
    }
}

// MARK: - Sheet Routes

/// A modal presentation. The navigator stores these in a stack so a sheet can
/// present another sheet (or be atomically replaced — see
/// ``AppNavigator/present(_:replacingTop:)``) without view-local `@State`
/// flags and `onDismiss` callbacks.
///
/// Routes are pure values; views that need a "what happens next" callback
/// (e.g. confirmation dialogs) are still better off staying as in-place
/// sheets owned by the view.
nonisolated enum SheetRoute: Hashable, Identifiable, Codable {
    // App-level
    /// `routine` pre-stages that routine's items into the tray on open —
    /// the landing state for a routine-reminder notification tap.
    ///
    /// `prefillSubstance` opens the sheet with one library substance already
    /// staged and its dose editor expanded — the "Log" affordance on a
    /// substance's detail screen. Carries the **canonical** substance name (the
    /// lookup key), never a user-typed alias.
    case quickLog(routine: String?, prefillSubstance: String? = nil)
    case settings
    case help
    case onboarding

    /// Session / entries
    case sessionDetail
    /// Entry detail sheet. Carries the entry's stable `id` with `timestamp`
    /// as the resolution fallback (see `PushRoute` — same compatibility
    /// contract for pre-V4 payloads and id-less `piru://entry/<ts>` URLs).
    case entryDetail(timestamp: Date, id: UUID?)

    // Daily dose tracking
    case dailyDoseLog(category: String)
    case dailyDoseSettings

    /// Substances
    /// Personalize a shipped substance (override its display name, dose ladder,
    /// duration, half-life, notes). Carries the canonical name; the dispatcher
    /// resolves the library substance + any existing override.
    case personalizeSubstance(name: String)

    /// Substance database settings
    case sourcePriority

    /// Every source's dose ladder for one route of one substance, on one scale —
    /// opened from the source line under the dose card. Read-only: it explains
    /// the spread, it doesn't change which source wins (that's `.sourcePriority`).
    case doseSources(substance: String, route: RouteOfAdministration)
    case advancedSearch

    /// Pickers / mini-flows
    /// Pick a color for `substance`. `remaining` carries any substances that
    /// still need a color after this one — when the user picks (or skips),
    /// the picker can re-present itself with `replacingTop: true` for the
    /// next substance in the queue.
    ///
    /// `dismissAllOnComplete`: when `true`, finishing the queue calls
    /// `navigator.dismissAll()` instead of `navigator.dismiss()`. Set this for
    /// save handlers that are completing a multi-sheet logging flow (e.g.
    /// QuickLog → ColorPicker) so the user lands back at root.
    /// Leave `false` for edit-from-detail flows where the user expects to
    /// return to the originating sheet.
    case colorPicker(substance: String, remaining: [String] = [], dismissAllOnComplete: Bool = false)

    /// Inventory
    /// Add / restock sheet. `id == nil` is the generic add form (with a
    /// Substance picker); a non-nil id restocks that existing item (and the
    /// Substance field is omitted). `prefillSubstance`/`prefillSalt` open the add
    /// form pre-targeted at a substance (the "Track" button in substance detail).
    case inventoryItemForm(id: UUID?, prefillSubstance: String? = nil, prefillSalt: String? = nil)
    /// Edit screen reached from the detail-view pencil.
    case inventoryItemEdit(id: UUID)

    /// Day utilities
    case timeAdjust(entryTimestamp: Date)

    var id: Self {
        self
    }

    /// Sheets whose root hosts a `NavigationStack` with the app's push
    /// destinations registered. While one of these is on top of the sheet
    /// stack, `AppNavigator.push` targets the sheet's own path — pushing onto
    /// the tab stack would navigate the screen *behind* the sheet instead.
    /// Must stay in sync with `SheetRouteView`'s dispatch.
    var supportsPushNavigation: Bool {
        switch self {
        case .sessionDetail, .entryDetail, .dailyDoseSettings: true
        default: false
        }
    }
}

// MARK: - Payloads

/// Prefill values for the entry form sheet. Lives at the route level so the
/// route is self-contained — no view-local `@State prefill` indirection.
///
/// Marked `nonisolated` so the type is freely constructible from any actor
/// context (including the test suite). The default file-level MainActor
/// isolation would otherwise pin its init to the main actor and contradict
/// `Sendable`.
nonisolated struct EntryPrefillPayload: Hashable, Codable {
    var substance: String
    var route: RouteOfAdministration
    var unit: String
}

// MARK: - Snapshot

/// A serializable snapshot of the navigator's full state. Used as the codec
/// boundary for deep links — `URL` ↔ `NavigatorSnapshot` is the entire deep
/// link surface.
nonisolated struct NavigatorSnapshot: Hashable, Codable {
    var selectedTab: AppTab
    var paths: [AppTab: [PushRoute]]
    var sheetStack: [SheetRoute]

    init(
        selectedTab: AppTab = .journal,
        paths: [AppTab: [PushRoute]] = [:],
        sheetStack: [SheetRoute] = [],
    ) {
        self.selectedTab = selectedTab
        self.paths = paths
        self.sheetStack = sheetStack
    }
}
