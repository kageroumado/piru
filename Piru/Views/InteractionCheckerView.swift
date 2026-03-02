import SwiftUI

private struct SubstanceEntry: Identifiable, Equatable {
    let id = UUID()
    var name: String = ""
}

struct InteractionCheckerView: View {
    @State private var entries: [SubstanceEntry] = [SubstanceEntry(), SubstanceEntry()]
    @State private var swipeOffsets: [UUID: CGFloat] = [:]
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
                                ZStack(alignment: .trailing) {
                                    // Delete background
                                    if entries.count > 2 {
                                        HStack {
                                            Spacer()
                                            Image(systemName: "trash.fill")
                                                .foregroundStyle(.white)
                                                .padding(.trailing, 20)
                                        }
                                        .frame(maxHeight: .infinity)
                                        .background(Color.red)
                                    }

                                    HStack(spacing: 8) {
                                        SubstanceSearchField(text: $entry.name) { selected in
                                            entry.name = selected.name
                                            recheckInteractions()
                                        } onCustom: {
                                            recheckInteractions()
                                        }

                                        if !entry.name.isEmpty {
                                            Button {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    entry.name = ""
                                                    recheckInteractions()
                                                }
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.title3)
                                                    .symbolRenderingMode(.hierarchical)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color(.systemBackground))
                                    .offset(x: swipeOffsets[entry.id] ?? 0)
                                    .gesture(
                                        entries.count > 2 ?
                                        DragGesture(minimumDistance: 20)
                                            .onChanged { value in
                                                let translation = min(0, value.translation.width)
                                                swipeOffsets[entry.id] = translation
                                            }
                                            .onEnded { value in
                                                if value.translation.width < -100 {
                                                    withAnimation(.easeInOut(duration: 0.25)) {
                                                        swipeOffsets[entry.id] = -400
                                                    }
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                                        withAnimation {
                                                            entries.remove(at: index)
                                                            swipeOffsets.removeValue(forKey: entry.id)
                                                            recheckInteractions()
                                                        }
                                                    }
                                                } else {
                                                    withAnimation(.easeInOut(duration: 0.2)) {
                                                        swipeOffsets[entry.id] = 0
                                                    }
                                                }
                                            }
                                        : nil
                                    )
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
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    entries.append(SubstanceEntry())
                                }
                            } label: {
                                Label("Add Substance", systemImage: "plus.circle")
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
                            Text(results.count == 1 ? "1 Interaction Found" : "\(results.count) Interactions Found")
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
