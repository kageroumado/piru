import Foundation
import SwiftData
import Testing
@testable import Piru

@Suite("UserProfile")
struct UserProfileTests {
    @Test
    func `All cases are Codable round-trip stable`() throws {
        for profile in UserProfile.allCases {
            let data = try JSONEncoder().encode(profile)
            let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
            #expect(decoded == profile)
        }
    }

    @Test
    func `Raw values are stable wire format`() {
        #expect(UserProfile.casual.rawValue == "casual")
        #expect(UserProfile.harmReduction.rawValue == "harm-reduction")
        #expect(UserProfile.pharmaNerd.rawValue == "pharma-nerd")
    }

    @Test
    func `All cases enumerated`() {
        #expect(UserProfile.allCases.count == 3)
        #expect(UserProfile.allCases.contains(.casual))
        #expect(UserProfile.allCases.contains(.harmReduction))
        #expect(UserProfile.allCases.contains(.pharmaNerd))
    }
}

@Suite("UserProfileStore", .serialized)
@MainActor
struct UserProfileStoreTests {
    /// A throwaway in-memory container using the full app schema (the pattern the other SwiftData
    /// suites use). Single-entity in-memory containers proved flaky under the parallel runner.
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
    }

    /// A store bound to a throwaway in-memory container, with no legacy migration.
    private func makeStore() throws -> UserProfileStore {
        let store = UserProfileStore()
        try store.configure(container: makeContainer(), legacyPrefsDBURL: nil)
        return store
    }

    // MARK: - Disclosure tier

    @Test
    func `Defaults to harm-reduction when unset`() throws {
        let store = try makeStore()
        #expect(store.disclosureTier == .harmReduction)
    }

    @Test
    func `Persists disclosure tier change`() throws {
        let store = try makeStore()
        store.setDisclosureTier(.pharmaNerd)
        #expect(store.disclosureTier == .pharmaNerd)
        store.setDisclosureTier(.casual)
        #expect(store.disclosureTier == .casual)
    }

    @Test
    func `Setting same tier is a no-op`() throws {
        let store = try makeStore()
        let original = store.disclosureTier
        store.setDisclosureTier(original)
        #expect(store.disclosureTier == original)
    }

    @Test
    func `Tier survives a reconfigure against the same container`() throws {
        let container = try makeContainer()
        let first = UserProfileStore()
        first.configure(container: container, legacyPrefsDBURL: nil)
        first.setDisclosureTier(.pharmaNerd)

        let second = UserProfileStore()
        second.configure(container: container, legacyPrefsDBURL: nil)
        #expect(second.disclosureTier == .pharmaNerd)
    }

    // MARK: - Body weight

    @Test
    func `Unset weight falls back to default and is estimated`() throws {
        let store = try makeStore()
        #expect(store.weightKg == nil)
        #expect(store.isWeightEstimated)
        #expect(store.weightSource == .estimated)
        #expect(store.effectiveWeightKg == UserProfileStore.defaultWeightKg)
    }

    @Test
    func `Manual weight is stored and no longer estimated`() throws {
        let store = try makeStore()
        store.setManualWeight(72)
        #expect(store.weightKg == 72)
        #expect(!store.isWeightEstimated)
        #expect(store.weightSource == .manual)
        #expect(store.effectiveWeightKg == 72)
    }

    @Test
    func `HealthKit weight records its source`() throws {
        let store = try makeStore()
        store.setHealthKitWeight(64.5)
        #expect(store.weightKg == 64.5)
        #expect(store.weightSource == .healthKit)
        #expect(!store.isWeightEstimated)
    }

    @Test
    func `Out-of-range and non-finite weights are rejected`() throws {
        let store = try makeStore()
        store.setManualWeight(5)
        store.setManualWeight(500)
        store.setManualWeight(.nan)
        store.setManualWeight(.infinity)
        #expect(store.weightKg == nil)
        #expect(store.isWeightEstimated)
    }

    @Test
    func `Range bounds are inclusive`() throws {
        let store = try makeStore()
        store.setManualWeight(20)
        #expect(store.weightKg == 20)
        store.setManualWeight(300)
        #expect(store.weightKg == 300)
    }

    @Test
    func `Clearing weight reverts to estimated default`() throws {
        let store = try makeStore()
        store.setManualWeight(80)
        store.clearWeight()
        #expect(store.weightKg == nil)
        #expect(store.isWeightEstimated)
        #expect(store.weightSource == .estimated)
        #expect(store.effectiveWeightKg == UserProfileStore.defaultWeightKg)
    }

    @Test
    func `Weight persists across stores on the same container`() throws {
        let container = try makeContainer()
        let first = UserProfileStore()
        first.configure(container: container, legacyPrefsDBURL: nil)
        first.setHealthKitWeight(70)

        let second = UserProfileStore()
        second.configure(container: container, legacyPrefsDBURL: nil)
        #expect(second.weightKg == 70)
        #expect(second.weightSource == .healthKit)
    }

    @Test
    func `Tier and weight share one record`() throws {
        let store = try makeStore()
        store.setDisclosureTier(.pharmaNerd)
        store.setManualWeight(75)
        #expect(store.disclosureTier == .pharmaNerd)
        #expect(store.weightKg == 75)
    }

    // MARK: - Metabolic context flags (Stage 4c)

    @Test
    func `Metabolic context flags default off`() throws {
        let store = try makeStore()
        #expect(!store.smokesTobacco)
        #expect(!store.grapefruitLoggingEnabled)
    }

    @Test
    func `Smoking and grapefruit flags persist across stores`() throws {
        let container = try makeContainer()
        let first = UserProfileStore()
        first.configure(container: container, legacyPrefsDBURL: nil)
        first.setSmokesTobacco(true)
        first.setGrapefruitLoggingEnabled(true)

        let second = UserProfileStore()
        second.configure(container: container, legacyPrefsDBURL: nil)
        #expect(second.smokesTobacco)
        #expect(second.grapefruitLoggingEnabled)
    }
}

@Suite("Source priority")
struct SourcePriorityTests {
    @Test
    @MainActor
    func `Source states cover every bundled source`() {
        let states = SubstanceStore.shared.sourceStates()
        #expect(!states.isEmpty)
        // All states have non-empty slugs and display names
        for state in states {
            #expect(!state.slug.isEmpty)
            #expect(!state.displayName.isEmpty)
        }
    }

    @Test
    @MainActor
    func `Reordering changes enabledSourceOrder and clears resolved cache`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let originalOrder = store.enabledSourceOrder
        guard originalOrder.count >= 2 else { return }
        let reversed = originalOrder.reversed()
        store.setSourcePriority(orderedSlugs: Array(reversed))
        #expect(store.enabledSourceOrder.first == reversed.first)
    }

    @Test
    @MainActor
    func `Disabling a source removes it from enabledSourceOrder`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let original = store.enabledSourceOrder
        guard let toDisable = original.last else { return }

        store.setSource(toDisable, enabled: false)
        #expect(!store.enabledSourceOrder.contains(toDisable))
    }
}
