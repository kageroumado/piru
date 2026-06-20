import SwiftData
import SwiftUI

/// Renders a `SheetRoute` by dispatching to its corresponding existing view.
///
/// Each case mirrors the wrapping (e.g. embedding in a `NavigationStack`) that
/// the call site previously did inline. As views are migrated to consume the
/// navigator directly, this dispatcher is the single place that knows how to
/// present a route.
///
/// Some cases are stubs in Phase 1 — they'll be wired up as their owning
/// flows migrate. Presenting an unmigrated route shows a clearly-labeled
/// placeholder rather than crashing.
struct SheetRouteView: View {
    let route: SheetRoute

    var body: some View {
        switch route {
        case let .quickLog(routine):
            QuickLogView(prestagedRoutine: routine)

        case .settings:
            // SettingsView owns its own xmark toolbar item.
            NavigationStack { SettingsView() }

        case .help:
            HelpView()

        case .onboarding:
            OnboardingView()

        case .sessionDetail:
            NavigationStack {
                CurrentSessionHost()
                    .withCancellationCloseButton()
                    .withAppDestinations()
            }

        case let .entryDetail(timestamp, id):
            EntryLookupView(id: id, timestamp: timestamp) { entry in
                NavigationStack {
                    EntryDetailView(entry: entry)
                        .withCancellationCloseButton()
                        .withAppDestinations()
                }
            }

        case let .entryForm(prefill):
            if let prefill {
                EntryFormView(
                    prefillSubstance: prefill.substance,
                    prefillRoute: prefill.route,
                    prefillUnit: prefill.unit,
                )
            } else {
                EntryFormView()
            }

        case let .entryEdit(timestamp, id):
            EntryLookupView(id: id, timestamp: timestamp) { entry in
                EntryFormView(entry: entry)
            }

        case let .colorPicker(substance, remaining, dismissAllOnComplete):
            ColorPickerHost(
                substance: substance,
                remaining: remaining,
                dismissAllOnComplete: dismissAllOnComplete,
            )

        case let .timeAdjust(timestamp):
            EntryLookupView(id: nil, timestamp: timestamp) { entry in
                TimeAdjustHost(entry: entry)
            }

        case let .dailyDoseLog(category):
            LogMedicationsView(category: category)

        case .sourcePriority:
            NavigationStack {
                SourcePriorityView()
                    .withCancellationCloseButton()
            }

        case .advancedSearch:
            NavigationStack {
                AdvancedSearchView()
                    .withCancellationCloseButton()
            }

        case let .personalizeSubstance(name):
            PersonalizeSubstanceHost(name: name)

        case .dailyDoseSettings:
            NavigationStack {
                RoutinesSettingsView()
                    .withCancellationCloseButton()
            }

        case let .inventoryItemForm(id, prefillSubstance, prefillSalt):
            InventoryItemFormHost(itemID: id, prefillSubstance: prefillSubstance, prefillSalt: prefillSalt)

        case let .inventoryItemEdit(id):
            InventoryItemEditHost(itemID: id)

        case .dailyDoseItemForm,
             .customSubstancesList,
             .customSubstanceForm,
             .journalFilters,
             .journalCalendar,
             .dayShare:
            UnmigratedRoutePlaceholder(route: route)
        }
    }
}

// MARK: - Helpers

/// Common toolbar Close button for sheet roots that wrap a NavigationStack.
private struct CancellationCloseButton: ViewModifier {
    @Environment(\.appNavigator) private var navigator

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    navigator.dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close")
            }
        }
    }
}

private extension View {
    func withCancellationCloseButton() -> some View {
        modifier(CancellationCloseButton())
    }
}

/// Resolves a `DoseEntry` — by its stable `id` first, falling back to a ±2 s
/// timestamp window for id-less routes (pre-V4 payloads, the Live Activity's
/// timestamp-only deep links; mirrors `PushRouteView.lookupEntry`) — and
/// renders `content` with the result. Falls back to nothing visible if the
/// entry can't be found — the navigator typically dismisses the sheet shortly
/// after.
private struct EntryLookupView<Content: View>: View {
    let id: UUID?
    let timestamp: Date
    @ViewBuilder let content: (DoseEntry) -> Content

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if let entry = lookup() {
            content(entry)
        }
    }

    private func lookup() -> DoseEntry? {
        if let id {
            var descriptor = FetchDescriptor<DoseEntry>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let entry = try? modelContext.fetch(descriptor).first {
                return entry
            }
        }
        let lower = timestamp.addingTimeInterval(-2)
        let upper = timestamp.addingTimeInterval(2)
        var descriptor = FetchDescriptor<DoseEntry>(
            predicate: #Predicate { $0.timestamp >= lower && $0.timestamp <= upper },
        )
        descriptor.sortBy = [SortDescriptor(\.timestamp)]
        return try? modelContext.fetch(descriptor).first
    }
}

