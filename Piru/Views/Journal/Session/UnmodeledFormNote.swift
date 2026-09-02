import SwiftUI

/// One line, where the timeline would be, explaining why a dose here draws a dot
/// instead of a curve: the session names a form the app declines to model
/// (``DoseEntry/namesUnmodeledForm``). Better to withhold the timing than to draw
/// the base form's curve under a form that doesn't follow it — see
/// `Specs/psid-identity-consumption.md` LB-2.
struct UnmodeledFormNote: View {
    enum Content: Equatable {
        /// A single form, named for the row: "the Concerta form of Methylphenidate".
        case named(product: String, base: String)
        /// More than one, or a title that would restate its base — a neutral line.
        case generic
    }

    let content: Content

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: Spacing.xl) {
                Image(systemName: "clock.badge.questionmark")
                    .font(.title3)
                    .foregroundStyle(Theme.secondaryLabel)
                    .accessibilityHidden(true)
                Text(message)
                    .captionSecondary()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    private var message: LocalizedStringKey {
        switch content {
        case let .named(product, base):
            "Piru doesn't model a timeline for the \(product) form of \(base). How long a form like this stays active isn't something Piru estimates, so the session shows when each dose was taken — not how long it lasts."
        case .generic:
            "Piru doesn't model a timeline for some of these forms. How long they stay active isn't something Piru estimates, so the session shows when each dose was taken — not how long it lasts."
        }
    }
}
