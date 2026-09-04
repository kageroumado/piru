import SwiftUI

struct SubstanceSearchField: View {
    @Binding var text: String
    /// Reports the picked substance and the **brand/alias the query matched**, if
    /// any — so a caller can keep "Concerta" as the product name even though the
    /// field then shows the canonical "Methylphenidate". `nil` when the user typed
    /// the canonical/display name. Callers that don't track products ignore it.
    var onSelect: (Substance, String?) -> Void
    var onCustom: (() -> Void)?
    var locked: Bool
    var favoriteNames: Set<String>

    @State private var results: [Substance] = []
    @State private var showResults = false
    @State private var suppressSearch = false
    @State private var searchTrigger = 0
    @FocusState private var isFocused: Bool

    init(text: Binding<String>, locked: Bool = false, favoriteNames: Set<String> = [], onSelect: @escaping (Substance, String?) -> Void, onCustom: (() -> Void)? = nil) {
        _text = text
        self.locked = locked
        self.favoriteNames = favoriteNames
        self.onSelect = onSelect
        self.onCustom = onCustom
    }

    /// The product name to carry for a tapped result: the alias the current query
    /// matched, resolved through the same ranked search the quick-log capture uses
    /// (`SubstanceMatch/matchedAlias`), so both paths keep the user's word the same
    /// way. `nil` when the query was the canonical/display name.
    private func matchedProduct(for substance: Substance) -> String? {
        SubstanceLibrary.searchMatches(text).first { $0.substance.id == substance.id }?.matchedAlias
    }

    private var hasExactMatch: Bool {
        let q = text.lowercased()
        return results.contains { $0.name.lowercased() == q || $0.aliases.contains { $0.lowercased() == q } }
    }

    /// Canonical name + aliases for the subtitle, dropping whichever entries the
    /// title (``Substance/displayTitle``) already shows, so the line doesn't echo
    /// the title back (e.g. title "2-Br-DCK" → subtitle "Bromoketamine, …").
    private func secondaryNames(for substance: Substance) -> String? {
        let title = substance.displayTitle.lowercased()
        let names = ([substance.name] + substance.aliases)
            .filter { $0.lowercased() != title }
        return names.isEmpty ? nil : names.prefix(3).joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Substance name", text: $text)
                .autocorrectionDisabled()
                .focused($isFocused)
                .disabled(locked)
                .foregroundStyle(locked ? Theme.secondaryLabel : Color.primary)
                .onChange(of: text) {
                    if suppressSearch {
                        suppressSearch = false
                        return
                    }
                    if text.isEmpty {
                        results = []
                        showResults = false
                    } else if isFocused, !locked {
                        searchTrigger += 1
                    }
                }
                .task(id: searchTrigger) {
                    guard searchTrigger > 0 else { return }
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled, !text.isEmpty, isFocused else { return }
                    let raw = await SubstanceLibrary.searchAsync(text, limit: 12)
                    guard !Task.isCancelled else { return }
                    if favoriteNames.isEmpty {
                        results = raw
                    } else {
                        let favs = raw.filter { favoriteNames.contains($0.name.lowercased()) }
                        let rest = raw.filter { !favoriteNames.contains($0.name.lowercased()) }
                        results = favs + rest
                    }
                    showResults = true
                }
                // Hide a beat after focus loss (cancellable, unlike the old
                // `asyncAfter`) — refocusing within the beat keeps the results.
                .task(id: isFocused) {
                    guard !isFocused else { return }
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    showResults = false
                }

            if showResults {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(results.prefix(12)) { substance in
                            Button {
                                let product = matchedProduct(for: substance)
                                suppressSearch = true
                                text = substance.name
                                showResults = false
                                isFocused = false
                                onSelect(substance, product)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                                        HStack(spacing: Spacing.xs) {
                                            // Show the same presentation name as
                                            // the journal / quick-log (display
                                            // override, regional name); the
                                            // canonical name still leads the
                                            // subtitle so it stays discoverable.
                                            Text(substance.displayTitle)
                                                .font(.body)
                                                .foregroundStyle(.primary)
                                            if favoriteNames.contains(substance.name.lowercased()) {
                                                Image(systemName: "star.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.yellow)
                                                    .accessibilityHidden(true)
                                            }
                                        }
                                        if let secondary = secondaryNames(for: substance) {
                                            Text(secondary)
                                                .captionSecondary()
                                        }
                                    }
                                    Spacer()
                                    Text(substance.category.displayName)
                                        .font(.caption2)
                                        .padding(.horizontal, Spacing.sm)
                                        .padding(.vertical, Spacing.xxs)
                                        .background(.fill.secondary, in: Capsule())
                                }
                                .padding(.horizontal, Spacing.xl)
                                .padding(.vertical, Spacing.md)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(favoriteNames.contains(substance.name.lowercased()) ? Text("Favorite") : Text(verbatim: ""))

                            Divider().padding(.leading, Spacing.xl)
                        }

                        // Custom substance option
                        if !text.isEmpty, !hasExactMatch {
                            Button {
                                showResults = false
                                isFocused = false
                                onCustom?()
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(Theme.accent)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                                        Text("Use \"\(text)\"")
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        Text("Custom substance (no dose data)")
                                            .captionSecondary()
                                    }
                                    Spacer()
                                    Text("Custom")
                                        .font(.caption2)
                                        .padding(.horizontal, Spacing.sm)
                                        .padding(.vertical, Spacing.xxs)
                                        .background(Theme.accent.opacity(Theme.Opacity.emphasis), in: Capsule())
                                        .foregroundStyle(Theme.accent)
                                }
                                .padding(.horizontal, Spacing.xl)
                                .padding(.vertical, Spacing.md)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 280)
                .background(CardBackground())
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.input))
                .shadow(color: .black.opacity(Theme.Opacity.tint), radius: 4, y: 2)
            }
        }
    }
}
