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
    /// Shows the "Logged" confirmation, then returns to the grid.
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 6) {
            Text(item.displayName ?? item.substance)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text("\(WatchDoseFormat.amount(amount)) \(item.unit)")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .animation(.snappy, value: amount)
                // VoiceOver takes the Crown, so the amount steps by swipe as
                // well, by the same increment the Crown uses.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Amount")
                .accessibilityValue("\(WatchDoseFormat.amount(amount)) \(item.unit)")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: step(by: 1)
                    case .decrement: step(by: -1)
                    @unknown default: break
                    }
                }

            Text(WatchDoseFormat.route(item.route))
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button(action: log) {
                Label("Log", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            // 5.2:1 under the white label; the default gray fill is 3.95:1.
            .tint(.logButton)
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
        .overlay { if confirming { LoggedOverlay().transition(.opacity) } }
        .animation(.snappy, value: confirming)
        .task(id: confirming) {
            guard confirming else { return }
            try? await Task.sleep(for: .seconds(0.85))
            dismiss()
        }
        .navigationTitle("Amount")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Moves the amount one Crown step and the Crown with it, so a later turn
    /// continues from the new value.
    private func step(by steps: Double) {
        amount = max(0, amount + steps * item.step)
        crown = amount
    }

    private func log() {
        let payload = item.makePayload(id: UUID(), amount: amount, timestamp: Date())
        guard sync.log(payload) else { dismiss(); return }
        WKInterfaceDevice.current().play(.success)
        confirming = true
    }
}
