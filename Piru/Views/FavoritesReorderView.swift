import SwiftData
import SwiftUI

// MARK: - Favorites Reorder

/// Native drag-handle reorder for favorites, presented from the Favorites
/// section header's Edit button. Always in edit mode — drag to reorder,
/// swipe/minus to unfavorite. Local sheet, so `@Environment(\.dismiss)`
/// (NOT `navigator.dismiss()`, which would pop the whole Log sheet).
struct FavoritesReorderView: View {
    @Query(sort: [SortDescriptor(\FavoriteSubstance.sortOrder), SortDescriptor(\FavoriteSubstance.createdAt, order: .reverse)]) private var favorites: [FavoriteSubstance]
    @Query private var substanceColors: [SubstanceColor]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var customStore = CustomSubstanceStore.shared

    var body: some View {
        NavigationStack {
            List {
                ForEach(favorites) { favorite in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(color(for: favorite.substance))
                            .frame(width: 10, height: 10)
                        Text(customStore.displayName(for: favorite.substance))
                    }
                }
                .onMove(perform: move)
                .onDelete(perform: delete)
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func color(for substance: String) -> Color {
        Array(substanceColors).hexColorMap[substance.lowercased()]
            .map { Color(hex: $0) } ?? .gray
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = favorites
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, favorite) in ordered.enumerated() {
            favorite.sortOrder = index
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(favorites[index])
        }
    }
}
