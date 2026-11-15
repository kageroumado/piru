import Foundation

// MARK: - Tabs

/// The five stock tabs. Also the "home" a destination belongs to — deep links
/// and `AppNavigator.open(_:home:)` speak it; the bar itself is `[TabID]`.
nonisolated enum AppTab: String, Hashable, Codable, CaseIterable {
    case journal
    case library
    case tools
    case insights
    case search
}

/// A screen the user can pin as its own tab (Settings ▸ Tabs). Each maps to
/// exactly one `PushRoute`, whose destination view doubles as the tab's root.
nonisolated enum PinnedScreen: Hashable {
    case tool(Tool)
    case insight(Insight)
    case insightGroup(InsightGroup)
    case myMeds
    case timeline
    case dataStorage

    var route: PushRoute {
        switch self {
        case let .tool(tool): .tool(tool)
        case let .insight(insight): .insight(insight)
        case let .insightGroup(group): .insightGroup(group)
        case .myMeds: .myMeds
        case .timeline: .timeline
        case .dataStorage: .dataStorage
        }
    }

    /// The pinnable screen a route shows, or `nil` for routes that are not a
    /// screen in their own right (a session, a substance). Routes that render
    /// the same screen collapse onto one pin, so a link to either finds it.
    init?(route: PushRoute) {
        switch route {
        case let .tool(tool): self = .tool(tool)
        case .comedownGuide: self = .tool(.recovery)
        case .insight(.inSystem), .insight(.bodyLoad), .insight(.steadyStateProjection):
            self = .insightGroup(.inYourBody)
        case let .insight(insight): self = .insight(insight)
        case let .insightGroup(group): self = .insightGroup(group)
        case .myMeds: self = .myMeds
        case .timeline: self = .timeline
        case .dataStorage: self = .dataStorage
        default: return nil
        }
    }

    /// Every screen the tab picker offers, in picker order. The In Your Body
    /// insights are offered once, as their group — they share one screen.
    static let pickable: [PinnedScreen] = {
        let tools: [Tool] = [
            .interactions, .inventory, .identify, .calculator, .steadyState, .injectionLevels,
            .volumetric, .pharma, .benzoEquivalence, .opioidEquivalence, .ceiling,
            .toleranceInfo, .recovery, .drugClasses, .effects,
        ]
        let insights: [Insight] = [
            .adherence, .usage, .tolerance, .receptorLoad, .hormoneLevels, .patterns, .feltPatterns, .reports,
        ]
        return tools.map(PinnedScreen.tool) + [.myMeds, .dataStorage]
            + insights.map(PinnedScreen.insight)
            + [.insightGroup(.inYourBody), .insightGroup(.toleranceReceptors), .timeline]
    }()

    /// Screens that already put the app's overflow menu (Help · Skins ·
    /// Settings) in their own toolbar, so their tab root must not add another.
    var ownsOverflowMenu: Bool {
        switch self {
        case .tool(.benzoEquivalence), .tool(.opioidEquivalence), .tool(.ceiling), .tool(.toleranceInfo): true
        default: false
        }
    }

    /// Stable string identity — what the tab layout persists.
    var storageKey: String {
        switch self {
        case let .tool(tool): "tool.\(tool.rawValue)"
        case let .insight(insight): "insight.\(insight.rawValue)"
        case let .insightGroup(group): "insightGroup.\(group.rawValue)"
        case .myMeds: "myMeds"
        case .timeline: "timeline"
        case .dataStorage: "dataStorage"
        }
    }

    init?(storageKey: String) {
        switch storageKey {
        case "myMeds": self = .myMeds
        case "timeline": self = .timeline
        case "dataStorage": self = .dataStorage
        default:
            let parts = storageKey.split(separator: ".", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            switch parts[0] {
            case "tool": guard let tool = Tool(rawValue: parts[1]) else { return nil }
                self = .tool(tool)
            case "insight": guard let insight = Insight(rawValue: parts[1]) else { return nil }
                self = .insight(insight)
            case "insightGroup": guard let group = InsightGroup(rawValue: parts[1]) else { return nil }
                self = .insightGroup(group)
            default: return nil
            }
        }
    }
}

/// One slot in the tab bar: a stock tab or a pinned screen. `AppTab` keeps
/// meaning "the tab a destination belongs to" (deep links speak it); this is
/// what the bar, the selection and the per-tab push paths are keyed by.
///
/// Codes as a single string (`storageKey`) — a stock tab's key is its
/// `AppTab` raw value, so a selection persisted before pinning existed still
/// restores.
nonisolated enum TabID: Hashable, Codable, CodingKeyRepresentable, Identifiable {
    case stock(AppTab)
    case pinned(PinnedScreen)

    static var journal: TabID { .stock(.journal) }
    static var library: TabID { .stock(.library) }
    static var tools: TabID { .stock(.tools) }
    static var insights: TabID { .stock(.insights) }
    static var search: TabID { .stock(.search) }

    var id: String {
        storageKey
    }

    var storageKey: String {
        switch self {
        case let .stock(tab): tab.rawValue
        case let .pinned(screen): screen.storageKey
        }
    }

    init?(storageKey: String) {
        if let tab = AppTab(rawValue: storageKey) {
            self = .stock(tab)
        } else if let screen = PinnedScreen(storageKey: storageKey) {
            self = .pinned(screen)
        } else {
            return nil
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let key = try container.decode(String.self)
        guard let tab = TabID(storageKey: key) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown tab \(key)")
        }
        self = tab
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storageKey)
    }

    var codingKey: any CodingKey {
        AnyCodingKey(storageKey)
    }

    init?(codingKey: some CodingKey) {
        self.init(storageKey: codingKey.stringValue)
    }

    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue _: Int) { nil }
    }
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
    case comedownGuide
    case timeline
    /// A substance's detail page. `brand` preselects that product in the page's
    /// Branded formulations picker — a search for "Concerta" lands on
    /// Methylphenidate with Concerta's curve drawn. The synthesized `Codable`
    /// decodes a missing `brand` key as `nil`, so old snapshots keep decoding.
    case substance(name: String, brand: String? = nil)
    case libraryCategory(SubstanceCategory)
    /// Substances flagged with a metadata tag (the Library's Common card).
    case libraryTag(String)
    case libraryFavorites
    case libraryCustom
    /// The user's custom dose units (`CustomUnitsView`), pushed from the
    /// Library's Yours card.
    case libraryUnits
    /// The user's substance colors (`SubstanceColorsListView`), pushed from
    /// the Library's Yours card.
    case libraryColors
    case tool(Tool)
    /// Data & Backup (`DataStorageView`): export, import, encrypted backups,
    /// and recovery snapshots. Pushed from the Tools hub.
    case dataStorage
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
    /// One inventory item's detail screen (`InventoryItemDetailView`), by its
    /// stable `InventoryItem.id`. Pushed by value like every other route: a
    /// view-based `NavigationLink` in this path-driven stack is rebuilt on top
    /// of whatever the detail pushes next (its Substance Info row).
    case inventoryItem(id: UUID)
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
    /// Estimated serum hormone level (estradiol / testosterone) over time, summed
    /// per logged ester and calibrated to the user's own labs — the first-class,
    /// log-driven counterpart to the prediction Tool (`Tool.injectionLevels`).
    /// Retrospective, so it lives in Insights (`Specs/injection-levels-v3.md`).
    case hormoneLevels
    /// Record-and-model patterns for self or a clinician: days used, cumulative
    /// exposure (clinical equivalents where they exist), dose trend, and
    /// co-exposure. Off the shared `SummaryStats` layer the PDF report also uses.
    case patterns
    /// What the "did it work?" answers on session notes line up with — dose
    /// hour, amount, day of week, caffeine before it. The interpretive half of
    /// a note, kept out of the note itself (`Specs/adhd-audience-fit-v2.md` §5).
    case feltPatterns
    /// Export hub: multi-select sessions for batch export (images, markdown),
    /// generate a clinical PDF with key findings first and compressed
    /// interactions, filter by substance and precise dates.
    case reports

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
        case .inYourBody: [.inSystem, .bodyLoad]
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
    ///
    /// `prefillDose` stages that substance as a complete dose (strength read
    /// off a scanned box, with the brand it was sold under) instead of an
    /// empty editor — the box scanner's "Log This" hand-off.
    ///
    /// `prefillRoute` stages `prefillSubstance` on that route instead of the
    /// substance's default — the route tab a reader had open on dose.wiki when
    /// they followed its "Log in Piru" link.
    case quickLog(
        routine: String?,
        prefillSubstance: String? = nil,
        prefillDose: DosePrefill? = nil,
        prefillRoute: RouteOfAdministration? = nil,
    )
    case settings
    /// Settings ▸ Profiles on its own, from the avatar menu's Manage Profiles.
    case profiles
    case skins
    case help
    case onboarding

    /// Session / entries
    case sessionDetail
    /// The add/edit sheet for one timestamped session note. `noteID == nil`
    /// composes a new note on `sessionID`'s session; `checkIn` tags that new
    /// note `.checkIn` (the landing state for a check-in notification tap), and
    /// `summary` makes it the session's summary.
    case sessionNoteEditor(sessionID: UUID, noteID: UUID? = nil, checkIn: Bool = false, summary: Bool = false)
    /// Choose when a session's check-in prompts fire — the custom schedule
    /// behind `Cadence.custom`.
    case checkInSchedule(sessionID: UUID)
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

    /// Import a CSV or TSV dose log exported from a spreadsheet, mapping its
    /// columns to Piru's fields.
    case spreadsheetImport
    /// Whose journal each person in a PsychonautWiki file goes into, before
    /// it imports (``PsyLogImportRequest`` holds the file).
    case psyLogImport

    /// Every source's dose ladder for one route of one substance, on one scale —
    /// opened from the source line under the dose card. Read-only: it explains
    /// the spread, it doesn't change which source wins (that's `.sourcePriority`).
    case doseSources(substance: String, route: RouteOfAdministration)
    case advancedSearch

    /// Inventory
    /// Add / restock sheet. `id == nil` is the generic add form (with a
    /// Substance picker); a non-nil id restocks that existing item (and the
    /// Substance field is omitted). `prefillSubstance`/`prefillSalt` open the add
    /// form pre-targeted at a substance (the "Track" button in substance detail).
    /// `prefill` carries what a scanned box stated (pack count, unit, a note)
    /// so the add form opens filled in; with no count the amount stays empty.
    case inventoryItemForm(id: UUID?, prefillSubstance: String? = nil, prefillSalt: String? = nil, prefill: InventoryPrefill? = nil)
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

