import SwiftUI

/// Small watch-local helpers. The watch deliberately shares only the pure wire types with the
/// phone, so display formatting, hex-color parsing, and Crown step sizing live here rather than
/// pulling `Shared/` files that import UIKit (unavailable on watchOS).
enum WatchDoseFormat {
    /// Trim a numeric amount for display: integer when whole, else up to one decimal.
    static func amount(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.1f", value)
    }

    /// The route rawValue as a display label — the enum's `displayName` is just the
    /// capitalized rawValue, so the watch reproduces it without importing the (UIKit-bound) enum.
    static func route(_ rawValue: String) -> String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

/// Grams of ethanol for a drink — display-only on the watch (the phone recomputes the canonical
/// stored value with `ByVolumeDosing`). Kept identical to that formula: volume × (ABV/100) × 0.789.
enum WatchDrinkMath {
    static let ethanolDensity = 0.789
    static let standardDrinkGrams = 14.0

    static func grams(volumeML: Double, abv: Double) -> Double {
        guard volumeML > 0, abv > 0 else { return 0 }
        return volumeML * (abv / 100) * ethanolDensity
    }

    static func standardDrinks(volumeML: Double, abv: Double) -> Double {
        grams(volumeML: volumeML, abv: abv) / standardDrinkGrams
    }
}

/// Brief full-screen confirmation shown after a dose is queued, before the log screen
/// returns to the grid — so the tap reads as "done," with the pending sync surfaced there.
struct LoggedOverlay: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.65)).ignoresSafeArea()
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)
                Text("Logged")
                    .font(.headline)
                Label("Syncing to iPhone", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension Color {
    /// Parse `#RRGGBB` (or bare `RRGGBB`) into a Color. Returns nil for anything else, so the
    /// caller falls back to the accent color.
    init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
        )
    }
}
