import SwiftUI

/// The "Combinations" section — hand-curated, per-substance editorial content on
/// notable drug interactions, ranked by evidence rather than reputation. Each row
/// carries a severity tag, a substance/class name, and a plain-language
/// explanation. Self-hides for the long tail (empty data). See ``Combination``.
struct CombinationsSection: View {
    let combinations: [Combination]

    var body: some View {
        if !combinations.isEmpty {
            Section {
                ForEach(sorted, id: \.offset) { _, combo in
                    CombinationRow(combination: combo)
                }
            } header: {
                Label("Combinations", systemImage: "arrow.triangle.merge")
                    .font(.subheadline.weight(.semibold))
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
        HStack(alignment: .top, spacing: 10) {
            severityChip
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(combination.name)
                        .font(.subheadline.weight(.semibold))
                    if let note = combination.note {
                        Text(note)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.secondaryLabel)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.secondaryLabel.opacity(0.1), in: Capsule())
                    }
                }
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var severityChip: some View {
        Text(combination.severity.label)
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .textCase(.uppercase)
            .foregroundStyle(combination.severity.foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(combination.severity.background, in: RoundedRectangle(cornerRadius: 4))
            .fixedSize()
    }

    private var description: AttributedString {
        (try? AttributedString(markdown: combination.description)) ?? AttributedString(combination.description)
    }

    private var accessibilityLabel: String {
        "\(combination.severity.label): \(combination.name). \(combination.description)"
    }
}

extension Combination.Severity {
    var label: LocalizedStringKey {
        switch self {
        case .danger: "Danger"
        case .caution: "Caution"
        case .note: "Note"
        }
    }

    var foreground: Color {
        switch self {
        case .danger: .red
        case .caution: .orange
        case .note: Theme.secondaryLabel
        }
    }

    var background: Color {
        switch self {
        case .danger: Color.red.opacity(0.12)
        case .caution: Color.orange.opacity(0.12)
        case .note: Theme.secondaryLabel.opacity(0.1)
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
