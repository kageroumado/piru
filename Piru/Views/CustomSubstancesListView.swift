import SwiftUI

struct CustomSubstancesListView: View {
    @State private var store = CustomSubstanceStore.shared

    @State private var showingForm = false
    @State private var editingSubstance: CustomSubstanceEntry?

    var body: some View {
        List {
            if store.all.isEmpty {
                ContentUnavailableView(
                    "No Custom Substances",
                    systemImage: "flask",
                    description: Text("Custom substances you create will appear here. You can also create them from the Quick Log search."),
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(store.all) { substance in
                    Button {
                        editingSubstance = substance
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: substance.category.icon)
                                .foregroundStyle(substance.category.color)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(substance.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                HStack(spacing: 6) {
                                    Text(substance.category.displayName)
                                    Text("·")
                                    Text(substance.defaultRoute.localizedName)
                                    Text("·")
                                    Text(substance.unit)
                                }
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryLabel)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }
                }
                .onDelete { offsets in
                    store.delete(at: offsets)
                }
                .listRowBackground(Theme.cardBackground)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Custom Substances")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingForm = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingForm) {
            CustomSubstanceFormView()
        }
        .sheet(item: $editingSubstance) { substance in
            CustomSubstanceFormView(existing: substance)
        }
    }
}
