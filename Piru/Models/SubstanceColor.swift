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

    static let all: [PresetColor] = [
        // Sky
        PresetColor(hex: "00add3", name: "Sky"),
        PresetColor(hex: "41c6e2", name: "Light Sky"),
        PresetColor(hex: "009ec1", name: "Dark Sky"),
        // Iris
        PresetColor(hex: "2ca2f5", name: "Iris"),
        PresetColor(hex: "71befd", name: "Light Iris"),
        PresetColor(hex: "2695e1", name: "Dark Iris"),
        // Lavender
        PresetColor(hex: "8394ff", name: "Lavender"),
        PresetColor(hex: "a2b2ff", name: "Light Lavender"),
        PresetColor(hex: "7887eb", name: "Dark Lavender"),
        // Red
        PresetColor(hex: "b885ef", name: "Red"),
        PresetColor(hex: "cda7f8", name: "Light Red"),
        PresetColor(hex: "a979dc", name: "Dark Red"),
        // Turquoise
        PresetColor(hex: "dd79c9", name: "Turquoise"),
        PresetColor(hex: "eb9eda", name: "Light Turquoise"),
        PresetColor(hex: "cb6eb8", name: "Dark Turquoise"),
        // Azure
        PresetColor(hex: "f17395", name: "Azure"),
        PresetColor(hex: "fc9bb1", name: "Light Azure"),
        PresetColor(hex: "dd6988", name: "Dark Azure"),
        // Mulberry
        PresetColor(hex: "f27859", name: "Mulberry"),
        PresetColor(hex: "fd9e86", name: "Light Mulberry"),
        PresetColor(hex: "de6d51", name: "Dark Mulberry"),
        // Flamingo
        PresetColor(hex: "e08600", name: "Flamingo"),
        PresetColor(hex: "eda963", name: "Light Flamingo"),
        PresetColor(hex: "ce7b00", name: "Dark Flamingo"),
        // Mustard
        PresetColor(hex: "bb9900", name: "Mustard"),
        PresetColor(hex: "cfb657", name: "Light Mustard"),
        PresetColor(hex: "ab8c00", name: "Dark Mustard"),
        // Pear
        PresetColor(hex: "83a926", name: "Pear"),
        PresetColor(hex: "a3c26b", name: "Light Pear"),
        PresetColor(hex: "779a20", name: "Dark Pear"),
        // Green
        PresetColor(hex: "21b26a", name: "Green"),
        PresetColor(hex: "6fc991", name: "Light Green"),
        PresetColor(hex: "1ca360", name: "Dark Green"),
        // Cyan
        PresetColor(hex: "00b3a2", name: "Cyan"),
        PresetColor(hex: "3fcabc", name: "Light Cyan"),
        PresetColor(hex: "00a494", name: "Dark Cyan"),
        // Aqua
        PresetColor(hex: "00BFC8", name: "Aqua"),
        PresetColor(hex: "2ECDD4", name: "Light Aqua"),
        PresetColor(hex: "00B0B8", name: "Dark Aqua"),
        // Ocean
        PresetColor(hex: "00A4E8", name: "Ocean"),
        PresetColor(hex: "55B8F0", name: "Light Ocean"),
        PresetColor(hex: "0097D5", name: "Dark Ocean"),
        // Violet
        PresetColor(hex: "9B8DF7", name: "Violet"),
        PresetColor(hex: "B5A5FF", name: "Light Violet"),
        PresetColor(hex: "8E80E3", name: "Dark Violet"),
        // Orchid
        PresetColor(hex: "CB7FDD", name: "Orchid"),
        PresetColor(hex: "DC9CEB", name: "Light Orchid"),
        PresetColor(hex: "BA73CA", name: "Dark Orchid"),
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
