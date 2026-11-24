import SwiftUI

/// A dose quantity rendered Apple-Health-style: a large **rounded** numeral in the
/// primary label color with a smaller, **non-rounded** unit trailing in the
/// secondary color. The size/weight contrast — not an SI space — is what separates
/// value from unit, so the gap is a tight 2pt rather than a full space.
///
/// One source of truth for every dose/total readout (the entry rows and the "In
/// Your Body" totals both use it) so the number treatment can never drift between
/// surfaces. Size-configurable via ``numberStyle`` for the hero readout vs. the
/// quieter cumulative form.
///
/// Renders as a single combined accessibility element ("110 mg"); callers that
/// need to append more (e.g. a dose level) should override with their own
/// `.accessibilityLabel`.
struct MeasurementLabel: View {
    let amount: Double
    let unit: String
    /// Whether the amount is an estimate — renders a leading `~` on the numeral
    /// and reads "approximately …" to VoiceOver, so a logged guess never looks
    /// like a measured figure. Off for the cumulative "In Your Body" totals,
    /// which are computed, not guessed.
    var isApproximate: Bool = false
    /// How far off an estimated amount may be (``DoseEntry/amountDeviation``).
    /// Trails the numeral in the unit's quieter style, "10 ± 1 mg", and takes
    /// the place of the `~`: the ± already says the amount is an estimate.
    var deviation: Double?
    /// Whether the amount is unknown (``DoseEntry/isUnknownDose``) — the numeral
    /// is a `?` in the same rounded face, the unit still trails it, and VoiceOver
    /// reads "unknown amount". Takes precedence over ``isApproximate`` and
    /// ``deviation``.
    var isUnknown: Bool = false
    /// The numeral's text style — the tunable "size" of the readout.
    var numberStyle: Font.TextStyle = .title3
    var numberWeight: Font.Weight = .semibold
    /// The trailing unit's text style. Body-sized by default so it reads as a
    /// quiet suffix under the rounded numeral.
    var unitStyle: Font.TextStyle = .subheadline

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
            Text(verbatim: numeral)
                .font(.system(numberStyle, design: .rounded).weight(numberWeight))
                .foregroundStyle(.primary)
            Text(verbatim: trailing)
                .font(.system(unitStyle))
                .foregroundStyle(Theme.secondaryLabel)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var numeral: String {
        if isUnknown { return "?" }
        return "\(isApproximate && shownDeviation == nil ? "~" : "")\(amount.doseFormatted)"
    }

    private var trailing: String {
        guard let shownDeviation else { return displayUnit }
        return "\(shownDeviation.deviationFormatted) \(displayUnit)"
    }

    private var shownDeviation: Double? {
        isUnknown ? nil : DoseReadout.validDeviation(deviation)
    }

    private var accessibilityText: Text {
        if isUnknown { return Text("unknown amount") }
        return Text(Self.spoken(amount: amount, unit: displayUnit, isApproximate: isApproximate, deviation: shownDeviation))
    }

    /// The dose as VoiceOver says it: "10 mg, give or take 1" with a deviation,
    /// "approximately 10 mg" for an estimate without one, else the bare figure.
    static func spoken(amount: Double, unit: String, isApproximate: Bool, deviation: Double?) -> String {
        let formatted = amount.doseFormatted
        if let deviation = DoseReadout.validDeviation(deviation) {
            return String(localized: "\(formatted) \(unit), give or take \(deviation.doseFormatted)")
        }
        return isApproximate ? String(localized: "approximately \(formatted) \(unit)") : "\(formatted) \(unit)"
    }

    /// "1 units" → "1 unit" and any other singular/plural fixups the shared helper
    /// applies; every other unit passes through untouched.
    private var displayUnit: String {
        unit.unitDisplay(for: amount)
    }
}
