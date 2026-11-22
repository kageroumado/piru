import SwiftUI

/// The "± 1 mg" cluster that takes an estimate's spread
/// (``DoseEntry/amountDeviation``): the sign, a decimal field, and the dose's
/// unit. The quick-log editor and the entry edit form each wrap it in a row of
/// their own, which owns the focus so a tap anywhere on the row lands here.
///
/// The field is optional by design: left empty, the dose stays a plain `~`
/// estimate.
struct DoseDeviationField: View {
    @Binding var text: String
    let unit: String
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text(verbatim: "±")
                .foregroundStyle(Theme.secondaryLabel)
                .accessibilityHidden(true)
            TextField(text: $text, prompt: Text(verbatim: "0")) { Text("Might be off by") }
                .decimalKeyboard()
                .multilineTextAlignment(.trailing)
                .focused(focus)
                .fixedSize(horizontal: true, vertical: false)
            Text(unit)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }
}
