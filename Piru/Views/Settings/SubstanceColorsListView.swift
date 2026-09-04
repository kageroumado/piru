import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SubstanceColorsListView: View {
    @Query(sort: \SubstanceColor.substance) private var substanceColors: [SubstanceColor]
    @Environment(\.modelContext) private var modelContext
    @State private var editingSubstance: SubstanceColor?

    private func takenColorMap(excluding substance: String) -> [String: String] {
        // Two substances may legitimately share a hex (~1700 substances,
        // ~30 preset colors), so this dictionary must use uniquingKeysWith —
        // Dictionary(uniqueKeysWithValues:) traps on any duplicate-hex
        // assignment.
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
                        HStack(spacing: Spacing.xl) {
                            Circle()
                                .fill(sc.color)
                                .frame(width: IconSize.iconCompact, height: IconSize.iconCompact)
                            Text(CustomSubstanceStore.shared.displayName(for: sc.substance))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("Change")
                                .captionSecondary()
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
        .themedPage()
        .navigationTitle("Substance Colors")
        .inlineNavigationTitle()
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
