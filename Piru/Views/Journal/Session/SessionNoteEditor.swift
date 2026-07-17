import SwiftUI

/// A small sheet for editing a session's free-form note.
struct SessionNoteEditor: View {
    /// Bound to the caller's scratch draft (seeded from `session.note` before the
    /// sheet opens). Binding — not a re-seeded `@State` — so the existing note is
    /// always present on re-open; Cancel simply discards the unsaved draft.
    @Binding var text: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    /// The rounded, padded editor ground — concentric with the sheet, matching
    /// the share sheet's card language.
    private var editorShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background { editorShape.fill(.thickMaterial) }
                .overlay(editorShape.stroke(Color.primary.opacity(0.08), lineWidth: 1))
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
                .navigationTitle("Session Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.body.weight(.semibold))
                        }
                        .accessibilityLabel(Text("Cancel"))
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            onSave(text)
                            dismiss()
                        } label: {
                            Image(systemName: "checkmark").font(.body.weight(.semibold))
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.accent)
                        .accessibilityLabel(Text("Save"))
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { focused = true }
    }
}
