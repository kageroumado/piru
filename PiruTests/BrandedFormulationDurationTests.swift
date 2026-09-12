import Foundation
import Testing
@testable import Piru

/// The Branded formulations section's data gate: a substance surfaces the picker
/// only when at least one of its branded products carries an authored
/// duration envelope (`product_durations`). Mirrors ``DoseDurationSection``'s
/// `brandedDurations` — uid → `brandProducts` → `productDuration` filter — against
/// the real bundled DB.
@MainActor
@Suite("Branded formulation durations")
struct BrandedFormulationDurationTests {
    /// Products of `name` that carry a duration envelope, resolved the way the
    /// detail section resolves them.
    private func brandedDurations(_ store: SubstanceStore, _ name: String) throws -> [String] {
        let uid = try #require(store.substanceUID(forNameOrAlias: name), "\(name) should resolve a FAMILY")
        return store.brandProducts(forUID: uid).compactMap { brand in
            store.productDuration(forProduct: brand.name) != nil ? brand.name : nil
        }
    }

    @Test
    func `Methylphenidate and Amphetamine expose branded duration envelopes`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { tearDownIsolatedSubstanceStore(store, tempDir: tempDir) }

        let mph = try brandedDurations(store, "Methylphenidate")
        #expect(!mph.isEmpty, "Methylphenidate should surface branded durations")
        #expect(
            mph.contains { $0.caseInsensitiveCompare("Concerta") == .orderedSame },
            "Concerta's manufacturer envelope is one of them",
        )

        let amph = try brandedDurations(store, "Amphetamine")
        #expect(!amph.isEmpty, "Amphetamine should surface branded durations")
        #expect(
            amph.contains { $0.caseInsensitiveCompare("Adderall XR") == .orderedSame },
            "Adderall XR's envelope is one of them",
        )
    }

    @Test
    func `A plain substance exposes no branded durations`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { tearDownIsolatedSubstanceStore(store, tempDir: tempDir) }

        #expect(try brandedDurations(store, "Caffeine").isEmpty, "Caffeine has no branded envelope")
    }
}
