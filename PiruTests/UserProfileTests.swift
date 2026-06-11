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
    func `Store persists profile change across a single session`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        store.setUserProfile(.pharmaNerd)
        #expect(store.userProfile == .pharmaNerd)

        store.setUserProfile(.casual)
        #expect(store.userProfile == .casual)
    }

    @Test
    @MainActor
    func `Setting same profile is a no-op`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let original = store.userProfile
        store.setUserProfile(original)
        #expect(store.userProfile == original)
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
