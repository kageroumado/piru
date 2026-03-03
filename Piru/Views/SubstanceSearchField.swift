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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Substance name", text: $text)
                .autocorrectionDisabled()
                .focused($isFocused)
                .disabled(locked)
                .foregroundStyle(locked ? .secondary : .primary)
                .onChange(of: text) {
                    if suppressSearch {
                        suppressSearch = false
                        return
                    }
                    if text.isEmpty {
                        results = []
                        showResults = false
                    } else if isFocused && !locked {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(50))
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
                    }
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
                                            Text(substance.name)
                                                .font(.body)
                                                .foregroundStyle(.primary)
                                            if favoriteNames.contains(substance.name.lowercased()) {
                                                Image(systemName: "star.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.yellow)
                                            }
                                        }
                                        if !substance.aliases.isEmpty {
                                            Text(substance.aliases.prefix(3).joined(separator: ", "))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text(substance.category.rawValue)
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
                        if !text.isEmpty && !hasExactMatch {
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
                                            .foregroundStyle(.secondary)
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
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            }
        }
    }
}
