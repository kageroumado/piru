import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Day-grouping, timeline, and quick-log preferences.
struct JournalSettingsView: View {
    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var stackRedoses = true
    @AppStorage(LaneModeDefaults.enabledKey, store: UserDefaults(suiteName: LaneModeDefaults.suite)) private var stackedLanesEnabled = LaneModeDefaults.enabledDefault
    @AppStorage(LaneModeDefaults.thresholdKey, store: UserDefaults(suiteName: LaneModeDefaults.suite)) private var laneModeThreshold = LaneModeDefaults.thresholdDefault
    @AppStorage(QuickLogManager.fixedOrderDefaultsKey) private var quickLogFixedOrder = false
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
                } header: {
                    Text("Day Grouping")
                } footer: {
                    Text("Doses logged before this hour count toward the previous day — so a 2 AM dose stays with the night before instead of starting a new day at midnight. Set to 12 AM for standard calendar days.")
                }

                Section {
                    Toggle(isOn: $stackRedoses) {
                        Label("Stack Redoses", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    .tint(Theme.accent)
                } footer: {
                    Text("Combine repeat doses of the same substance into a single curve, where each redose adds to the combined intensity. When off, each dose is drawn as its own line.")
                }

                Section {
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
                } footer: {
                    Text("When a session reaches this many different substances, the timeline splits overlapping curves into separate stacked lanes — one per substance — so a busy session stays readable. When off, every curve is always overlaid on one graph.")
                }

                Section {
                    Toggle(isOn: $sessionGraphEnlarged) {
                        Label("Expand Session Graph", systemImage: "arrow.up.backward.and.arrow.down.forward")
                    }
                    .tint(Theme.accent)
                } footer: {
                    Text("Always show the taller timeline graph when viewing a session. When off, the graph starts compact and you can expand it per session from the graph menu.")
                }

                Section {
                    Toggle(isOn: $quickLogFixedOrder) {
                        Label("Keep Quick-Log Order", systemImage: "pin")
                    }
                    .tint(Theme.accent)

                    NavigationLink {
                        DoseTimeSettingsView()
                    } label: {
                        Label("Quick Times", systemImage: "clock.arrow.circlepath")
                    }
                } footer: {
                    Text("Keep your quick-log doses in a fixed order. When off, logging a dose moves it to the front so your most-used doses stay on top.")
                }
            }
            .listRowBackground(CardBackground())
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var boundaryHourLabel: String {
        var components = DateComponents()
        components.hour = dayBoundaryHour
        let date = Calendar.current.date(from: components) ?? .now
        return date.formatted(.dateTime.hour())
    }
}

// MARK: - Substance Database
