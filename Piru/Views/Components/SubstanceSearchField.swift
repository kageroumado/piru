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
    /// When true, the field keeps the matched brand the user tapped ("Medikinet")
    /// instead of resetting to the canonical name — for callers that store the
    /// canonical identity separately (via the `onSelect` substance) and want the
    /// box to keep reading the user's word. Default off: callers that persist the
    /// field text as the substance identity (Inventory) must keep the canonical.
    var keepsMatchedName: Bool

    @State private var results: [SubstanceMatch] = []
    @State private var showResults = false
    @State private var suppressSearch = false
    @State private var searchTrigger = 0
    @FocusState private var isFocused: Bool

    init(text: Binding<String>, locked: Bool = false, favoriteNames: Set<String> = [], keepsMatchedName: Bool = false, onSelect: @escaping (Substance, String?) -> Void, onCustom: (() -> Void)? = nil) {
        _text = text
        self.locked = locked
        self.favoriteNames = favoriteNames
        self.keepsMatchedName = keepsMatchedName
        self.onSelect = onSelect
        self.onCustom = onCustom
    }

    private var hasExactMatch: Bool {
        let q = text.lowercased()
        return results.contains {
            $0.substance.name.lowercased() == q || $0.substance.aliases.contains { $0.lowercased() == q }
        }
    }

    /// Canonical name + aliases for the subtitle, dropping whichever entry the row
    /// title already shows (the matched brand, e.g. "Medikinet", or the display
    /// title) and leading with the canonical name so a brand row reads "Medikinet"
    /// over "Methylphenidate, Ritalin, …".
    private func secondaryNames(for match: SubstanceMatch) -> String? {
        let shown = match.displayName.lowercased()
        let candidates = [match.substance.displayTitle, match.substance.name] + match.substance.aliases
        var seen = Set<String>()
        var names: [String] = []
        for name in candidates {
            let key = name.lowercased()
            guard key != shown, !seen.contains(key) else { continue }
            seen.insert(key)
            names.append(name)
        }
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
                    let raw = await SubstanceLibrary.searchMatchesAsync(text, limit: 12)
                    guard !Task.isCancelled else { return }
                    if favoriteNames.isEmpty {
                        results = raw
                    } else {
                        let favs = raw.filter { favoriteNames.contains($0.substance.name.lowercased()) }
                        let rest = raw.filter { !favoriteNames.contains($0.substance.name.lowercased()) }
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
                        ForEach(results.prefix(12)) { match in
                            let substance = match.substance
                            Button {
                                suppressSearch = true
                                text = keepsMatchedName ? match.displayName : substance.name
                                showResults = false
                                isFocused = false
                                onSelect(substance, match.matchedAlias)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                                        HStack(spacing: Spacing.xs) {
                                            // Lead with the matched name — the brand
                                            // the user typed ("Medikinet") when they
                                            // searched one, else the display title —
                                            // matching quick-log; the canonical name
                                            // leads the subtitle so it stays clear.
                                            Text(match.displayName)
                                                .font(.body)
                                                .foregroundStyle(.primary)
                                            if favoriteNames.contains(substance.name.lowercased()) {
                                                Image(systemName: "star.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.yellow)
                                                    .accessibilityHidden(true)
                                            }
                                        }
                                        if let secondary = secondaryNames(for: match) {
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
