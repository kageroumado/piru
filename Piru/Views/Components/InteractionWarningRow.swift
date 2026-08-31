import SwiftUI

/// One interaction warning — drug names at leading edge, mechanism icon + severity
/// at trailing. Shared by the interaction checker, session detail, and log confirmation.
struct InteractionWarningRow: View {
    let warning: InteractionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(warning.substanceA) + \(warning.substanceB)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(warning.severity.labelColor)
                Spacer(minLength: 4)
                Image(systemName: warning.severity == .dangerous
                    ? warning.mechanism.filledIconName : warning.mechanism.iconName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(warning.severity.labelColor)
                    .accessibilityHidden(true)
                Text(String(localized: warning.severity.label).lowercased())
                    .capsuleChip(text: warning.severity.labelColor, fill: warning.severity.color)
            }
            Text(warning.description)
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
