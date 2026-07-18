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

// MARK: - Receptor Literature Row

// Single binding row inside the pharma-nerd "Receptor Literature" disclosure.
// Each row shows the target, action, Ki or EC50 value, optional species,
// source slug, and a PMID/DOI affordance so the user can verify the claim.

// MARK: - Substance Tag Flow
