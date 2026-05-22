import Foundation
import SwiftData
import SwiftUI

/// User-assigned color for a specific substance.
///
/// SwiftData `@Model` shared across the main Piru app, the Home Screen widget
/// (`PiruWidget`), and the Lock Screen Live Activity extension
/// (`PiruLiveActivityExtension`), so dose chips render the same color
/// everywhere they appear.
///
/// ## Uniqueness
/// ``substance`` is marked `@Attribute(.unique)` — there is exactly one
/// `SubstanceColor` row per substance name. SwiftData treats inserts with
/// a duplicate `substance` value as an upsert against the existing row,
/// so callers should update an existing instance rather than constructing
/// a new one to recolor.
///
/// ## Color Sources
/// Colors are usually picked from ``PresetColor/all``, but the user can
/// define their own palette entries via ``UserColor`` and assign any hex
/// to a substance. The two models are independent: ``UserColor`` is the
/// palette catalog, ``SubstanceColor`` is the substance→hex mapping.
@Model
final class SubstanceColor {
    /// Substance name this color applies to. Unique key.
    @Attribute(.unique) var substance: String
    /// Hex string (without `#`), e.g. `"00add3"`.
    var hexColor: String

    init(substance: String, hexColor: String) {
        self.substance = substance
        self.hexColor = hexColor
    }

    /// SwiftUI `Color` resolved from ``hexColor``.
    var color: Color {
        Color(hex: hexColor)
    }
}

// MARK: - Preset Colors

/// A fixed palette entry shown in the color picker.
///
/// Presets are defined statically in ``all`` and never persisted — they exist
/// only as in-memory choices the user can pick from. The selected hex is
/// what gets stored on the substance via ``SubstanceColor``. Look up a
/// preset by ``name`` or ``hex`` when you need the human-readable label
/// for a stored hex value.
struct PresetColor: Identifiable, Hashable {
    /// Hex string (without `#`).
    let hex: String
    /// Human-readable name shown in the UI (e.g. `"Sky"`, `"Light Lavender"`).
    let name: String

    var id: String { hex }
    var color: Color { Color(hex: hex) }

    static let all: [PresetColor] = [
        // Sky
        PresetColor(hex: "00add3", name: "Sky"),
        PresetColor(hex: "41c6e2", name: "Light Sky"),
        PresetColor(hex: "009ec1", name: "Dark Sky"),
        // Azure
        PresetColor(hex: "2ca2f5", name: "Azure"),
        PresetColor(hex: "71befd", name: "Light Azure"),
        PresetColor(hex: "2695e1", name: "Dark Azure"),
        // Lavender
        PresetColor(hex: "8394ff", name: "Lavender"),
        PresetColor(hex: "a2b2ff", name: "Light Lavender"),
        PresetColor(hex: "7887eb", name: "Dark Lavender"),
        // Lilac
        PresetColor(hex: "b885ef", name: "Lilac"),
        PresetColor(hex: "cda7f8", name: "Light Lilac"),
        PresetColor(hex: "a979dc", name: "Dark Lilac"),
        // Magenta
        PresetColor(hex: "dd79c9", name: "Magenta"),
        PresetColor(hex: "eb9eda", name: "Light Magenta"),
        PresetColor(hex: "cb6eb8", name: "Dark Magenta"),
        // Rose
        PresetColor(hex: "f17395", name: "Rose"),
        PresetColor(hex: "fc9bb1", name: "Light Rose"),
        PresetColor(hex: "dd6988", name: "Dark Rose"),
        // Coral
        PresetColor(hex: "f27859", name: "Coral"),
        PresetColor(hex: "fd9e86", name: "Light Coral"),
        PresetColor(hex: "de6d51", name: "Dark Coral"),
        // Tangerine
        PresetColor(hex: "e08600", name: "Tangerine"),
        PresetColor(hex: "eda963", name: "Light Tangerine"),
        PresetColor(hex: "ce7b00", name: "Dark Tangerine"),
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
        // Teal
        PresetColor(hex: "00b3a2", name: "Teal"),
        PresetColor(hex: "3fcabc", name: "Light Teal"),
        PresetColor(hex: "00a494", name: "Dark Teal"),
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

    /// Map of lowercased substance name -> hex string
    var hexColorMap: [String: String] {
        Dictionary(map { ($0.substance.lowercased(), $0.hexColor) }, uniquingKeysWith: { _, last in last })
    }

    /// Whether a color has been assigned to the given substance name
    func hasColor(for name: String) -> Bool {
        contains { $0.substance.lowercased() == name.lowercased() }
    }
}
