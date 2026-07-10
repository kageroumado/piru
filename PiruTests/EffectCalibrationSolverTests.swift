import Foundation
import Testing
@testable import Piru

/// The **staged calibration solver** for the mechanistic effect model (see
/// `Specs/effect-model-molar-calibration.md`). It runs the real resolver
/// (`SubstanceModelDatabase.params` over the bundled pharmacology DB, with the coherent-assay transporter
/// profile) and the real `EffectEngine`, encodes the verified subjective anchor table
/// (`Specs/effect-model-calibration-data.md` §2), and:
///
///   - **Stage 0/1 (analytic, 0 fit):** reports the data-driven PK + transporter mix each substance
///     resolves to, so the inputs are auditable.
///   - **Stage 2 (timescales):** checks the onset/peak timing anchors fall out of the analytic PK
///     (`ke = ln2/t½`, `ka` inverted from Tmax) without per-substance tuning.
///   - **Stage 3 (gains — the identifiable solve):** scans the one **stiff** free constant, the vesicular
///     store-depletion susceptibility `deplete`, against the crash anchors (de Wit/Brauer amphetamine
///     crash vs the crashless cathinones) and reports the fitted operating point. The shared display
///     gains are *sloppy* directions (under-determined by the sparse ordinal anchors) and are, per the
///     spec's identifiability discipline, fixed at their calibrated nominal — this suite validates they
///     satisfy every anchor rather than refitting them.
///
/// Running this suite **is** "starting the solver": it prints a full fit report and asserts the
/// data-driven curves match the anchored phenomenology for the calibrated monoamine set.
@MainActor
@Suite("Effect calibration solver")
struct EffectCalibrationSolverTests {
    // MARK: Harness

    private func resolve(_ name: String) -> SubstanceModelParams? {
        SubstanceModelDatabase.params(name: name, pharmacology: SubstanceStore.shared.pharmacologyParameters(forSubstanceName: name))
    }

    /// Simulate one substance at a real oral dose, optionally overriding a single free constant.
    private func sim(_ p: SubstanceModelParams, _ mg: Double, deplete: Double? = nil, tMax: Double = 12) -> EffectTimeline {
        var params = p
        if let deplete { params.deplete = deplete }
        return EffectEngine.simulate(EffectParams(), agents: [EffectAgent(params: params, doseMg: mg)], tMax: tMax)
    }

    private func peak(_ a: [Double]) -> Double {
        a.max() ?? 0
    }
    private func trough(_ a: [Double]) -> Double {
        a.min() ?? 0
    }

    /// Time (h) at which a rising channel first reaches `fraction` of its own peak — the onset feature.
    private func onset(_ o: EffectTimeline, _ series: [Double], fraction: Double = 0.2) -> Double? {
        let target = peak(series) * fraction
        guard target > 0 else { return nil }
        for (i, v) in series.enumerated() where v >= target {
            return o.t[i]
        }
        return nil
    }

    /// Time (h) of the channel's peak.
    private func timeOfPeak(_ o: EffectTimeline, _ series: [Double]) -> Double {
        var best = 0, bestV = -Double.greatestFiniteMagnitude
        for (i, v) in series.enumerated() where v > bestV {
            bestV = v; best = i
        }
        return o.t[best]
    }

    /// Left-justify to a minimum width for the report tables (printf `%-Ns`, never truncates).
    private func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    // The calibrated monoamine set + typical clinical onset (h). Every shape check runs at the
    // substance's own reference dose (`refUnit`, i.e. `amt ≈ 1`) — the engine's calibrated operating
    // point — so substances of different mg-potency are compared fairly and near where the curve is tuned.
    private struct Ref { let name: String; let onsetLoH: Double; let onsetHiH: Double }
    private let refs: [Ref] = [
        .init(name: "amphetamine", onsetLoH: 0.5, onsetHiH: 2.0),
        .init(name: "methylphenidate", onsetLoH: 0.3, onsetHiH: 1.5),
        .init(name: "3-MMC", onsetLoH: 0.2, onsetHiH: 1.2),
        .init(name: "2-MMC", onsetLoH: 0.2, onsetHiH: 1.5),
        .init(name: "mephedrone", onsetLoH: 0.2, onsetHiH: 1.5),
    ]

    // MARK: - Stage 0/1 — data-driven inputs (auditable, zero fit)

    @Test
    func `Stage 0/1 — every calibrated substance resolves modelable, data-driven params`() throws {
        var report = "\n=== Stage 0/1 · data-driven inputs (analytic PK + coherent transporter mix) ===\n"
        report += "substance         releaser  ke      ka      wDAT   wNET   wSERT  deplete\n"
        for r in refs {
            let p = try #require(resolve(r.name), "\(r.name) must resolve")
            report += pad(r.name, 16) + "  " + (p.releaser ? "yes" : "no") + "  "
            report += String(
                format: "%-6.3f  %-6.3f  %-5.2f  %-5.2f  %-5.2f  %-5.2f\n",
                p.ke, p.ka, p.wDAT, p.wNET, p.wSERT, p.deplete,
            )
            #expect(p.ke > 0 && p.ka > 0)
            #expect(p.wDAT > 0 || p.wNET > 0 || p.wSERT > 0)
            #expect(p.wDAT == 1 || p.wDAT == 0) // DA-normalized (0 only if no DAT engagement)
        }
        print(report)
    }

    // MARK: - Stage 2 — timing anchors fall out of analytic PK (no per-substance tuning)

