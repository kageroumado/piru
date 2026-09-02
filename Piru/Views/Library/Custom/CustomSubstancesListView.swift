import SwiftUI

struct CustomSubstancesListView: View {
    @State private var store = CustomSubstanceStore.shared

    @State private var showingForm = false
    @State private var editingSubstance: CustomSubstanceEntry?

    var body: some View {
        List {
            if store.all.isEmpty {
                ContentUnavailableView(
                    "No Substances Yet",
                    systemImage: "flask",
                    description: Text("Substances you create or personalize appear here. You can also create them from the Quick Log search."),
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(store.all) { substance in
                    Button {
                        editingSubstance = substance
                    } label: {
                        HStack(spacing: Spacing.xl) {
                            Image(systemName: substance.category.icon)
                                .foregroundStyle(substance.category.labelColor)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(substance.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                HStack(spacing: Spacing.sm) {
                                    Text(substance.category.displayName)
                                    Middot()
                                    Text(substance.defaultRoute.localizedName)
                                    Middot()
                                    Text(substance.unit)
                                }
                                .captionSecondary()
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .captionSecondary()
                                .accessibilityHidden(true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .onDelete { offsets in
                    store.delete(at: offsets)
                }
                .listRowBackground(CardBackground())
            }
        }
        .themedPage()
        .navigationTitle("Custom Substances")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Custom Substance")
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
