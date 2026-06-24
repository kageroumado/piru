import Foundation
import SwiftData
import Testing
@testable import Piru

/// Golden / synthetic verification for the tolerance replay against the **live on-simulator dose
/// log** (the imported multi-thousand-entry store that exposed the performance hang).
///
/// The contract: ``ToleranceStore/simulate`` is the pure core that produces every value the Tolerance
/// tool renders. This suite opens the real store read-only, runs `simulate` at a *fixed* `now`
/// (deterministic given the frozen, imported data), and snapshots the per-target output to a golden
/// JSON in the app's Documents (persists on the sim across runs). On the first run it records the
/// baseline; on later runs it asserts the optimized engine still matches the baseline within a
/// tolerance far below display resolution — so a performance pass that *doesn't* intend to change a
/// number can prove it didn't, and an unexpected diff is a signal to investigate.
///
/// Hosted by `Piru.app`, so it reads the same App-Group store the app uses. Skipped (not failed) when
/// no store is present (CI / a fresh sim), since it depends on the user's local imported data.
@Suite("Tolerance golden (live store)", .tags(.pharmacokinetics))
@MainActor
struct ToleranceGoldenTests {
    /// The canonical store the running app uses (App-Group container, with the app's fallbacks).
    nonisolated static var storeURL: URL {
        StoreRecovery.canonicalStoreURL()
    }

    /// Only run when a real store file exists on this machine/sim.
    nonisolated static var hasStore: Bool {
        FileManager.default.fileExists(atPath: storeURL.path)
    }

    /// Raw per-target output — every number the tool's rows derive from.
    private struct TargetGolden: Codable, Equatable {
        var availability: Double
        var acute: Double
        var load: Double
        var receptorClass: String
        var confidence: String
    }

    private struct GoldenSnapshot: Codable {
        var now: Double
        var weightKg: Double
        var entryCount: Int
        var targets: [String: TargetGolden]
    }

    private static var goldenURL: URL {
        URL.documentsDirectory.appendingPathComponent("tolerance-golden.json")
    }

    /// Values match if every shared target agrees to within `tol` and the key sets are identical. The
    /// ε-pruning in the optimized engine perturbs availability/load well below 1e-6 (and far below the
    /// integer-percent the UI shows), so 1e-6 catches a real regression without flagging the prune.
    private static let tol = 1e-6

    @Test(.enabled(if: hasStore))
    func `simulate matches the golden baseline on the live imported log`() async throws {
        let container = try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(url: Self.storeURL, allowsSave: false, cloudKitDatabase: .none),
        )
        let context = ModelContext(container)
        let entries = try context.fetch(FetchDescriptor<DoseEntry>())
        guard !entries.isEmpty else {
            print("[tolerance-golden] live store has no dose entries — skipping")
            return
        }

        // Same weight the app would use; configure the shared profile store against this store.
        UserProfileStore.shared.configure(container: container)
        let weight = UserProfileStore.shared.effectiveWeightKg

        // Deterministic `now`: the latest logged dose. Frozen with the imported data, so the golden is
        // reproducible run-to-run regardless of wall-clock.
        let now = entries.map(\.timestamp).max() ?? .now

        let resolve: (String) -> PharmacologyParameters? = {
            SubstanceStore.shared.pharmacologyParameters(forSubstanceName: $0)
        }

        // Serial path (the canonical/synchronous core used by the small main-actor callers).
        let clock = ContinuousClock()
        var result: [String: TargetTolerance] = [:]
        let serialElapsed = clock.measure {
            result = ToleranceStore.simulate(entries: entries, now: now, weightKg: weight, resolve: resolve)
        }

        // Concurrent path (what the background `recompute` runs): build the same Sendable snapshot the
        // main-actor wrapper would, then fan out across the TaskGroup. Time it and assert it agrees with
        // the serial result — same math, only the driver differs.
        let doses = entries.map {
            ToleranceStore.SimDose(
                substance: $0.substance,
                amountMg: DoseUnit.convert($0.amount, from: $0.unit, to: "mg"),
                timestamp: $0.timestamp,
            )
        }
        var params: [String: PharmacologyParameters] = [:]
        var resolved = Set<String>()
        for dose in doses where resolved.insert(dose.substance).inserted {
            params[dose.substance] = resolve(dose.substance)
        }
        let concurrentStart = clock.now
        let concurrent = await ToleranceStore.simulateConcurrently(doses: doses, params: params, now: now, weightKg: weight)
        let concurrentElapsed = clock.now - concurrentStart

        print("[tolerance-golden] entries=\(entries.count) targets=\(result.count) weight=\(weight) serial=\(serialElapsed) concurrent=\(concurrentElapsed)")

