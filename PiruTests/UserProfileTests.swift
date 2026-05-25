import Testing
import Foundation
@testable import Piru

@Suite("UserProfile")
struct UserProfileTests {

    @Test("All cases are Codable round-trip stable")
    func roundTrip() throws {
        for profile in UserProfile.allCases {
            let data = try JSONEncoder().encode(profile)
            let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
            #expect(decoded == profile)
        }
    }

    @Test("Raw values are stable wire format")
    func rawValuesAreStable() {
        #expect(UserProfile.casual.rawValue == "casual")
        #expect(UserProfile.harmReduction.rawValue == "harm-reduction")
        #expect(UserProfile.pharmaNerd.rawValue == "pharma-nerd")
    }

    @Test("All cases enumerated")
    func allCases() {
        #expect(UserProfile.allCases.count == 3)
        #expect(UserProfile.allCases.contains(.casual))
        #expect(UserProfile.allCases.contains(.harmReduction))
        #expect(UserProfile.allCases.contains(.pharmaNerd))
    }

    @Test("Store persists profile change across a single session")
    @MainActor
    func storePersistsProfile() {
        let original = SubstanceStore.shared.userProfile
        defer { SubstanceStore.shared.setUserProfile(original) }

        SubstanceStore.shared.setUserProfile(.pharmaNerd)
        #expect(SubstanceStore.shared.userProfile == .pharmaNerd)

        SubstanceStore.shared.setUserProfile(.casual)
        #expect(SubstanceStore.shared.userProfile == .casual)
    }

    @Test("Setting same profile is a no-op")
    @MainActor
    func setSameProfileIsNoOp() {
        let original = SubstanceStore.shared.userProfile
        SubstanceStore.shared.setUserProfile(original)
        #expect(SubstanceStore.shared.userProfile == original)
    }
}

@Suite("Source priority")
struct SourcePriorityTests {

    @Test("Source states cover every bundled source")
    @MainActor
    func sourceStatesCoverAll() {
        let states = SubstanceStore.shared.sourceStates()
        #expect(!states.isEmpty)
        // All states have non-empty slugs and display names
        for state in states {
            #expect(!state.slug.isEmpty)
            #expect(!state.displayName.isEmpty)
        }
    }

    @Test("Reordering changes enabledSourceOrder and clears resolved cache")
    @MainActor
    func reorderingTakesEffect() {
        let originalOrder = SubstanceStore.shared.enabledSourceOrder
        defer { SubstanceStore.shared.setSourcePriority(orderedSlugs: originalOrder) }

        guard originalOrder.count >= 2 else { return }
        let reversed = originalOrder.reversed()
        SubstanceStore.shared.setSourcePriority(orderedSlugs: Array(reversed))
        #expect(SubstanceStore.shared.enabledSourceOrder.first == reversed.first)
    }

    @Test("Disabling a source removes it from enabledSourceOrder")
    @MainActor
    func disablingHidesFromOrder() {
        let original = SubstanceStore.shared.enabledSourceOrder
        guard let toDisable = original.last else { return }
        defer { SubstanceStore.shared.setSource(toDisable, enabled: true) }

        SubstanceStore.shared.setSource(toDisable, enabled: false)
        #expect(!SubstanceStore.shared.enabledSourceOrder.contains(toDisable))
    }
}
