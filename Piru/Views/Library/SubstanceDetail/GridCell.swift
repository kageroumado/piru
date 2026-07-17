import SwiftUI

/// One labeled cell in the Info / Chemistry two-column grids. Only the *value*
/// is selectable (long-press to select & copy) — the label isn't, so you can't
/// accidentally grab the neighbouring cell's value (the old whole-row
/// contextMenu copied the wrong field and felt confusing). Shared by both the
/// Info and Chemistry disclosures.
struct GridCell: View {
    let label: LocalizedStringResource
    let value: String
    var mono = false

    init(_ label: LocalizedStringResource, _ value: String, mono: Bool = false) {
        self.label = label
        self.value = value
        self.mono = mono
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
                .textCase(.uppercase)
            Text(value)
                .font(mono ? .footnote.monospaced() : .subheadline)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
