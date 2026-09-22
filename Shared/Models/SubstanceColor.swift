import Foundation
import os
import SwiftData
import SwiftUI

/// The color of one substance the user has met.
///
/// SwiftData `@Model` shared across the main Piru app, the Home Screen widget
/// (`PiruWidget`), and the Lock Screen Live Activity extension
/// (`PiruLiveActivityExtension`), so dose chips render the same color
/// everywhere they appear.
///
/// ## Default and custom
/// A substance's default color comes from its class and identity (see
/// `SubstanceColorGenerator`). A row with ``usesDefault`` set holds that
/// generated color; a row with it cleared holds a color the user picked. The
/// resolved Display P3 components are stored either way, because the widget
/// and App Intents read this row with no substance catalog to generate from.
///
/// ## Uniqueness
/// ``substance`` is marked `@Attribute(.unique)` — there is exactly one row per
/// substance name. SwiftData treats an insert with a duplicate `substance` as
/// an upsert against the existing row, so callers recolor the existing
/// instance rather than constructing a new one.
@Model
final class SubstanceColor {
    /// Substance name this color applies to. Unique key.
    @Attribute(.unique) var substance: String
    /// sRGB hex from builds that predate class colors. Non-empty marks a row
    /// the color-update notice has yet to convert; ``tint`` reads it until
    /// then. Nothing writes a new value here.
    var hexColor: String = ""
    /// Encoded Display P3 components of the resolved color.
    var red: Double = 0
    var green: Double = 0
    var blue: Double = 0
    /// Whether the components are the generator's output for this substance.
    var usesDefault: Bool = true

    init(substance: String, tint: P3Color, usesDefault: Bool) {
        self.substance = substance
        hexColor = ""
        red = tint.red
        green = tint.green
        blue = tint.blue
        self.usesDefault = usesDefault
    }

    /// Whether the row still carries its pre-class-colors hex.
    var isLegacy: Bool {
        !hexColor.isEmpty
    }

    /// The color to show.
    var tint: P3Color {
        isLegacy ? LegacyColorImport.p3(fromSRGBHex: hexColor) : P3Color(red: red, green: green, blue: blue)
    }

    var color: Color {
        tint.color
    }

    /// Stores `tint` and retires any legacy hex.
    func set(_ tint: P3Color, usesDefault: Bool) {
        hexColor = ""
        red = tint.red
        green = tint.green
        blue = tint.blue
        self.usesDefault = usesDefault
    }
}

// MARK: - Legacy import

/// The one place an sRGB hex becomes a color: rows and backups written before
/// class colors, and PsyLog's named palette.
nonisolated enum LegacyColorImport {
    /// `"RRGGBB"`, with or without a leading `#`. Malformed input reads as
    /// ``P3Color/neutral``.
    static func p3(fromSRGBHex hex: String) -> P3Color {
        let digits = hex.filter(\.isHexDigit)
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return .neutral }
        func linear(_ byte: UInt32) -> Double {
            let v = Double(byte) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return Oklch(
            linearRed: linear((value >> 16) & 0xFF),
            green: linear((value >> 8) & 0xFF),
            blue: linear(value & 0xFF),
        ).displayP3
    }
}

// MARK: - SubstanceColor Collection Helpers

extension [SubstanceColor] {
    /// Map of lowercased substance name -> Color
    var colorMap: [String: Color] {
        Dictionary(map { ($0.substance.lowercased(), $0.color) }, uniquingKeysWith: { _, last in last })
    }

    /// Map of lowercased substance name -> Display P3 components
    var tintMap: [String: P3Color] {
        Dictionary(map { ($0.substance.lowercased(), $0.tint) }, uniquingKeysWith: { _, last in last })
    }

    /// Whether a color has been assigned to the given substance name
    func hasColor(for name: String) -> Bool {
        contains { $0.substance.lowercased() == name.lowercased() }
    }
}

// MARK: - Resolved Colors

/// The generated default color of every catalog substance, keyed by lowercased
/// name. The app installs it once the catalog is loaded; the widget and the
/// Live Activity have no catalog and leave it empty.
nonisolated enum CatalogTints {
    private static let storage = OSAllocatedUnfairLock<[String: P3Color]>(initialState: [:])

    static func install(_ tints: [String: P3Color]) {
        storage.withLock { $0 = tints }
    }

    static func tint(for name: String) -> P3Color? {
        let key = name.lowercased()
        return storage.withLock { $0[key] }
    }
}

/// Resolve a substance's display color: its ``SubstanceColor`` row if it has
/// one, else its generated default, else ``P3Color/neutral``. The single
/// fallback everywhere (dots, curves, markers, accents), so a substance looks
/// the same in every place it appears. Callers pass a precomputed
/// `colorMap`/`tintMap` to stay cheap in hot paths.
nonisolated enum SubstancePalette {
    static func color(for name: String, colorMap: [String: Color]) -> Color {
        colorMap[name.lowercased()] ?? fallback(for: name).color
    }

    static func tint(for name: String, tintMap: [String: P3Color]) -> P3Color {
        tintMap[name.lowercased()] ?? fallback(for: name)
    }

    static func fallback(for name: String) -> P3Color {
        CatalogTints.tint(for: name) ?? .neutral
    }
}
