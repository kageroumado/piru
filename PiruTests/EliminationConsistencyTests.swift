import Foundation
import Testing
@testable import Piru

/// Cross-checks the elimination sources the app resolves against each other: the bundled DB's
/// `Substance.halfLifeMinutes`, the PK-derived `PharmacologyParameters.halfLifeMinutes`, and the
/// felt-effect `ke` patches in `SubstanceModelDatabase` (stored per-hour, exposed here only through
/// the minutes-typed `curatedHalfLifeMinutes(for:)` boundary).
///
/// This is the *resolver-side* mirror of `pipeline/audit/pk_sanity.py`, which compares the same two
/// tables in SQL. Both are worth having: the pipeline gate catches a bad row, this one catches a
/// resolver that reaches a different row than the SQL does.
///
/// The gate is **2.0×**, because published population half-lives routinely span that across studies
/// and anything tighter is a report rather than a gate. What 2× reliably catches is the failure modes
/// that matter: a unit error (a per-hour value read as per-minute shows up as 60×), a
/// metabolite/depot/prodrug value filed under the parent, and plain data bugs. Known-legitimate
/// disagreements live in `data/curated/elimination-consistency-allowlist.json`, each with a mandatory
/// prose note; a waiver that stops tripping fails the suite so the allowlist can't rot.
@Suite("Elimination consistency")
struct EliminationConsistencyTests {
    static let gateRatio = 2.0

    // MARK: - Allowlist

    struct Waiver: Hashable {
        /// Folded substance key (`PharmacologyNameKey.fold` form).
        let name: String
        /// Which comparison the waiver covers: `halflife-pk` (resolved DB t½ vs PK-derived t½) or
        /// `override` (felt-effect ke patch vs either measured source).
        let pair: String
        let note: String
    }

    enum AllowlistError: Error, CustomStringConvertible {
        case unreadable(String)
        case malformed(String)

        var description: String {
            switch self {
            case let .unreadable(detail): "allowlist unreadable: \(detail)"
            case let .malformed(detail): "allowlist entry malformed: \(detail)"
            }
        }
    }

    /// Loads the allowlist; a missing/empty `note` is a parse failure by
    /// design — a waiver without a reason is indistinguishable from a rubber
    /// stamp.
    static func loadAllowlist() throws -> [Waiver] {
        let url = repoRoot().appendingPathComponent("data/curated/elimination-consistency-allowlist.json")
        guard let data = try? Data(contentsOf: url) else {
            throw AllowlistError.unreadable(url.path)
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = obj["entries"] as? [[String: Any]] else {
            throw AllowlistError.malformed("top level must be {_note, entries: [...]}")
        }
        return try entries.map { entry in
            guard let name = entry["name"] as? String,
                  let pair = entry["pair"] as? String,
                  ["halflife-db", "halflife-pk", "override"].contains(pair),
                  let note = entry["note"] as? String,
                  !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw AllowlistError.malformed("\(entry) — needs name, a valid pair, and a non-empty note")
            }
            return Waiver(name: name, pair: pair, note: note)
        }
    }

    // MARK: - Measurement

    struct Violation: CustomStringConvertible {
        let pair: String
        let name: String
        let a: Double
        let b: Double

        var ratio: Double {
            max(a, b) / min(a, b)
        }

        var description: String {
            "\(pair) \(name): \(a) vs \(b) min (\(String(format: "%.2f", ratio))x)"
        }
    }

