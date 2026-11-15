import Foundation

/// Bidirectional URL ↔ navigator state codec.
///
/// ## URL Scheme
///
/// All deep links use the `piru://` scheme. The URL `host` selects the kind
/// of destination; path components and query items carry parameters. Decoding
/// an unrecognised URL returns `nil` so callers can fall back to default
/// behavior.
///
/// **Whose journal** — any link takes `profile=<uuid>` (``profileQueryItem``):
/// the app opens that profile's journal first, then lands where the rest of
/// the link says.
///
/// **Tab selection** — `piru://<tab>` selects the tab and clears any modal:
/// `piru://journal`, `piru://library`, `piru://tools`, `piru://insights`,
/// `piru://search`.
///
/// **App-level sheets** (open over the current tab):
/// - `piru://quicklog[?routine=<name>][?substance=<name>[&route=<route>]]` →
///   present `.quickLog`, optionally pre-staging a routine's items
///   (routine-reminder notification taps) or one substance with its dose editor
///   open (the "Log" button on a substance's detail screen), on `route` when
///   given (`oral`, `insufflated`, `smoked`, … as ``RouteOfAdministration``
///   parses them)
/// - `piru://quicklog?substance=<name>&amount=<n>&unit=<unit>&route=<route>`
///   `&time=<when>&meal=<empty|light|full>&notes=<text>&tags=<a,b>&product=<brand>`
///   → the same sheet with that dose staged for review (a ``DosePrefill``):
///   the automation form, and what the Start Dose Log action opens. `substance`
///   may be a brand ("Concerta"), which is kept as the dose's product. `time`
///   is ISO 8601 (`2026-10-18T09:30:00Z`, offsets allowed) or epoch seconds.
///   Every parameter but `substance` is optional; without `amount` the editor
///   opens on the reference dose. A link never saves on its own.
/// - `piru://settings` → present `.settings`
/// - `piru://profiles` → present `.profiles` (Settings ▸ Profiles)
/// - `piru://skins` → present `.skins`
/// - `piru://help` → present `.help`
///
/// **Entry-flow sheets** (select journal, then present):
/// - `piru://day` → present `.sessionDetail`
/// - `piru://entry/<unix-timestamp>[?id=<uuid>]` → present
///   `.entryDetail(timestamp:id:)`; `id` is the dose's stable identity, and
///   id-less URLs (pre-V4 links, the Live Activity) resolve by timestamp
///
/// **Medication sheets**:
/// - `piru://meds/<category>` → present `.dailyDoseLog(category:)`
///
/// **Inventory sheets**:
/// - `piru://inventory/<uuid>` → present `.inventoryItemForm(id:)` (restock)
/// - `piru://inventory` → present `.inventoryItemForm(id: nil)` (new item)
///
/// **Push destinations** (replace the target tab's stack). The tab named here
/// is the destination's *home*; where it lands depends on the user's bar
/// (`TabRouting`): a tab the user pinned for that screen wins, and with the
/// home tab hidden the route is pushed onto the current tab.
/// - `piru://tool/<name>` → Tools tab, push that tool full-screen. `<name>`
///   matches a `Tool` raw value case-insensitively (`tolerance`, `ceiling`,
///   `benzoEquivalence`, `pharma`, `calculator`, `volumetric`, `recovery`,
///   `interactions`, `inventory`).
/// - `piru://session/<uuid>` → Journal tab, push that session's detail.
/// - `piru://substance/<name>[?brand=<product>]` → Library tab, push that
///   substance's detail (percent-encode spaces, e.g.
///   `piru://substance/Psilocybin%20mushrooms`); `brand` preselects that product
///   in the page's Branded formulations picker.
///
/// **Web links** (`https://kagerou.glass/piru/…`, the App Link / Universal
/// Link form that dose.wiki's articles carry) name a substance by its
/// dose.wiki slug, which only the loaded catalog can resolve. They decode to a
/// ``DosewikiLink`` through ``decodeWebLink(_:)``, and the caller turns that
/// into an outcome once the slug has a name:
/// - `/piru/log?substance=<slug>[&route=<route>]` → the same outcome as
///   `piru://quicklog?substance=<name>&route=<route>`
/// - `/piru/open?substance=<slug>` → the same outcome as
///   `piru://substance/<name>`
///
/// The encoder always emits a single URL describing the *top* of the modal
/// stack (or just the tab when no modal is presented). Multi-level stacks
/// aren't yet representable as a single URL — that's by design, since deep
/// links open a specific destination, not arbitrary nav state.
/// The intent of a single deep-link URL: maybe switch to a tab, maybe
/// present a sheet. Distinct from `NavigatorSnapshot` because deep links
/// don't speak about *unchanged* state — a URL like `piru://quicklog`
/// shouldn't clobber the user's current tab.
nonisolated struct DeepLinkOutcome: Hashable {
    /// `nil` means "preserve the current tab".
    var tab: AppTab?
    /// `nil` means "no sheet to present" (the URL is tab-only or
    /// unrepresentable).
    var sheet: SheetRoute?
    /// `nil` means "leave the tab's push stack untouched". A non-nil value
    /// *replaces* the target tab's stack — used by tool and session deep
    /// links (`piru://tool/<name>`, `piru://session/<id>`) which push a
    /// full-screen destination rather than presenting a modal.
    var path: [PushRoute]?

    init(tab: AppTab? = nil, sheet: SheetRoute? = nil, path: [PushRoute]? = nil) {
        self.tab = tab
        self.sheet = sheet
        self.path = path
    }
}

