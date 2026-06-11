import SwiftUI

// MARK: - Read-Only Tag Display

struct TagChipsView: View {
    let tags: [String]
    var compact: Bool = false

    var body: some View {
        if !tags.isEmpty {
            FlowLayout(spacing: 4) {
                ForEach(tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(compact ? .caption2 : .caption)
                        .padding(.horizontal, compact ? 5 : 6)
                        .padding(.vertical, compact ? 2 : 3)
                        .background(Theme.accent.opacity(0.12))
                        .foregroundStyle(Theme.accent)
                        .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - Editable Tag Editor

struct TagEditorView: View {
    @Binding var tags: [String]
    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !tags.isEmpty {
                FlowLayout(spacing: 6) {
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
                                    .padding(12)
                                    .contentShape(Rectangle())
                            }
                            .padding(-12)
                            .accessibilityLabel(Text("Remove \(tag)"))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.accent.opacity(0.15))
                        .foregroundStyle(Theme.accent)
                        .clipShape(Capsule())
                    }
                }
            }

            HStack {
                TextField("Add tag...", text: $newTag)
                    .font(.subheadline)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { addTag() }
                if !newTag.isEmpty {
                    Button("Add") { addTag() }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.accent)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(availableSuggestions, id: \.self) { suggestion in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                tags.append(suggestion)
                            }
                        } label: {
                            Text("#\(suggestion)")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.secondarySystemFill))
                                .foregroundStyle(.secondary)
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