    /// Every cross-source disagreement above the gate ratio. One pass, shared
    /// by the gate tests and the stale-waiver test so they cannot diverge.
    @MainActor
    static func measuredViolations() async -> [Violation] {
        await SubstanceStore.shared.ensureAllLoaded()
        var violations: [Violation] = []

        func check(_ pair: String, _ name: String, _ a: Double, _ b: Double) {
            guard a > 0, b > 0 else { return }
            if max(a, b) / min(a, b) > gateRatio {
                violations.append(Violation(pair: pair, name: name, a: a, b: b))
            }
        }

        for substance in SubstanceStore.shared.all {
            guard let resolved = substance.halfLifeMinutes,
                  let pk = SubstanceStore.shared
                  .pharmacologyParameters(forSubstanceName: substance.name).halfLifeMinutes
            else { continue }
            check("halflife-pk", PharmacologyNameKey.fold(substance.name), resolved, pk)
        }

        for name in SubstanceModelDatabase.curatedOverrideNames {
            guard let felt = SubstanceModelDatabase.curatedHalfLifeMinutes(for: name) else { continue }
            if let substance = SubstanceLibrary.lookup(name) {
                if let resolved = substance.halfLifeMinutes {
                    check("override", name, felt, resolved)
                }
                if let pk = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: name).halfLifeMinutes {
                    check("override", name, felt, pk)
                }
            }
        }

        return violations
    }

    // MARK: - Gates

    @Test
    @MainActor
    func `The resolved half-life agrees with the PK-derived one within 2x`() async throws {
        let waived = try Set(Self.loadAllowlist().map { "\($0.pair)|\($0.name)" })
        let violations = await Self.measuredViolations()
            .filter { $0.pair != "override" }
            .filter { !waived.contains("\($0.pair)|\($0.name)") }
        #expect(violations.isEmpty, "unwaived elimination disagreements:\n\(violations.map(\.description).joined(separator: "\n"))")
    }

    @Test
    @MainActor
    func `Effect-model override ke agrees with the measured half-life within 2x`() async throws {
        let waived = try Set(Self.loadAllowlist().map { "\($0.pair)|\($0.name)" })
        let violations = await Self.measuredViolations()
            .filter { $0.pair == "override" }
            .filter { !waived.contains("\($0.pair)|\($0.name)") }
        #expect(violations.isEmpty, "unwaived override disagreements:\n\(violations.map(\.description).joined(separator: "\n"))")
    }

    /// A waiver that no longer trips the gate has outlived its reason and must
    /// be deleted, or it will silently cover a future, different regression.
    @Test
    @MainActor
    func `Allowlist has no stale entries`() async throws {
        let tripping = await Set(Self.measuredViolations().map { "\($0.pair)|\($0.name)" })
        let stale = try Self.loadAllowlist().filter { !tripping.contains("\($0.pair)|\($0.name)") }
        #expect(stale.isEmpty, "waivers no longer tripping — delete them: \(stale.map { "\($0.pair)/\($0.name)" })")
    }

    /// `Overrides.ke` is per-HOUR. This literal only holds under that unit —
    /// heroin's patch is ln2/2.5 per hour, i.e. a 2.5 h felt half-life. If the
    /// stored unit ever changes, this fails loudly instead of every curve
    /// silently going 60× wrong.
    @Test
    func `Override ke unit boundary converts per-hour to minutes`() {
        #expect(SubstanceModelDatabase.curatedHalfLifeMinutes(for: "heroin") == 150)
        #expect(SubstanceModelDatabase.curatedHalfLifeMinutes(for: "morphine") == nil)
    }

    /// Opt-in dump for reseeding the allowlist after a deliberate data change:
    /// `PIRU_ELIM_DUMP=1` writes every current violation to
    /// `Audits/elimination-violations.json`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PIRU_ELIM_DUMP"] != nil))
    @MainActor
    func `Dump current violations`() async throws {
        let violations = await Self.measuredViolations()
        let rows = violations
            .sorted { $0.ratio > $1.ratio }
            .map { ["name": $0.name, "pair": $0.pair, "observedRatio": Double(String(format: "%.2f", $0.ratio))!, "note": ""] as [String: Any] }
        let dir = Self.repoRoot().appendingPathComponent("Audits", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("elimination-violations.json")
        let data = try JSONSerialization.data(withJSONObject: ["entries": rows], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
        print("ELIM DUMP → \(url.path) (\(rows.count) violations)")
    }

    /// `<repo>/PiruTests/EliminationConsistencyTests.swift` → `<repo>`.
    private static func repoRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