nonisolated enum DeepLink {
    static let scheme = "piru"

    // MARK: - Profile

    /// The query item naming whose journal a link opens: any `piru://` URL
    /// takes `profile=<uuid>`, and the app switches to that profile before it
    /// routes. Absent, the link opens in whichever profile is active.
    static let profileQueryItem = "profile"

    static func profileID(in url: URL) -> UUID? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == profileQueryItem }?
            .value
            .flatMap(UUID.init(uuidString:))
    }

    /// `url` with `profile=<id>` set, replacing any profile it named.
    static func tagging(_ url: URL, profile id: UUID) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = (components.queryItems ?? []).filter { $0.name != profileQueryItem }
        items.append(URLQueryItem(name: profileQueryItem, value: id.uuidString.lowercased()))
        components.queryItems = items
        return components.url ?? url
    }

    // MARK: - Decode

    /// Parse a `piru://` URL into a navigator outcome. Returns `nil` for
    /// unsupported schemes or unrecognised hosts.
    static func decode(_ url: URL) -> DeepLinkOutcome? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == scheme,
              let host = components.host?.lowercased()
        else { return nil }

        let pathSegments = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        // A repeated parameter keeps its first value. The URL comes from outside
        // the app (a notification, another app, a pasted link), so its shape is
        // untrusted input and a duplicate key must never trap.
        let query = Dictionary((components.queryItems ?? []).compactMap { item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name, value)
        }, uniquingKeysWith: { first, _ in first })

        // Tab-only deep link: switch tab, no sheet.
        if let tab = AppTab(rawValue: host), pathSegments.isEmpty {
            return DeepLinkOutcome(tab: tab, sheet: nil)
        }

        // Explicit tab override via `?tab=library` etc. — overrides whatever
        // default the host would imply.
        let overrideTab = query["tab"].flatMap(AppTab.init(rawValue:))

        switch host {
        case "quicklog":
            // App-level sheets preserve the current tab by default.
            return DeepLinkOutcome(
                tab: overrideTab,
                sheet: .quickLog(
                    routine: query["routine"],
                    prefillSubstance: query["substance"],
                    prefillDose: dosePrefill(from: query),
                    prefillRoute: query["route"].flatMap(route(named:)),
                ),
            )

        case "settings":
            return DeepLinkOutcome(tab: overrideTab, sheet: .settings)

        case "profiles":
            return DeepLinkOutcome(tab: overrideTab, sheet: .profiles)

        case "skins":
            return DeepLinkOutcome(tab: overrideTab, sheet: .skins)

        case "help":
            return DeepLinkOutcome(tab: overrideTab, sheet: .help)

        case "day":
            // Journal-flow routes implicitly land on the journal tab since the
            // sheet makes no sense in any other context.
            return DeepLinkOutcome(tab: overrideTab ?? .journal, sheet: .sessionDetail)

        case "entry":
            guard let tsString = pathSegments.first,
                  let ts = TimeInterval(tsString) else { return nil }
            let timestamp = Date(timeIntervalSince1970: ts)
            // `id` is optional: pre-V4 URLs and the Live Activity's
            // timestamp-only links omit it, and the route's lookup falls back
            // to the ±2 s window.
            return DeepLinkOutcome(
                tab: overrideTab ?? .journal,
                sheet: .entryDetail(timestamp: timestamp, id: query["id"].flatMap(UUID.init(uuidString:))),
            )

        case "meds":
            guard let category = pathSegments.first else { return nil }
            return DeepLinkOutcome(
                tab: overrideTab ?? .journal,
                sheet: .dailyDoseLog(category: category),
            )

        case "inventory":
            if let segment = pathSegments.first {
                guard let id = UUID(uuidString: segment) else { return nil }
                return DeepLinkOutcome(
                    tab: overrideTab ?? .tools,
                    sheet: .inventoryItemForm(id: id),
                )
            }
            return DeepLinkOutcome(
                tab: overrideTab ?? .tools,
                sheet: .inventoryItemForm(id: nil),
            )

        case "tool":
            // `piru://tool/<rawValue>` pushes a tool onto the Tools tab.
            // Raw values are matched case-insensitively so hand-typed links
            // like `piru://tool/benzoequivalence` resolve the camelCase case.
            guard let toolRaw = pathSegments.first else { return nil }
            // Back-compat alias (§7): Tolerance moved from Tools to Insights, so the old
            // `piru://tool/tolerance` links (used for sim QA) still resolve — to the new insight route.
            if toolRaw.lowercased() == "tolerance" {
                return DeepLinkOutcome(tab: overrideTab ?? .insights, path: [.insight(.tolerance)])
            }
            guard let tool = Tool.allCases.first(where: { $0.rawValue.lowercased() == toolRaw.lowercased() })
            else { return nil }
            return DeepLinkOutcome(
                tab: overrideTab ?? .tools,
                path: [.tool(tool)],
            )

        case "insight":
            // `piru://insight/<rawValue>` pushes an insight detail onto the Insights tab.
            guard let insightRaw = pathSegments.first,
                  let insight = Insight.allCases.first(where: { $0.rawValue.lowercased() == insightRaw.lowercased() })
            else { return nil }
            return DeepLinkOutcome(
                tab: overrideTab ?? .insights,
                path: [.insight(insight)],
            )

        case "session":
            // `piru://session/<uuid>` pushes a session detail onto the Journal tab;
            // `?note=new|checkIn` additionally opens the note sheet on it — the
            // check-in notification's landing.
            guard let idString = pathSegments.first,
                  let id = UUID(uuidString: idString) else { return nil }
            let noteSheet: SheetRoute? = switch query["note"] {
            case "checkIn": .sessionNoteEditor(sessionID: id, checkIn: true)
            case "new": .sessionNoteEditor(sessionID: id)
            default: nil
            }
            return DeepLinkOutcome(
                tab: overrideTab ?? .journal,
                sheet: noteSheet,
                path: [.session(id: id)],
            )

        case "substance":
            // `piru://substance/<name>` pushes a substance detail onto the Library tab.
            // `piru://substance/<name>/data/<section>` pushes that substance's
            // deep-data page (chemistry / receptor-literature / pharmacokinetics /
            // sources). The name is the path up to an optional trailing
            // `data/<section>`, so multi-word names like `.../Psilocybin%20mushrooms`
            // still resolve.
            var nameSegments = pathSegments
            var dataSection: DataSection?
            if nameSegments.count >= 3, nameSegments[nameSegments.count - 2] == "data" {
                // A recognized section routes to the deep-data page. A `data`
                // marker with an unknown section (a typo, or a link from a
                // newer app version) still opens the substance itself rather
                // than folding "data/<typo>" into the substance name.
                dataSection = DataSection(rawValue: nameSegments[nameSegments.count - 1])
                nameSegments.removeLast(2)
            }
            let name = nameSegments.joined(separator: "/")
            guard !name.isEmpty else { return nil }
            let route: PushRoute = dataSection.map { .substanceData(name: name, section: $0) }
                ?? .substance(name: name, brand: query["brand"])
            return DeepLinkOutcome(
                tab: overrideTab ?? .library,
                path: [route],
            )

        default:
            return nil
        }
    }

    /// A route named in a link, or `nil` for one ``RouteOfAdministration``
    /// does not know, so an unknown route falls back to the substance's
    /// default rather than staging the dose as "Other".
    private static func route(named name: String) -> RouteOfAdministration? {
        let route = RouteOfAdministration.from(string: name)
        return route == .other ? nil : route
    }

    /// The dose a `piru://quicklog` link describes beyond its substance and
    /// route, or `nil` when it names none of those fields. A value the link
    /// gets wrong (a non-numeric amount, an unknown meal word) is dropped, not
    /// the whole link: the sheet still opens, on what the link did say.
    private static func dosePrefill(from query: [String: String]) -> DosePrefill? {
        let tags = query["tags"]?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let prefill = DosePrefill(
            amount: query["amount"].flatMap(Double.init).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil },
            unit: query["unit"].nonBlank,
            productName: query["product"].nonBlank,
            time: query["time"].flatMap(date(named:)),
            meal: query["meal"].flatMap { MealState(rawValue: $0.lowercased()) },
            note: query["notes"].nonBlank,
            tags: tags.flatMap { $0.isEmpty ? nil : $0 },
        )
        return prefill == DosePrefill() ? nil : prefill
    }

    /// `time=` as a link may write it: ISO 8601 with or without fractional
    /// seconds (`2026-10-18T09:30:00Z`, `…09:30:00+02:00`), or Unix epoch seconds.
    private static func date(named value: String) -> Date? {
        if let date = try? Date(value, strategy: .iso8601) {
            return date
        }
        if let seconds = Double(value), seconds.isFinite, seconds > 0 {
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }

    /// The `time=` form the encoder writes: UTC ISO 8601 to the second. A date
    /// with fractional seconds loses them on the way through a URL.
    static func timeParameter(for date: Date) -> String {
        date.formatted(.iso8601)
    }

    /// `amount=` without a trailing `.0` for whole numbers, so the URL reads the
    /// way a person would write it.
    static func amountParameter(for amount: Double) -> String {
        amount == amount.rounded() && abs(amount) < 1e15
            ? String(Int(amount))
            : String(amount)
    }

    // MARK: - Web links

    /// The host of dose.wiki's links into the app (`AndroidManifest.xml`'s
    /// App Link filter names the same host and paths).
    static let webHost = "kagerou.glass"

    /// Parse a `https://kagerou.glass/piru/…` link. Returns `nil` for any other
    /// host or path, so a link the app does not understand changes nothing on
    /// screen. Pure: the slug stays unresolved until the catalog is loaded.
    static func decodeWebLink(_ url: URL) -> DosewikiLink? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == webHost
        else { return nil }
        let pathSegments = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.lowercased() }
        guard pathSegments.count == 2, pathSegments[0] == "piru" else { return nil }
        // First value wins, as in `decode`: the link is untrusted input.
        let query = Dictionary((components.queryItems ?? []).compactMap { item -> (String, String)? in
            guard let value = item.value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
            return (item.name, value)
        }, uniquingKeysWith: { first, _ in first })

        switch pathSegments[1] {
        case "log":
            return DosewikiLink(action: .log, slug: query["substance"], route: query["route"].flatMap(route(named:)))
        case "open":
            guard let slug = query["substance"] else { return nil }
            return DosewikiLink(action: .open, slug: slug, route: nil)
        default:
            return nil
        }
    }

    // MARK: - Encode

    /// Produce a canonical `piru://` URL for a snapshot.
    ///
    /// Encoding is *lossy* by design: only the top of the sheet stack and the
    /// selected tab are represented. If the stack is empty, the URL is just
    /// the tab selector. If the top sheet has no canonical URL form (e.g.
    /// `.timeAdjust`), encoding returns `nil`.
    static func encode(_ snapshot: NavigatorSnapshot) -> URL? {
        // A pinned tab has no URL of its own and emits no `?tab=`: its links
        // find it again by their route (`TabRouting`).
        let stockTab: AppTab? = if case let .stock(tab) = snapshot.selectedTab { tab } else { nil }
        if snapshot.sheetStack.isEmpty {
            // No modal: encode the top of the selected tab's push stack if it
            // has a canonical URL form (tool / session), otherwise just the tab
            // — for a pinned tab, its root screen's route.
            if let top = snapshot.paths[snapshot.selectedTab]?.last,
               let url = encode(push: top, tab: stockTab) {
                return url
            }
            switch snapshot.selectedTab {
            case let .stock(tab): return URL(string: "\(scheme)://\(tab.rawValue)")
            case let .pinned(screen): return encode(push: screen.route, tab: nil)
            }
        }

        guard let top = snapshot.sheetStack.last else { return nil }
        return encode(sheet: top, tab: stockTab)
    }

    /// Canonical URL for a push route, or `nil` for app-internal pushes that
    /// aren't deep-linkable. Only tools and sessions round-trip.
    private static func encode(push route: PushRoute, tab: AppTab?) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        switch route {
        case let .tool(tool):
            components.host = "tool"
            components.path = "/\(tool.rawValue)"
            if let tab, tab != .tools {
                components.queryItems = [URLQueryItem(name: "tab", value: tab.rawValue)]
            }
        case let .session(id):
            components.host = "session"
            components.path = "/\(id.uuidString)"
            if let tab, tab != .journal {
                components.queryItems = [URLQueryItem(name: "tab", value: tab.rawValue)]
            }
        case let .insight(insight):
            components.host = "insight"
            components.path = "/\(insight.rawValue)"
            if let tab, tab != .insights {
                components.queryItems = [URLQueryItem(name: "tab", value: tab.rawValue)]
            }
        case let .substance(name, brand):
            components.host = "substance"
            components.path = "/\(name)"
            var items: [URLQueryItem] = []
            if let brand { items.append(URLQueryItem(name: "brand", value: brand)) }
            if let tab, tab != .library { items.append(URLQueryItem(name: "tab", value: tab.rawValue)) }
            if !items.isEmpty { components.queryItems = items }
        case let .substanceData(name, section):
            components.host = "substance"
            components.path = "/\(name)/data/\(section.rawValue)"
            if let tab, tab != .library {
                components.queryItems = [URLQueryItem(name: "tab", value: tab.rawValue)]
            }
        // Explicit non-encodable list (matching the sheet encoder below), so
        // adding a PushRoute case forces a deliberate decision here instead of
        // silently falling out of deep-link coverage.
        case .entry,
             .comedownGuide,
             .timeline,
             .libraryCategory,
             .libraryTag,
             .libraryFavorites,
             .libraryCustom,
             .libraryUnits,
             .libraryColors,
             .dataStorage,
             .drugClass,
             .drugClassGroup,
             .insightGroup,
             .myMeds,
             .medDetail,
             .inventoryItem:
            return nil
        }
        return components.url
    }

    private static func encode(sheet: SheetRoute, tab: AppTab?) -> URL? {
        var components = URLComponents()
        components.scheme = scheme

        switch sheet {
        case let .quickLog(routine, prefillSubstance, prefillDose, prefillRoute):
            components.host = "quicklog"
            var items: [URLQueryItem] = []
            if let routine {
                items.append(URLQueryItem(name: "routine", value: routine))
            }
            if let prefillSubstance {
                items.append(URLQueryItem(name: "substance", value: prefillSubstance))
            }
            if let amount = prefillDose?.amount {
                items.append(URLQueryItem(name: "amount", value: amountParameter(for: amount)))
            }
            if let unit = prefillDose?.unit {
                items.append(URLQueryItem(name: "unit", value: unit))
            }
            if let prefillRoute {
                items.append(URLQueryItem(name: "route", value: prefillRoute.rawValue))
            }
            if let time = prefillDose?.time {
                items.append(URLQueryItem(name: "time", value: timeParameter(for: time)))
            }
            if let meal = prefillDose?.meal {
                items.append(URLQueryItem(name: "meal", value: meal.rawValue))
            }
            if let note = prefillDose?.note {
                items.append(URLQueryItem(name: "notes", value: note))
            }
            if let tags = prefillDose?.tags, !tags.isEmpty {
                items.append(URLQueryItem(name: "tags", value: tags.joined(separator: ",")))
            }
            if let product = prefillDose?.productName {
                items.append(URLQueryItem(name: "product", value: product))
            }
            if !items.isEmpty {
                components.queryItems = items
            }

        case .settings:
            components.host = "settings"

        case .profiles:
            components.host = "profiles"

        case .skins:
            components.host = "skins"

        case .help:
            components.host = "help"

        case .sessionDetail:
            components.host = "day"

        case let .sessionNoteEditor(sessionID, noteID, checkIn, _):
            // Only a new note has a URL form (an existing note's id is not
            // addressable from outside the app).
            guard noteID == nil else { return nil }
            components.host = "session"
            components.path = "/\(sessionID.uuidString)"
            components.queryItems = [URLQueryItem(name: "note", value: checkIn ? "checkIn" : "new")]

        case let .entryDetail(timestamp, id):
            components.host = "entry"
            components.path = "/\(timestamp.timeIntervalSince1970)"
            if let id {
                components.queryItems = [URLQueryItem(name: "id", value: id.uuidString)]
            }

        case let .dailyDoseLog(category):
            components.host = "meds"
            components.path = "/\(category)"

        case let .inventoryItemForm(id, prefillSubstance, prefillSalt, prefill):
            if prefillSubstance != nil || prefillSalt != nil || prefill != nil {
                return nil
            }
            components.host = "inventory"
            if let id {
                components.path = "/\(id.uuidString)"
            }

        case .onboarding,
             .dailyDoseSettings,
             .personalizeSubstance,
             .timeAdjust,
             .sourcePriority,
             .spreadsheetImport,
             .psyLogImport,
             .doseSources,
             .advancedSearch,
             .inventoryItemEdit,
             .checkInSchedule:
            return nil
        }

        // Preserve the tab if it isn't the default (.journal) so the encoded
        // URL round-trips through decode.
        if let tab, tab != .journal {
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: "tab", value: tab.rawValue))
            components.queryItems = items
        }

        return components.url
    }
}

