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
    /// Raw Crown accumulator, snapped to ``volumeML`` in 10 mL steps.
    @State private var volumeCrown: Double = 0
    @State private var abv: Double = 0
    /// The Crown drives whichever element has focus. With the ABV ± and Log buttons
    /// also focusable, focus has to be pinned to the volume control or the Crown does
    /// nothing — hence explicit focus here (the amount view needs none: Log is its
    /// only button).
    @FocusState private var volumeFocused: Bool
    /// Shows the "Logged" confirmation, then returns to the grid.
    @State private var confirming = false

    /// Volume nudge, matching the dock's 10 mL increment.
    private static let volumeStepML = 10.0

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
        .focused($volumeFocused)
        .digitalCrownRotation(
            $volumeCrown,
            from: 0,
            through: 2_000,
            by: Self.volumeStepML,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true,
        )
        .onChange(of: volumeCrown) { _, raw in
            // Snap to 10 mL steps anchored to the preset volume, so a 44 mL shot
            // nudges 34 / 44 / 54 rather than a jittery 41.7.
            let steps = ((raw - preset.volumeML) / Self.volumeStepML).rounded()
            volumeML = max(0, preset.volumeML + steps * Self.volumeStepML)
        }
        .onAppear {
            volumeML = preset.volumeML
            abv = preset.defaultABV
            volumeCrown = preset.volumeML
            volumeFocused = true
        }
        .overlay { if confirming { LoggedOverlay().transition(.opacity) } }
        .animation(.snappy, value: confirming)
        .task(id: confirming) {
            guard confirming else { return }
            try? await Task.sleep(for: .seconds(0.85))
            dismiss()
        }
        .navigationTitle("Volume")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var abvStepper: some View {
        HStack(spacing: 8) {
            // Return focus to the volume Crown after a tap, so it stays adjustable.
            Button { abv = max(0.5, abv - 0.5); volumeFocused = true } label: { Image(systemName: "minus") }
            Text("\(WatchDoseFormat.amount(abv))% ABV")
                .font(.caption)
                .monospacedDigit()
            Button { abv = min(80, abv + 0.5); volumeFocused = true } label: { Image(systemName: "plus") }
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
    }

    private var grams: Double {
        WatchDrinkMath.grams(volumeML: volumeML, abv: abv)
    }
    private var drinks: Double {
        WatchDrinkMath.standardDrinks(volumeML: volumeML, abv: abv)
    }

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
        confirming = true
    }
}
