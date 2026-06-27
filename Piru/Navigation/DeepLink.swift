import Foundation

/// Bidirectional URL ↔ navigator state codec.
///
/// ## URL Scheme
///
/// All deep links use the `piru://` scheme. The URL `host` selects the kind
/// of destination; path components and query items carry parameters. Decoding
/// an unrecognised URL returns `nil` so callers can fall back to default
/// behaviour.
///
/// **Tab selection** — `piru://<tab>` selects the tab and clears any modal:
/// `piru://journal`, `piru://library`, `piru://tools`, `piru://insights`,
/// `piru://search`.
///
/// **App-level sheets** (open over the current tab):
/// - `piru://quicklog[?routine=<name>]` → present `.quickLog`, optionally
///   pre-staging a routine's items (routine-reminder notification taps)
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
            return DeepLinkOutcome(tab: overrideTab, sheet: .quickLog(routine: query["routine"]))

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

        case "tool":
            // `piru://tool/<rawValue>` pushes a tool onto the Tools tab.
            // Raw values are matched case-insensitively so hand-typed links
            // like `piru://tool/benzoequivalence` resolve the camelCase case.
            guard let toolRaw = pathSegments.first,
                  let tool = Tool.allCases.first(where: { $0.rawValue.lowercased() == toolRaw.lowercased() })
            else { return nil }
            return DeepLinkOutcome(
                tab: overrideTab ?? .tools,
                path: [.tool(tool)],
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
            // The name is the rest of the path (percent-decoded by URLComponents), so
            // multi-word names like `piru://substance/Psilocybin%20mushrooms` resolve.
            let name = pathSegments.joined(separator: "/")
            guard !name.isEmpty else { return nil }
            return DeepLinkOutcome(
                tab: overrideTab ?? .library,
                path: [.substance(name: name)],
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
        case let .substance(name):
            components.host = "substance"
            components.path = "/\(name)"
            if tab != .library {
                components.queryItems = [URLQueryItem(name: "tab", value: tab.rawValue)]
            }
        default:
            return nil
        }
        return components.url
    }

    private static func encode(sheet: SheetRoute, tab: AppTab) -> URL? {
        var components = URLComponents()
        components.scheme = scheme

        switch sheet {
        case let .quickLog(routine):
            components.host = "quicklog"
            if let routine {
                components.queryItems = [URLQueryItem(name: "routine", value: routine)]
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

        case .onboarding,
             .entryEdit,
             .dailyDoseSettings,
             .dailyDoseItemForm,
             .customSubstancesList,
             .customSubstanceForm,
             .personalizeSubstance,
             .colorPicker,
             .journalFilters,
             .journalCalendar,
             .timeAdjust,
             .dayShare,
             .sourcePriority,
             .advancedSearch,
             .inventoryItemForm,
             .inventoryItemEdit:
            // Not represented as deep links — these are app-internal flows.
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
