import SwiftUI

/// The picker offers only what the engine can simulate, split into what can
/// anchor a plan and what merely shapes one. Searching the whole library let you
/// pick, say, lisdexamfetamine and get a dose marker with no curve.
struct SandboxSubstancePicker: View {
    let onPick: (Substance) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    private func matches(_ substance: Substance) -> Bool {
        guard !trimmedQuery.isEmpty else { return true }
        return substance.displayTitle.localizedCaseInsensitiveContains(trimmedQuery)
            || substance.name.localizedCaseInsensitiveContains(trimmedQuery)
    }

    private var anchors: [Substance] {
        SandboxModelability.anchors.filter(matches)
    }

    private var adjuncts: [Substance] {
        SandboxModelability.adjuncts.filter(matches)
    }

    var body: some View {
        NavigationStack {
            List {
                if !anchors.isEmpty {
                    Section {
                        ForEach(anchors) { row($0) }
                    } header: {
                        Text("Calibrated")
                    } footer: {
                        Text("The model was calibrated on these. Each one can be modeled on its own.")
                    }
                }
                if !adjuncts.isEmpty {
                    Section {
                        ForEach(adjuncts) { row($0) }
                    } header: {
                        Text("Modeled alongside")
                    } footer: {
                        Text("The engine can simulate these as part of a plan, but they need a calibrated substance in the same plan to anchor the curve.")
                    }
                }
                if anchors.isEmpty, adjuncts.isEmpty {
                    ContentUnavailableView.search(text: trimmedQuery)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search substances")
            .navigationTitle("Pick a substance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                }
            }
        }
    }

    private func row(_ substance: Substance) -> some View {
        Button {
            onPick(substance)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(substance.displayTitle)
                        .foregroundStyle(.primary)
                    Text(substance.category.displayName)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
