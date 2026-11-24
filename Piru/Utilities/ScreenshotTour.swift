#if DEBUG
    import SwiftData
    import SwiftUI
    #if canImport(UIKit)
        import UIKit
    #endif
    #if os(macOS)
        import AppKit
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
    /// A sandboxed Mac app can write to no directory the host can read, so on
    /// macOS the host passes `-piruScreenshotHost <url>` instead: each request
    /// is POSTed to `<url>/request` and the response is the ack; the report goes
    /// to `<url>/done`. The window is sized to `-piruScreenshotWindow <w>x<h>`
    /// (default 1280x820) so every capture has one frame. Either way the tour
    /// runs on its own store (`StoreRecovery.activeStoreName`).
    ///
    /// Screens are captured in the `piru` skin first, then a subset again in
    /// every other skin the picker offers (`Skin.available`), so a skin added to
    /// the enum is in the next pass with no change here. The language is the
    /// process's own (`-AppleLanguages`), so one launch is one locale.
    ///
    /// Arguments, all optional after the first:
    /// - `-piruScreenshots <dir>` — output directory; enables the tour.
    /// - `-piruScreenshotScreens all|charts|charts-static|<name,…>` — which
    ///   screens (default all). `charts` is every chart screen that draws the
    ///   journal, to run once per persona; `charts-static` the chart screens
    ///   that draw only the substance catalog, to run once.
    /// - `-piruScreenshotSkins all|none|<skin,…>` — which skins beyond `piru`.
    /// - `-piruScreenshotSkinScreens all|<name,…>` — screens per skin.
    /// - `-piruScreenshotSettle <seconds>` — wait after navigating (default 1.2).
    /// - `-piruWallpapers` — the root shows only the skin backdrop (no chrome,
    ///   no status bar) and the tour captures one frame per skin, as
    ///   `<skin>.png`, so each skin's scene can be used as a wallpaper.
    @MainActor
    enum ScreenshotTour {
        // MARK: - Launch arguments

        static var isRequested: Bool {
            argument(after: "-piruScreenshots") != nil
        }

        static var wantsWallpapers: Bool {
            ProcessInfo.processInfo.arguments.contains("-piruWallpapers")
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
            /// The persona whose seed this screen shows; `nil` for a screen every
            /// persona fills. A pass under another persona leaves it out.
            var persona: String?
            /// The named set this screen belongs to, selectable as a whole.
            var set: ScreenSet?
            /// The control state the screen is staged in, in words: the range,
            /// filter or mode selected and how far it is scrolled.
            var state: String?
            let stage: @MainActor (Stage) async -> Void
        }

        /// Screens selectable by one name in `-piruScreenshotScreens`.
        enum ScreenSet: String {
            /// Chart screens whose content comes from the journal: one pass per persona.
            case charts
            /// Chart screens drawn from the substance catalog alone: one pass.
            case chartsStatic = "charts-static"
        }

        /// Every screen, in capture order. Names are the file names.
        static let catalog: [Screen] = screens + chartScreens

        private static let screens: [Screen] = [
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
            // New screens go last: a file's number is its place in this list,
            // so an insertion renumbers every capture after it.
            Screen(name: "quicklog-concerta") { stage in
                Self.stagedDockSearch = "Concerta"
                stage.tab(.journal)
                stage.present(.quickLog(routine: nil))
            },
            // The sheet forms of My Meds, a med, and a stocked item: on iPad
            // each is a portrait panel, where the pushed screens fill a
            // landscape-wide canvas.
            Screen(name: "my-meds-sheet") { stage in
                stage.tab(.tools)
                stage.present(.dailyDoseSettings)
            },
            Screen(name: "med-concerta") { stage in
                guard let med = stage.med(product: "Concerta") else { return }
                stage.tab(.tools)
                stage.present(.dailyDoseSettings)
                await stage.settleSheet()
                stage.pushInSheet(.medDetail(identityKey: med.identityKey, sortOrder: med.sortOrder))
            },
            Screen(name: "inventory-concerta") { stage in
                guard let item = stage.inventoryItem(of: "Methylphenidate") else { return }
                stage.tab(.tools)
                stage.present(.inventoryItemEdit(id: item.id))
            },
            // Empty under the default `week` persona; capture it with
            // `pipeline/screenshots.py --persona transfemHRT` to see the curves.
            Screen(name: "hormone-levels") { stage in
                stage.push(.insight(.hormoneLevels), in: .insights)
            },
            Screen(name: "profiles") { stage in
                stage.tab(.journal)
                stage.present(.profiles)
            },
            // `sharedNight` seeds Alice and Bob and the night the three of them
            // shared: `pipeline/screenshots.py --persona sharedNight`.
            Screen(name: "shared-session", persona: "sharedNight") { stage in
                guard let id = stage.sessionID(titled: "Kitchen disco") else { return }
                stage.push(.session(id: id), in: .journal)
            },
            Screen(name: "shared-peek", persona: "sharedNight") { stage in
                guard let session = stage.session(titled: "Kitchen disco"),
                      let experience = session.sharedExperienceID,
                      let other = ProfileDirectory.shared.profiles.first(where: { !$0.isOwner })
                else { return }
                stage.push(.session(id: session.id), in: .journal)
                stage.present(.sharedSessionPeek(experienceID: experience, profileID: other.id))
            },
            Screen(name: "add-people", persona: "sharedNight") { stage in
                guard let id = stage.sessionID(titled: "Kitchen disco") else { return }
                stage.push(.session(id: id), in: .journal)
                stage.present(.addPeople(sessionID: id))
            },
            Screen(name: "dose-sources-mdma") { stage in
                stage.push(.substance(name: "MDMA"), in: .library)
                stage.present(.doseSources(substance: "MDMA", route: .oral))
            },
        ]

        /// Every chart surface, in each state a reviewer must see: each range,
        /// filter and mode, the parts below the fold (`-pN` is N − 1 screens
        /// down), and a selected point where the chart offers one.
        private static let chartScreens: [Screen] = [
            chart("chart-journal-timeline", state: "Journal, Timeline grouping, curves off") { stage in
                stage.grouping(.timeline)
                stage.tab(.journal)
            },
            chart("chart-journal-timeline-curves", state: "Journal, Timeline grouping, Show Curves on") { stage in
                stage.grouping(.timeline)
                stage.setShared("timelinePKCurves", true)
                stage.tab(.journal)
            },
            chart("chart-journal-days", state: "Journal, Days grouping (Active Now graph when a dose is active)") { stage in
                stage.grouping(.byDay)
                stage.tab(.journal)
            },
            chart("chart-session", pages: 4, state: "the session with the most doses") { stage in
                guard let id = stage.busiestSession()?.id else { return }
                stage.push(.session(id: id), in: .journal)
            },
            chart("chart-entry", pages: 2, state: "the newest entry's detail sheet") { stage in
                guard let entry = stage.newestEntry() else { return }
                stage.tab(.journal)
                stage.present(.entryDetail(timestamp: entry.timestamp, id: entry.id))
            },
            chart("chart-insights", pages: 3, state: "Insights tab") { stage in
                stage.tab(.insights)
            },
            chart("chart-stats-7d", state: "Usage, range 7D, Common doses, all substances") { stage in
                stage.usage(range: .sevenDays)
            },
            chart("chart-stats-30d", pages: 6, state: "Usage, range 30D, Common doses, all substances") { stage in
                stage.usage(range: .thirtyDays)
            },
            chart("chart-stats-90d", state: "Usage, range 90D, Common doses, all substances") { stage in
                stage.usage(range: .ninetyDays)
            },
            chart("chart-stats-1y", state: "Usage, range 1Y, Common doses, all substances") { stage in
                stage.usage(range: .oneYear)
            },
            chart("chart-stats-all", pages: 6, state: "Usage, range All, Common doses, all substances") { stage in
                stage.usage(range: .all)
            },
            chart("chart-stats-entries", pages: 3, state: "Usage, range 30D, Measure Entries, all substances") { stage in
                stage.usage(range: .thirtyDays, metric: .entries)
            },
            chart(
                "chart-stats-filtered", pages: 3,
                state: "Usage, range 30D, Common doses, substance filter set to the two most-logged substances of the last 30 days",
            ) { stage in
                stage.usage(range: .thirtyDays, substances: Set(stage.mostLoggedSubstances(2, days: 30)))
            },
            chart("chart-stats-trend-selected", pages: 2, state: "Usage, range 30D, the day ten days ago selected on Substance trends") { stage in
                stage.select(.usageTrends, at: Calendar.current.startOfDay(for: DebugClock.now.addingTimeInterval(-10 * 86_400)))
                stage.usage(range: .thirtyDays)
            },
            chart("chart-modeled-levels", pages: 4, state: "In Your Body, range 30D, all substances") { stage in
                stage.push(.insightGroup(.inYourBody), in: .insights)
            },
            chart("chart-modeled-levels-selected", state: "In Your Body, range 30D, the point one day ago selected") { stage in
                stage.select(.modeledLevels, at: DebugClock.now.addingTimeInterval(-86_400))
                stage.push(.insightGroup(.inYourBody), in: .insights)
            },
            chart("chart-tolerance", pages: 4, state: "Modeled Tolerance, Show By mechanism, Detail Level Curious") { stage in
                stage.push(.insight(.tolerance), in: .insights)
            },
            chart("chart-tolerance-substance", pages: 3, state: "Modeled Tolerance, Show By substance, Detail Level Curious") { stage in
                stage.toleranceMode(.perSubstance)
                stage.push(.insight(.tolerance), in: .insights)
            },
            chart("chart-tolerance-casual", pages: 3, state: "Modeled Tolerance, Show By mechanism, Detail Level Casual") { stage in
                stage.disclosure(.casual)
                stage.push(.insight(.tolerance), in: .insights)
            },
            chart("chart-receptor-load", pages: 2, state: "Receptor Load, range 7D") { stage in
                stage.push(.insight(.receptorLoad), in: .insights)
            },
            chart("chart-receptor-load-selected", state: "Receptor Load, range 7D, the point one day ago selected") { stage in
                stage.select(.receptorLoad, at: DebugClock.now.addingTimeInterval(-86_400))
                stage.push(.insight(.receptorLoad), in: .insights)
            },
            chart("chart-hormone-levels", pages: 3, state: "Hormone Levels, its default range") { stage in
                stage.push(.insight(.hormoneLevels), in: .insights)
            },
            chart("chart-patterns", pages: 3, state: "Patterns, range 90D") { stage in
                stage.push(.insight(.patterns), in: .insights)
            },
            chart("chart-adherence", pages: 2, state: "Adherence, this month") { stage in
                stage.push(.insight(.adherence), in: .insights)
            },
            chart("chart-substance-estradiol", persona: "transfemHRT", pages: 3, state: "Estradiol page: History and Depot levels") { stage in
                stage.push(.substance(name: "Estradiol"), in: .library)
            },
            chart("chart-half-life", .chartsStatic, pages: 2, state: "Half-life calculator, Caffeine, its default dose and route, taken now") { stage in
                stage.calculator("Caffeine")
                stage.push(.tool(.calculator), in: .tools)
            },
            chart("chart-steady-state", .chartsStatic, pages: 2, state: "Steady State, Sertraline, its default dose every 24 h") { stage in
                stage.calculator("Sertraline")
                stage.push(.tool(.steadyState), in: .tools)
            },
            chart("chart-injection-levels", .chartsStatic, pages: 3, state: "Injection Levels, its default hormone, ester and source") { stage in
                stage.push(.tool(.injectionLevels), in: .tools)
            },
            chart("chart-ceiling", .chartsStatic, pages: 4, state: "Ceiling Effect tool") { stage in
                stage.push(.tool(.ceiling), in: .tools)
            },
            chart("chart-interaction-timeline", .chartsStatic, pages: 2, state: "Interaction timeline, Alcohol + Lorazepam, both at their default times") { stage in
                stage.hostInteractionTimeline("Alcohol", "Lorazepam")
            },
            chart("chart-interaction-timeline-codeine", .chartsStatic, pages: 2, state: "Interaction timeline, Codeine + Diazepam, both at their default times") { stage in
                stage.hostInteractionTimeline("Codeine", "Diazepam")
            },
            chart("chart-substance-mdma", .chartsStatic, pages: 3, state: "MDMA page, its default route and tier") { stage in
                stage.push(.substance(name: "MDMA"), in: .library)
            },
            chart("chart-substance-mdma-tier", .chartsStatic, pages: 2, state: "MDMA page, the fourth dose tier tapped") { stage in
                stage.doseTier(3)
                stage.push(.substance(name: "MDMA"), in: .library)
            },
            chart("chart-substance-codeine", .chartsStatic, pages: 5, state: "Codeine page (its Also active section charts metabolizer variation)") { stage in
                stage.push(.substance(name: "Codeine"), in: .library)
            },
            chart("chart-pharmacology-mdma", .chartsStatic, pages: 3, state: "MDMA Pharmacology section") { stage in
                stage.push(.substanceData(name: "MDMA", section: .pharmacology), in: .library)
            },
            chart("chart-pharmacology-ketamine", .chartsStatic, pages: 2, state: "Ketamine Pharmacology section") { stage in
                stage.push(.substanceData(name: "Ketamine", section: .pharmacology), in: .library)
            },
            chart("chart-tolerance-substance-casual", pages: 3, state: "Modeled Tolerance, Show By substance, Detail Level Casual") { stage in
                stage.disclosure(.casual)
                stage.toleranceMode(.perSubstance)
                stage.push(.insight(.tolerance), in: .insights)
            },
            chart("chart-tolerance-selected", state: "Modeled Tolerance, the point two days ahead selected") { stage in
                stage.select(.tolerance, at: DebugClock.now.addingTimeInterval(2 * 86_400))
                stage.push(.insight(.tolerance), in: .insights)
            },
        ].flatMap(\.self)

        /// One chart screen, plus a screen per page below the fold.
        private static func chart(
            _ name: String, _ set: ScreenSet = .charts, persona: String? = nil, pages: Int = 1, state: String,
            stage: @escaping @MainActor (Stage) async -> Void,
        ) -> [Screen] {
            (0 ..< pages).map { page in
                Screen(
                    name: page == 0 ? name : "\(name)-p\(page + 1)", persona: persona, set: set,
                    state: page == 0 ? state : "\(state); scrolled \(page) screen\(page == 1 ? "" : "s") down",
                ) { screen in
                    await stage(screen)
                    await screen.waitWhileLoading()
                    if page > 0 { await screen.scroll(pages: page) }
                }
            }
        }

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

        /// A search the quick-log dock runs on its next appearance, staging the
        /// recent it finds with the editor open; `.quickLog` carries no search
        /// text. Read once by `takeStagedDockSearch()`.
        private static var stagedDockSearch: String?

        static func takeStagedDockSearch() -> String? {
            defer { stagedDockSearch = nil }
            return stagedDockSearch
        }

        /// Chart control state with no route to carry it, each read once by the
        /// view that owns the control (`takeStagedChart(_:)`).
        struct ChartStage {
            var usageRange: UsageTimeRange?
            var usageMetric: UsageRankMetric?
            var usageSubstances: Set<String>?
            var toleranceMode: ToleranceDetailMode?
            var calculatorSubstance: String?
            var doseTier: Int?
        }

        /// A chart with a selectable point the tour can preselect.
        enum ChartSelection: Hashable {
            case usageTrends
            case modeledLevels
            case receptorLoad
            case tolerance
        }

        fileprivate static var stagedChart = ChartStage()
        fileprivate static var stagedSelections: [ChartSelection: Date] = [:]

        static func takeStagedChart<Value>(_ field: WritableKeyPath<ChartStage, Value?>) -> Value? {
            defer { stagedChart[keyPath: field] = nil }
            return stagedChart[keyPath: field]
        }

        static func takeStagedSelection(_ chart: ChartSelection) -> Date? {
            stagedSelections.removeValue(forKey: chart)
        }

        // MARK: - Run

        /// What the tour writes for one capture.
        private struct Request: Codable {
            let file: String
            let screen: String
            let state: String?
            let skin: String
            let index: Int
            let total: Int
        }

        private struct Report: Codable {
            var captured: [String] = []
            var skipped: [String] = []
            var failed: [String] = []
            var seconds: Double = 0
            /// What the persona seeded, as counts and dates.
            var data: [String: String] = [:]
        }

        private static var hasStarted = false

        /// Runs the whole tour. Call once the store is seeded and the substance
        /// batch cache is warm; returns when `done.json` is on disk.
        static func run(container: ModelContainer) async {
            // The launch hook re-runs when the root view reappears, as it does
            // after a full-screen presentation is dismissed; one tour per launch.
            guard let root = argument(after: "-piruScreenshots"), !hasStarted else { return }
            hasStarted = true
            let started = Date.now
            print("ScreenshotTour: now is \(DebugClock.now.formatted(date: .abbreviated, time: .shortened))\(DebugClock.override == nil ? " (wall clock)" : " (pinned)")")
            let settle = argument(after: "-piruScreenshotSettle").flatMap(Double.init) ?? 1.2
            // A wallpaper is the backdrop alone, so there is nothing to stage.
            let wallpaper = Screen(name: "wallpaper", stage: { _ in })
            let mainScreens = wantsWallpapers ? [wallpaper] : select(list(after: "-piruScreenshotScreens"), from: catalog)
            let skinScreens = wantsWallpapers ? [wallpaper] : select(list(after: "-piruScreenshotSkinScreens") ?? skinScreenNames, from: catalog)
            let skins = selectSkins(list(after: "-piruScreenshotSkins"))

            let host = argument(after: "-piruScreenshotHost").flatMap(URL.init(string:))
            let tourDirectory = URL(filePath: root).appending(path: ".tour")
            try? FileManager.default.createDirectory(at: tourDirectory, withIntermediateDirectories: true)

            // No onboarding cover, no launch sheet on top of a capture.
            UserDefaults.standard.set(true, forKey: OnboardingState.completedKey)
            try? await Task.sleep(for: .seconds(1.5))
            await SubstanceStore.shared.ensureAllLoaded()
            await waitForOwnership()

            // The stock bar in every capture, whatever this device's own layout.
            TabLayoutStore.shared.setEphemeral(.default)
            #if os(macOS)
                sizeWindow()
            #endif
            let stage = Stage(context: container.mainContext)
            let originalGrouping = stage.currentGrouping
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
                let file = if wantsWallpapers {
                    "\(skin.rawValue).png"
                } else if skin == .piru {
                    "\(stem).png"
                } else {
                    "skins/\(skin.rawValue)/\(stem)-\(skin.rawValue).png"
                }
                if let needed = screen.persona, needed != argument(after: "-piruPersona") {
                    report.skipped.append(file)
                    print("ScreenshotTour: [\(index)/\(total)] \(file) skipped — needs -piruPersona \(needed)")
                    return
                }
                await stage.reset()
                await screen.stage(stage)
                try? await Task.sleep(for: .seconds(settle))
                let request = Request(file: file, screen: screen.name, state: screen.state, skin: skin.rawValue, index: index, total: total)
                print("ScreenshotTour: [\(index)/\(total)] \(file)")
                switch await handshake(request, in: tourDirectory, host: host) {
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
            report.data = stage.journalFacts()
            stage.restoreGrouping(originalGrouping)
            TabLayoutStore.shared.setEphemeral(nil)

            report.seconds = Date.now.timeIntervalSince(started)
            if let host {
                await post(report, to: host.appending(path: "done"))
            } else {
                write(report, to: tourDirectory.appending(path: "done.json"))
            }
            print("ScreenshotTour: done — \(report.captured.count) captured, \(report.failed.count) failed, \(report.skipped.count) skipped")
        }

        /// The screens a pass captures: the named ones, or every screen the
        /// running persona fills.
        private static func select(_ names: [String]?, from catalog: [Screen]) -> [Screen] {
            let persona = argument(after: "-piruPersona")
            guard let names, names != ["all"] else {
                return catalog.filter { $0.set == nil && ($0.persona == nil || $0.persona == persona) }
            }
            if names.count == 1, let set = ScreenSet(rawValue: names[0]) {
                return catalog.filter { $0.set == set && ($0.persona == nil || $0.persona == persona) }
            }
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

        // MARK: - Wallpaper

        /// The root under `-piruWallpapers`: the skin's backdrop and nothing
        /// else. Decorations are forced on by naming the skin, and the home
        /// indicator is hidden so the capture is the scene alone. The status
        /// bar is hidden by the app root, outside the view `SkinnedRoot`
        /// re-creates per skin: re-registering the preference on every skin
        /// change left the simulator's Dynamic Island painted black in one
        /// capture out of eight.
        struct WallpaperCanvas: View {
            @State private var skins = SkinStore.shared

            var body: some View {
                SkinBackdrop(skin: skins.current)
                    .ignoresSafeArea()
                    .persistentSystemOverlays(.hidden)
            }
        }

        // MARK: - Handshake

        private enum Outcome { case captured, timedOut }

        /// Asks the host for one capture and waits for its ack (30 s): over
        /// HTTP when the host serves one, else through `request.json`/`ack`.
        private static func handshake(_ request: Request, in directory: URL, host: URL?) async -> Outcome {
            if let host {
                return await post(request, to: host.appending(path: "request")) ? .captured : .timedOut
            }
            return await fileHandshake(request, in: directory)
        }

        /// Writes the request, waits for the host's ack (30 s), then clears both.
        private static func fileHandshake(_ request: Request, in directory: URL) async -> Outcome {
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

        /// POSTs `value` as JSON; the host answers once it has acted on it.
        @discardableResult
        private static func post(_ value: some Encodable, to url: URL) async -> Bool {
            var request = URLRequest(url: url, timeoutInterval: 30)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(value)
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                return (response as? HTTPURLResponse)?.statusCode == 200
            } catch {
                print("ScreenshotTour: \(url.lastPathComponent) failed — \(error.localizedDescription)")
                return false
            }
        }

        #if os(macOS)
            /// One frame for every capture, whatever size the window was restored at.
            private static func sizeWindow() {
                let raw = argument(after: "-piruScreenshotWindow") ?? "1280x820"
                let parts = raw.split(separator: "x").compactMap { Double($0) }
                guard parts.count == 2, let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
                window.setContentSize(NSSize(width: parts[0], height: parts[1]))
                window.center()
            }
        #endif

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
            private let navigator = AppNavigator.shared
            private let groupDefaults = UserDefaults(suiteName: AppIdentity.appGroup)

            init(context: ModelContext) {
                self.context = context
            }

            /// Every sheet down, every stack popped to root, and the state a
            /// chart screen changed put back.
            func reset() async {
                var hadSheet = !navigator.sheetStack.isEmpty
                #if canImport(UIKit)
                    if let hosted = Self.hosted {
                        hosted.dismiss(animated: false)
                        Self.hosted = nil
                        hadSheet = true
                    }
                #endif
                navigator.dismissAll()
                navigator.resetAllPaths()
                ScreenshotTour.stagedChart = ChartStage()
                ScreenshotTour.stagedSelections = [:]
                restoreTouchedState()
                try? await Task.sleep(for: .seconds(hadSheet ? 0.6 : 0.2))
            }

            // MARK: Chart state

            /// App Group defaults a screen changed, each with the value it had
            /// before (`nil` when it was unset).
            private static var touchedDefaults: [String: Any?] = [:]
            private static var originalDisclosure: UserProfile?

            func setShared(_ key: String, _ value: Any) {
                if Self.touchedDefaults.index(forKey: key) == nil {
                    Self.touchedDefaults[key] = .some(groupDefaults?.object(forKey: key))
                }
                groupDefaults?.set(value, forKey: key)
            }

            func disclosure(_ tier: UserProfile) {
                if Self.originalDisclosure == nil {
                    Self.originalDisclosure = UserProfileStore.shared.disclosureTier
                }
                UserProfileStore.shared.setDisclosureTier(tier)
            }

            func restoreTouchedState() {
                for (key, original) in Self.touchedDefaults {
                    groupDefaults?.set(original, forKey: key)
                }
                Self.touchedDefaults = [:]
                if let tier = Self.originalDisclosure {
                    UserProfileStore.shared.setDisclosureTier(tier)
                    Self.originalDisclosure = nil
                }
            }

            /// Opens Usage with its range, measure and substance filter set.
            func usage(range: UsageTimeRange, metric: UsageRankMetric = .commonDoses, substances: Set<String> = []) {
                ScreenshotTour.stagedChart.usageRange = range
                ScreenshotTour.stagedChart.usageMetric = metric
                ScreenshotTour.stagedChart.usageSubstances = substances
                push(.insight(.usage), in: .insights)
            }

            func select(_ chart: ChartSelection, at date: Date) {
                ScreenshotTour.stagedSelections[chart] = date
            }

            func toleranceMode(_ mode: ToleranceDetailMode) {
                ScreenshotTour.stagedChart.toleranceMode = mode
            }

            func calculator(_ substance: String) {
                ScreenshotTour.stagedChart.calculatorSubstance = substance
            }

            func doseTier(_ tier: Int) {
                ScreenshotTour.stagedChart.doseTier = tier
            }

            func busiestSession() -> Session? {
                let sessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
                return sessions.max { lhs, rhs in
                    let left = lhs.doses?.count ?? 0
                    let right = rhs.doses?.count ?? 0
                    return left == right ? lhs.startDate < rhs.startDate : left < right
                }
            }

            func newestEntry() -> DoseEntry? {
                var descriptor = FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
                descriptor.fetchLimit = 1
                return try? context.fetch(descriptor).first
            }

            /// The `count` substances with the most entries in the last `days`
            /// days, each by its dose title: the name Usage's substance filter
            /// keys on ("Estradiol Valerate", "Concerta").
            func mostLoggedSubstances(_ count: Int, days: Int) -> [String] {
                let since = DebugClock.now.addingTimeInterval(-Double(days) * 86_400)
                let entries = (try? context.fetch(FetchDescriptor<DoseEntry>(predicate: #Predicate { $0.timestamp >= since }))) ?? []
                let tally = Dictionary(grouping: entries) { DoseTitle.resolve(for: $0) }.mapValues(\.count)
                return tally.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
                    .prefix(count).map(\.key)
            }

            /// What the journal holds, for the capture index.
            func journalFacts() -> [String: String] {
                let entries = (try? context.fetch(FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp)]))) ?? []
                let calendar = Calendar.current
                var facts = [
                    "entries": "\(entries.count)",
                    "substances": "\(Set(entries.map(\.substance)).count)",
                    "sessions": "\((try? context.fetchCount(FetchDescriptor<Session>())) ?? 0)",
                    "myMeds": "\((try? context.fetchCount(FetchDescriptor<DailyDoseItem>())) ?? 0)",
                    "labs": "\((try? context.fetchCount(FetchDescriptor<LabMeasurement>())) ?? 0)",
                    "daysWithEntries": "\(Set(entries.map { calendar.startOfDay(for: $0.timestamp) }).count)",
                    "now": DebugClock.now.formatted(.iso8601),
                ]
                if let first = entries.first?.timestamp, let last = entries.last?.timestamp {
                    facts["first"] = first.formatted(.iso8601)
                    facts["last"] = last.formatted(.iso8601)
                    facts["spanDays"] = "\(Int((DebugClock.now.timeIntervalSince(first) / 86_400).rounded(.up)))"
                }
                return facts
            }

            /// Scrolls the frontmost screen's main scroll view down `pages`
            /// screens, one at a time so lazy content lays out on the way.
            func scroll(pages: Int) async {
                #if canImport(UIKit)
                    try? await Task.sleep(for: .seconds(1.2))
                    for _ in 0 ..< pages {
                        guard let scrollView = Self.mainScrollView() else {
                            print("ScreenshotTour: no scroll view on screen")
                            return
                        }
                        let inset = scrollView.adjustedContentInset
                        let step = (scrollView.bounds.height - inset.top - inset.bottom) * 0.85
                        let bottom = max(-inset.top, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
                        let y = min(scrollView.contentOffset.y + step, bottom)
                        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: false)
                        try? await Task.sleep(for: .seconds(0.5))
                    }
                #endif
            }

            /// Waits (up to 60 s) until the frontmost screen shows no spinning
            /// progress indicator, so a slow model is captured with its result.
            func waitWhileLoading() async {
                #if canImport(UIKit)
                    try? await Task.sleep(for: .seconds(0.8))
                    for _ in 0 ..< 120 {
                        guard let root = Self.topViewController()?.view, Self.hasSpinner(in: root) else { return }
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                    print("ScreenshotTour: still loading after 60 s")
                #endif
            }

            #if canImport(UIKit)
                private static func hasSpinner(in view: UIView) -> Bool {
                    guard !view.isHidden, view.alpha > 0.01, view.window != nil else { return false }
                    if let spinner = view as? UIActivityIndicatorView, spinner.isAnimating { return true }
                    return view.subviews.contains(where: hasSpinner(in:))
                }

                /// A screen with no route of its own, presented over the app.
                private static var hosted: UIViewController?

                /// The interaction timeline for a pair, as the checker opens it
                /// from a warning row.
                func hostInteractionTimeline(_ first: String, _ second: String) {
                    guard let warning = InteractionChecker.checkBatch([first, second], against: [], policy: .explore).first,
                          let top = Self.topViewController()
                    else {
                        print("ScreenshotTour: no interaction between \(first) and \(second)")
                        return
                    }
                    let root = NavigationStack {
                        InteractionTimelineView(
                            substanceA: warning.substanceA, substanceB: warning.substanceB,
                            severity: warning.severity, mechanism: warning.description,
                        )
                    }
                    .modelContainer(context.container)
                    let host = UIHostingController(rootView: root)
                    host.modalPresentationStyle = .overFullScreen
                    top.present(host, animated: false)
                    Self.hosted = host
                }

                private static func topViewController() -> UIViewController? {
                    let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                        .flatMap(\.windows).first(where: \.isKeyWindow)
                    var top = window?.rootViewController
                    while let presented = top?.presentedViewController, !presented.isBeingDismissed {
                        top = presented
                    }
                    return top
                }

                /// The largest vertically scrolling view on screen in the
                /// frontmost view controller.
                private static func mainScrollView() -> UIScrollView? {
                    guard let root = topViewController()?.view, let window = root.window else { return nil }
                    var best: UIScrollView?
                    var bestArea: CGFloat = 0
                    func visit(_ view: UIView) {
                        guard !view.isHidden, view.alpha > 0.01 else { return }
                        if let scroll = view as? UIScrollView,
                           scroll.contentSize.height > scroll.bounds.height + 20, scroll.bounds.height > 300 {
                            let frame = scroll.convert(scroll.bounds, to: window).intersection(window.bounds)
                            let area = frame.isNull ? 0 : frame.width * frame.height
                            if area > bestArea {
                                best = scroll
                                bestArea = area
                            }
                        }
                        view.subviews.forEach(visit)
                    }
                    visit(root)
                    return best
                }
            #endif

            func tab(_ tab: TabID) {
                navigator.select(tab)
            }

            func push(_ route: PushRoute, in tab: TabID) {
                navigator.select(tab)
                navigator.setPath([route], in: tab)
            }

            func present(_ sheet: SheetRoute) {
                navigator.present(sheet)
            }

            /// Waits out a sheet's presentation, so a push onto its stack
            /// lands on a settled sheet.
            func settleSheet() async {
                try? await Task.sleep(for: .seconds(0.8))
            }

            /// Pushes onto the top sheet's own stack.
            func pushInSheet(_ route: PushRoute) {
                navigator.push(route)
            }

            func med(product: String) -> DailyDoseItem? {
                var descriptor = FetchDescriptor<DailyDoseItem>(predicate: #Predicate { $0.productName == product })
                descriptor.fetchLimit = 1
                return try? context.fetch(descriptor).first
            }

            func inventoryItem(of substance: String) -> InventoryItem? {
                var descriptor = FetchDescriptor<InventoryItem>(predicate: #Predicate { $0.substance == substance })
                descriptor.fetchLimit = 1
                return try? context.fetch(descriptor).first
            }

            func grouping(_ grouping: JournalGrouping) {
                groupDefaults?.set(grouping.rawValue, forKey: "journalGrouping")
            }

            /// The grouping the device had before the tour, so the run can put
            /// it back: it lives in the App Group defaults the real app reads.
            var currentGrouping: String? {
                groupDefaults?.string(forKey: "journalGrouping")
            }

            func restoreGrouping(_ raw: String?) {
                groupDefaults?.set(raw, forKey: "journalGrouping")
            }

            func sessionID(titled title: String) -> UUID? {
                session(titled: title)?.id
            }

            func session(titled title: String) -> Session? {
                var descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.title == title })
                descriptor.fetchLimit = 1
                return try? context.fetch(descriptor).first
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
