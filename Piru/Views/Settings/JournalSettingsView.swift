import SwiftUI

/// Day-grouping and timeline preferences.
struct JournalSettingsView: View {
    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var stackRedoses = true
    @AppStorage(LaneModeDefaults.enabledKey, store: UserDefaults(suiteName: LaneModeDefaults.suite)) private var stackedLanesEnabled = LaneModeDefaults.enabledDefault
    @AppStorage(LaneModeDefaults.thresholdKey, store: UserDefaults(suiteName: LaneModeDefaults.suite)) private var laneModeThreshold = LaneModeDefaults.thresholdDefault
    @AppStorage(Calendar.dayBoundaryHourKey, store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var dayBoundaryHour = 4
    @AppStorage(SessionGraphDefaults.enlargedKey, store: UserDefaults(suiteName: SessionGraphDefaults.suite)) private var sessionGraphEnlarged = SessionGraphDefaults.enlargedDefault

    var body: some View {
        List {
            Group {
                Section {
                    Stepper(value: $dayBoundaryHour, in: 0 ... 12) {
                        HStack {
                            Label("Day Starts At", systemImage: "moon.stars")
                            Spacer()
                            Text(boundaryHourLabel)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }
                } footer: {
                    Text("Doses before this hour count toward the previous day. Set to 12 AM for standard calendar days.")
                }

                Section {
                    Toggle(isOn: $stackRedoses) {
                        Label("Stack Redoses", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    .tint(Theme.accent)

                    Toggle(isOn: $stackedLanesEnabled) {
                        Label("Stack Busy Sessions", systemImage: "square.stack.3d.up")
                    }
                    .tint(Theme.accent)

                    if stackedLanesEnabled {
                        Stepper(value: $laneModeThreshold, in: LaneModeDefaults.thresholdRange) {
                            HStack {
                                Text("Stack From")
                                Spacer()
                                Text(laneModeThreshold, format: .number)
                                    .foregroundStyle(Theme.secondaryLabel)
                            }
                        }
                    }

                    Toggle(isOn: $sessionGraphEnlarged) {
                        Label("Expand Session Graph", systemImage: "arrow.up.backward.and.arrow.down.forward")
                    }
                    .tint(Theme.accent)
                } header: {
                    Text("Timeline")
                } footer: {
                    Text("Stacking merges redoses into one curve and splits busy sessions into lanes. Expanding starts the graph full-height.")
                }
            }
            .listRowBackground(CardBackground())
        }
        .themedPage()
        .navigationTitle("Journal")
        .inlineNavigationTitle()
    }

    private var boundaryHourLabel: String {
        var components = DateComponents()
        components.hour = dayBoundaryHour
        let date = Calendar.current.date(from: components) ?? .now
        return date.formatted(.dateTime.hour())
    }
}
