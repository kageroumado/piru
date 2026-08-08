import SwiftUI

/// The misconceptions block — evidence-checked corrections to popular claims,
/// each with per-claim citation chips. A refuting paper reads as an accent chip;
/// the *retracted source* of a myth is marked and, when it links, points at the
/// retraction notice rather than the discredited paper. Rendered inside the
/// ``SafetySection`` card under a "Common misconceptions" sub-heading; the caller
/// gates on empty data. See ``MythBust``.
struct MythBustList: View {
    let misconceptions: [MythBust]
    var accent: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(misconceptions.enumerated()), id: \.offset) { index, myth in
                if index > 0 {
                    Divider().padding(.vertical, 8)
                }
                MythBustRow(myth: myth, accent: accent)
            }
        }
    }
}

/// One myth, collapsed to just its claim row. Tapping expands it to reveal the
/// correction, an optional pull-quote, and the citation chips — one at a time, so
/// the whole section stays a half-screen rather than an essay. Collapsed by
/// default at every tier.
private struct MythBustRow: View {
    let myth: MythBust
    let accent: Color

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Text(correction)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)

                if let quote = myth.pullQuote {
                    PullQuoteView(quote: quote)
                }

                if !myth.citations.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(myth.citations.enumerated()), id: \.offset) { _, citation in
                            MythCitationChip(citation: citation, accent: accent)
                        }
                    }
                }
            }
            .padding(.top, 6)
            .padding(.leading, Self.markerWidth)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .frame(width: Self.markerWidth - 8, alignment: .leading)
                    .accessibilityHidden(true)
                Text(myth.claim)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    // Prefix so VoiceOver never reads the claim as an endorsed
                    // fact before reaching the correction (the ✕ is silent).
                    .accessibilityLabel(Text("Myth: \(myth.claim)"))
            }
        }
        .tint(Theme.secondaryLabel)
        .padding(.vertical, 2)
    }

    /// Indent that aligns the expanded correction under the claim text, past the
    /// neutral marker glyph.
    private static let markerWidth: CGFloat = 28

    /// Renders the correction's Markdown emphasis (`**bold**`), falling back to
    /// plain text if the string somehow fails to parse.
    private var correction: AttributedString {
        (try? AttributedString(markdown: myth.correction)) ?? AttributedString(myth.correction)
    }
}

/// A short attributed quotation, set apart with a leading rule.
private struct PullQuoteView: View {
    let quote: PullQuote

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("“\(quote.text)”")
                .font(.callout.italic())
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
            Text("— \(quote.attribution)")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(Theme.secondaryLabel.opacity(0.3))
                .frame(width: 2)
        }
    }
}

/// A single citation chip. Tappable (opens the reference) when the citation
/// resolves to a URL; styled by role — a refuting source in the accent color, a
/// retracted source struck in red with a "no" glyph, a dataset in a neutral gray.
private struct MythCitationChip: View {
    let citation: MythCitation
    let accent: Color

    var body: some View {
        if let url = citation.citation.resolvedURL {
            Link(destination: url) { chip(linked: true) }
        } else {
            chip(linked: false)
        }
    }

    private var label: String {
        citation.note ?? citation.citation.label
    }

    private func chip(linked: Bool) -> some View {
        HStack(spacing: 3) {
            if citation.role == .retractedSource {
                Image(systemName: "nosign")
                    .font(.caption2)
                    .accessibilityHidden(true)
            }
            Text(label)
                .font(.caption2.weight(.medium))
                .strikethrough(citation.role == .retractedSource)
            if linked {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .semibold))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(background, in: Capsule())
        .accessibilityLabel(accessibilityLabel)
    }

    private var foreground: Color {
        switch citation.role {
        case .retractedSource: .red
        case .refutes: accent
        case .dataset: Theme.secondaryLabel
        }
    }

    private var background: Color {
        switch citation.role {
        case .retractedSource: Color.red.opacity(0.12)
        case .refutes: accent.opacity(0.12)
        case .dataset: Theme.secondaryLabel.opacity(0.1)
        }
    }

    private var accessibilityLabel: String {
        switch citation.role {
        case .retractedSource: String(localized: "Retracted source: \(label)")
        case .refutes, .dataset: label
        }
    }
}
