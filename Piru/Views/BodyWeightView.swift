import SwiftUI
import UIKit

/// Body-weight settings: shows the current value + its provenance, lets the user enter it by hand or
/// pull it from Apple Health, and explains *why* it matters (honestly, with a relatable example) so
/// the ask doesn't read as gratuitous data collection.
///
/// Health is read-only and its access can be silently revoked (see ``HealthKitBodyMass``), so the
/// "Connect"/"Sync" button always works and, when a read comes back empty, points the user at
/// Settings to restore access — covering revocation, reinstall, and new-device.
struct BodyWeightView: View {
    @State private var profile = UserProfileStore.shared
    @State private var health = HealthKitBodyMass.shared
    @State private var weightText = ""
    @State private var entryError: String?
    @State private var isSyncing = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Form {
            currentSection
            whySection
            manualSection
            if health.isAvailable { healthSection }
            if profile.weightKg != nil { clearSection }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Body Weight")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { weightText = profile.weightKg.map { Self.format($0) } ?? "" }
    }

    // MARK: - Current value

    private var currentSection: some View {
        Section {
            HStack {
                Text("Your weight")
                Spacer()
                Text(profile.weightKg.map { "\(Self.format($0)) kg" } ?? String(localized: "Not set"))
                    .foregroundStyle(Theme.secondaryLabel)
            }
            HStack {
                Text("Source")
                Spacer()
                Text(sourceLabel)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            if profile.isWeightEstimated {
                Label("Estimated — set your weight for more accurate estimates.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Theme.legibleYellow)
                    .accessibilityLabel("Estimated — set your weight for more accurate estimates.")
            }
        }
        .listRowBackground(CardBackground())
    }

    private var sourceLabel: LocalizedStringResource {
        switch profile.weightSource {
        case .healthKit: "Apple Health"
        case .manual: "Entered manually"
        case .estimated: "Estimated (default 60 kg)"
        }
    }

    // MARK: - Why

    private var whySection: some View {
        Section {
            Text("Your weight is the denominator that turns a dose into an exposure: the same dose hits harder the less you weigh. With it, Piru can estimate things like how strong a drink is for *your* body, and how repeated use builds tolerance. Without it, those numbers fall back to an average adult and are marked estimated.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryLabel)
        } header: {
            Text("Why we ask")
        }
        .listRowBackground(CardBackground())
    }

    // MARK: - Manual entry

    private var manualSection: some View {
        Section {
            HStack {
                TextField("Weight", text: $weightText)
                    .keyboardType(.decimalPad)
                    .focused($fieldFocused)
                Text("kg").foregroundStyle(Theme.secondaryLabel)
                Spacer()
                Button("Save") { saveManual() }
                    .buttonStyle(.borderedProminent)
                    .disabled(weightText.isEmpty)
            }
            if let entryError {
                Text(entryError).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Set manually")
        }
        .listRowBackground(CardBackground())
    }

    private func saveManual() {
        let normalized = weightText.replacingOccurrences(of: ",", with: ".")
        guard let kg = Double(normalized), kg.isFinite else {
            entryError = String(localized: "Enter a number.")
            return
        }
        guard UserProfileStore.weightRangeKg.contains(kg) else {
            entryError = String(localized: "Enter a weight between 20 and 300 kg.")
            return
        }
        entryError = nil
        fieldFocused = false
        profile.setManualWeight(kg)
    }

    // MARK: - Apple Health

    private var healthSection: some View {
        Section {
            Button {
                Task { await syncFromHealth() }
            } label: {
                HStack {
                    Label("Use Apple Health", systemImage: "heart.text.square")
                    Spacer()
                    if isSyncing { ProgressView() }
                }
            }
            .disabled(isSyncing)

            switch health.lastResult {
            case .updated:
                Label("Updated from Apple Health.", systemImage: "checkmark.circle")
                    .font(.footnote).foregroundStyle(.green)
            case .noData:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn't read a weight from Health. You may not have granted access, or haven't recorded a weight there yet.")
                        .font(.footnote).foregroundStyle(Theme.secondaryLabel)
                    Button("Open Settings") { openSettings() }
                        .font(.footnote)
                }
            case .unavailable:
                Text("Apple Health isn't available on this device.")
                    .font(.footnote).foregroundStyle(Theme.secondaryLabel)
            case .none:
                EmptyView()
            }
        } header: {
            Text("Apple Health")
        } footer: {
            Text("Piru reads your latest body weight from Health, read-only. You can turn this off anytime in Settings ▸ Health ▸ Data Access.")
        }
        .listRowBackground(CardBackground())
    }

    private func syncFromHealth() async {
        isSyncing = true
        let result = await health.requestAndSync()
        isSyncing = false
        if case let .updated(kg) = result { weightText = Self.format(kg) }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Clear

    private var clearSection: some View {
        Section {
            Button(role: .destructive) {
                profile.clearWeight()
                weightText = ""
            } label: {
                Text("Use the estimated default")
            }
        } footer: {
            Text("Reverts to the average-adult default (60 kg). Estimates will be marked estimated.")
        }
        .listRowBackground(CardBackground())
    }

    // MARK: - Helpers

    private static func format(_ kg: Double) -> String {
        kg.rounded() == kg ? String(Int(kg)) : String(format: "%.1f", kg)
    }
}

#Preview {
    NavigationStack { BodyWeightView() }
}
