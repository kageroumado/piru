import SwiftData
import SwiftUI
import UIKit

/// One row in the merged "Sources" list — a contributing database or a piece of
/// primary literature, deep-linked to this substance's page where one exists.
struct DetailSourceLink: Identifiable {
    let id = UUID()
    let label: String
    let url: URL?
}

/// Small inline badge that names the source that supplied a specific field
/// after source-priority resolution. Visible to all tiers so users always see
/// where each fact came from — the per-field counterpart to the
/// substance-level "Sources" disclosure at the bottom of the detail view.
///
/// The displayed source name is resolved from the bundled `sources` table
/// via ``SubstanceStore/sourceDisplayName(forSlug:)`` so users see the
/// human-readable name ("TripSit factsheets") instead of the wire slug
/// ("tripsit").
/// The one folded-section look used across the whole substance screen — a
/// `DisclosureGroup` with a semibold subheadline label, a leading SF Symbol, and
/// an optional count badge. Extracted so Mechanism, Receptor Literature, Info,
/// Chemistry and the Cautions list fold identically. Crucially, a section's
/// source-attribution row goes *inside* `content` so it collapses with the body
/// rather than dangling beneath a closed disclosure.
struct CollapsibleSection<Content: View>: View {
    let title: LocalizedStringResource
    let systemImage: String
    var count: Int?
    /// When set, a trailing (i) button appears in the header that runs this action — used to open a
    /// plain-language help sheet for the denser cards. Borderless so it captures its own tap and
    /// doesn't also toggle the disclosure.
    var onInfo: (() -> Void)?
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    init(
        _ title: LocalizedStringResource,
        systemImage: String,
        count: Int? = nil,
        onInfo: (() -> Void)? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content,
    ) {
        self.title = title
        self.systemImage = systemImage
        self.count = count
        self.onInfo = onInfo
        _isExpanded = isExpanded
        self.content = content
    }

    var body: some View {
        Section {
            if let onInfo {
                // The (i) button nested in a DisclosureGroup label isn't reliably reachable under
                // VoiceOver, so expose the same help via a custom action on the section itself.
                disclosureGroup
                    .accessibilityAction(named: Text("About this section")) { onInfo() }
            } else {
                disclosureGroup
            }
        }
    }

    private var disclosureGroup: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content()
        } label: {
            HStack(spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                if let count {
                    Text(verbatim: "\(count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.secondaryLabel)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Theme.secondaryLabel.opacity(0.12), in: Capsule())
                }
                if let onInfo {
                    Spacer(minLength: 0)
                    Button(action: onInfo) {
                        Image(systemName: "info.circle")
                            .font(.subheadline)
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("What do these mean?")
                }
            }
        }
    }
}

struct SourceAttributionRow: View {
    let slug: String
    let label: LocalizedStringResource
    /// When set, the row becomes a tappable link to the source's page for this
    /// substance. Without it (a source with no deep link), it renders as plain
    /// attribution text.
    var deepLink: URL?

    private var displayName: String {
        SubstanceStore.shared.sourceDisplayName(forSlug: slug)
    }

    private var rowContent: some View {
        let linked = deepLink != nil
        return HStack(spacing: 6) {
            Image(systemName: linked ? "checkmark.seal.fill" : "checkmark.seal")
                .font(.caption2)
                .foregroundStyle(linked ? Theme.accent : Theme.secondaryLabel)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
            Text("·")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
            Text(displayName)
                .font(.caption2)
                .foregroundStyle(linked ? Theme.accent : Theme.secondaryLabel)
            if linked {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(String(localized: label)), source: \(displayName)"))
    }

    var body: some View {
        if let deepLink {
            Link(destination: deepLink) { rowContent }
        } else {
            rowContent
        }
    }
}

// MARK: - Shareable Drug-Info Card

/// The dark-themed card rendered to an image when the user shares a substance's
/// dosing. Reuses ``RouteDosingCard`` so the shared image matches what's on
/// screen; self-contained (no environment) so `ImageRenderer` can draw it.
struct SubstanceShareCard: View {
    let substance: Substance
    let route: SubstanceRoute
    let showsDoseLadder: Bool
    let showsDuration: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(substance.displayTitle)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                HStack(spacing: 8) {
                    Circle()
                        .fill(substance.category.color)
                        .frame(width: 10, height: 10)
                    Text(substance.category.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            RouteDosingCard(
                route: route.route,
                unit: route.unit,
                doses: route.doses,
                duration: showsDuration ? route.duration : nil,
                releaseWindow: route.durationOfAction?.formattedWindow,
                showsDoseLadder: showsDoseLadder,
                showsDuration: showsDuration,
                showDisclaimers: false,
                showsTitle: true,
            )
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(white: 0.10)))

            Text("Generated by Piru · kagerou.glass/piru")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(24)
        .frame(width: 390, alignment: .leading)
        .background(Color(white: 0.04))
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Receptor Literature Row

// Single binding row inside the pharma-nerd "Receptor Literature" disclosure.
// Each row shows the target, action, Ki or EC50 value, optional species,
// source slug, and a PMID/DOI affordance so the user can verify the claim.

// MARK: - Substance Tag Flow
