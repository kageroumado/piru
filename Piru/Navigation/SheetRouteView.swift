import SwiftData
import SwiftUI

/// Renders a `SheetRoute` by dispatching to its corresponding existing view.
///
/// Each case owns the wrapping its view needs (e.g. embedding in a
/// `NavigationStack`) — this dispatcher is the single place that knows how to
/// present a route.
struct SheetRouteView: View {
    let route: SheetRoute
    /// This sheet's depth in the navigator's stack. Keys the sheet's own push
    /// path (`AppNavigator.sheetPathBinding(atDepth:)`) for routes that host a
    /// `NavigationStack` — an unbound stack here would leave `navigator.push`
    /// calls from the sheet's content mutating the tab stack *behind* it.
    var depth: Int = 0

    @Environment(\.appNavigator) private var navigator

    var body: some View {
        switch route {
        case let .quickLog(routine, prefillSubstance):
            QuickLogSheet(prestagedRoutine: routine, prefillSubstance: prefillSubstance)

        case .settings:
            // SettingsView owns its own xmark toolbar item.
            NavigationStack { SettingsView() }

        case .help:
            HelpView()

        case .onboarding:
            OnboardingView()

        case .sessionDetail:
            NavigationStack(path: navigator.sheetPathBinding(atDepth: depth)) {
                CurrentSessionHost()
                    .withCancellationCloseButton()
                    .withAppDestinations()
            }

        case let .entryDetail(timestamp, id):
            EntryLookupView(id: id, timestamp: timestamp) { entry in
                NavigationStack(path: navigator.sheetPathBinding(atDepth: depth)) {
                    EntryDetailView(entry: entry)
                        .withCancellationCloseButton()
                        .withAppDestinations()
                }
            }

        case let .sessionNoteEditor(sessionID, _, _):
            SessionNoteHost(sessionID: sessionID)

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

        case let .doseSources(substance, route):
            DoseSourceComparisonView(
                substanceName: substance,
                route: route,
                accent: SubstanceLibrary.resolveFull(substance)?.category.color ?? Theme.accent,
            )

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
            // The Meds redesign: this route now lands on the My Meds hub
            // (route case name kept for Codable compatibility with persisted
            // snapshots and deep links). Path-bound so the hub's med-detail
            // pushes land on THIS stack when the hub is a sheet.
            NavigationStack(path: navigator.sheetPathBinding(atDepth: depth)) {
                MyMedsHubView()
                    .withCancellationCloseButton()
                    .withAppDestinations()
            }

        case let .inventoryItemForm(id, prefillSubstance, prefillSalt):
            InventoryItemFormHost(itemID: id, prefillSubstance: prefillSubstance, prefillSalt: prefillSalt)

        case let .inventoryItemEdit(id):
            InventoryItemEditHost(itemID: id)
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
        DoseEntry.resolveForRoute(id: id, near: timestamp, in: modelContext)
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
            // `takenColorMap` uses `uniquingKeysWith:`: two substances may
            // legitimately share a hex, and building this dictionary with
            // `Dictionary(uniqueKeysWithValues:)` instead traps on any
            // duplicate-hex assignment.
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
/// personal override, then hosts the personalize form.
private struct PersonalizeSubstanceHost: View {
    let name: String
    @State private var customStore = CustomSubstanceStore.shared

    var body: some View {
        // Shell resolve — an index hit by exact canonical name. `all.first(where:)`
        // was an O(catalog) scan in body, with the cold-cache synchronous batch
        // build behind it.
        if let base = SubstanceLibrary.shell(name) {
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
    @Environment(\.modelContext) private var modelContext
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
        DoseNotificationManager.doseRescheduled(entry: entry, previousTimestamp: original, in: modelContext)
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

/// Resolves a session by id and hosts its note editor. The draft is seeded
/// from the session's note once, so reopening shows the existing text.
private struct SessionNoteHost: View {
    let sessionID: UUID
    @Environment(\.modelContext) private var modelContext
    @State private var session: Session?
    @State private var draft = ""

    var body: some View {
        Group {
            if let session {
                SessionNoteEditor(text: $draft) { SessionService.setNote($0, for: session) }
            } else {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "calendar.day.timeline.left",
                    description: Text("Log a dose to start your first session."),
                )
            }
        }
        .task {
            guard session == nil else { return }
            var descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == sessionID })
            descriptor.fetchLimit = 1
            session = try? modelContext.fetch(descriptor).first
            draft = session?.note ?? ""
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
                    .accessibilityHidden(true)
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
