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
    /// The numeral's text style — the tunable "size" of the readout.
    var numberStyle: Font.TextStyle = .title3
    var numberWeight: Font.Weight = .semibold
    /// The trailing unit's text style. Body-sized by default so it reads as a
    /// quiet suffix under the rounded numeral.
    var unitStyle: Font.TextStyle = .subheadline

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(verbatim: "\(isApproximate ? "~" : "")\(amount.doseFormatted)")
                .font(.system(numberStyle, design: .rounded).weight(numberWeight))
                .foregroundStyle(.primary)
            Text(displayUnit)
                .font(.system(unitStyle))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: Text {
        isApproximate
            ? Text("approximately \(amount.doseFormatted) \(displayUnit)")
            : Text(verbatim: "\(amount.doseFormatted) \(displayUnit)")
    }

    /// "1 units" → "1 unit" and any other singular/plural fixups the shared helper
    /// applies; every other unit passes through untouched.
    private var displayUnit: String {
        unit.unitDisplay(for: amount)
    }
}
