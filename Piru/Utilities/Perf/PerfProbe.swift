#if DEBUG
    import Darwin
    import Foundation
    import GRDB
    import os

    /// The in-process half of `pipeline/perf/`: counters for the work a trace
    /// cannot count exactly, a main run-loop stall monitor, and the step marks
    /// both sides cut a recording by.
    ///
    /// Everything is off unless the process was launched with `-piruPerf <dir>`,
    /// so a DEBUG build that is not being measured pays one `Bool` read per
    /// probe. Counters are machine-speed independent (SQL statements, heavy
    /// resolves, batch-cache misses), which is what the CI gate compares.
    nonisolated enum PerfProbe {
        /// Whether this process is a perf run.
        static let isActive = ProcessInfo.processInfo.arguments.contains("-piruPerf")

        /// Signposts land in Points of Interest, so the stock Time Profiler
        /// template already records them; the analyzer cuts the trace by the
        /// `step` intervals.
        static let signposter = OSSignposter(subsystem: "glass.kagerou.piru.perf", category: .pointsOfInterest)

        private static let counters = OSAllocatedUnfairLock(initialState: [String: Int]())

        /// Adds `amount` to the counter `key`.
        static func count(_ key: String, by amount: Int = 1) {
            guard isActive else { return }
            counters.withLock { $0[key, default: 0] += amount }
        }

        static func snapshot() -> [String: Int] {
            counters.withLock { $0 }
        }

        /// Counts every statement a GRDB connection runs, under `sql.<label>`.
        static func install(on configuration: inout Configuration) {
            guard isActive else { return }
            let key = "sql.\(configuration.label ?? "unlabeled")"
            configuration.prepareDatabase { db in
                db.trace(options: .statement) { _ in PerfProbe.count(key) }
            }
        }

        // MARK: - Process readings

        /// The process's physical footprint, in bytes — the number the system's
        /// memory limit is measured against.
        static func footprint() -> UInt64 {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            return result == KERN_SUCCESS ? info.phys_footprint : 0
        }

        /// CPU time the calling thread has used, in milliseconds.
        static func threadCPUMilliseconds() -> Double {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
            let port = mach_thread_self()
            defer { mach_port_deallocate(mach_task_self_, port) }
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    thread_info(port, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }
            guard result == KERN_SUCCESS else { return 0 }
            let user = Double(info.user_time.seconds) * 1000 + Double(info.user_time.microseconds) / 1000
            let system = Double(info.system_time.seconds) * 1000 + Double(info.system_time.microseconds) / 1000
            return user + system
        }

        /// CPU time the whole process has used, in milliseconds.
        static func processCPUMilliseconds() -> Double {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            let user = Double(usage.ru_utime.tv_sec) * 1000 + Double(usage.ru_utime.tv_usec) / 1000
            let system = Double(usage.ru_stime.tv_sec) * 1000 + Double(usage.ru_stime.tv_usec) / 1000
            return user + system
        }

        /// Voluntary and involuntary context switches of the process so far.
        static func contextSwitches() -> (voluntary: Int, involuntary: Int) {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            return (Int(usage.ru_nvcsw), Int(usage.ru_nivcsw))
        }

        /// When the kernel started this process.
        static func processStart() -> Date? {
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
            guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0 else { return nil }
            let start = info.kp_proc.p_un.__p_starttime
            return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
        }
    }

    // MARK: - Run-loop stalls

    /// Measures how long the main run loop stays busy between two waits. A busy
    /// span is the time from waking to going back to sleep: a span over 100 ms
    /// is a hitch the user sees, over 250 ms a hang. This is the same signal
    /// the Hangs instrument reports, taken in process so a run without a trace
    /// (or a trace whose export fails) still has it.
    @MainActor
    final class RunLoopStallMonitor {
        struct Span: Codable {
            let startMs: Double
            let durationMs: Double
        }

        /// Spans at least this long are kept.
        private let floorMs: Double
        private var observer: CFRunLoopObserver?
        private var wokeAt: UInt64 = 0
        private(set) var spans: [Span] = []
        private var idleWaiters: [CheckedContinuation<Void, Never>] = []
        private let origin = mach_continuous_time()

        init(floorMs: Double = 50) {
            self.floorMs = floorMs
        }

        func start() {
            let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
            observer = CFRunLoopObserverCreateWithHandler(nil, activities, true, Int.max) { [weak self] _, activity in
                MainActor.assumeIsolated { self?.observe(activity) }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            wokeAt = mach_continuous_time()
        }

        func stop() {
            if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
            observer = nil
        }

        /// Returns when the main run loop next goes to sleep.
        func nextIdle() async {
            await withCheckedContinuation { idleWaiters.append($0) }
        }

        /// Clears the spans collected so far and returns them.
        func drain() -> [Span] {
            defer { spans.removeAll() }
            return spans
        }

        private func observe(_ activity: CFRunLoopActivity) {
            let now = mach_continuous_time()
            if activity == .afterWaiting {
                wokeAt = now
                return
            }
            if !idleWaiters.isEmpty {
                let waiters = idleWaiters
                idleWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
            let duration = Self.milliseconds(now - wokeAt)
            guard duration >= floorMs else { return }
            spans.append(Span(startMs: Self.milliseconds(wokeAt - origin), durationMs: duration))
        }

        static func milliseconds(_ ticks: UInt64) -> Double {
            var timebase = mach_timebase_info_data_t()
            mach_timebase_info(&timebase)
            return Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000
        }
    }
#endif
