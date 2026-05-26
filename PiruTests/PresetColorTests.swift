import Testing
import Foundation
@testable import Piru

@Suite("[SubstanceColor].takenColorMap")
struct TakenColorMapTests {

    @Test("Duplicate hex assignments don't crash (build-11 regression)")
    func duplicateHexDoesNotCrash() {
        // The old code used `Dictionary(uniqueKeysWithValues:)` and crashed
        // when two substances shared a color — see
        // testflight_feedback/crashlog.crash (build 11).
        let colors = [
            SubstanceColor(substance: "Aspirin",   hexColor: "FF0000"),
            SubstanceColor(substance: "Ibuprofen", hexColor: "FF0000"),
            SubstanceColor(substance: "Caffeine",  hexColor: "00FF00"),
        ]
        let map = colors.takenColorMap
        #expect(map.count == 2)
        #expect(map["FF0000"] != nil)
        #expect(map["00FF00"] == "Caffeine")
    }

    @Test("Empty array returns empty map")
    func emptyArray() {
        let colors: [SubstanceColor] = []
        #expect(colors.takenColorMap.isEmpty)
    }
}

@Suite("PresetColor")
struct PresetColorTests {

    @Test("All presets have non-empty hex")
    func allHaveHex() {
        for preset in PresetColor.all {
            #expect(!preset.hex.isEmpty, "\(preset.name) should have a hex value")
        }
    }

    @Test("All presets have non-empty name")
    func allHaveName() {
        for preset in PresetColor.all {
            #expect(!preset.name.isEmpty, "Preset with hex \(preset.hex) should have a name")
        }
    }

    @Test("All hex values are 6 characters")
    func allHexAre6Chars() {
        for preset in PresetColor.all {
            #expect(preset.hex.count == 6, "\(preset.name) hex should be 6 chars but is \(preset.hex.count)")
        }
    }

    @Test("All hex values are valid hex strings")
    func allHexValid() {
        let hexChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        for preset in PresetColor.all {
            let isValid = preset.hex.unicodeScalars.allSatisfy { hexChars.contains($0) }
            #expect(isValid, "\(preset.name) has invalid hex: \(preset.hex)")
        }
    }

    @Test("Preset IDs are hex values")
    func idIsHex() {
        for preset in PresetColor.all {
            #expect(preset.id == preset.hex)
        }
    }

    @Test("Has a reasonable number of presets")
    func presetCount() {
        #expect(PresetColor.all.count >= 30)
    }

    @Test("Includes expected color families")
    func hasColorFamilies() {
        let names = Set(PresetColor.all.map(\.name))
        // Should have at least some of these base families
        #expect(names.contains("Green"))
        #expect(names.contains("Teal"))
    }
}
