import SwiftUI

/// Lets the user drag the inventory's class sections into their own order.
///
/// A separate editor rather than in-place dragging because `List` can reorder
/// rows within a `ForEach` but has no notion of moving a whole `Section` — the
/// same reason ``SourcePriorityView`` exists, and it follows that screen's shape:
/// a permanently-editing list whose only affordance is the grab handle, plus a
/// Reset that hands ordering back to the sort.
struct InventoryClassOrderView: View {
    @Bindable var model: InventoryListModel
    /// Classes present in the inventory, in the order the manager shows them.
    let categories: [SubstanceCategory]

    @Environment(\.dismiss) private var dismiss
    /// Local working copy: dragging mutates this, and each move commits to the
    /// model so the list behind the sheet keeps up.
    @State private var ordered: [SubstanceCategory] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ordered) { category in
                        Label {
                            Text(category.displayName)
                                .font(.body.weight(.medium))
                        } icon: {
                            Image(systemName: category.icon)
                                .foregroundStyle(Theme.accent)
                                .accessibilityHidden(true)
                        }
                        .listRowBackground(CardBackground())
                    }
                    .onMove(perform: move)
                } footer: {
                    Text("Drag to set the order class sections appear in. Reset to let the current sort decide.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            // Permanent edit mode: the grips are always visible, and with no
            // delete or toggle the row is unmistakably about order.
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Arrange Classes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        model.resetCategoryOrder()
                        ordered = categories
                    }
                    .disabled(!model.hasCustomCategoryOrder)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear { ordered = categories }
    }

    private func move(from source: IndexSet, to destination: Int) {
        ordered.move(fromOffsets: source, toOffset: destination)
        model.setCategoryOrder(ordered)
    }
}
