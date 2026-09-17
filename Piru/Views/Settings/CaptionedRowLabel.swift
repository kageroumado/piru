import SwiftUI

/// A settings row's label: the title with one caption line under it saying what
/// the row does, and the row's symbol when it has one. The caption sits under
/// the title text, not under the symbol, so a captioned row reads like a system
/// Settings row.
///
/// A row whose value is a control (toggle, picker, stepper) puts the label in an
/// `HStack` with a `Spacer` and the control trailing. Never `LabeledContent`:
/// once the label wraps to a second line it stacks the value under the caption
/// instead of keeping it trailing, and whether it wraps depends on the locale.
struct CaptionedRowLabel: View {
    let title: LocalizedStringKey
    var systemImage: String?
    let caption: Text
    /// The row's current state, under the caption in the title column — for a
    /// pushed row whose value is a summary too long to sit trailing.
    var detail: Text?

    var body: some View {
        if let systemImage {
            Label {
                titleStack
            } icon: {
                Image(systemName: systemImage)
            }
        } else {
            titleStack
        }
    }

    private var titleStack: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
            caption
                .captionSecondary()
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                detail
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
    }
}
