import Foundation
import Testing
@testable import Piru

/// Stereoisomer forms (Stage A): a route can carry a racemic ladder plus one or
/// more resolved-enantiomer ladders (Ketamine + Esketamine + Arketamine), nested
/// as `DoseVariant`s under one `SubstanceRoute` alongside — and orthogonal to —
/// the salt axis. The racemic form is a first-class, named picker option, and
/// `…(for:…:isomer:)` overloads narrow the dose data to a chosen enantiomer.
@MainActor
@Suite("Isomer forms")
struct IsomerFormTests {
    /// A methylphenidate-like isomer family: racemic (mirrored at the top level)
    /// plus a distinct D-enantiomer ladder titled "Dexmethylphenidate".
    private var methylphenidate: Substance {
        let oral = SubstanceRoute(
            route: .oral,
            unit: "mg",
            doses: DoseRange(common: 10 ... 40), // mirrors the racemic default
            saltForms: [
                DoseVariant(isomer: nil, unit: "mg", doses: DoseRange(common: 10 ... 40)),
                DoseVariant(
                    isomer: "D", isomerDisplayName: "Dexmethylphenidate",
                    unit: "mg", doses: DoseRange(common: 5 ... 20),
                ),
            ],
        )
        return Substance(
            name: "Methylphenidate", aliases: [], category: .stimulant,
            defaultRoute: .oral, routes: [oral], effects: [],
        )
    }

    private var caffeine: Substance {
        Substance(
            name: "Caffeine", aliases: [], category: .stimulant, defaultRoute: .oral,
            routes: [SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(common: 50 ... 100))],
            effects: [],
        )
    }

    // MARK: - Model

    @Test
    func `availableIsomers lists resolved enantiomers, excluding racemic`() {
        #expect(methylphenidate.availableIsomers == ["D"])
        #expect(caffeine.availableIsomers.isEmpty)
    }

    @Test
    func `isomerOptions are named, racemic first`() {
        let options = methylphenidate.isomerOptions(for: .oral)
        #expect(options.count == 2)
        #expect(options.first?.code == nil)
        #expect(options.first?.displayName == "Methylphenidate")
        #expect(options.last?.code == "D")
        #expect(options.last?.displayName == "Dexmethylphenidate")
        // A substance with no isomer axis shows no options (picker stays hidden).
        #expect(caffeine.isomerOptions(for: .oral).isEmpty)
    }

    @Test
    func `defaultIsomer prefers the racemic form`() {
        #expect(methylphenidate.defaultIsomer(for: .oral) == nil)
        #expect(caffeine.defaultIsomer(for: .oral) == nil)
    }

    @Test
    func `doseRange narrows to the chosen enantiomer`() {
        #expect(methylphenidate.doseRange(for: .oral, saltForm: nil, isomer: "D")?.common == 5 ... 20)
        // nil isomer resolves the racemic ladder; an unknown one falls back to it.
        #expect(methylphenidate.doseRange(for: .oral, saltForm: nil, isomer: nil)?.common == 10 ... 40)
        #expect(methylphenidate.doseRange(for: .oral, saltForm: nil, isomer: "Z")?.common == 10 ... 40)
    }

    @Test
    func `isomerDisplayName resolves a code to its recognized title`() {
        #expect(methylphenidate.isomerDisplayName(for: "D") == "Dexmethylphenidate")
        #expect(methylphenidate.isomerDisplayName(for: "S") == nil)
    }

    // MARK: - Bundled DB

    @Test
    func `Ketamine loads its enantiomers from the bundled DB`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let ketamine = try #require(store.lookup("Ketamine"))
        let isomers = Set(ketamine.availableIsomers)
        #expect(isomers.contains("S"))
        #expect(isomers.contains("R"))
        // Each enantiomer keeps its recognized name (route-independent), so the
        // picker titles it "Esketamine"/"Arketamine" rather than a bare letter.
        #expect(ketamine.isomerDisplayName(for: "S") == "Esketamine")
        #expect(ketamine.isomerDisplayName(for: "R") == "Arketamine")
    }

    @Test
    func `Methylphenidate folds Dexmethylphenidate as its D form`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mph = try #require(store.lookup("Methylphenidate"))
        #expect(mph.availableIsomers.contains("D"))
        #expect(mph.isomerDisplayName(for: "D") == "Dexmethylphenidate")
    }

    @Test
    func `A single-isomer substance exposes no isomer axis`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let caffeine = try #require(store.lookup("Caffeine"))
        #expect(caffeine.availableIsomers.isEmpty)
        #expect(caffeine.isomerOptions(for: caffeine.defaultRoute).isEmpty)
    }
}
