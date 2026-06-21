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
    case insight(Insight)
}

/// A detail screen reachable from the Insights overview.
nonisolated enum Insight: String, Hashable, Codable, CaseIterable, Identifiable {
    case adherence
    case usage

    var id: String {
        rawValue
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
    case quickLog(routine: String?)
    case settings
    case help
    case onboarding

    /// Session / entries
    case sessionDetail
    /// Entry detail sheet. Carries the entry's stable `id` with `timestamp`
    /// as the resolution fallback (see `PushRoute` — same compatibility
    /// contract for pre-V4 payloads and id-less `piru://entry/<ts>` URLs).
    case entryDetail(timestamp: Date, id: UUID?)
    case entryForm(prefill: EntryPrefillPayload?)
    /// Edit an existing entry. Carries the entry's stable `id` so a batch of
    /// doses sharing one timestamp resolves to the exact row the user acted on;
    /// `timestamp` stays as the fallback for id-less/legacy payloads.
    case entryEdit(timestamp: Date, id: UUID?)

    // Daily dose tracking
    case dailyDoseLog(category: String)
    case dailyDoseSettings
    case dailyDoseItemForm(itemID: UUID?)

    // Substances
    case customSubstancesList
    case customSubstanceForm(id: UUID?)
    /// Personalize a shipped substance (override its display name, dose ladder,
    /// duration, half-life, notes). Carries the canonical name; the dispatcher
    /// resolves the library substance + any existing override.
    case personalizeSubstance(name: String)

    // Substance database settings
    case sourcePriority
    case advancedSearch

    /// Pickers / mini-flows
    /// Pick a color for `substance`. `remaining` carries any substances that
    /// still need a color after this one — when the user picks (or skips),
    /// the picker can re-present itself with `replacingTop: true` for the
    /// next substance in the queue. Replaces the chained `onDismiss` color
    /// loop in `LogDailyDoseView`.
    ///
    /// `dismissAllOnComplete`: when `true`, finishing the queue calls
    /// `navigator.dismissAll()` instead of `navigator.dismiss()`. Set this for
    /// save handlers that are completing a multi-sheet logging flow (e.g.
    /// QuickLog → EntryForm → ColorPicker) so the user lands back at root.
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

    // Day utilities
    case journalFilters
    case journalCalendar
    case timeAdjust(entryTimestamp: Date)
    case dayShare(date: Date)

    var id: Self {
        self
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
