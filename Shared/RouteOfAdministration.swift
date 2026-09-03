import Foundation
import SwiftUI

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
    /// A fixed tint per route — so a route reads the same everywhere (every
    /// "oral" badge is the same colour), independent of the substance's own
    /// colour. Used by the dose-row / detail ROA pills.
    ///
    /// Values live in the design system (`design-system/color/palette-L2.json`,
    /// scale `route`) and resolve from the asset catalog. Hue is preserved from
    /// the hand-tuned table this replaced; only lightness and chroma moved.
    var tintColor: Color {
        switch self {
        case .oral: .Route.Oral.accent
        case .sublingual: .Route.Sublingual.accent
        case .buccal: .Route.Buccal.accent
        case .insufflation: .Route.Insufflation.accent
        case .inhalation: .Route.Inhalation.accent
        case .intravenous: .Route.Intravenous.accent
        case .intramuscular: .Route.Intramuscular.accent
        case .subcutaneous: .Route.Subcutaneous.accent
        case .transdermal: .Route.Transdermal.accent
        case .rectal: .Route.Rectal.accent
        case .other: .Route.Other.accent
        }
    }

    /// Legible text variant for the ~11pt pill label.
    ///
    /// Guarantees ≥4.5:1 contrast against the pill's 0.10-alpha fill in both
    /// light and dark mode. Never raise that fill alpha without re-checking dark
    /// mode: a color on a tint of itself asymptotes toward roughly 4.5:1
    /// regardless of lightness, so the fill alpha itself is load-bearing for
    /// reaching that ratio in dark mode.
    var tintTextColor: Color {
        switch self {
        case .oral: .Route.Oral.text
        case .sublingual: .Route.Sublingual.text
        case .buccal: .Route.Buccal.text
        case .insufflation: .Route.Insufflation.text
        case .inhalation: .Route.Inhalation.text
        case .intravenous: .Route.Intravenous.text
        case .intramuscular: .Route.Intramuscular.text
        case .subcutaneous: .Route.Subcutaneous.text
        case .transdermal: .Route.Transdermal.text
        case .rectal: .Route.Rectal.text
        case .other: .Route.Other.text
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
