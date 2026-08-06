import SwiftUI
import WatchKit

/// A mass dose adjusted with the Digital Crown, then logged. Starts at the tile's default
/// amount; the Crown nudges it by a dose-scaled step. "Log" queues the transfer and returns.
struct AmountLogView: View {
    let item: QuickLogManifestItem

    @Environment(WatchSyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var amount: Double = 0

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
            $amount,
            from: 0,
            through: max(item.amount * 10, 1000),
            by: AmountStep.forAmount(item.amount),
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true,
        )
        .onAppear { amount = item.amount }
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
