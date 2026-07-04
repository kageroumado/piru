import SwiftUI

struct SubstanceSearchField: View {
    @Binding var text: String
    var onSelect: (Substance) -> Void
    var onCustom: (() -> Void)?
    var locked: Bool
    var favoriteNames: Set<String>

    @State private var results: [Substance] = []
    @State private var showResults = false
    @State private var suppressSearch = false
    @State private var searchTrigger = 0
    @FocusState private var isFocused: Bool

    init(text: Binding<String>, locked: Bool = false, favoriteNames: Set<String> = [], onSelect: @escaping (Substance) -> Void, onCustom: (() -> Void)? = nil) {
        _text = text
        self.locked = locked
        self.favoriteNames = favoriteNames
        self.onSelect = onSelect
        self.onCustom = onCustom
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
                    let raw = SubstanceLibrary.search(text, limit: 12)
                    if favoriteNames.isEmpty {
                        results = raw
                    } else {
                        let favs = raw.filter { favoriteNames.contains($0.name.lowercased()) }
                        let rest = raw.filter { !favoriteNames.contains($0.name.lowercased()) }
                        results = favs + rest
                    }
                    showResults = true
                }
                .onChange(of: isFocused) {
                    if !isFocused {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showResults = false
                        }
                    }
                }

            if showResults {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(results.prefix(12)) { substance in
                            Button {
                                suppressSearch = true
                                text = substance.name
                                showResults = false
                                isFocused = false
                                onSelect(substance)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 4) {
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
                                            }
                                        }
                                        if let secondary = secondaryNames(for: substance) {
                                            Text(secondary)
                                                .font(.caption)
                                                .foregroundStyle(Theme.secondaryLabel)
                                        }
                                    }
                                    Spacer()
                                    Text(substance.category.displayName)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.fill.secondary, in: Capsule())
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Divider().padding(.leading, 12)
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
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Use \"\(text)\"")
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        Text("Custom substance (no dose data)")
                                            .font(.caption)
                                            .foregroundStyle(Theme.secondaryLabel)
                                    }
                                    Spacer()
                                    Text("Custom")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Theme.accent.opacity(0.25), in: Capsule())
                                        .foregroundStyle(Theme.accent)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 280)
                .background(CardBackground())
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            }
        }
    }
}
