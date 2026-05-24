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
/// - `piru://quicklog` → present `.quickLog`
/// - `piru://settings` → present `.settings`
/// - `piru://help` → present `.help`
///
/// **Entry-flow sheets** (select journal, then present):
/// - `piru://day` → present `.sessionDetail`
/// - `piru://entry/<unix-timestamp>` → present `.entryDetail(timestamp:)`
/// - `piru://entryform?substance=&route=&unit=` → present `.entryForm`
///   with optional prefill (omit the query for a blank form)
///
/// **Medication sheets**:
/// - `piru://meds/<category>` → present `.dailyDoseLog(category:)`
///
/// The encoder always emits a single URL describing the *top* of the modal
/// stack (or just the tab when no modal is presented). Multi-level stacks
/// aren't yet representable as a single URL — that's by design, since deep
/// links open a specific destination, not arbitrary nav state.
nonisolated enum DeepLink {

    static let scheme = "piru"

    // MARK: - Decode

    /// Parse a `piru://` URL into a navigator snapshot. Returns `nil` for
    /// unsupported schemes or unrecognised hosts.
    static func decode(_ url: URL) -> NavigatorSnapshot? {
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

        // Tab-only deep link.
        if let tab = AppTab(rawValue: host), pathSegments.isEmpty {
            return NavigatorSnapshot(selectedTab: tab)
        }

        // Sheet routes are presented over the journal tab by default. Callers
        // can override the tab by including it in the query (`?tab=library`).
        let baseTab = query["tab"].flatMap(AppTab.init(rawValue:)) ?? .journal

        switch host {
        case "quicklog":
            return NavigatorSnapshot(selectedTab: baseTab, sheetStack: [.quickLog])

        case "settings":
            return NavigatorSnapshot(selectedTab: baseTab, sheetStack: [.settings])

        case "help":
            return NavigatorSnapshot(selectedTab: baseTab, sheetStack: [.help])

        case "day":
            return NavigatorSnapshot(selectedTab: .journal, sheetStack: [.sessionDetail])

        case "entry":
            guard let tsString = pathSegments.first,
                  let ts = TimeInterval(tsString) else { return nil }
            let timestamp = Date(timeIntervalSince1970: ts)
            return NavigatorSnapshot(
                selectedTab: .journal,
                sheetStack: [.entryDetail(timestamp: timestamp)]
            )

        case "entryform":
            let prefill: EntryPrefillPayload? = {
                guard
                    let substance = query["substance"],
                    let routeRaw = query["route"],
                    let route = RouteOfAdministration(rawValue: routeRaw),
                    let unit = query["unit"]
                else { return nil }
                return EntryPrefillPayload(substance: substance, route: route, unit: unit)
            }()
            return NavigatorSnapshot(
                selectedTab: .journal,
                sheetStack: [.entryForm(prefill: prefill)]
            )

        case "meds":
            guard let category = pathSegments.first else { return nil }
            return NavigatorSnapshot(
                selectedTab: .journal,
                sheetStack: [.dailyDoseLog(category: category)]
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
            return URL(string: "\(scheme)://\(snapshot.selectedTab.rawValue)")
        }

        guard let top = snapshot.sheetStack.last else { return nil }
        return encode(sheet: top, tab: snapshot.selectedTab)
    }

    private static func encode(sheet: SheetRoute, tab: AppTab) -> URL? {
        var components = URLComponents()
        components.scheme = scheme

        switch sheet {
        case .quickLog:
            components.host = "quicklog"

        case .settings:
            components.host = "settings"

        case .help:
            components.host = "help"

        case .sessionDetail:
            components.host = "day"

        case .entryDetail(let timestamp):
            components.host = "entry"
            components.path = "/\(timestamp.timeIntervalSince1970)"

        case .entryForm(let prefill):
            components.host = "entryform"
            if let prefill {
                components.queryItems = [
                    URLQueryItem(name: "substance", value: prefill.substance),
                    URLQueryItem(name: "route", value: prefill.route.rawValue),
                    URLQueryItem(name: "unit", value: prefill.unit),
                ]
            }

        case .dailyDoseLog(let category):
            components.host = "meds"
            components.path = "/\(category)"

        case .onboarding,
             .entryEdit,
             .dailyDoseSettings,
             .dailyDoseItemForm,
             .customSubstancesList,
             .customSubstanceForm,
             .colorPicker,
             .journalFilters,
             .journalCalendar,
             .timeAdjust,
             .dayShare:
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
