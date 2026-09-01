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
/// **Tab selection** — `piru://<tab>` selects the tab and clears any modal:
/// `piru://journal`, `piru://library`, `piru://tools`, `piru://insights`,
/// `piru://search`.
///
/// **App-level sheets** (open over the current tab):
/// - `piru://quicklog[?routine=<name>][?substance=<name>]` → present
///   `.quickLog`, optionally pre-staging a routine's items (routine-reminder
///   notification taps) or one substance with its dose editor open (the "Log"
///   button on a substance's detail screen)
/// - `piru://settings` → present `.settings`
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
/// **Push destinations** (replace the target tab's stack):
/// - `piru://tool/<name>` → Tools tab, push that tool full-screen. `<name>`
///   matches a `Tool` raw value case-insensitively (`tolerance`, `ceiling`,
///   `benzoEquivalence`, `pharma`, `calculator`, `volumetric`, `recovery`,
///   `interactions`, `inventory`).
/// - `piru://session/<uuid>` → Journal tab, push that session's detail.
/// - `piru://substance/<name>` → Library tab, push that substance's detail
///   (percent-encode spaces, e.g. `piru://substance/Psilocybin%20mushrooms`).
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
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })

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
                sheet: .quickLog(routine: query["routine"], prefillSubstance: query["substance"]),
            )

        case "settings":
            return DeepLinkOutcome(tab: overrideTab, sheet: .settings)

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
            // `piru://session/<uuid>` pushes a session detail onto the Journal tab.
            guard let idString = pathSegments.first,
                  let id = UUID(uuidString: idString) else { return nil }
            return DeepLinkOutcome(
                tab: overrideTab ?? .journal,
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
                ?? .substance(name: name)
            return DeepLinkOutcome(
                tab: overrideTab ?? .library,
                path: [route],
            )

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
    /// `.colorPicker`), encoding returns `nil`.
    static func encode(_ snapshot: NavigatorSnapshot) -> URL? {
        if snapshot.sheetStack.isEmpty {
            // No modal: encode the top of the selected tab's push stack if it
            // has a canonical URL form (tool / session), otherwise just the tab.
            if let top = snapshot.paths[snapshot.selectedTab]?.last,
               let url = encode(push: top, tab: snapshot.selectedTab) {
                return url
            }
            return URL(string: "\(scheme)://\(snapshot.selectedTab.rawValue)")
        }

        guard let top = snapshot.sheetStack.last else { return nil }
        return encode(sheet: top, tab: snapshot.selectedTab)
    }

    /// Canonical URL for a push route, or `nil` for app-internal pushes that
    /// aren't deep-linkable. Only tools and sessions round-trip.
    private static func encode(push route: PushRoute, tab: AppTab) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        switch route {
        case let .tool(tool):
            components.host = "tool"
            components.path = "/\(tool.rawValue)"
            if tab != .tools {
                components.queryItems = [URLQueryItem(name: "tab", value: tab.rawValue)]
            }
        case let .session(id):
            components.host = "session"
            components.path = "/\(id.uuidString)"
            if tab != .journal {
                components.queryItems = [URLQueryItem(name: "tab", value: tab.rawValue)]
            }
        case let .insight(insight):
            components.host = "insight"
            components.path = "/\(insight.rawValue)"
            if tab != .insights {
                components.queryItems = [URLQueryItem(name: "tab", value: tab.rawValue)]
            }
        case let .substance(name):
            components.host = "substance"
            components.path = "/\(name)"
            if tab != .library {
                components.queryItems = [URLQueryItem(name: "tab", value: tab.rawValue)]
            }
        case let .substanceData(name, section):
            components.host = "substance"
            components.path = "/\(name)/data/\(section.rawValue)"
            if tab != .library {
                components.queryItems = [URLQueryItem(name: "tab", value: tab.rawValue)]
            }
        // Explicit non-encodable list (matching the sheet encoder below), so
        // adding a PushRoute case forces a deliberate decision here instead of
        // silently falling out of deep-link coverage.
        case .entry,
             .rampDown,
             .comedownGuide,
             .timeline,
             .libraryCategory,
             .libraryTag,
             .libraryFavorites,
             .libraryCustom,
             .libraryColors,
             .dataStorage,
             .drugClass,
             .drugClassGroup,
             .insightGroup,
             .myMeds,
             .medDetail:
            return nil
        }
        return components.url
    }

    private static func encode(sheet: SheetRoute, tab: AppTab) -> URL? {
        var components = URLComponents()
        components.scheme = scheme

        switch sheet {
        case let .quickLog(routine, prefillSubstance):
            components.host = "quicklog"
            var items: [URLQueryItem] = []
            if let routine {
                items.append(URLQueryItem(name: "routine", value: routine))
            }
            if let prefillSubstance {
                items.append(URLQueryItem(name: "substance", value: prefillSubstance))
            }
            if !items.isEmpty {
                components.queryItems = items
            }

        case .settings:
            components.host = "settings"

        case .help:
            components.host = "help"

        case .sessionDetail:
            components.host = "day"

        case let .entryDetail(timestamp, id):
            components.host = "entry"
            components.path = "/\(timestamp.timeIntervalSince1970)"
            if let id {
                components.queryItems = [URLQueryItem(name: "id", value: id.uuidString)]
            }

        case let .dailyDoseLog(category):
            components.host = "meds"
            components.path = "/\(category)"

        case let .inventoryItemForm(id, prefillSubstance, prefillSalt):
            if prefillSubstance != nil || prefillSalt != nil {
                return nil
            }
            components.host = "inventory"
            if let id {
                components.path = "/\(id.uuidString)"
            }

        case .onboarding,
             .sessionNoteEditor,
             .dailyDoseSettings,
             .personalizeSubstance,
             .colorPicker,
             .timeAdjust,
             .sourcePriority,
             .doseSources,
             .advancedSearch,
             .inventoryItemEdit:
            return nil
        }

        // Preserve the tab if it isn't the default (.journal) so the encoded
        // URL round-trips through decode.
        if tab != .journal {
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: "tab", value: tab.rawValue))
            components.queryItems = items
        }

        return components.url
    }
}
