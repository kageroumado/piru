import SwiftUI

struct SubstanceSearchField: View {
    @Binding var text: String
    var onSelect: (Substance) -> Void
    var onCustom: (() -> Void)?

    @State private var results: [Substance] = []
    @State private var showResults = false
    @FocusState private var isFocused: Bool

    init(text: Binding<String>, onSelect: @escaping (Substance) -> Void, onCustom: (() -> Void)? = nil) {
        _text = text
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
                .onChange(of: text) {
                    if text.isEmpty {
                        results = []
                        showResults = false
                    } else if isFocused {
                        results = SubstanceLibrary.search(text)
                        showResults = true
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
                                text = substance.name
                                showResults = false
                                isFocused = false
                                onSelect(substance)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(substance.name)
                                            .font(.body)
                                            .foregroundStyle(.primary)
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
                                        .background(.fill.tertiary, in: Capsule())
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
                                        .background(Theme.accent.opacity(0.15), in: Capsule())
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