        #expect(Set(result.keys) == Set(concurrent.keys), "serial vs concurrent target sets differ")
        for (target, serialState) in result {
            guard let concurrentState = concurrent[target] else { continue }
            #expect(abs(serialState.availability - concurrentState.availability) < 1e-12, "serial≠concurrent availability[\(target)]")
            #expect(abs(serialState.acute - concurrentState.acute) < 1e-12, "serial≠concurrent acute[\(target)]")
            #expect(abs(serialState.load - concurrentState.load) < 1e-12, "serial≠concurrent load[\(target)]")
        }

        let current = GoldenSnapshot(
            now: now.timeIntervalSince1970,
            weightKg: weight,
            entryCount: entries.count,
            targets: result.mapValues {
                TargetGolden(
                    availability: $0.availability, acute: $0.acute, load: $0.load,
                    receptorClass: $0.receptorClass.rawValue, confidence: $0.confidence.rawValue,
                )
            },
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let currentJSON = try encoder.encode(current)
        // Record the full snapshot as a test attachment (lands in the .xcresult bundle) instead of
        // dumping ~200 lines of JSON to the console; the one-line timing headline above stays a `print`
        // so it remains visible in plain CLI `xcodebuild test` logs.
        Attachment.record(currentJSON, named: "tolerance-golden.json")

        guard let goldenData = try? Data(contentsOf: Self.goldenURL),
              let golden = try? JSONDecoder().decode(GoldenSnapshot.self, from: goldenData) else {
            try currentJSON.write(to: Self.goldenURL)
            print("[tolerance-golden] no baseline yet — wrote \(Self.goldenURL.path). Re-run after optimizing to compare.")
            return
        }

        // Compare against the recorded baseline.
        #expect(current.entryCount == golden.entryCount, "entry count changed (\(golden.entryCount) → \(current.entryCount)); golden is stale for this data")
        #expect(Set(current.targets.keys) == Set(golden.targets.keys), """
        target set diverged.
          missing now: \(Set(golden.targets.keys).subtracting(current.targets.keys).sorted())
          new now:     \(Set(current.targets.keys).subtracting(golden.targets.keys).sorted())
        """)

        for (target, g) in golden.targets {
            guard let c = current.targets[target] else { continue }
            #expect(abs(c.availability - g.availability) < Self.tol, "availability[\(target)] \(g.availability) → \(c.availability)")
            #expect(abs(c.acute - g.acute) < Self.tol, "acute[\(target)] \(g.acute) → \(c.acute)")
            #expect(abs(c.load - g.load) < Self.tol, "load[\(target)] \(g.load) → \(c.load)")
            #expect(c.receptorClass == g.receptorClass, "receptorClass[\(target)] \(g.receptorClass) → \(c.receptorClass)")
            #expect(c.confidence == g.confidence, "confidence[\(target)] \(g.confidence) → \(c.confidence)")
        }
    }

    /// Times the **dose-entry warning path** over the live log. `crossToleranceReadouts` and
    /// `opioidResetRisk` run synchronously on the main actor when the entry form appears, so their wall
    /// time decides whether they're acceptable on-main (a >~400 ms stall is perceptible) or must move
    /// off-main / read the warm cache. A μ-opioid substance is chosen so the opioid-reset gate runs its
    /// full multi-replay rather than bailing early.
    @Test(.enabled(if: hasStore))
    func `Dose-entry warning path timing on the live log`() throws {
        let container = try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(url: Self.storeURL, allowsSave: false, cloudKitDatabase: .none),
        )
        let context = ModelContext(container)
        let entries = try context.fetch(FetchDescriptor<DoseEntry>())
        guard !entries.isEmpty else {
            print("[warning-path] live store has no dose entries — skipping")
            return
        }

        // A fresh store instance (not the shared singleton) keeps this test isolated.
        UserProfileStore.shared.configure(container: container)
        let tolerance = ToleranceStore()
        tolerance.configure(container: container)

        let substance = "O-Desmethyltramadol" // μ-opioid present in the log → exercises the reset gate
        let clock = ContinuousClock()

        let crossStart = clock.now
        let cross = tolerance.crossToleranceReadouts(forSubstance: substance)
        let crossElapsed = clock.now - crossStart

        let opioidStart = clock.now
        let opioidReset = tolerance.opioidResetRisk(forSubstance: substance)
        let opioidElapsed = clock.now - opioidStart

        print("[warning-path] entries=\(entries.count) crossTolerance=\(crossElapsed) (\(cross.count) readouts) opioidReset=\(opioidElapsed) (\(opioidReset == nil ? "no risk" : "fired")) substance=\(substance)")
    }
}
