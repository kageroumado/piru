import SwiftUI

private struct SubstanceEntry: Identifiable, Equatable {
    let id = UUID()
    var name: String = ""
}

struct InteractionCheckerView: View {
    @State private var entries: [SubstanceEntry] = [SubstanceEntry(), SubstanceEntry()]
    @State private var results: [InteractionResult] = []
    @State private var hasChecked = false

    private var filledNames: [String] {
        entries.map(\.name).filter { !$0.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Substances section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Substances to check")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal)

                    VStack(spacing: 0) {
                        ForEach(Array($entries.enumerated()), id: \.element.id) { index, $entry in
                            VStack(spacing: 0) {
                                SubstanceSearchField(text: $entry.name) { selected in
                                    entry.name = selected.name
                                    recheckInteractions()
                                } onCustom: {
                                    recheckInteractions()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)

                                if entries.count > 2 {
                                    HStack {
                                        Spacer()
                                        Button(role: .destructive) {
                                            entries.remove(at: index)
                                            if entries.count < 2 {
                                                entries.append(SubstanceEntry())
                                            }
                                            recheckInteractions()
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundStyle(.red)
                                                .font(.body)
                                        }
                                    }
                                    .padding(.trailing, 16)
                                    .padding(.bottom, 4)
                                }

                                if index < entries.count - 1 {
                                    Divider()
                                        .padding(.leading, 16)
                                }
                            }
                        }

                        if entries.count < 8 {
                            Divider()
                                .padding(.leading, 16)
                            Button {
                                entries.append(SubstanceEntry())
                            } label: {
                                Label("Add Substance", systemImage: "plus.circle")
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    Text("Enter 2 or more substances to check for interactions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                // Results section
                if hasChecked {
                    if results.isEmpty {
                        VStack(spacing: 0) {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.title3)
                                Text("No known interactions found between these substances.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(16)
                        }
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(
                                results.count == 1 ? "1 Interaction Found" : "\(results.count) Interactions Found",
                                systemImage: results.first?.severity == .dangerous
                                    ? "exclamationmark.triangle.fill" : "exclamationmark.triangle"
                            )
                            .font(.subheadline)
                            .foregroundStyle((results.first?.severity ?? .caution).color)
                            .textCase(.uppercase)
                            .padding(.horizontal)

                            VStack(spacing: 0) {
                                ForEach(Array(results.enumerated()), id: \.offset) { index, warning in
                                    InteractionWarningRow(warning: warning)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                    if index < results.count - 1 {
                                        Divider()
                                            .padding(.leading, 16)
                                    }
                                }
                            }
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.top, 12)
        }
        .background(Color(.systemBackground))
    }

    private func recheckInteractions() {
        let filled = filledNames
        guard filled.count >= 2 else {
            results = []
            hasChecked = false
            return
        }
        results = InteractionChecker.checkBatch(filled, against: [])
        hasChecked = true
    }
}
