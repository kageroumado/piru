import Foundation
import Testing
@testable import Piru

@Suite("[SubstanceColor].takenColorMap")
struct TakenColorMapTests {
    @Test
    func `Duplicate hex assignments don't crash (build-11 regression)`() {
        // The old code used `Dictionary(uniqueKeysWithValues:)` and crashed
        // when two substances shared a color — see
        // testflight_feedback/crashlog.crash (build 11).
        let colors = [
            SubstanceColor(substance: "Aspirin", hexColor: "FF0000"),
            SubstanceColor(substance: "Ibuprofen", hexColor: "FF0000"),
            SubstanceColor(substance: "Caffeine", hexColor: "00FF00"),
        ]
        let map = colors.takenColorMap
        #expect(map.count == 2)
        #expect(map["FF0000"] != nil)
        #expect(map["00FF00"] == "Caffeine")
    }

    @Test
    func `Empty array returns empty map`() {
        let colors: [SubstanceColor] = []
        #expect(colors.takenColorMap.isEmpty)
    }
}

@Suite("PresetColor")
struct PresetColorTests {
    @Test
    func `All presets have non-empty hex`() {
        for preset in PresetColor.all {
            #expect(!preset.hex.isEmpty, "\(preset.name) should have a hex value")
        }
    }

    @Test
    func `All presets have non-empty name`() {
        for preset in PresetColor.all {
            #expect(!preset.name.isEmpty, "Preset with hex \(preset.hex) should have a name")
        }
    }

    @Test
    func `All hex values are 6 characters`() {
        for preset in PresetColor.all {
            #expect(preset.hex.count == 6, "\(preset.name) hex should be 6 chars but is \(preset.hex.count)")
        }
    }

    @Test
    func `All hex values are valid hex strings`() {
        let hexChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        for preset in PresetColor.all {
            let isValid = preset.hex.unicodeScalars.allSatisfy { hexChars.contains($0) }
            #expect(isValid, "\(preset.name) has invalid hex: \(preset.hex)")
        }
    }

    @Test
    func `Preset IDs are hex values`() {
        for preset in PresetColor.all {
            #expect(preset.id == preset.hex)
        }
    }

    @Test
    func `Has a reasonable number of presets`() {
        #expect(PresetColor.all.count >= 30)
    }

    @Test
    func `Includes expected color families`() {
        let names = Set(PresetColor.all.map(\.name))
        // Should have at least some of these base families
        #expect(names.contains("Green"))
        #expect(names.contains("Teal"))
    }
}

@Suite("PresetColor.deterministic")
struct DeterministicColorTests {
    /// Pinned expected hexes. If the palette or hash function changes, these
    /// fail — a deliberate tripwire, because changing them silently re-colours
    /// every unassigned substance in everyone's journal.
    @Test
    func `Same name maps to the same colour every call`() {
        for name in ["Amphetamine", "Metformin", "2C-E", "Lisinopril", "Caffeine"] {
            let first = PresetColor.deterministic(for: name)
            for _ in 0 ..< 100 {
                #expect(PresetColor.deterministic(for: name) == first)
            }
        }
    }

    @Test
    func `Result is a member of the palette`() {
        for name in ["Amphetamine", "Metformin", "Psilocybin", "x"] {
            #expect(PresetColor.all.contains(PresetColor.deterministic(for: name)))
        }
    }

    @Test
    func `Lookup is case-insensitive`() {
        #expect(PresetColor.deterministic(for: "Amphetamine") == PresetColor.deterministic(for: "amphetamine"))
        #expect(PresetColor.deterministic(for: "2C-E") == PresetColor.deterministic(for: "2c-e"))
    }

    @Test
    func `Pinned hashes stay stable (regression tripwire)`() {
        // Hard-coded expected hexes so a switch to the per-launch-random
        // String.hashValue, or a palette reorder, is caught immediately rather
        // than silently re-colouring every unassigned substance in everyone's
        // journal. Update deliberately only if the palette intentionally changes.
        let expected: [String: String] = [
            "amphetamine": "3fcabc",
            "metformin": "00add3",
            "2c-e": "bb9900",
            "lisinopril": "eda963",
        ]
        for (name, hex) in expected {
            #expect(PresetColor.deterministic(for: name).hex == hex, "\(name) should map to \(hex)")
        }
    }

    @Test
    func `Spreads across the palette (not all one colour)`() {
        let names = (0 ..< 200).map { "substance-\($0)" }
        let distinct = Set(names.map { PresetColor.deterministic(for: $0).hex })
        // With 48 presets and 200 names we should hit a healthy spread, not
        // collapse onto a single fallback the way the old code did.
        #expect(distinct.count >= 20)
    }
}