/// Color picker host that persists the chosen color and either advances the
/// remaining queue (via `replacingTop`) or dismisses when done. Replaces the
/// chained `onDismiss` color loop in `LogMedicationsView` and `QuickLogView`.
///
/// SubstanceColorPickerView does not call `dismiss()` internally — the host
/// owns the transition, either via `replacingTop` (when the queue has more
/// substances) or `navigator.dismiss()` (when empty). This avoids the
/// `@Environment(\.dismiss)` → sheet-binding-nil → `truncateSheetStack` chain
/// that would otherwise wipe the queue between picks.
private struct ColorPickerHost: View {
    let substance: String
    let remaining: [String]
    let dismissAllOnComplete: Bool

    @Environment(\.appNavigator) private var navigator
    @Environment(\.modelContext) private var modelContext
    @Query private var substanceColors: [SubstanceColor]

    var body: some View {
        SubstanceColorPickerView(
            substanceName: substance,
            // `takenColorMap` uses `uniquingKeysWith:` so two substances
            // sharing a hex don't crash here (build 11 TestFlight crash —
            // user had a duplicate-hex assignment and tapped "add new
            // substance", which hit `Dictionary(uniqueKeysWithValues:)`).
            takenColors: Array(substanceColors).takenColorMap,
        ) { hex in
            let color = SubstanceColor(substance: substance, hexColor: hex)
            modelContext.insert(color)
            // Re-read all colors from the store and patch the active session
            // so any in-flight doses for this substance pick up the new color.
            // `refresh()` alone would only prune; we need a full color refresh.
            let allColors = (try? modelContext.fetch(FetchDescriptor<SubstanceColor>())) ?? []
            ActiveSessionManager.shared.applyColorUpdates(allColors: allColors)
            advance()
        }
    }

    private func advance() {
        if let next = remaining.first {
            // Carry the dismiss flag through the queue so the final pick
            // honours the originating flow's request.
            navigator.present(
                .colorPicker(
                    substance: next,
                    remaining: Array(remaining.dropFirst()),
                    dismissAllOnComplete: dismissAllOnComplete,
                ),
                replacingTop: true,
            )
        } else if dismissAllOnComplete {
            navigator.dismissAll()
        } else {
            navigator.dismiss()
        }
    }
}

/// Resolves a canonical substance name to its library substance + any existing
/// personal override, then hosts the personalize form. Lives here so the form
/// is presented as a navigator sheet (its `navigator.dismiss()` then works).
private struct PersonalizeSubstanceHost: View {
    let name: String
    @State private var customStore = CustomSubstanceStore.shared
    @Environment(\.appNavigator) private var navigator

    var body: some View {
        if let base = SubstanceLibrary.all.first(where: { $0.name == name }) {
            CustomSubstanceFormView(existing: customStore.first(whereName: name), personalizing: base)
        } else {
            UnmigratedRoutePlaceholder(route: .personalizeSubstance(name: name))
        }
    }
}

/// Hosts the time-adjust mini sheet used from `SessionDetailView`.
private struct TimeAdjustHost: View {
    @Bindable var entry: DoseEntry
    @Environment(\.appNavigator) private var navigator
    @Query private var substanceColors: [SubstanceColor]
    @State private var originalTimestamp: Date?

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "Time",
                    selection: $entry.timestamp,
                    displayedComponents: [.date, .hourAndMinute],
                )
            }
            .navigationTitle("Adjust Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        navigator.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { if originalTimestamp == nil { originalTimestamp = entry.timestamp } }
        .onDisappear { syncSessionIfTimeChanged() }
    }

    /// Editing `entry.timestamp` writes straight through to SwiftData, but the
    /// session accessory + Live Activity read from `ActiveSessionManager`'s
    /// snapshot — without this they keep showing the dose's pre-edit time.
    private func syncSessionIfTimeChanged() {
        guard let original = originalTimestamp, original != entry.timestamp else { return }
        ActiveSessionManager.shared.refreshEditedEntry(
            previousTimestamp: original,
            entry: entry,
            allColors: Array(substanceColors),
        )
        // Pending reminders are keyed to the old timestamp — a moved dose
        // must drop them and reschedule from its new time.
        DoseNotificationManager.doseRescheduled(entry: entry, previousTimestamp: original)
    }
}

/// Resolves the most recent session and shows its detail — the target of the
/// `piru://day` deep link, now "open the current session." Falls back to a clear
/// empty state when there are no sessions yet.
private struct CurrentSessionHost: View {
    @Query(sort: \Session.startDate, order: .reverse) private var sessions: [Session]

    var body: some View {
        if let session = sessions.first {
            SessionDetailView(session: session)
        } else {
            ContentUnavailableView(
                "No Sessions",
                systemImage: "calendar.day.timeline.left",
                description: Text("Log a dose to start your first session."),
            )
        }
    }
}

/// Placeholder for routes whose owning view hasn't migrated yet. Visible only
/// during phased rollout; production deployments should never hit this.
private struct UnmigratedRoutePlaceholder: View {
    let route: SheetRoute
    @Environment(\.appNavigator) private var navigator

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "wrench.adjustable")
                    .font(.largeTitle)
                Text("Route not yet migrated:")
                Text(String(describing: route))
                    .font(.caption.monospaced())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { navigator.dismiss() }
                }
            }
        }
    }
}
