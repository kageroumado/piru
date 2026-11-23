#if DEBUG
    import Foundation
    import os
    import SwiftData

    /// Scripted journeys for `pipeline/perf/`, driven inside the app so every
    /// run performs the same steps at the same pace.
    ///
    /// Arguments:
    /// - `-piruPerf <dir>` — a host directory the app writes its results to;
    ///   enables the tour and opens the store `perf.store`.
    /// - `-piruPerfFixture <name>` — seed a ``PerfFixtures/Fixture`` first.
    /// - `-piruPerfSeedOnly` — seed, write `seeded.json`, run nothing else. The
    ///   host seeds in one launch and measures in the next, so a recording
    ///   starts on a cold process over an already-full store.
    /// - `-piruPerfFlows <name,…>` — which flows, in order (default: all).
    /// - `-piruPerfLoops <n>` — passes over the flow list (default 1); memory
    ///   growth is read across passes.
    ///
    /// Every step is an `os_signpost` interval named `step` (subsystem
    /// `glass.kagerou.piru.perf`, Points of Interest) whose message is
    /// `<flow>/<step>#<loop>`, and a row in `<dir>/steps.json` with the in-process
    /// readings (CPU, footprint, run-loop stalls, counters). `<dir>/done.json`
    /// closes the run.
    @MainActor
    enum PerfTour {
        static var directory: URL? {
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: "-piruPerf"), args.indices.contains(i + 1) else { return nil }
            return URL(filePath: args[i + 1])
        }

        static var isRequested: Bool {
            PerfProbe.isActive && directory != nil
        }

        private static func argument(after flag: String) -> String? {
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
            return args[i + 1]
        }

        /// When the launch hook ran: the store is open and the root view is
        /// being built. Launch is also measured from here, because a process
        /// launched under `xctrace` sits suspended before it runs, which puts
        /// the kernel's start time arbitrarily early.
        private static var hookedAt = Date.now

        /// The launch hook: seed, or run the flows.
        static func start(container: ModelContainer) {
            guard let directory else { return }
            hookedAt = .now
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            UserDefaults.standard.set(true, forKey: OnboardingState.completedKey)
            let monitor = RunLoopStallMonitor()
            monitor.start()
            if ProcessInfo.processInfo.arguments.contains("-piruPerfSeedOnly") {
                Task(name: "Perf seed") {
                    await SubstanceStore.shared.ensureAllLoaded()
                    let fixture = PerfFixtures.requested ?? .heavy
                    let summary = PerfFixtures.seed(fixture, container: container)
                    write(summary, to: directory.appending(path: "seeded.json"))
                    print("PerfTour: seeded \(fixture.rawValue) — \(summary.doses) doses in \(String(format: "%.1f", summary.seconds)) s")
                }
                return
            }
            Task(name: "Perf tour") {
                await run(container: container, monitor: monitor, directory: directory)
            }
        }

        // MARK: - Results

        struct StepResult: Codable {
            let flow: String
            let step: String
            let loop: Int
            let startEpoch: Double
            let wallMs: Double
            let mainCPUMs: Double
            let processCPUMs: Double
            let footprintStartMB: Double
            let footprintEndMB: Double
            let footprintPeakMB: Double
            let voluntarySwitches: Int
            let involuntarySwitches: Int
            let counters: [String: Int]
            let stalls: [RunLoopStallMonitor.Span]
            var note: String?
        }

        struct LaunchResult: Codable {
            /// Process start to the tour's first line (the root view is up).
            let toTourStartMs: Double?
            /// Process start to the substance catalog warm.
            let toCatalogWarmMs: Double?
            /// Process start to the main run loop's first wait after the
            /// catalog was warm and the Journal drawn: the app is interactive.
            let toInteractiveMs: Double?
            /// The launch hook (store open, root building) to interactive.
            let hookToInteractiveMs: Double
            let footprintMB: Double
        }

        struct Report: Codable {
            var fixture: String?
            var flows: [String] = []
            var launch: LaunchResult?
            var steps: [StepResult] = []
            var seconds: Double = 0
            var device = ""
            var system = ""
            var configuration = ""
        }

        // MARK: - Run

        private static func run(container: ModelContainer, monitor: RunLoopStallMonitor, directory: URL) async {
            let processStart = PerfProbe.processStart()
            let tourStart = Date.now
            var report = Report()
            report.fixture = PerfFixtures.requested?.rawValue
            report.device = ProcessInfo.processInfo.hostName
            report.system = ProcessInfo.processInfo.operatingSystemVersionString
            report.configuration = _isDebugAssertConfiguration() ? "debug-assert" : "optimized"
            await SubstanceStore.shared.ensureAllLoaded()
            let warm = Date.now
            PerfProbe.signposter.emitEvent("catalogWarm")
            // Interactive: the main run loop's first wait once the catalog is
            // warm, so the Journal has drawn over it and input is served.
            await monitor.nextIdle()
            let interactive = Date.now
            PerfProbe.signposter.emitEvent("interactive")
            report.launch = LaunchResult(
                toTourStartMs: processStart.map { tourStart.timeIntervalSince($0) * 1000 },
                toCatalogWarmMs: processStart.map { warm.timeIntervalSince($0) * 1000 },
                toInteractiveMs: processStart.map { interactive.timeIntervalSince($0) * 1000 },
                hookToInteractiveMs: interactive.timeIntervalSince(hookedAt) * 1000,
                footprintMB: Double(PerfProbe.footprint()) / 1_048_576,
            )
            _ = monitor.drain()
            // Let launch-time passes finish so the first step measures itself.
            try? await Task.sleep(for: .seconds(3))
            TabLayoutStore.shared.setEphemeral(.default)
            let driver = PerfDriver(context: container.mainContext, container: container, directory: directory)
            let originalGrouping = driver.currentGrouping
            let flows = selectedFlows()
            report.flows = flows.map(\.name)
            let loops = max(1, Int(argument(after: "-piruPerfLoops") ?? "") ?? 1)
            for loop in 1 ... loops {
                for flow in flows {
                    await driver.reset()
                    for step in flow.steps {
                        let result = await measure(flow: flow.name, step: step, loop: loop, driver: driver, monitor: monitor)
                        report.steps.append(result)
                        write(report, to: directory.appending(path: "steps.json"))
                    }
                }
            }
            await driver.reset()
            driver.restoreGrouping(originalGrouping)
            TabLayoutStore.shared.setEphemeral(nil)
            report.seconds = Date.now.timeIntervalSince(tourStart)
            write(report, to: directory.appending(path: "steps.json"))
            write(["seconds": report.seconds], to: directory.appending(path: "done.json"))
            print("PerfTour: done — \(report.steps.count) steps in \(Int(report.seconds)) s")
        }

        private static func measure(flow: String, step: Step, loop: Int, driver: PerfDriver, monitor: RunLoopStallMonitor) async -> StepResult {
            let label = "\(flow)/\(step.name)#\(loop)"
            write(["step": label], to: driver.directory.appending(path: "progress.json"))
            _ = monitor.drain()
            let peak = FootprintSampler()
            let counters = PerfProbe.snapshot()
            let switches = PerfProbe.contextSwitches()
            let footprint = PerfProbe.footprint()
            let mainCPU = PerfProbe.threadCPUMilliseconds()
            let processCPU = PerfProbe.processCPUMilliseconds()
            let start = Date.now
            let state = PerfProbe.signposter.beginInterval("step", "\(label, privacy: .public)")
            Logger.routeTour.notice("PerfTour begin \(label, privacy: .public)")
            let note = await step.run(driver)
            // A step ends when the main run loop next goes idle, so work the
            // step queued is counted against it.
            await Task.yield()
            PerfProbe.signposter.endInterval("step", state)
            let wall = Date.now.timeIntervalSince(start) * 1000
            let after = PerfProbe.snapshot()
            let delta = after.reduce(into: [String: Int]()) { result, pair in
                let change = pair.value - (counters[pair.key] ?? 0)
                if change != 0 { result[pair.key] = change }
            }
            let switchesAfter = PerfProbe.contextSwitches()
            let endFootprint = PerfProbe.footprint()
            return StepResult(
                flow: flow, step: step.name, loop: loop, startEpoch: start.timeIntervalSince1970, wallMs: wall,
                mainCPUMs: PerfProbe.threadCPUMilliseconds() - mainCPU,
                processCPUMs: PerfProbe.processCPUMilliseconds() - processCPU,
                footprintStartMB: Double(footprint) / 1_048_576, footprintEndMB: Double(endFootprint) / 1_048_576,
                footprintPeakMB: Double(max(peak.stop(), endFootprint)) / 1_048_576,
                voluntarySwitches: switchesAfter.voluntary - switches.voluntary,
                involuntarySwitches: switchesAfter.involuntary - switches.involuntary,
                counters: delta, stalls: monitor.drain(), note: note,
            )
        }

        private static func selectedFlows() -> [Flow] {
            guard let raw = argument(after: "-piruPerfFlows"), raw != "all" else { return catalog }
            let names = raw.split(separator: ",").map(String.init)
            let unknown = names.filter { name in !catalog.contains { $0.name == name } }
            if !unknown.isEmpty {
                print("PerfTour: unknown flows \(unknown) — known: \(catalog.map(\.name).joined(separator: ", "))")
            }
            return names.compactMap { name in catalog.first { $0.name == name } }
        }

        static func write(_ value: some Encodable, to url: URL) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(value) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Samples the process footprint every 50 ms off the main thread and keeps
    /// the highest reading, so a step's peak is seen even while main is busy.
    final nonisolated class FootprintSampler: Sendable {
        private let peak = OSAllocatedUnfairLock(initialState: UInt64(0))
        private let timer: DispatchSourceTimer

        init() {
            timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            timer.schedule(deadline: .now(), repeating: .milliseconds(50))
            timer.setEventHandler { @Sendable [peak] in
                let reading = PerfProbe.footprint()
                peak.withLock { $0 = max($0, reading) }
            }
            timer.resume()
        }

        func stop() -> UInt64 {
            timer.cancel()
            return peak.withLock { $0 }
        }
    }
#endif
