import SwiftUI

/// The combinations block — hand-curated, per-substance editorial content on
/// notable drug interactions, ranked by evidence rather than reputation. Each row
/// carries a severity tag, a substance/class name, and a plain-language
/// explanation. Rendered inside the ``SafetySection`` card under a "Combinations"
/// sub-heading; the caller gates on empty data. See ``Combination``.
struct CombinationsList: View {
    let combinations: [Combination]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sorted, id: \.offset) { index, combo in
                if index > 0 {
                    Divider().padding(.vertical, Spacing.md)
                }
                CombinationRow(combination: combo)
            }
        }
    }

    private var sorted: [(offset: Int, element: Combination)] {
        Array(combinations.sorted { $0.severity.sortOrder < $1.severity.sortOrder }.enumerated())
    }
}

private struct CombinationRow: View {
    let combination: Combination

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Text(combination.name)
                    .sectionLabel()
                if let note = combination.note {
                    Text(note)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.secondaryLabel)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.secondaryLabel.opacity(Theme.Opacity.tint), in: Capsule())
                }
                Spacer(minLength: 8)
                EditorialPill(
                    label: Text(combination.severity.label),
                    foreground: combination.severity.foreground,
                    background: combination.severity.background,
                )
            }
            Text(description)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var description: AttributedString {
        (try? AttributedString(markdown: combination.description)) ?? AttributedString(combination.description)
    }

    private var accessibilityLabel: String {
        let severity = String(localized: combination.severity.label)
        return "\(severity): \(combination.name). \(combination.description)"
    }
}

extension Combination.Severity {
    /// `LocalizedStringResource`, not `LocalizedStringKey`: the accessibility
    /// label needs a real `String`, and interpolating a key into one yields its
    /// debug description — VoiceOver was reading out
    /// `LocalizedStringKey(key: "Danger", hasFormatting: false, …)`.
    var label: LocalizedStringResource {
        switch self {
        case .danger: "Danger"
        case .caution: "Caution"
        case .note: "Note"
        }
    }

    var foreground: Color {
        switch self {
        case .danger: .dangerText
        case .caution: .cautionText
        case .note: Theme.secondaryLabel
        }
    }

    /// The fill is the `accent` variant at ``Theme/Opacity/tint``, never an
    /// authored color: the `text` foreground above is contrast-gated against
    /// exactly that derivation.
    var background: Color {
        switch self {
        case .danger: Color.dangerAccent.opacity(Theme.Opacity.tint)
        case .caution: Color.cautionAccent.opacity(Theme.Opacity.tint)
        case .note: Theme.secondaryLabel.opacity(Theme.Opacity.tint)
        }
    }

    var sortOrder: Int {
        switch self {
        case .danger: 0
        case .caution: 1
        case .note: 2
        }
    }
}
