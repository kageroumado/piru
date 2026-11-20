import SwiftUI

/// Picks a new "When" preset as hours + minutes, rejecting duplicates and values
/// outside ``DoseTimeDefaults/range``. Presented by the quick-log Edit sheet's
/// inline dose-times list.
struct DoseTimeAddSheet: View {
    let existing: [Int]
    let onAdd: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hours = 1
    @State private var minutes = 0

    private var total: Int {
        hours * 60 + minutes
    }
    private var isDuplicate: Bool {
        existing.contains(total)
    }
    private var isValid: Bool {
        DoseTimeDefaults.range.contains(total) && !isDuplicate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 0) {
                        Picker("Hours", selection: $hours) {
                            ForEach(0 ..< 24) { Text("\($0) h").tag($0) }
                        }
                        .wheelPickerStyle()
                        Picker("Minutes", selection: $minutes) {
                            ForEach(0 ..< 60) { Text("\($0) min").tag($0) }
                        }
                        .wheelPickerStyle()
                    }
                    .labelsHidden()
                } footer: {
                    if isDuplicate {
                        Text("That preset already exists.")
                    } else if total < DoseTimeDefaults.range.lowerBound {
                        Text("Choose at least one minute.")
                    } else {
                        Text("Adds “\(TrayTime.offsetLabel(minutes: total))”.")
                    }
                }
            }
            .themedPage()
            .navigationTitle("Add Preset")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        onAdd(total)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
