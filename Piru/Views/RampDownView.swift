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

    private var category: SubstanceCategory? {
        SubstanceLibrary.lookupByNameOrAlias(entry.substance)?.category
    }

    private var isRedoseTimePast: Bool {
        redoseTime < Date.now
    }

    var body: some View {
        List {
            Group {
                infoSection
                timingSection
                actionSection
                recoveryTipsSection
            }
            .listRowBackground(Theme.cardBackground)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
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

                Text("Piru will notify you as the comedown approaches with practical care reminders — hydration, nutrition, and rest tips tailored to what you took.")
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
                Text("Comedown alert")
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
                    Text("Comedown window has passed")
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
                Text("You'll get care reminders as the effects begin to fade — hydration, nutrition, and recovery tips.")
            }
        }
    }

    // MARK: - Recovery Tips

    private var recoveryTipsSection: some View {
        Section("Recovery tips") {
            let guide = ComedownGuideView.guide(for: category ?? .other)
            ForEach(guide.rightNow.prefix(3), id: \.self) { tip in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "leaf.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text(tip)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            NavigationLink {
                ComedownGuideView()
            } label: {
                Label("Full recovery guide", systemImage: "heart.text.clipboard")
                    .font(.subheadline)
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
                entryID: entry.persistentModelID.hashValue,
                category: category
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
