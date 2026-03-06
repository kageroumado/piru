import SwiftUI
import SwiftData

struct RampDownView: View {
    let entry: DoseEntry
    let duration: DurationProfile

    @State private var isActive: Bool = false
    @State private var permissionDenied = false
    @State private var showingCancelConfirmation = false

    private var redoseTime: Date {
        RampDownScheduler.calculateRedoseTime(doseTime: entry.timestamp, duration: duration)
    }

    private var suggestedAmount: Double {
        RampDownScheduler.suggestedRedoseAmount(entry.amount)
    }

    private var isRedoseTimePast: Bool {
        redoseTime < Date.now
    }

    var body: some View {
        List {
            infoSection
            timingSection
            actionSection
        }
        .navigationTitle("Ramp Down")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isActive = RampDownScheduler.isActive(for: entry.persistentModelID.hashValue)
        }
        .alert("Notifications Disabled", isPresented: $permissionDenied) {
            Button("OK") {}
        } message: {
            Text("Please enable notifications in Settings to use Ramp Down alerts.")
        }
        .confirmationDialog(
            "Cancel Ramp Down?",
            isPresented: $showingCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel Alert", role: .destructive) {
                cancelAlert()
            }
        } message: {
            Text("This will cancel the comedown notification.")
        }
    }

    // MARK: - Info

    private var infoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("How it works", systemImage: "info.circle")
                    .font(.subheadline.weight(.semibold))

                Text("When you're approaching the comedown, Piru will notify you. Taking a small redose at that moment lets the comeup of the new dose overlap with the fadeout of the current one — no crash gap.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Timing

    private var timingSection: some View {
        Section("Timing") {
            LabeledContent("Dose taken", value: entry.timestamp.formatted(date: .omitted, time: .shortened))

            LabeledContent("Peak ends ~", value: peakEndTime.formatted(date: .omitted, time: .shortened))

            HStack {
                Text("Redose alert")
                Spacer()
                if isRedoseTimePast {
                    Text(redoseTime.formatted(date: .omitted, time: .shortened))
                        .foregroundStyle(Theme.secondaryLabel)
                    Text("(past)")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text(redoseTime.formatted(date: .omitted, time: .shortened))
                    Text("(\(redoseTime, style: .relative))")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }

            LabeledContent("Suggested redose") {
                Text("~\(suggestedAmount.doseFormatted) \(entry.unit)")
                    .foregroundStyle(Theme.accent)
                    .fontWeight(.semibold)
            }
        }
    }

    private var peakEndTime: Date {
        let peakEndMinutes = duration.phaseBoundaries.peakEnd
        return entry.timestamp.addingTimeInterval(peakEndMinutes * 60)
    }

    // MARK: - Action

    private var actionSection: some View {
        Section {
            if isActive {
                HStack {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(.green)
                    Text("Alert scheduled")
                        .font(.headline)
                    Spacer()
                    Text(redoseTime.formatted(date: .omitted, time: .shortened))
                        .foregroundStyle(Theme.secondaryLabel)
                }

                Button("Cancel Alert", role: .destructive) {
                    showingCancelConfirmation = true
                }
                .frame(maxWidth: .infinity)
            } else if isRedoseTimePast {
                HStack {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                    Text("Redose window has passed")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            } else {
                Button {
                    activateAlert()
                } label: {
                    Label("Enable Comedown Alert", systemImage: "bell.badge")
                        .font(.headline)
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                }
            }
        } footer: {
            if !isActive && !isRedoseTimePast {
                Text("You'll get a notification when it's time to consider a small redose to soften the comedown.")
            }
        }
    }

    // MARK: - Actions

    private func activateAlert() {
        Task {
            let granted = await RampDownScheduler.requestPermissionIfNeeded()
            guard granted else {
                permissionDenied = true
                return
            }
            RampDownScheduler.scheduleNotification(
                substanceName: entry.substance,
                initialAmount: entry.amount,
                unit: entry.unit,
                doseTime: entry.timestamp,
                duration: duration,
                entryID: entry.persistentModelID.hashValue
            )
            RampDownScheduler.saveActiveEntry(entry.persistentModelID.hashValue)
            isActive = true
        }
    }

    private func cancelAlert() {
        RampDownScheduler.cancelNotification(for: entry.persistentModelID.hashValue)
        RampDownScheduler.removeActiveEntry(entry.persistentModelID.hashValue)
        isActive = false
    }
}
