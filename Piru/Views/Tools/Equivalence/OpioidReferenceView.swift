import SwiftUI

/// Sourced oral MME factors and their applicability notes.
struct OpioidReferenceView: View {
    @State private var entries: [OpioidEquivalence] = []

    var body: some View {
        List {
            Section {
                Text("Published oral morphine milligram equivalent (MME) factors compare amounts across opioids. They must not be used to choose a replacement dose when switching medications.")
                    .font(.subheadline)
                Text("CDC 2022 reference factors. Individual response varies.")
                    .captionSecondary()
            }
            Section("Reference table") {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.pickerLabel).font(.headline)
                            Spacer()
                            if entry.convertibility == .linear, let factor = entry.mmePerMg {
                                Text("\(factor.doseFormatted) MME per mg")
                                    .font(.subheadline.monospacedDigit())
                            }
                        }
                        if let reason = entry.unconvertibleReason {
                            Text(reason).captionSecondary()
                        }
                    }
                    .padding(.vertical, Spacing.xxs)
                }
            }
        }
        .insetGroupedListStyle()
        .skinBackdrop()
        .appNavigationBar("Opioid MME")
        .task {
            await SubstanceStore.shared.ensureAllLoaded()
            entries = SubstanceStore.shared.opioidEquivalences()
                .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        }
    }
}
