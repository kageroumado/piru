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
                            CaptionedRowLabel(
                                title: "Day Starts At",
                                systemImage: "moon.stars",
                                caption: Text("Entries before this hour count toward the previous day. Set to 12 AM for standard calendar days."),
                            )
                            Spacer()
                            Text(boundaryHourLabel)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }
                }

                Section {
                    Toggle(isOn: $stackRedoses) {
                        CaptionedRowLabel(
                            title: "Combine Repeated Entries",
                            systemImage: "chart.line.uptrend.xyaxis",
                            caption: Text("Combine repeated entries for the same substance into one curve. When off, each entry has its own curve."),
                        )
                    }
                    .tint(Theme.accent)

                    Toggle(isOn: $stackedLanesEnabled) {
                        CaptionedRowLabel(
                            title: "Stack Busy Sessions",
                            systemImage: "square.stack.3d.up",
                            caption: Text("Splits a busy session's overlapping curves into one lane per substance."),
                        )
                    }
                    .tint(Theme.accent)

                    if stackedLanesEnabled {
                        Stepper(value: $laneModeThreshold, in: LaneModeDefaults.thresholdRange) {
                            HStack {
                                CaptionedRowLabel(
                                    title: "Stack From",
                                    caption: Text("How many substances a session needs before it splits into lanes."),
                                )
                                Spacer()
                                Text(laneModeThreshold, format: .number)
                                    .foregroundStyle(Theme.secondaryLabel)
                            }
                        }
                    }

                    Toggle(isOn: $sessionGraphEnlarged) {
                        CaptionedRowLabel(
                            title: "Expand Session Graph",
                            systemImage: "arrow.up.backward.and.arrow.down.forward",
                            caption: Text("Always show the full-height timeline. When off, graphs start compact — expand from the graph menu."),
                        )
                    }
                    .tint(Theme.accent)
                } header: {
                    Text("Timeline")
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
