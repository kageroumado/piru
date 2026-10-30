import Foundation
import Testing
@testable import Piru

/// The quick-log tray checks a staged dose against what is already in the
/// body, states only the dangerous pairs, and names the logged dose each one
/// is with — the tray cannot show the journal.
@MainActor
@Suite("Tray Interaction Check")
struct TrayInteractionCheckTests {
    init() async {
        await SubstanceStore.shared.ensureAllLoaded()
    }

    /// A dose in the substance's own unit: 20 of alcohol is 20 g, not 20 mg.
    private func entry(_ name: String, amount: Double, hoursAgo: Double) -> DoseEntry {
        DoseEntry(
            substance: name,
            amount: amount,
            unit: SubstanceLibrary.lookup(name)?.defaultUnit ?? "mg",
            route: .oral,
            timestamp: Date.now.addingTimeInterval(-hoursAgo * 3_600),
        )
    }

    @Test
    func `a staged benzo against active alcohol names the alcohol dose`() throws {
        let alcohol = entry("Alcohol", amount: 20, hoursAgo: 1)
        let warnings = TrayInteractionCheck.warnings(staged: ["Alprazolam"], history: [alcohol], at: .now)

        #expect(warnings.count == 1)
        let warning = try #require(warnings.first)
        #expect(warning.severity == .dangerous)
        let counterpart = try #require(warning.counterpart)
        #expect(counterpart.entryID == alcohol.id)
        #expect(counterpart.amount == 20)
        #expect(counterpart.unit == alcohol.unit)
        #expect(counterpart.timestamp == alcohol.timestamp)
        #expect(counterpart.trayLine.contains("20"))
        #expect(counterpart.trayLine.contains(counterpart.title))
        #expect(counterpart.trayLine.contains("1h"))
    }

    @Test
    func `a staged dose against an active unsafe or caution pair stays out of the tray`() {
        // Ketamine + alcohol is `unsafe`, an orexin antagonist + alcohol is
        // `caution`: both real, neither shown against a logged dose here.
        #expect(InteractionChecker.drugClasses(for: "Ketamine").contains(.dissociative))
        let alcohol = entry("Alcohol", amount: 20, hoursAgo: 0.5)
        let engine = InteractionChecker.checkBatch(["Ketamine", "Lemborexant"], against: [alcohol])
        #expect(engine.contains { $0.counterpart != nil && $0.severity == .unsafe })
        #expect(engine.contains { $0.counterpart != nil && $0.severity == .caution })

        for name in ["Ketamine", "Lemborexant"] {
            let warnings = TrayInteractionCheck.warnings(staged: [name], history: [alcohol], at: .now)
            #expect(warnings.isEmpty, "\(name) against logged alcohol must not show in the tray")
        }
    }

    @Test
    func `doses staged together keep the notable floor`() {
        // The same unsafe pair, staged together, is still stated.
        let warnings = TrayInteractionCheck.warnings(staged: ["Ketamine", "Alcohol"], history: [], at: .now)
        #expect(warnings.contains { $0.severity == .unsafe && $0.counterpart == nil })
    }

    @Test
    func `a trivially small active dose is still suppressed`() {
        let alcohol = entry("Alcohol", amount: 0.001, hoursAgo: 0.5)
        let warnings = TrayInteractionCheck.warnings(staged: ["Alprazolam"], history: [alcohol], at: .now)
        #expect(warnings.isEmpty, "The checker's dose gate decides; the tray must not bypass it")
    }

    @Test
    func `a dose filed 10 h ago is checked against what was active then`() throws {
        // Alcohol drunk 11 h ago is long gone now, and was an hour in at the
        // time the benzo is being filed for.
        let alcohol = entry("Alcohol", amount: 20, hoursAgo: 11)
        let tenHoursAgo = Date.now.addingTimeInterval(-10 * 3_600)

        let now = TrayInteractionCheck.warnings(staged: ["Alprazolam"], history: [alcohol], at: .now)
        #expect(now.isEmpty)

        let then = TrayInteractionCheck.warnings(staged: ["Alprazolam"], history: [alcohol], at: tenHoursAgo)
        let warning = try #require(then.first)
        #expect(warning.severity == .dangerous)
        #expect(warning.counterpart?.entryID == alcohol.id)
    }
}
