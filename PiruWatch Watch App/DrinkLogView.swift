import SwiftUI
import WatchKit

/// The alcohol-by-drink flow — the originating "log a drink as you order it" use case. Pick a
/// preset (Beer/Wine/Shot/Pint), then adjust its volume on the Crown and log. The watch shows a
/// live grams/standard-drinks estimate; the phone recomputes the canonical stored grams.
struct DrinkLogView: View {
    let item: QuickLogManifestItem

    @Environment(WatchSyncCoordinator.self) private var sync

    var body: some View {
        List {
            ForEach(presets) { preset in
                NavigationLink {
                    DrinkVolumeView(item: item, preset: preset)
                } label: {
                    HStack(spacing: 10) {
                        Text(preset.emoji)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(preset.name).font(.headline)
                            Text("\(WatchDoseFormat.amount(preset.volumeML)) mL · \(WatchDoseFormat.amount(preset.defaultABV))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(item.displayName ?? item.substance)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if presets.isEmpty {
                ContentUnavailableView("No Drink Presets", systemImage: "wineglass")
            }
        }
    }

    private var presets: [ManifestDrinkPreset] {
        sync.manifest?.drinkPresets ?? []
    }
}

/// Volume + ABV adjust for one preset, with a live readout, then log.
struct DrinkVolumeView: View {
    let item: QuickLogManifestItem
    let preset: ManifestDrinkPreset

    @Environment(WatchSyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var volumeML: Double = 0
    @State private var abv: Double = 0

    var body: some View {
        VStack(spacing: 4) {
            Text("\(preset.emoji) \(preset.name)")
                .font(.headline)

            Text("\(WatchDoseFormat.amount(volumeML)) mL")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: volumeML)

            abvStepper

            Text("≈ \(WatchDoseFormat.amount(grams)) g · ≈ \(WatchDoseFormat.amount(drinks)) drinks")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button(action: log) {
                Label("Log", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 2)
        }
        .focusable()
        .digitalCrownRotation(
            $volumeML,
            from: 10,
            through: 1500,
            by: 10,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true,
        )
        .onAppear {
            volumeML = preset.volumeML
            abv = preset.defaultABV
        }
        .navigationTitle("Volume")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var abvStepper: some View {
        HStack(spacing: 8) {
            Button { abv = max(0.5, abv - 0.5) } label: { Image(systemName: "minus") }
            Text("\(WatchDoseFormat.amount(abv))% ABV")
                .font(.caption)
                .monospacedDigit()
            Button { abv = min(80, abv + 0.5) } label: { Image(systemName: "plus") }
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
    }

    private var grams: Double { WatchDrinkMath.grams(volumeML: volumeML, abv: abv) }
    private var drinks: Double { WatchDrinkMath.standardDrinks(volumeML: volumeML, abv: abv) }

    private func log() {
        let payload = item.makePayload(
            id: UUID(),
            amount: grams,
            timestamp: Date(),
            volumeML: volumeML,
            abv: abv,
            drinkName: preset.name,
            emoji: preset.emoji,
        )
        sync.log(payload)
        WKInterfaceDevice.current().play(.success)
        dismiss()
    }
}