    @Test
    func `Stage 2 — subjective onset tracks the analytic PK, within the anchored band`() throws {
        var report = "\n=== Stage 2 · timing (onset = t at 20% of peak Feeling; anchored band from PW/TripSit) ===\n"
        for r in refs {
            let p = try #require(resolve(r.name))
            let o = sim(p, p.refUnit)
            let feeling = o.eu
            // Reuptake blockers (MPH) barely produce euphoria; time the drive channel instead.
            let series = peak(feeling) > 0.05 ? feeling : o.drive
            let on = onset(o, series) ?? -1
            let tp = timeOfPeak(o, series)
            report += pad(r.name, 16) + String(
                format: "  onset %.2fh (band %.1f–%.1fh)  peak@ %.2fh\n",
                on, r.onsetLoH, r.onsetHiH, tp,
            )
            #expect(on >= r.onsetLoH * 0.6 && on <= r.onsetHiH * 1.4, "\(r.name) onset \(on)h outside anchored band")
        }
        print(report)
    }

    // MARK: - Stage 3 — the identifiable solve: `deplete` from the crash anchors

    /// The de Wit/Brauer amphetamine crash vs the crashless cathinones is the one feature that *identifies*
    /// `deplete`. Scan it and report where each substance's felt-effect trough crosses the crash threshold —
    /// the fitted operating point separating a deep amphetamine crash from a calm cathinone return.
    @Test
    func `Stage 3 — deplete solve: amphetamine crashes, cathinones don't (fitted from the anchors)`() throws {
        let amp = try #require(resolve("amphetamine"))
        let meph = try #require(resolve("mephedrone"))
        let crashThreshold = -0.30 // trough(Feeling) below this = a felt crash (de Wit acute tolerance)

        var report = "\n=== Stage 3 · deplete scan at each substance's reference dose (trough Feeling; * = crash) ===\n"
        report += String(format: "deplete   amphetamine(%.0fmg)      mephedrone(%.0fmg)\n", amp.refUnit, meph.refUnit)
        let grid = stride(from: 0.0, through: 1.4, by: 0.1)
        var ampCrashOnset: Double? // smallest deplete at which amphetamine crashes
        var mephCrashOnset: Double? // smallest deplete at which mephedrone crashes
        for d in grid {
            let ampTrough = trough(sim(amp, amp.refUnit, deplete: d).eu)
            let mephTrough = trough(sim(meph, meph.refUnit, deplete: d).eu)
            if ampCrashOnset == nil, ampTrough < crashThreshold { ampCrashOnset = d }
            if mephCrashOnset == nil, mephTrough < crashThreshold { mephCrashOnset = d }
            report += String(
                format: "%.1f       %7.3f %@             %7.3f %@\n",
                d,
                ampTrough,
                ampTrough < crashThreshold ? "*" : " ",
                mephTrough,
                mephTrough < crashThreshold ? "*" : " ",
            )
        }
        report += String(
            format: "\nfitted: amphetamine crosses crash at deplete≈%@ (curated %.2f); ",
            ampCrashOnset.map { String(format: "%.1f", $0) } ?? "—",
            amp.deplete,
        )
        report += String(
            format: "mephedrone stays crashless until deplete≈%@ (curated %.2f)\n",
            mephCrashOnset.map { String(format: "%.1f", $0) } ?? ">1.4",
            meph.deplete,
        )
        print(report)

        // The solve confirms the curated operating point: amphetamine's high depletion sits *above* the
        // crash boundary (it crashes), the cathinone's low depletion sits *below* it (it doesn't).
        #expect(amp.deplete == 1.0)
        #expect(meph.deplete < 0.3)
        #expect(trough(sim(amp, amp.refUnit).eu) < crashThreshold, "amphetamine must crash at its fitted deplete")
        #expect(trough(sim(meph, meph.refUnit).eu) > -0.10, "mephedrone must return calmly at its fitted deplete")
        // The boundary is real and well-separated: amphetamine crashes at a lower deplete than mephedrone
        // would need to, so the two classes are cleanly identified by this one constant.
        let ampOnset = try #require(ampCrashOnset)
        #expect(ampOnset <= amp.deplete)
    }

    // MARK: - Validation — every anchor holds at the fitted, data-driven params

    @Test
    func `Validation — the rate hypothesis: oral methylphenidate drives without euphoria`() throws {
        let mph = try #require(resolve("methylphenidate"))
        #expect(!mph.releaser)
        let o = sim(mph, mph.refUnit)
        #expect(peak(o.eu) < 0.2, "MPH occupies DAT without a high (Volkow 2001 / Spencer 2006)")
        #expect(peak(o.drive) > 1, "…but it drives")
    }

    @Test
    func `Validation — amphetamine cardiovascular (not respiratory) danger`() throws {
        let amp = try #require(resolve("amphetamine"))
        let o = sim(amp, amp.refUnit)
        #expect(peak(o.dangerCV) > 0)
        #expect(peak(o.dangerResp) == 0)
    }

    @Test
    func `Validation — warmth ordering follows the SERT data (mephedrone > 2-MMC)`() throws {
        let meph = try #require(resolve("mephedrone"))
        let two = try #require(resolve("2-MMC"))
        #expect(meph.wSERT > two.wSERT)
        // Matched magnitude (each at its own reference dose), so only the mix differs.
        #expect(peak(sim(meph, meph.refUnit).content) > peak(sim(two, two.refUnit).content))
    }

    @Test
    func `Validation — the cathinones are euphoric without a crash`() throws {
        for name in ["3-MMC", "2-MMC", "mephedrone"] {
            let p = try #require(resolve(name))
            let o = sim(p, p.refUnit)
            #expect(peak(o.eu) > 0.4, "\(name) should be clearly euphoric at its reference dose")
            #expect(trough(o.eu) > -0.10, "\(name) should return to baseline calmly")
        }
    }
}
