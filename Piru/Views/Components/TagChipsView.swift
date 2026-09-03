import SwiftUI

// MARK: - Read-Only Tag Display

struct TagChipsView: View {
    let tags: [String]
    var compact: Bool = false

    var body: some View {
        if !tags.isEmpty {
            // Quiet inline treatment (Option C): one tag glyph + the tags joined,
            // kept low-key since they're secondary information, not chips competing
            // with the dose.
            HStack(spacing: Spacing.sm) {
                Image(systemName: "tag")
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(.tertiary)
                Text(tags.joined(separator: " · "))
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Tags: \(tags.joined(separator: ", "))"))
        }
    }
}

// MARK: - Editable Tag Editor

struct TagEditorView: View {
    @Binding var tags: [String]
    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if !tags.isEmpty {
                FlowLayout(spacing: Spacing.sm) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 3) {
                            Text("#\(tag)")
                                .font(.caption)
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    tags.removeAll { $0 == tag }
                                }
                            } label: {
                                // Inner padding grows the tappable area toward
                                // 44pt; the outer negative padding cancels it
                                // out of layout so the chip looks unchanged.
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                                    .padding(Spacing.xl)
                                    .contentShape(Rectangle())
                            }
                            .padding(-12)
                            .accessibilityLabel(Text("Remove \(tag)"))
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs)
                        .background(Theme.accent.opacity(Theme.Opacity.tint))
                        .foregroundStyle(Theme.accent)
                        .clipShape(Capsule())
                    }
                }
            }

            HStack {
                TextField("Add tag...", text: $newTag)
                    .font(.subheadline)
                    .autocorrectionDisabled()
                    .neverAutocapitalize()
                    .onSubmit { addTag() }
                if !newTag.isEmpty {
                    Button("Add") { addTag() }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.accent)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(availableSuggestions, id: \.self) { suggestion in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                tags.append(suggestion)
                            }
                        } label: {
                            Text("#\(suggestion)")
                                .font(.caption)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.xs)
                                .background(Color.platformSecondarySystemFill)
                                .foregroundStyle(Theme.secondaryLabel)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    private var availableSuggestions: [String] {
        TagExtractor.suggestions.filter { !tags.contains($0) }
    }

    private func addTag() {
        let cleaned = newTag
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: "#", with: "")
        guard !cleaned.isEmpty, !tags.contains(cleaned) else {
            newTag = ""
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            tags.append(cleaned)
        }
        newTag = ""
    }
}
