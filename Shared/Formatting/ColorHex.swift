import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// Parses a hex color string into normalized RGBA components in `0...1`.
///
/// Accepts `"RGB"`, `"RRGGBB"`, or `"RRGGBBAA"`. Non-alphanumeric leading
/// characters (e.g., `#`) are stripped. Returns opaque black on malformed
/// input so callers don't have to handle failure separately.
private nonisolated func parseHex(_ string: String) -> (r: Double, g: Double, b: Double, a: Double) {
    let hex = string.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    let r, g, b, a: Double
    switch hex.count {
    case 3:
        // Expand shorthand: "FFF" → "FFFFFF"
        r = Double(((int >> 8) & 0xF) * 17) / 255
        g = Double(((int >> 4) & 0xF) * 17) / 255
        b = Double((int & 0xF) * 17) / 255
        a = 1
    case 6:
        r = Double((int >> 16) & 0xFF) / 255
        g = Double((int >> 8) & 0xFF) / 255
        b = Double(int & 0xFF) / 255
        a = 1
    case 8:
        // RRGGBBAA
        r = Double((int >> 24) & 0xFF) / 255
        g = Double((int >> 16) & 0xFF) / 255
        b = Double((int >> 8) & 0xFF) / 255
        a = Double(int & 0xFF) / 255
    default:
        r = 0; g = 0; b = 0; a = 1
    }
    return (r, g, b, a)
}

extension Color {
    nonisolated init(hex: String) {
        let c = parseHex(hex)
        // Preserve prior behavior: ignore alpha channel for SwiftUI.Color.
        self.init(red: c.r, green: c.g, blue: c.b)
    }
}
