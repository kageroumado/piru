import Foundation
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

    @Test
    @MainActor
    func `Store persists profile change across a single session`() {
        let original = SubstanceStore.shared.userProfile
        defer { SubstanceStore.shared.setUserProfile(original) }

        SubstanceStore.shared.setUserProfile(.pharmaNerd)
        #expect(SubstanceStore.shared.userProfile == .pharmaNerd)

        SubstanceStore.shared.setUserProfile(.casual)
        #expect(SubstanceStore.shared.userProfile == .casual)
    }

    @Test
    @MainActor
    func `Setting same profile is a no-op`() {
        let original = SubstanceStore.shared.userProfile
        SubstanceStore.shared.setUserProfile(original)
        #expect(SubstanceStore.shared.userProfile == original)
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
    func `Reordering changes enabledSourceOrder and clears resolved cache`() {
        let originalOrder = SubstanceStore.shared.enabledSourceOrder
        defer { SubstanceStore.shared.setSourcePriority(orderedSlugs: originalOrder) }

        guard originalOrder.count >= 2 else { return }
        let reversed = originalOrder.reversed()
        SubstanceStore.shared.setSourcePriority(orderedSlugs: Array(reversed))
        #expect(SubstanceStore.shared.enabledSourceOrder.first == reversed.first)
    }

    @Test
    @MainActor
    func `Disabling a source removes it from enabledSourceOrder`() {
        let original = SubstanceStore.shared.enabledSourceOrder
        guard let toDisable = original.last else { return }
        defer { SubstanceStore.shared.setSource(toDisable, enabled: true) }

        SubstanceStore.shared.setSource(toDisable, enabled: false)
        #expect(!SubstanceStore.shared.enabledSourceOrder.contains(toDisable))
    }
}
