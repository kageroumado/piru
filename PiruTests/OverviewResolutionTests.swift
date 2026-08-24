import Foundation
import Testing
@testable import Piru

/// Two testers reported that only one substance's Overview shows per app
/// launch: open Pregabalin first and it renders, then Tramadol has none, then
/// Pregabalin again renders. That shape — first-one-wins, resets on relaunch —
/// is what a single-slot cache looks like from outside.
@Suite("Overview resolution")
@MainActor
struct OverviewResolutionTests {
    @Test
    func `Every substance with a description resolves one, in any order`() {
        // The reported sequence, in one process.
        for name in ["Pregabalin", "Tramadol", "Pregabalin", "Amphetamine", "Tramadol"] {
            let substance = SubstanceLibrary.resolveFull(name)
            #expect(substance != nil, "\(name) missing from the library")
            #expect(
                substance?.overview?.text.isEmpty == false,
                "\(name) resolved no overview on this pass",
            )
        }
    }

    @Test
    func `A repeated lookup returns the same overview it did the first time`() {
        let first = SubstanceLibrary.resolveFull("Tramadol")?.overview?.text
        _ = SubstanceLibrary.resolveFull("Pregabalin")
        _ = SubstanceLibrary.resolveFull("Amphetamine")
        let second = SubstanceLibrary.resolveFull("Tramadol")?.overview?.text
        #expect(first == second, "an intervening lookup changed Tramadol's overview")
        #expect(first?.isEmpty == false)
    }
}

/// A dose ladder with no tiers cannot place a dose.
@Suite("Empty dose ladder")
struct EmptyDoseLadderTests {
    @Test
    func `A ladder with no tiers yields no level`() {
        // The tester's case: a custom substance added with no dose information
        // was labeled "sub-threshold" — a claim about the dose, from an absence
        // of data, and indistinguishable from a real sub-threshold reading.
        let empty = DoseRange(threshold: nil, light: nil, common: nil, strong: nil, heavy: nil)
        #expect(!empty.hasAnyValue)
        #expect(empty.level(for: 0) == nil)
        #expect(empty.level(for: 500) == nil)
    }

    @Test
    func `A ladder with any tier still places a dose`() {
        let ladder = DoseRange(threshold: 5, light: 10 ... 20, common: nil, strong: nil, heavy: nil)
        #expect(ladder.level(for: 1) == .sub)
        #expect(ladder.level(for: 6) == .threshold)
        #expect(ladder.level(for: 15) == .light)
    }
}
