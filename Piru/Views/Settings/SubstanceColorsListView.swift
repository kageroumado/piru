import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SubstanceColorsListView: View {
    @Query(sort: \SubstanceColor.substance) private var substanceColors: [SubstanceColor]
    @Environment(\.modelContext) private var modelContext
    @State private var editingSubstance: SubstanceColor?

    private func takenColorMap(excluding substance: String) -> [String: String] {
        // Use uniquingKeysWith — two substances may legitimately share a hex
        // (we have ~1700 substances and ~30 preset colors). Without it, this
        // crashed in build 11 when the user opened the color picker with
        // any duplicate-hex assignment present.
        Dictionary(
            substanceColors
                .filter { $0.substance != substance }
                .map { ($0.hexColor, $0.substance) },
            uniquingKeysWith: { first, _ in first },
        )
    }

    var body: some View {
        List {
            if substanceColors.isEmpty {
                ContentUnavailableView(
                    "No Substance Colors",
                    systemImage: "paintpalette",
                    description: Text("Colors appear here after you log your first entry. Tap one to change it."),
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(substanceColors) { sc in
                    Button {
                        editingSubstance = sc
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(sc.color)
                                .frame(width: 24, height: 24)
                            Text(CustomSubstanceStore.shared.displayName(for: sc.substance))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("Change")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        modelContext.delete(substanceColors[index])
                    }
                }
                .listRowBackground(CardBackground())
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Substance Colors")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingSubstance) { sc in
            SubstanceColorPickerView(
                substanceName: sc.substance,
                takenColors: takenColorMap(excluding: sc.substance),
            ) { hex in
                sc.hexColor = hex
                editingSubstance = nil
            }
            .presentationDetents([.large])
        }
    }
}