/// What a quick-log opener already knows about the dose, staged into the tray
/// for review: the box scanner's strength and brand, or the full set a
/// `piru://quicklog` link or the Start Dose Log action carries. Every field is
/// optional — with no `amount` the substance stages as a draft on its
/// reference dose, and the tray-wide fields (`time`, `meal`, `tags`) apply
/// either way.
nonisolated struct DosePrefill: Hashable, Codable {
    /// The dose, in `unit` (a scanned box's per-unit strength).
    var amount: Double?
    /// Defaults to the substance's unit on the staged route.
    var unit: String?
    /// The brand the dose was named by ("Concerta"), kept as the staged row's
    /// `productName`. A link that names the substance by a brand gets it
    /// filled from the alias the catalog matched.
    var productName: String?
    /// The tray's "When"; defaults to now.
    var time: Date?
    /// The tray's stomach state, committed onto oral doses only, like the chip.
    var meal: MealState?
    /// The staged row's note.
    var note: String?
    /// Tray-wide tags, added to whatever the tray already carries.
    var tags: [String]?
}

/// What a scanned box stated about its contents, for the inventory add form.
/// `count` in `unit` ("tabs", "caps", "mL"); `strengthMG` is the per-unit
/// strength when the box printed one, so the form can seed the amount in mg.
nonisolated struct InventoryPrefill: Hashable, Codable {
    var count: Double?
    var unit: String?
    var strengthMG: Double?
    var note: String?
}

// MARK: - Snapshot

/// A serializable snapshot of the navigator's full state. Used as the codec
/// boundary for deep links — `URL` ↔ `NavigatorSnapshot` is the entire deep
/// link surface.
nonisolated struct NavigatorSnapshot: Hashable, Codable {
    var selectedTab: TabID
    var paths: [TabID: [PushRoute]]
    var sheetStack: [SheetRoute]

    init(
        selectedTab: TabID = .journal,
        paths: [TabID: [PushRoute]] = [:],
        sheetStack: [SheetRoute] = [],
    ) {
        self.selectedTab = selectedTab
        self.paths = paths
        self.sheetStack = sheetStack
    }
}
