import Foundation
import SwiftUI
import Testing
@testable import Piru

/// The body-load card must call a substance what the dose rows above it call it.
/// It used to re-derive the label from the canonical name alone, so a dose logged
/// as 美金刚 (a Chinese alias in the catalog) or Concerta reappeared underneath as
/// "Memantine" / "Methylphenidate" — the same screen naming one substance two ways.
@Suite("Session body load naming")
@MainActor
struct SessionBodyLoadNamingTests {
    private func entry(
        _ substance: String,
        productName: String? = nil,
        amount: Double = 10,
        minutesAgo: Double = 30,
    ) -> DoseEntry {
        DoseEntry(
            substance: substance, amount: amount, unit: "mg", route: .oral,
            productName: productName,
            timestamp: Date().addingTimeInterval(-minutesAgo * 60),
        )
    }

    private func names(_ entries: [DoseEntry]) -> [String] {
        let model = SessionBodyLoadModel.make(entries: entries, colorMap: [:])
        return model.active.map(\.displayName) + model.cleared.map(\.displayName)
    }

    @Test
    func `A dose logged under an alias keeps that name in the body-load card`() {
        // The zh-Hans report: the dose row said 美金刚, this card said "Memantine".
        #expect(names([entry("Memantine", productName: "美金刚")]).contains("美金刚"))
    }

    @Test
    func `A brand-logged dose keeps its brand`() {
        #expect(names([entry("Methylphenidate", productName: "Concerta")]).contains("Concerta"))
    }

    @Test
    func `A dose logged under the canonical name is unchanged`() {
        #expect(names([entry("Memantine")]).contains("Memantine"))
    }

    @Test
    func `A group mixing products falls back to the canonical name`() {
        // One brand can't title a total that isn't all that brand.
        let resolved = names([
            entry("Methylphenidate", productName: "Concerta"),
            entry("Methylphenidate", productName: "Ritalin"),
        ])
        #expect(resolved.contains("Methylphenidate"))
        #expect(!resolved.contains("Concerta"))
        #expect(!resolved.contains("Ritalin"))
    }

    @Test
    func `A group where only some doses name a product falls back too`() {
        let resolved = names([
            entry("Methylphenidate", productName: "Concerta"),
            entry("Methylphenidate"),
        ])
        #expect(resolved.contains("Methylphenidate"))
        #expect(!resolved.contains("Concerta"))
    }

    @Test
    func `Doses that agree on one product keep it across a redose`() {
        let resolved = names([
            entry("Memantine", productName: "美金刚", minutesAgo: 90),
            entry("Memantine", productName: "美金刚", minutesAgo: 30),
        ])
        #expect(resolved.contains("美金刚"))
    }
}