/// A `kagerou.glass/piru/…` link from a dose.wiki article, decoded but not yet
/// resolved: `slug` is the article's slug, which names a substance only
/// through the catalog's `dosewiki_slug` column.
nonisolated struct DosewikiLink: Hashable {
    enum Action: Hashable {
        /// `/piru/log`: the "Log in Piru" pill — Quick Log with the substance staged.
        case log
        /// `/piru/open`: the header chip — the substance's page.
        case open
    }

    var action: Action
    var slug: String?
    var route: RouteOfAdministration?

    /// The navigator outcome once the slug has resolved to `substanceName`
    /// (`nil` when it named nothing in the catalog). A log link still opens
    /// Quick Log without a substance, since the reader came to log; an open
    /// link with no substance to show changes nothing.
    func outcome(substanceName: String?) -> DeepLinkOutcome? {
        switch action {
        case .log:
            DeepLinkOutcome(sheet: .quickLog(
                routine: nil,
                prefillSubstance: substanceName,
                prefillRoute: substanceName == nil ? nil : route,
            ))
        case .open:
            substanceName.map { DeepLinkOutcome(tab: .library, path: [.substance(name: $0)]) }
        }
    }
}

private nonisolated extension String? {
    /// The value with surrounding whitespace removed, or `nil` when nothing is
    /// left: a link's `notes=` or `unit=` with no text names no field.
    var nonBlank: String? {
        guard let trimmed = self?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
