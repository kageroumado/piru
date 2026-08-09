import Foundation
import Testing
@testable import Piru

/// Per-product duration envelopes: an extended-release brand draws a curve of the
/// labeled length instead of its parent's immediate-release curve (or nothing).
@Suite("Product durations")
@MainActor
struct ProductDurationTests {
    @Test
    func `Concerta has an authored ~12h envelope`() {
        let dur = SubstanceLibrary.productDuration(for: "Concerta")
        #expect(dur != nil)
        // ~11–12 h total (660–720 min), far past methylphenidate IR's ~3–5 h.
        #expect((dur?.total?.max ?? 0) >= 660)
    }

    @Test
    func `Case and whitespace do not matter`() {
        #expect(SubstanceLibrary.productDuration(for: "  adderall xr ") != nil)
    }

    @Test
    func `A bare or IR product has no override`() {
        // "Ritalin" is the IR base — it draws the parent curve, not a product one.
        #expect(SubstanceLibrary.productDuration(for: "Ritalin") == nil)
        #expect(SubstanceLibrary.productDuration(for: "Tylenol") == nil)
    }

    @Test
    func `A Concerta dose draws its own extended curve`() {
        let entry = DoseEntry(
            substance: "Methylphenidate", amount: 36, unit: "mg", route: .oral,
            releaseForm: "XR", productName: "Concerta",
        )
        #expect(!entry.drawsNoAcuteCurve, "a modeled product is not 'unmodeled'")
        let state = ActiveSubstanceState.from(entry: entry, colorHex: "000000")
        #expect(state != nil, "Concerta must draw a curve, not a bare marker")
        #expect((state?.totalMinutes ?? 0) >= 600, "the curve runs ~11–12 h, not Ritalin's ~4 h")
    }

    @Test
    func `An XR with no known product stays a marker`() {
        // Release form XR but no product name — we can't tell Concerta from Ritalin
        // LA, so we honestly draw nothing rather than guess a duration.
        let entry = DoseEntry(
            substance: "Methylphenidate", amount: 36, unit: "mg", route: .oral,
            releaseForm: "XR",
        )
        #expect(entry.drawsNoAcuteCurve)
        #expect(ActiveSubstanceState.from(entry: entry, colorHex: "000000") == nil)
    }

    @Test
    func `Adderall XR draws its own long curve`() {
        let entry = DoseEntry(
            substance: "Amphetamine", amount: 20, unit: "mg", route: .oral,
            releaseForm: "XR", productName: "Adderall XR",
        )
        let state = ActiveSubstanceState.from(entry: entry, colorHex: "000000")
        #expect(state != nil)
        #expect((state?.totalMinutes ?? 0) >= 600)
    }
}
