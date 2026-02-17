import Foundation
import SwiftData
import SwiftUI

@Model
final class SubstanceColor {
    @Attribute(.unique) var substance: String
    var hexColor: String

    init(substance: String, hexColor: String) {
        self.substance = substance
        self.hexColor = hexColor
    }

    var color: Color {
        Color(hex: hexColor)
    }
}

// MARK: - Preset Colors

struct PresetColor: Identifiable, Hashable {
    let hex: String
    let name: String

    var id: String { hex }
    var color: Color { Color(hex: hex) }

    // 64 colors: 8 hue families × 8 shades each
    static let all: [PresetColor] = [
        // Reds
        PresetColor(hex: "FF3B30", name: "Red"),
        PresetColor(hex: "FF6B6B", name: "Coral"),
        PresetColor(hex: "D32F2F", name: "Crimson"),
        PresetColor(hex: "FF8A80", name: "Salmon"),
        PresetColor(hex: "C62828", name: "Scarlet"),
        PresetColor(hex: "E57373", name: "Rose Red"),
        PresetColor(hex: "B71C1C", name: "Maroon"),
        PresetColor(hex: "EF9A9A", name: "Blush Red"),

        // Oranges
        PresetColor(hex: "FF9500", name: "Orange"),
        PresetColor(hex: "FFBF00", name: "Amber"),
        PresetColor(hex: "FF6D00", name: "Tangerine"),
        PresetColor(hex: "FFAB40", name: "Apricot"),
        PresetColor(hex: "E65100", name: "Burnt Orange"),
        PresetColor(hex: "FFCC80", name: "Peach"),
        PresetColor(hex: "FF7043", name: "Papaya"),
        PresetColor(hex: "BF360C", name: "Rust"),

        // Yellows
        PresetColor(hex: "FFCC00", name: "Yellow"),
        PresetColor(hex: "FFD600", name: "Gold"),
        PresetColor(hex: "FDD835", name: "Sunflower"),
        PresetColor(hex: "F9A825", name: "Honey"),
        PresetColor(hex: "FFF176", name: "Lemon"),
        PresetColor(hex: "FFE082", name: "Butter"),
        PresetColor(hex: "F57F17", name: "Marigold"),
        PresetColor(hex: "FFF9C4", name: "Cream"),

        // Greens
        PresetColor(hex: "34C759", name: "Green"),
        PresetColor(hex: "A8D800", name: "Lime"),
        PresetColor(hex: "2E7D32", name: "Forest"),
        PresetColor(hex: "66BB6A", name: "Sage"),
        PresetColor(hex: "00C853", name: "Emerald"),
        PresetColor(hex: "81C784", name: "Fern"),
        PresetColor(hex: "1B5E20", name: "Pine"),
        PresetColor(hex: "C5E1A5", name: "Pistachio"),

        // Teals & Cyans
        PresetColor(hex: "00C7BE", name: "Mint"),
        PresetColor(hex: "30B0C7", name: "Teal"),
        PresetColor(hex: "00BCD4", name: "Cyan"),
        PresetColor(hex: "4DD0E1", name: "Aqua"),
        PresetColor(hex: "00838F", name: "Deep Teal"),
        PresetColor(hex: "80DEEA", name: "Sky"),
        PresetColor(hex: "006064", name: "Ocean"),
        PresetColor(hex: "B2EBF2", name: "Ice"),

        // Blues
        PresetColor(hex: "007AFF", name: "Blue"),
        PresetColor(hex: "32ADE6", name: "Azure"),
        PresetColor(hex: "1565C0", name: "Navy"),
        PresetColor(hex: "42A5F5", name: "Cornflower"),
        PresetColor(hex: "0D47A1", name: "Cobalt"),
        PresetColor(hex: "90CAF9", name: "Periwinkle"),
        PresetColor(hex: "1A237E", name: "Midnight"),
        PresetColor(hex: "64B5F6", name: "Baby Blue"),

        // Purples
        PresetColor(hex: "5856D6", name: "Indigo"),
        PresetColor(hex: "AF52DE", name: "Purple"),
        PresetColor(hex: "8944AB", name: "Violet"),
        PresetColor(hex: "7E57C2", name: "Amethyst"),
        PresetColor(hex: "4A148C", name: "Deep Purple"),
        PresetColor(hex: "CE93D8", name: "Lavender"),
        PresetColor(hex: "6A1B9A", name: "Plum"),
        PresetColor(hex: "B39DDB", name: "Lilac"),

        // Pinks & Neutrals
        PresetColor(hex: "FF2D55", name: "Pink"),
        PresetColor(hex: "FF6FA3", name: "Blush"),
        PresetColor(hex: "E91E63", name: "Magenta"),
        PresetColor(hex: "F48FB1", name: "Flamingo"),
        PresetColor(hex: "AD1457", name: "Fuchsia"),
        PresetColor(hex: "F8BBD0", name: "Cotton Candy"),
        PresetColor(hex: "A2845E", name: "Brown"),
        PresetColor(hex: "8E8E93", name: "Gray"),
    ]
}

// MARK: - SubstanceColor Collection Helpers

extension [SubstanceColor] {
    /// Map of hex color -> substance name (for checking which colors are taken)
    var takenColorMap: [String: String] {
        Dictionary(map { ($0.hexColor, $0.substance) }, uniquingKeysWith: { _, last in last })
    }

    /// Map of lowercased substance name -> Color
    var colorMap: [String: Color] {
        Dictionary(map { ($0.substance.lowercased(), $0.color) }, uniquingKeysWith: { _, last in last })
    }

    /// Whether a color has been assigned to the given substance name
    func hasColor(for name: String) -> Bool {
        contains { $0.substance.lowercased() == name.lowercased() }
    }
}
