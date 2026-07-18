import SwiftData
import SwiftUI

struct RampDownView: View {
    let entry: DoseEntry
    let duration: DurationProfile

    @State private var isActive: Bool = false
    @State private var permissionDenied = false
    @State private var showingCancelConfirmation = false
    @State private var prefs = NotificationPreferencesStore.shared

    private var redoseTime: Date {
        RampDownScheduler.comedownStartTime(doseTime: entry.timestamp, duration: duration)
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
            .listRowBackground(CardBackground())
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Ramp Down")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isActive = RampDownScheduler.isActive(for: RampDownScheduler.entryKey(for: entry))
        }
        .alert("Notifications Disabled", isPresented: $permissionDenied) {
            Button("OK") {}
        } message: {
            Text("Please enable notifications in Settings to use Ramp Down alerts.")
        }
        .confirmationDialog(
            "Cancel Ramp Down?",
            isPresented: $showingCancelConfirmation,
            titleVisibility: .visible,
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
            } else if !prefs.isEffectivelyEnabled(.comedown) {
                // The scheduler would silently drop the request — say so
                // instead of offering a button that does nothing.
                HStack {
                    Image(systemName: "bell.slash")
                        .foregroundStyle(.orange)
                    Text("Comedown alerts are turned off")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    Label("Notification Settings", systemImage: "bell.badge")
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
            if !isActive, !isRedoseTimePast {
                if !prefs.isEffectivelyEnabled(.comedown) {
                    Text("Turn comedown alerts back on in Notification Settings to turn one on for this dose.")
                } else {
                    Text("You'll get care reminders as the effects begin to fade — hydration, nutrition, and recovery tips.")
                }
            }
        }
    }

    // MARK: - Recovery Tips

    private var recoveryTipsSection: some View {
        Section("Recovery tips") {
            let guide = ComedownGuideView.guide(for: category ?? .other)
            ForEach(Array(guide.rightNow.prefix(3).enumerated()), id: \.offset) { _, tip in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "leaf.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text(tip)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            NavigationLink(value: PushRoute.comedownGuide) {
                Label("Full recovery guide", systemImage: "heart.text.clipboard")
                    .font(.subheadline)
            }
        }
    }

    // MARK: - Actions

    private func activateAlert() {
        Task {
            // Arming an alert is the user explicitly asking for a
            // notification — the one place outside the management screen and
            // onboarding where the OS grant may be requested.
            let granted = await DoseNotificationManager.requestAuthorization()
            guard granted else {
                permissionDenied = true
                return
            }
            DoseNotificationManager.armComedownAlert(entry: entry, duration: duration)
            isActive = true
        }
    }

    private func cancelAlert() {
        DoseNotificationManager.cancelComedownAlert(entry: entry)
        isActive = false
    }
}
