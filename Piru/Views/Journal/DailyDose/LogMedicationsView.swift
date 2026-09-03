import ActivityKit
import SwiftData
import SwiftUI

struct LogMedicationsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appNavigator) private var navigator

    @Query(sort: \DailyDoseItem.sortOrder) private var allItems: [DailyDoseItem]
    @Query private var substanceColors: [SubstanceColor]
    @Query private var recentEntries: [DoseEntry]

    let category: String

    @State private var toggleStates: [String: Bool] = [:]
    @State private var interactionWarnings: [InteractionResult] = []
    @State private var showInteractionSheet = false

    init(category: String) {
        self.category = category
        let cutoff = Date.now.addingTimeInterval(-48 * 3_600)
        _recentEntries = Query(
            filter: #Predicate<DoseEntry> { e in
                e.timestamp >= cutoff
            },
            sort: \DoseEntry.timestamp,
        )
    }

    private var items: [DailyDoseItem] {
        allItems.filter { $0.category == category }
    }

    private var selectedCount: Int {
        items.count(where: { toggleStates[$0.substance + String($0.sortOrder)] ?? true })
    }

    private var selectedSubstanceNames: [String] {
        items.filter { toggleStates[itemKey(for: $0)] ?? true }.map(\.substance)
    }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section {
                        ForEach(items) { item in
                            Toggle(isOn: binding(for: item)) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.productName ?? CustomSubstanceStore.shared.displayName(for: item.substance))
                                        .font(.body)
                                    Text("\(item.amount.doseFormatted) \(item.unit) \u{2014} \(String(localized: item.route.localizedName))")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.secondaryLabel)
                                }
                            }
                        }
                    } header: {
                        Text("Toggle off any you don't want to log today")
                    }

                    Section {
                        Button {
                            attemptLog()
                        } label: {
                            HStack {
                                Spacer()
                                Label("Log \(selectedCount) Item\(selectedCount == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                                    .cardTitle()
                                Spacer()
                            }
                        }
                        .disabled(selectedCount == 0)
                    }
                }
                .listRowBackground(CardBackground())
            }
            .themedPage()
            .navigationTitle(category.isEmpty ? "Log Meds" : "Log \(category)")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { navigator.dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
            .sheet(isPresented: $showInteractionSheet) {
                InteractionWarningSheet(
                    warnings: interactionWarnings,
                    onProceed: {
                        showInteractionSheet = false
                        logSelected()
                    },
                    onCancel: {
                        showInteractionSheet = false
                    },
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func itemKey(for item: DailyDoseItem) -> String {
        item.substance + String(item.sortOrder)
    }

    private func binding(for item: DailyDoseItem) -> Binding<Bool> {
        let key = itemKey(for: item)
        return Binding(
            get: { toggleStates[key] ?? true },
            set: { toggleStates[key] = $0 },
        )
    }

    private func attemptLog() {
        let active = InteractionChecker.activeEntries(from: recentEntries)
        // Only a finding that has earned an interruption stops the log. A
        // `caution` pair — two stimulants, cannabis with a benzo — is true and
        // belongs in the session review, not in front of the button; a sheet
        // that appears for those is a sheet people learn to dismiss unread.
        let warnings = InteractionChecker.checkBatch(selectedSubstanceNames, against: active)
            .admitted(.notable)

        if warnings.isEmpty {
            logSelected()
        } else {
            interactionWarnings = warnings
            showInteractionSheet = true
        }
    }

    private func logSelected() {
        let now = Date.now
        var batch: [(entry: DoseEntry, substance: Substance?)] = []

        for item in items {
            let isOn = toggleStates[itemKey(for: item)] ?? true
            guard isOn else { continue }

            let entry = DoseEntry(
                substance: item.substance,
                amount: item.amount,
                unit: item.unit,
                route: item.route,
                timestamp: now,
                isBackgroundMed: item.isBackgroundMed,
            )
            let matchedSubstance = SubstanceLibrary.lookup(item.substance).flatMap {
                $0.name.lowercased() == item.substance.lowercased() ? $0 : nil
            }
            batch.append((entry, matchedSubstance))
        }

        // Meds pass no deferredBookkeeping: routine medications skip the
        // ramp-down notifications on purpose.
        DoseLogService.shared.logBatch(batch, colors: Array(substanceColors), in: modelContext)

        // Medication log completes a logging flow; clear the entire chain back
        // to root.
        navigator.dismissAll()
    }
}

// MARK: - Interaction Warning Sheet (for batch logging)

struct InteractionWarningSheet: View {
    let warnings: [InteractionResult]
    let onProceed: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section {
                        ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                            NavigationLink {
                                InteractionTimelineView(
                                    substanceA: warning.substanceA,
                                    substanceB: warning.substanceB,
                                    severity: warning.severity,
                                    mechanism: warning.description,
                                )
                            } label: {
                                InteractionWarningRow(warning: warning)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("\(warnings.count) interaction\(warnings.count == 1 ? "" : "s") detected")
                    }

                    Section {
                        Button(role: .destructive) {
                            onProceed()
                        } label: {
                            HStack {
                                Spacer()
                                Label("Log Anyway", systemImage: "exclamationmark.triangle")
                                    .cardTitle()
                                Spacer()
                            }
                        }
                    }
                }
                .listRowBackground(CardBackground())
            }
            .themedPage()
            .navigationTitle("Interaction Warning")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { onCancel() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
        }
    }
}
