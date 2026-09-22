import SwiftUI

/// A color as encoded Display P3 components, each `0…1` — the numbers an Apple
/// panel shows and an asset catalog's `display-p3` entry holds. This is the
/// form a substance color is stored in and travels in: the SwiftData row, the
/// Live Activity payload, the watch manifest, widget entries and layout caches.
nonisolated struct P3Color: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    /// Shown for a substance no color has been resolved for — a widget
    /// rendering a name the app has yet to mint a row for.
    static let neutral = P3Color(red: 0.62, green: 0.62, blue: 0.65)

    var color: Color {
        Color(.displayP3, red: red, green: green, blue: blue)
    }
}

/// Encodes as `[r, g, b]` at four decimals: a quarter of the keyed form's
/// bytes, which matters inside ActivityKit's 4 KB content-state budget, and
/// finer than any panel's code values.
nonisolated extension P3Color: Codable {
    private static let precision = 10000.0

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        red = try container.decode(Double.self)
        green = try container.decode(Double.self)
        blue = try container.decode(Double.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for component in [red, green, blue] {
            try container.encode((component * Self.precision).rounded() / Self.precision)
        }
    }
}
