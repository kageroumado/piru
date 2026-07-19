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
    /// The source's page for this substance, opened from inside the explainer.
    var deepLink: URL?
    /// When both are set, the explainer lists which sources actually carry this
    /// field — so a lower-ranked winner (the classic "why PsychonautWiki?") makes
    /// sense. Omitted call sites still get the generic explanation.
    var substanceName: String?
    var field: SubstanceStore.AttributableField?

    @State private var showExplainer = false

    private var displayName: String {
        SubstanceStore.shared.sourceDisplayName(forSlug: slug)
    }

    var body: some View {
        Button {
            showExplainer = true
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Explains why this source was used and lets you reorder sources"))
        .sheet(isPresented: $showExplainer) {
            SourceAttributionExplainer(
                label: label, winnerSlug: slug,
                substanceName: substanceName, field: field, deepLink: deepLink,
            )
            .presentationDetents([.medium, .large])
        }
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
                .foregroundStyle(Theme.accent)
            Image(systemName: "questionmark.circle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.secondaryLabel)
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(String(localized: label)), source: \(displayName)"))
    }
}

/// Explains *why* a displayed field came from a particular source: names the
/// winning source, states the plain priority rule, lists the sources that
/// actually carry this field (so a lower-ranked winner makes sense), links to the
/// source's page, and shortcuts to the reorder screen. Reached by tapping any
/// ``SourceAttributionRow`` badge.
struct SourceAttributionExplainer: View {
    let label: LocalizedStringResource
    let winnerSlug: String
    var substanceName: String?
    var field: SubstanceStore.AttributableField?
    var deepLink: URL?

    @Environment(\.dismiss) private var dismiss

    private var descriptions: [String: String] {
        Dictionary(
            SubstanceStore.shared.sourceStates().compactMap { state in
                state.description.map { (state.slug, $0) }
            },
            uniquingKeysWith: { first, _ in first },
        )
    }

    /// Enabled sources that carry this field, winner first. Empty when the caller
    /// gave no field context (generic explainer).
    private var candidates: [String] {
        guard let field, let substanceName else { return [] }
        return SubstanceStore.shared.sourcesProviding(field, forSubstanceName: substanceName)
    }

    private func displayName(_ slug: String) -> String {
        SubstanceStore.shared.sourceDisplayName(forSlug: slug)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(label)
                            .font(.caption2.weight(.bold))
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.secondaryLabel)
                        Text(displayName(winnerSlug))
                            .font(.title3.weight(.semibold))
                        if let description = descriptions[winnerSlug] {
                            Text(description)
                                .font(.callout)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Shown from")
                }

                Section {
                    Text("Piru shows the highest-priority source you've enabled that has this data — and you choose the order.")
                        .font(.callout)
                    ForEach(candidates, id: \.self) { slug in
                        HStack {
                            Text(displayName(slug))
                            Spacer()
                            if slug == winnerSlug {
                                Text("Shown")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                            } else {
                                Text("Also has this")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryLabel)
                            }
                        }
                    }
                } header: {
                    Text("Why this source")
                } footer: {
                    if field != nil {
                        Text("Higher-priority sources that don't list this field are skipped.")
                    }
                }

                Section {
                    if let deepLink {
                        Link(destination: deepLink) {
                            Label("Open \(displayName(winnerSlug)) page", systemImage: "arrow.up.right.square")
                        }
                    }
                    NavigationLink {
                        SourcePriorityView()
                    } label: {
                        Label("Manage source priority", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
            .navigationTitle("Where this comes from")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Receptor Literature Row

// Single binding row inside the pharma-nerd "Receptor Literature" disclosure.
// Each row shows the target, action, Ki or EC50 value, optional species,
// source slug, and a PMID/DOI affordance so the user can verify the claim.

// MARK: - Substance Tag Flow
