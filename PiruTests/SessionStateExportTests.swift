import Foundation
import SwiftData
import Testing
@testable import Piru

@MainActor
@Suite("Session state export")
struct SessionStateExportTests {
    /// A live poly-session: a first-order stimulant (methylphenidate), a
    /// first-order xanthine (caffeine), and a zero-order depressant (alcohol),
    /// all dosed recently so they're inside their effect windows.
    private func seedActive() -> [DoseEntry] {
        let now = Date.now
        return [
            DoseEntry(substance: "Methylphenidate", amount: 20, unit: "mg", timestamp: now.addingTimeInterval(-115 * 60)),
            DoseEntry(substance: "Caffeine", amount: 150, unit: "mg", timestamp: now.addingTimeInterval(-40 * 60)),
            DoseEntry(substance: "Alcohol", amount: 28, unit: "g", timestamp: now.addingTimeInterval(-60 * 60)),
        ]
    }

    @Test
    func `Builds a snapshot with subjective + elimination for active doses`() throws {
        let export = try #require(SessionStateExport.build(from: seedActive(), colors: []))
        #expect(!export.isEmpty)
        #expect(export.substances.count >= 2)

        // Every active substance carries a phase and an effect curve.
        for s in export.substances {
            #expect(!s.effectCurve.isEmpty)
            #expect(s.intensity >= 0 && s.intensity <= 1)
            #expect(s.totalMinutes > 0)
        }

        // Alcohol resolves to the zero-order branch; the stimulants to first-order.
        let alcohol = export.eliminations.first { $0.name.lowercased().contains("alcohol") }
        if let alcohol {
            if case .zeroOrder = alcohol.model {} else {
                Issue.record("Alcohol should be zero-order, got \(alcohol.model)")
            }
        }
        let mph = export.eliminations.first { $0.name.lowercased().contains("methylphenidate") }
        if let mph {
            if case .firstOrder = mph.model {} else {
                Issue.record("Methylphenidate should be first-order, got \(mph.model)")
            }
        }
    }

    @Test
    func `Redoses of one substance combine into a single elimination group`() throws {
        let now = Date.now
        let two = [
            DoseEntry(substance: "Alcohol", amount: 2, unit: "units", timestamp: now.addingTimeInterval(-90 * 60)),
            DoseEntry(substance: "Alcohol", amount: 1, unit: "units", timestamp: now.addingTimeInterval(-30 * 60)),
        ]
        let export = try #require(SessionStateExport.build(from: two, colors: []))
        let alcohol = try #require(export.eliminations.first { $0.name.lowercased().contains("alcohol") })
        #expect(export.eliminations.count == 1) // one combined group, not two
        #expect(alcohol.doseCount == 2)
        // "units" must convert to grams and drive the zero-order model, not fall to unknown.
        if case .zeroOrder = alcohol.model {} else {
            Issue.record("Alcohol in units should be zero-order, got \(alcohol.model)")
        }
    }

    @Test
    func `Markdown contains the expected sections`() throws {
        let export = try #require(SessionStateExport.build(from: seedActive(), colors: []))
        let md = export.markdown(locale: Locale(identifier: "en_US"))
        #expect(md.contains("# Piru"))
        #expect(md.contains("Current state"))
        #expect(md.contains("## Elimination"))
        #expect(md.contains("| ")) // a table
    }

    @Test
    func `PDF renders to a non-empty document`() throws {
        let export = try #require(SessionStateExport.build(from: seedActive(), colors: []))
        let data = SessionReportPDF.render(export)
        #expect(data.count > 2_000)
        // A valid PDF starts with "%PDF".
        #expect(data.prefix(4) == Data("%PDF".utf8))
    }

    @Test
    func `Empty input is nil; inactive doses yield a historical (non-live) report`() throws {
        // Nothing to export at all → nil (the current-state entry points gate on this).
        #expect(SessionStateExport.build(from: [], colors: []) == nil)

        // A session with only expired doses is still exportable as a historical
        // report, flagged not-live (no "right now" chrome).
        let old = Date.now.addingTimeInterval(-30 * 24 * 3_600)
        let stale = [DoseEntry(substance: "Caffeine", amount: 100, unit: "mg", timestamp: old)]
        let export = try #require(SessionStateExport.build(from: stale, colors: []))
        #expect(export.isLive == false)
        #expect(!export.substances.isEmpty)
    }
}
