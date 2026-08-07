import SwiftUI
import WatchKit

/// A mass dose adjusted with the Digital Crown, then logged. Starts at the tile's default
/// amount; the Crown nudges it by a dose-scaled step. "Log" queues the transfer and returns.
struct AmountLogView: View {
    let item: QuickLogManifestItem

    @Environment(WatchSyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss
    /// The value logged — always the tile amount ± a whole number of steps.
    @State private var amount: Double = 0
    /// The raw Crown accumulator, snapped to ``amount`` on change.
    @State private var crown: Double = 0

    var body: some View {
        VStack(spacing: 6) {
            Text(item.displayName ?? item.substance)
                .font(.headline)
                .lineLimit(1)

            Text("\(WatchDoseFormat.amount(amount)) \(item.unit)")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: amount)

            Text(WatchDoseFormat.route(item.route))
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button(action: log) {
                Label("Log", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .focusable()
        .digitalCrownRotation(
            $crown,
            from: 0,
            through: max(item.amount * 10, item.step * 200),
            by: item.step,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true,
        )
        .onChange(of: crown) { _, raw in
            // Snap to the dock's increment, anchored to the tile amount — so a 125 mg
            // chip nudges 115 / 125 / 135, never an off-ladder 124.5.
            let steps = ((raw - item.amount) / item.step).rounded()
            amount = max(0, item.amount + steps * item.step)
        }
        .onAppear {
            amount = item.amount
            crown = item.amount
        }
        .navigationTitle("Amount")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func log() {
        let payload = item.makePayload(id: UUID(), amount: amount, timestamp: Date())
        sync.log(payload)
        WKInterfaceDevice.current().play(.success)
        dismiss()
    }
}
