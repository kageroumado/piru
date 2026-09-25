import SwiftData
import SwiftUI

/// Dispatches an ``UpdateNotice`` to its page, and records it as seen once the
/// page goes away. Seen on dismissal, never on presentation: a notice the app
/// died under is still owed.
struct UpdateNoticeView: View {
    let notice: UpdateNotice

    var body: some View {
        page.onDisappear { notice.markSeen() }
    }

    @ViewBuilder
    private var page: some View {
        switch notice {
        case .appMoved: AppMovedNoticeView(successorHasImported: LegacyHandoff.successorImportedAt != nil)
        case .journalArrived: JournalArrivedNoticeView()
        case .classColors: ClassColorsNoticeView()
        }
    }
}

// MARK: - Handoff

/// The legacy build's notice: Piru lives in a new app. Before the new app has
/// run on this device it says the move is automatic; after, it says that what
/// is logged here no longer follows.
private struct AppMovedNoticeView: View {
    let successorHasImported: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NoticePage(systemImage: "shippingbox.fill") {
            if successorHasImported {
                Text("Your journal has moved")
            } else {
                Text("Piru has moved")
            }
        } message: {
            if successorHasImported {
                Text("The new Piru app already has your journal. Entries you add here stay in this app and won't follow, so the new one is the place to log from now on.")
            } else {
                Text("Piru now lives in a new app. Install it on this device and the first time you open it, your journal, meds and settings come across on their own. Nothing here is deleted.")
            }
        } actions: {
            GlassPillButton(title: "Open in TestFlight") {
                openURL(AppIdentity.successorTestFlightURL)
                dismiss()
            }
            GlassPillButton(title: "Not Now", prominence: .neutral) { dismiss() }
        }
    }
}

/// The successor's one-time notice after it brought a journal across.
private struct JournalArrivedNoticeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NoticePage(systemImage: "checkmark.circle.fill") {
            Text("Your journal came with you")
        } message: {
            Text("Everything from the old Piru app is here: your journal, meds and settings. Once you've looked it over, you can delete the old app.")
        } actions: {
            GlassPillButton(title: "Done") { dismiss() }
        }
    }
}

/// An icon, a title, a message and a stack of buttons, sized to its content.
private struct NoticePage<Title: View, Message: View, Actions: View>: View {
    let systemImage: String
    @ViewBuilder let title: Title
    @ViewBuilder let message: Message
    @ViewBuilder let actions: Actions
    @State private var contentHeight: CGFloat = 480
    @State private var safeAreaBottom: CGFloat = 34

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                Image(systemName: systemImage)
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                    .padding(.top, Spacing.xxxl)
                    .accessibilityHidden(true)

                title
                    .font(.piru(.title2, weight: .bold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                message
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: Spacing.md) {
                    actions
                }
            }
            .padding(.horizontal, Spacing.xxxl)
            .padding(.bottom, Spacing.xxl)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { safeAreaBottom = max(0, $0) }
        .presentationDetents([.height(contentHeight + safeAreaBottom)])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Class colors

/// Tells an existing user that substance colors follow class, shows what that
/// does to their own substances, and lets them move or stay. Leaving without
/// choosing keeps the colors they had: that path loses nothing, and Reset All
/// in Substance Colors is there for a later change of mind.
private struct ClassColorsNoticeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var samples: [Sample] = []
    @State private var legacyCount = 0
    @State private var hasChosen = false
    @State private var contentHeight: CGFloat = 640
    @State private var safeAreaBottom: CGFloat = 34

    private static let sampleLimit = 6

    struct Sample: Identifiable {
        let name: String
        let before: Color
        let after: Color
        var id: String { name }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                    .padding(.top, Spacing.xxxl)
                    .accessibilityHidden(true)

                Text("Colors now follow class")
                    .font(.piru(.title2, weight: .bold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text("Every substance now gets a color from its class — stimulants share one family, psychedelics another — so a timeline reads at a glance. You can still give any substance a color of your own.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if !samples.isEmpty {
                    ClassColorsSampleCard(samples: samples)
                }

                Text("You have \(legacyCount) substances with colors from before. Move them to class colors, or keep them exactly as they are.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: Spacing.md) {
                    GlassPillButton(title: "Use Class Colors") { resolve(adoptClassColors: true) }
                    GlassPillButton(title: "Keep My Colors", prominence: .neutral) { resolve(adoptClassColors: false) }
                }
            }
            .padding(.horizontal, Spacing.xxxl)
            .padding(.bottom, Spacing.xxl)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { safeAreaBottom = max(0, $0) }
        .presentationDetents([.height(contentHeight + safeAreaBottom)])
        .presentationDragIndicator(.visible)
        .task { load() }
        .onDisappear {
            if !hasChosen { resolve(adoptClassColors: false) }
        }
    }

    private func load() {
        let rows = ((try? modelContext.fetch(FetchDescriptor<SubstanceColor>(sortBy: [SortDescriptor(\.substance)]))) ?? [])
            .filter(\.isLegacy)
        legacyCount = rows.count
        // Two rows can share a display name (a relabeled substance and its
        // canonical name); the card shows each name once.
        var shown: Set<String> = []
        var picked: [Sample] = []
        for row in rows where picked.count < Self.sampleLimit {
            let name = CustomSubstanceStore.shared.displayName(for: row.substance)
            guard shown.insert(name).inserted else { continue }
            picked.append(Sample(
                name: name, before: row.color,
                after: SubstanceColorStore.defaultTint(for: row.substance).color,
            ))
        }
        samples = picked
    }

    private func resolve(adoptClassColors: Bool) {
        guard !hasChosen else { return }
        hasChosen = true
        SubstanceColorStore.resolveLegacyRows(adoptClassColors: adoptClassColors, in: modelContext)
        dismiss()
    }
}

/// The user's own substances, each with the color it has and the one its
/// class gives it.
private struct ClassColorsSampleCard: View {
    let samples: [ClassColorsNoticeView.Sample]

    var body: some View {
        VStack(spacing: Spacing.md) {
            ForEach(samples) { sample in
                HStack(spacing: Spacing.md) {
                    Text(sample.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer(minLength: Spacing.md)
                    Circle().fill(sample.before).frame(width: IconSize.iconCompact, height: IconSize.iconCompact)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    Circle().fill(sample.after).frame(width: IconSize.iconCompact, height: IconSize.iconCompact)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(sample.name))
            }
        }
        .padding(Spacing.xl)
        .background { CardBackground().clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)) }
    }
}
