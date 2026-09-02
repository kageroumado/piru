import SwiftUI

/// One interaction warning — drug names at leading edge, mechanism icon + severity
/// at trailing. Shared by the interaction checker, session detail, and log confirmation.
struct InteractionWarningRow: View {
    let warning: InteractionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                Text("\(warning.substanceA) + \(warning.substanceB)")
                    .sectionLabel()
                    .foregroundStyle(warning.severity.labelColor)
                Spacer(minLength: 4)
                Image(systemName: warning.severity == .dangerous
                    ? warning.mechanism.filledIconName : warning.mechanism.iconName)
                    .font(.chartLabel)
                    .foregroundStyle(warning.severity.labelColor)
                    .accessibilityHidden(true)
                Text(String(localized: warning.severity.label).lowercased())
                    .capsuleChip(text: warning.severity.labelColor, fill: warning.severity.color)
            }
            Text(warning.description)
                .captionSecondary()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Spacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
