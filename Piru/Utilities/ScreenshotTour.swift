#if DEBUG
    import SwiftData
    import SwiftUI
    #if canImport(UIKit)
        import UIKit
    #endif

    /// Walks the app through every screen worth a screenshot and has the host
    /// capture each one — the in-process half of `pipeline/screenshots.py`.
    ///
    /// The tour is enabled by `-piruScreenshots <dir>` (an absolute path on the
    /// host, which a simulator app can write to). For each screen it navigates
    /// through `AppNavigator`, waits for the screen to settle, and then writes
    /// `<dir>/.tour/request.json` naming the file it wants. The host takes the
    /// screenshot with `simctl io screenshot` — so the status-bar override and
    /// every real pixel are in the picture — and answers with `<dir>/.tour/ack`.
    /// `<dir>/.tour/done.json` closes the run.
    ///
    /// Screens are captured in the `piru` skin first, then a subset again in
    /// every other skin the picker offers (`Skin.available`), so a skin added to
    /// the enum is in the next pass with no change here. The language is the
    /// process's own (`-AppleLanguages`), so one launch is one locale.
    ///
    /// Arguments, all optional after the first:
    /// - `-piruScreenshots <dir>` — output directory; enables the tour.
    /// - `-piruScreenshotScreens all|<name,…>` — which screens (default all).
    /// - `-piruScreenshotSkins all|none|<skin,…>` — which skins beyond `piru`.
    /// - `-piruScreenshotSkinScreens all|<name,…>` — screens per skin.
    /// - `-piruScreenshotSettle <seconds>` — wait after navigating (default 1.2).
    @MainActor
    enum ScreenshotTour {
        // MARK: - Launch arguments

        static var isRequested: Bool {
            argument(after: "-piruScreenshots") != nil
        }

        private static func argument(after flag: String) -> String? {
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
            return args[i + 1]
        }

        private static func list(after flag: String) -> [String]? {
            guard let raw = argument(after: flag) else { return nil }
            return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }

        // MARK: - Screens

        /// One screen the tour can capture. Its file is numbered by its place
        /// in ``catalog``, so a name is stable when only a subset is captured.
        struct Screen {
            let name: String
            let stage: @MainActor (Stage) async -> Void
        }

        /// Substances whose detail screens are captured — three classes a
        /// visitor recognizes: an empathogen, a dissociative, a prescription.
        static let substances = ["MDMA", "Ketamine", "Methylphenidate"]

        /// Every screen, in capture order. Names are the file names.
        static let catalog: [Screen] = [
            Screen(name: "journal") { stage in
                stage.grouping(.timeline)
                stage.tab(.journal)
            },
            Screen(name: "journal-days") { stage in
                stage.grouping(.byDay)
                stage.tab(.journal)
            },
            Screen(name: "timeline") { stage in
                stage.grouping(.timeline)
                stage.push(.timeline, in: .journal)
            },
            Screen(name: "session") { stage in
                guard let id = stage.sessionID(titled: "Lake evening") else { return }
                stage.push(.session(id: id), in: .journal)
            },
            Screen(name: "entry") { stage in
                guard let entry = stage.newestEntry(of: "Methylphenidate") else { return }
                stage.tab(.journal)
                stage.present(.entryDetail(timestamp: entry.timestamp, id: entry.id))
            },
            Screen(name: "quicklog") { stage in
                stage.tab(.journal)
                stage.present(.quickLog(routine: MedTimeGroup.morning.slug))
            },
            Screen(name: "quicklog-substance") { stage in
                stage.tab(.journal)
                stage.present(.quickLog(routine: nil, prefillSubstance: "Caffeine"))
            },
            Screen(name: "library") { stage in
                stage.tab(.library)
            },
            Screen(name: "search") { stage in
                stage.tab(.search)
            },
            Screen(name: "search-results") { stage in
                // Entering Search from Journal seeds the Journal scope; from
                // Library it searches the catalog.
                stage.tab(.library)
                stage.tab(.search)
                await stage.search("ket")
            },
            Screen(name: "substance-mdma") { stage in
                stage.push(.substance(name: "MDMA"), in: .library)
            },
            Screen(name: "substance-mdma-pharmacology") { stage in
                stage.push(.substanceData(name: "MDMA", section: .pharmacology), in: .library)
            },
            Screen(name: "substance-ketamine") { stage in
                stage.push(.substance(name: "Ketamine"), in: .library)
            },
            Screen(name: "substance-ketamine-chemistry") { stage in
                stage.push(.substanceData(name: "Ketamine", section: .chemistry), in: .library)
            },
            Screen(name: "substance-methylphenidate") { stage in
                stage.push(.substance(name: "Methylphenidate"), in: .library)
            },
            Screen(name: "tools") { stage in
                stage.tab(.tools)
            },
            Screen(name: "my-meds") { stage in
                stage.push(.myMeds, in: .tools)
            },
            Screen(name: "inventory") { stage in
                stage.push(.tool(.inventory), in: .tools)
            },
            Screen(name: "interactions") { stage in
                Self.stagedInteraction = ["Alcohol", "Lorazepam"]
                stage.push(.tool(.interactions), in: .tools)
            },
            Screen(name: "half-life") { stage in
                stage.push(.tool(.calculator), in: .tools)
            },
            Screen(name: "insights") { stage in
                stage.tab(.insights)
            },
            Screen(name: "stats") { stage in
                stage.push(.insight(.usage), in: .insights)
            },
            Screen(name: "adherence") { stage in
                stage.push(.insight(.adherence), in: .insights)
            },
            Screen(name: "modeled-levels") { stage in
                stage.push(.insightGroup(.inYourBody), in: .insights)
            },
            Screen(name: "tolerance") { stage in
                stage.push(.insight(.tolerance), in: .insights)
            },
            Screen(name: "receptor-load") { stage in
                stage.push(.insight(.receptorLoad), in: .insights)
            },
            Screen(name: "skins") { stage in
                stage.tab(.journal)
                stage.present(.skins)
            },
            Screen(name: "settings") { stage in
                stage.tab(.journal)
                stage.present(.settings)
            },
        ]

        /// The screens captured again in every skin: the ones where a skin
        /// shows — the strip, the sheets, the cards.
        static let skinScreenNames = [
            "journal", "timeline", "quicklog", "library", "substance-mdma", "tools", "insights", "stats",
        ]

        // MARK: - Seams

        /// Substances the interaction checker adds on its next appearance;
        /// `.tool(.interactions)` carries no payload, so the tour hands them
        /// over here. Read once by `takeStagedInteraction()`.
        private static var stagedInteraction: [String] = []

        static func takeStagedInteraction() -> [String] {
            defer { stagedInteraction = [] }
            return stagedInteraction
        }

        // MARK: - Run

        /// What the tour writes for one capture.
        private struct Request: Codable {
            let file: String
            let screen: String
            let skin: String
            let index: Int
            let total: Int
        }

        private struct Report: Codable {
            var captured: [String] = []
            var skipped: [String] = []
            var failed: [String] = []
            var seconds: Double = 0
        }

        /// Runs the whole tour. Call once the store is seeded and the substance
        /// batch cache is warm; returns when `done.json` is on disk.
        static func run(container: ModelContainer) async {
            guard let root = argument(after: "-piruScreenshots") else { return }
            let started = Date.now
            print("ScreenshotTour: now is \(DebugClock.now.formatted(date: .abbreviated, time: .shortened))\(DebugClock.override == nil ? " (wall clock)" : " (pinned)")")
            let settle = argument(after: "-piruScreenshotSettle").flatMap(Double.init) ?? 1.2
            let mainScreens = select(list(after: "-piruScreenshotScreens"), from: catalog)
            let skinScreens = select(list(after: "-piruScreenshotSkinScreens") ?? skinScreenNames, from: catalog)
            let skins = selectSkins(list(after: "-piruScreenshotSkins"))

            let tourDirectory = URL(filePath: root).appending(path: ".tour")
            try? FileManager.default.createDirectory(at: tourDirectory, withIntermediateDirectories: true)

            // No onboarding cover, no launch sheet on top of a capture.
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            try? await Task.sleep(for: .seconds(1.5))
            await SubstanceStore.shared.ensureAllLoaded()
            await waitForOwnership()

            let stage = Stage(context: container.mainContext, settle: settle)
            let skinStore = SkinStore.shared
            let originalSkin = skinStore.chosen
            var report = Report()
            let total = mainScreens.count + skins.count * skinScreens.count
            var index = 0

            @MainActor
            func capture(_ screen: Screen, skin: Skin) async {
                index += 1
                let number = catalog.firstIndex { $0.name == screen.name }.map { $0 + 1 } ?? 0
                let stem = String(format: "%02d-%@", number, screen.name)
                let file = skin == .piru ? "\(stem).png" : "skins/\(skin.rawValue)/\(stem)-\(skin.rawValue).png"
                await stage.reset()
                await screen.stage(stage)
                try? await Task.sleep(for: .seconds(settle))
                let request = Request(file: file, screen: screen.name, skin: skin.rawValue, index: index, total: total)
                print("ScreenshotTour: [\(index)/\(total)] \(file)")
                switch await handshake(request, in: tourDirectory) {
                case .captured: report.captured.append(file)
                case .timedOut: report.failed.append(file)
                }
            }

            @MainActor
            func wear(_ skin: Skin) async {
                guard skinStore.chosen != skin else { return }
                skinStore.setSkin(skin)
                // The root re-creates itself on a skin change.
                try? await Task.sleep(for: .seconds(max(settle, 1.5)))
            }

            await wear(.piru)
            for screen in mainScreens {
                await capture(screen, skin: .piru)
            }
            for skin in skins {
                await wear(skin)
                guard skinStore.chosen == skin else {
                    report.skipped.append(contentsOf: skinScreens.map { "skins/\(skin.rawValue)/\($0.name)" })
                    print("ScreenshotTour: cannot wear \(skin.rawValue) — not owned; pass -piruOwnEverything")
                    continue
                }
                for screen in skinScreens {
                    await capture(screen, skin: skin)
                }
            }
            await wear(originalSkin)
            await stage.reset()

            report.seconds = Date.now.timeIntervalSince(started)
            write(report, to: tourDirectory.appending(path: "done.json"))
            print("ScreenshotTour: done — \(report.captured.count) captured, \(report.failed.count) failed, \(report.skipped.count) skipped")
        }

        private static func select(_ names: [String]?, from catalog: [Screen]) -> [Screen] {
            guard let names, names != ["all"] else { return catalog }
            let unknown = names.filter { name in !catalog.contains { $0.name == name } }
            if !unknown.isEmpty {
                print("ScreenshotTour: unknown screens \(unknown) — known: \(catalog.map(\.name).joined(separator: ", "))")
            }
            return catalog.filter { names.contains($0.name) }
        }

        private static func selectSkins(_ names: [String]?) -> [Skin] {
            let offered = Skin.available.filter { $0 != .piru }
            guard let names, names != ["all"] else { return offered }
            if names == ["none"] { return [] }
            let unknown = names.filter { name in !offered.contains { $0.rawValue == name } }
            if !unknown.isEmpty {
                print("ScreenshotTour: unknown skins \(unknown) — known: \(offered.map(\.rawValue).joined(separator: ", "))")
            }
            return offered.filter { names.contains($0.rawValue) }
        }

        /// `-piruOwnEverything` lands through `SkinShop.refreshOwned()`, which
        /// is async; a paid skin worn before it lands is refused.
        private static func waitForOwnership() async {
            guard ProcessInfo.processInfo.arguments.contains("-piruOwnEverything") else { return }
            for _ in 0 ..< 100 where !SkinShop.shared.ownsEverything {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        // MARK: - Handshake

        private enum Outcome { case captured, timedOut }

        /// Writes the request, waits for the host's ack (30 s), then clears both.
        private static func handshake(_ request: Request, in directory: URL) async -> Outcome {
            let requestURL = directory.appending(path: "request.json")
            let ackURL = directory.appending(path: "ack")
            write(request, to: requestURL)
            defer {
                try? FileManager.default.removeItem(at: ackURL)
                try? FileManager.default.removeItem(at: requestURL)
            }
            for _ in 0 ..< 600 {
                if FileManager.default.fileExists(atPath: ackURL.path) { return .captured }
                try? await Task.sleep(for: .milliseconds(50))
            }
            print("ScreenshotTour: no ack for \(request.file) — is pipeline/screenshots.py running?")
            return .timedOut
        }

        private static func write(_ value: some Encodable, to url: URL) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(value) else { return }
            try? data.write(to: url, options: .atomic)
        }

        // MARK: - Stage

        /// The moves a screen is staged with.
        @MainActor
        struct Stage {
            let context: ModelContext
            let settle: Double
            private let navigator = AppNavigator.shared
            private let groupDefaults = UserDefaults(suiteName: "group.dev.yumeji.piru")

            init(context: ModelContext, settle: Double) {
                self.context = context
                self.settle = settle
            }

            /// Every sheet down, every stack popped to root.
            func reset() async {
                let hadSheet = !navigator.sheetStack.isEmpty
                navigator.dismissAll()
                for tab in AppTab.allCases {
                    navigator.setPath([], in: tab)
                }
                try? await Task.sleep(for: .seconds(hadSheet ? 0.6 : 0.2))
            }

            func tab(_ tab: AppTab) {
                navigator.select(tab)
            }

            func push(_ route: PushRoute, in tab: AppTab) {
                navigator.select(tab)
                navigator.setPath([route], in: tab)
            }

            func present(_ sheet: SheetRoute) {
                navigator.present(sheet)
            }

            func grouping(_ grouping: JournalGrouping) {
                groupDefaults?.set(grouping.rawValue, forKey: "journalGrouping")
            }

            func sessionID(titled title: String) -> UUID? {
                var descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.title == title })
                descriptor.fetchLimit = 1
                return try? context.fetch(descriptor).first?.id
            }

            func newestEntry(of substance: String) -> DoseEntry? {
                var descriptor = FetchDescriptor<DoseEntry>(
                    predicate: #Predicate { $0.substance == substance },
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)],
                )
                descriptor.fetchLimit = 1
                return try? context.fetch(descriptor).first
            }

            /// Focuses the Search tab's field and types `query` through UIKit:
            /// the field is a `UISearchTextField` under SwiftUI's `.searchable`,
            /// and its `editingChanged` action is what feeds the text binding.
            func search(_ query: String) async {
                #if canImport(UIKit)
                    try? await Task.sleep(for: .seconds(0.6))
                    guard let field = Self.searchField() else {
                        print("ScreenshotTour: no search field on screen")
                        return
                    }
                    field.becomeFirstResponder()
                    try? await Task.sleep(for: .seconds(0.4))
                    field.text = query
                    field.sendActions(for: .editingChanged)
                #endif
            }

            #if canImport(UIKit)
                private static func searchField() -> UISearchTextField? {
                    for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                        for window in scene.windows {
                            if let field = searchField(in: window) { return field }
                        }
                    }
                    return nil
                }

                private static func searchField(in view: UIView) -> UISearchTextField? {
                    if let field = view as? UISearchTextField { return field }
                    for subview in view.subviews {
                        if let field = searchField(in: subview) { return field }
                    }
                    return nil
                }
            #endif
        }
    }
#endif
