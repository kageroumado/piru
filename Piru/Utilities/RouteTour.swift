#if DEBUG
    import os
    import SwiftData
    import SwiftUI

    /// Walks a list of deep links in one session, for profiling navigation on the
    /// simulator: `-piruRouteTour "piru://journal,piru://tool/tolerance,…"`, with
    /// `-piruRouteDwell <seconds>` (default 4) on each screen and
    /// `-piruRouteLoops <n>` (default 1) passes over the list. Every step returns
    /// to a clean navigator first, so each link opens the way a cold tap would,
    /// and is bracketed by a `RouteTour` signpost interval and a log line naming
    /// the link, so a trace or a sample can be cut per destination.
    /// `piru://session/latest` stands for the newest session.
    struct RouteTour {
        let urls: [URL]
        let dwell: Duration
        let loops: Int

        private static let signposter = OSSignposter(logger: .routeTour)

        init?(arguments: [String]) {
            guard let i = arguments.firstIndex(of: "-piruRouteTour"), arguments.indices.contains(i + 1) else { return nil }
            urls = arguments[i + 1].split(separator: ",").compactMap { URL(string: String($0)) }
            guard !urls.isEmpty else { return nil }
            dwell = .seconds(Self.number(after: "-piruRouteDwell", in: arguments) ?? 4)
            loops = max(1, Int(Self.number(after: "-piruRouteLoops", in: arguments) ?? 1))
        }

        private static func number(after flag: String, in arguments: [String]) -> Double? {
            guard let i = arguments.firstIndex(of: flag), arguments.indices.contains(i + 1) else { return nil }
            return Double(arguments[i + 1])
        }

        func run(navigator: AppNavigator, open: (URL) -> Void) async {
            // Let the launch passes settle, so the first step measures the
            // link rather than the launch.
            try? await Task.sleep(for: dwell)
            for loop in 1 ... loops {
                for url in urls {
                    navigator.dismissAll()
                    for tab in AppTab.allCases {
                        navigator.popToRoot(in: tab)
                    }
                    try? await Task.sleep(for: .milliseconds(600))
                    let state = Self.signposter.beginInterval("step", "\(url.absoluteString, privacy: .public)")
                    Logger.routeTour.notice("RouteTour start loop=\(loop) \(url.absoluteString, privacy: .public) t=\(Date.now.timeIntervalSince1970)")
                    open(url)
                    try? await Task.sleep(for: dwell)
                    Self.signposter.endInterval("step", state)
                    Logger.routeTour.notice("RouteTour end loop=\(loop) \(url.absoluteString, privacy: .public) t=\(Date.now.timeIntervalSince1970)")
                }
            }
            navigator.dismissAll()
            Logger.routeTour.notice("RouteTour done t=\(Date.now.timeIntervalSince1970)")
        }
    }

    extension URL {
        /// `piru://session/latest` → the newest session's link; any other URL
        /// unchanged.
        func resolvingLatestSession(in context: ModelContext) -> URL {
            guard scheme == DeepLink.scheme, host == "session", lastPathComponent == "latest" else { return self }
            var descriptor = FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
            descriptor.fetchLimit = 1
            guard let id = try? context.fetch(descriptor).first?.id else { return self }
            return URL(string: "piru://session/\(id.uuidString)") ?? self
        }
    }
#endif
