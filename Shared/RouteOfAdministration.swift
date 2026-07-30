import Foundation
import SwiftUI
import UIKit

enum RouteOfAdministration: String, Codable, CaseIterable, Identifiable {
    case oral
    case sublingual
    /// Absorbed across the cheek mucosa — nicotine pouches, snus, buccal films.
    /// Distinct from `oral`: it bypasses first-pass metabolism, so it has its own
    /// (much shorter) duration profile. The bundled DB has carried buccal rows all
    /// along; without this case they parsed to `.other`, so a pouch showed an
    /// "Other" pill sorted last and defaulted to oral's six-hour curve.
    case buccal
    case insufflation
    case inhalation
    case intravenous
    case intramuscular
    case subcutaneous
    case transdermal
    case rectal
    case other

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .oral: "Oral"
        case .sublingual: "Sublingual"
        case .buccal: "Buccal"
        case .insufflation: "Insufflation"
        case .inhalation: "Inhalation"
        case .intravenous: "Intravenous"
        case .intramuscular: "Intramuscular"
        case .subcutaneous: "Subcutaneous"
        case .transdermal: "Transdermal"
        case .rectal: "Rectal"
        case .other: "Other"
        }
    }

    var localizedName: LocalizedStringResource {
        switch self {
        case .oral: "Oral"
        case .sublingual: "Sublingual"
        case .buccal: "Buccal"
        case .insufflation: "Insufflation"
        case .inhalation: "Inhalation"
        case .intravenous: "Intravenous"
        case .intramuscular: "Intramuscular"
        case .subcutaneous: "Subcutaneous"
        case .transdermal: "Transdermal"
        case .rectal: "Rectal"
        case .other: "Other"
        }
    }
}

extension RouteOfAdministration {
    /// A fixed tint per route — so a route reads the same everywhere (every "oral"
    /// badge is the same color), independent of the substance's own color. Used
    /// by the dose-row / detail ROA pills as both the badge text and its 0.16 fill.
    ///
    /// Adaptive like `Theme.legibleYellow`: the vivid hue works on dark, but as
    /// ~11pt text on a near-white card several hues fail small-text contrast
    /// (orange/green worst), so light mode darkens each toward ≥4.5:1 while
    /// keeping the hue identity.
    ///
    /// **Verified, not assumed.** Every light value clears 4.5:1 against its own
    /// 16% fill over the measured card (`#f5f5f5` — the `.ultraThinMaterial`
    /// card is *not* white). Five originally missed that target — sublingual
    /// 4.02, buccal 4.18, other 4.19, inhalation 4.25, transdermal 4.32 — and
    /// were lowered in Oklab lightness with hue held exactly constant.
    /// Re-check with `Specs/design-system/color-audit/colorimetry.py`.
    var tintColor: Color {
        let (light, dark) = tintHexPair
        return Color(UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }

    private var tintHexPair: (light: String, dark: String) {
        switch self {
        case .oral: ("0B5FC2", "0A84FF") // blue
        case .sublingual: ("007184", "30B0C7") // teal
        case .buccal: ("007368", "00C7BE") // mint — mucosal, sibling to sublingual
        case .insufflation: ("8330AE", "AF52DE") // purple
        case .inhalation: ("995600", "FF9500") // orange
        case .intravenous: ("C22B22", "FF3B30") // red
        case .intramuscular: ("C21A3F", "FF2D55") // pink
        case .subcutaneous: ("4644B8", "5E5CE6") // indigo
        case .transdermal: ("127533", "34C759") // green
        case .rectal: ("7A6244", "A2845E") // brown
        case .other: ("656569", "8E8E93") // gray
        }
    }

    /// Parse a route string from TripSit/OpenFDA into our enum
    nonisolated static func from(string: String) -> RouteOfAdministration {
        switch string.lowercased().trimmingCharacters(in: .whitespaces) {
        case "oral", "oral_ir", "oral_er", "oral(benzedrex)", "oral(pure)": .oral
        case "sublingual": .sublingual
        case "buccal", "buccally", "pouch", "snus": .buccal
        case "insufflated", "insufflation", "insufflated(pure)", "intranasal", "nasal": .insufflation
        case "inhaled", "inhalation", "smoked", "vapourized", "vaporized": .inhalation
        case "intravenous", "iv": .intravenous
        case "intramuscular", "im": .intramuscular
        case "subcutaneous": .subcutaneous
        case "transdermal", "topical": .transdermal
        case "rectal", "plugged": .rectal
        default: .other
        }
    }
}
