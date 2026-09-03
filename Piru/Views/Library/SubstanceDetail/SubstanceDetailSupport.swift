import SwiftData
import SwiftUI

/// One row in the merged "Sources" list — a contributing database or a piece of
/// primary literature, deep-linked to this substance's page where one exists,
/// paired with what it actually supplied for *this* compound.
struct DetailSourceLink: Identifiable {
    let id = UUID()
    let label: String
    var url: URL?
    /// Which parts of the page this row is behind, most substantive first.
    /// Empty when the caller didn't load the contribution ledger, and for
    /// literature attached to the compound in general rather than to one fact.
    var provides: [SubstanceStore.SourceFacet] = []
    /// Content license for a copyleft source (CC BY-SA 4.0), shown beside the
    /// name. `nil` for sources that carry no such obligation.
    var license: String?
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
/// `DisclosureGroup` with a semibold subheadline label and an optional count
/// badge. Extracted so Mechanism, Receptor Literature, Info, Chemistry and the
/// Cautions list fold identically. Crucially, a section's source-attribution row
/// goes *inside* `content` so it collapses with the body rather than dangling
/// beneath a closed disclosure.
struct CollapsibleSection<Content: View>: View {
    /// A resolved `Text` rather than a key, so a section whose title is *data*
    /// — a pharmacological class read from the database — can use the same
    /// chrome without minting a catalog key per class.
    let title: Text
    var count: Int?
    /// When set, a trailing (i) button appears in the header that runs this action — used to open a
    /// plain-language help sheet for the denser cards. Borderless so it captures its own tap and
    /// doesn't also toggle the disclosure.
    var onInfo: (() -> Void)?
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    init(
        _ title: LocalizedStringResource,
        count: Int? = nil,
        onInfo: (() -> Void)? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content,
    ) {
        self.init(
            title: Text(title), count: count, onInfo: onInfo,
            isExpanded: isExpanded, content: content,
        )
    }

    /// For a title that is data. Pass `Text(verbatim:)`.
    init(
        title: Text,
        count: Int? = nil,
        onInfo: (() -> Void)? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content,
    ) {
        self.title = title
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
            HStack(spacing: Spacing.sm) {
                title
                    .sectionLabel()
                if let count {
                    Text(verbatim: "\(count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.secondaryLabel)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 1)
                        .background(Theme.secondaryLabel.opacity(Theme.Opacity.tint), in: Capsule())
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

/// The status pill in the top-right corner of an editorial card — a
/// combination's severity (DANGER / CAUTION / NOTE) or the water/heat takeaway
/// ("Sip to thirst", "≈ 1 glass / hour"). One Capsule style so the two cards
/// read as a set. The caller supplies a resolved `Text` (localized key or
/// verbatim data string) and the tint.
struct EditorialPill: View {
    let label: Text
    let foreground: Color
    let background: Color

    var body: some View {
        label
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .textCase(.uppercase)
            .foregroundStyle(foreground)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
            .fixedSize()
    }
}

/// A card's source footer — "Mechanism · FreeOD Wiki".
///
/// **Always nest this inside its card's own `VStack`; never make it a peer list
/// row.** Every call site does, and the uniformity is the point:
///
/// - As a peer row the gap above it was the card row's bottom inset *plus* its
///   own top inset — 39pt in Additional Info against the 20pt below it, while a
///   nested one was cramped at 13pt. Same component, three different rhythms.
/// - A row boundary under a card also sits at a position that depends on the
///   card's height, and at some heights it lands mid-pixel and the page
///   background shows through as a hairline white line. Expanding "All phases"
///   in Dose & Duration reproduced this every time.
///
/// Nesting removes both: one gap, stated once below, and no boundary to fall
/// through. Neither `listRowInsets` nor negative padding fixes the peer case —
/// they move the space below the row rather than removing it.
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

    /// Set here rather than by each card, so the footer sits the same distance
    /// below its content everywhere. Pairs with the ~20pt the enclosing section
    /// already leaves beneath it.
    private static let topGap: CGFloat = 12

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
        .padding(.top, Self.topGap)
        // A no-op while every call site nests this inside a card, and kept as
        // the backstop for the day one doesn't: as a peer row it used to grow a
        // separator that no other card had.
        .listRowSeparator(.hidden, edges: .top)
        .accessibilityHint(Text("Explains why this source was used and lets you reorder sources"))
        .sheet(isPresented: $showExplainer) {
            SourceAttributionExplainer(
                label: label, winnerSlug: slug,
                substanceName: substanceName, field: field, deepLink: deepLink,
            )
            .presentationDetents([.medium, .large])
        }
    }

    /// A book glyph marks the row as a source, and there's no trailing glyph.
    /// Keep it neutral: a source is a reference the app *drew from*, not a fact it
    /// vouches for — so never a `checkmark.seal` or any verification/approval mark,
    /// which reads as "we certify this" next to data we explicitly tell people to
    /// verify against the original. The accent source name is the tappable cue,
    /// same as everywhere else in the app.
    private var rowContent: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "book.closed")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
            Text("·")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
            Text(displayName)
                .font(.caption2)
                .foregroundStyle(Theme.accent)
            Spacer()
        }
        .padding(.vertical, Spacing.xxs)
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
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(label)
                            .font(.caption2.weight(.bold))
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.secondaryLabel)
                        Text(displayName(winnerSlug))
                            .screenTitle()
                        if let description = descriptions[winnerSlug] {
                            Text(description)
                                .font(.callout)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }
                    .padding(.vertical, Spacing.xxs)
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
                                    .captionSecondary()
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
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityLabel(Text("Done"))
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
