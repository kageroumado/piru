import SwiftUI
import SwiftData

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
        case .quickLog:
            QuickLogView()

        case .settings:
            // SettingsView owns its own xmark toolbar item.
            NavigationStack { SettingsView() }

        case .help:
            HelpView()

        case .onboarding:
            OnboardingView()

        case .sessionDetail:
            NavigationStack {
                DayDetailView(date: .now)
                    .withCancellationCloseButton()
                    .withAppDestinations()
            }

        case .entryDetail(let timestamp):
            EntryByTimestampView(timestamp: timestamp) { entry in
                NavigationStack {
                    EntryDetailView(entry: entry)
                        .withCancellationCloseButton()
                        .withAppDestinations()
                }
            }

        case .entryForm(let prefill):
            if let prefill {
                EntryFormView(
                    prefillSubstance: prefill.substance,
                    prefillRoute: prefill.route,
                    prefillUnit: prefill.unit
                )
            } else {
                EntryFormView()
            }

        case .entryEdit(let timestamp):
            EntryByTimestampView(timestamp: timestamp) { entry in
                EntryFormView(entry: entry)
            }

        case .colorPicker(let substance, let remaining, let dismissAllOnComplete):
            ColorPickerHost(
                substance: substance,
                remaining: remaining,
                dismissAllOnComplete: dismissAllOnComplete
            )

        case .timeAdjust(let timestamp):
            EntryByTimestampView(timestamp: timestamp) { entry in
                TimeAdjustHost(entry: entry)
            }

        case .dailyDoseLog(let category):
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

        case .dailyDoseSettings,
             .dailyDoseItemForm,
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
            }
        }
    }
}

private extension View {
    func withCancellationCloseButton() -> some View {
        modifier(CancellationCloseButton())
    }
}

/// Resolves a `DoseEntry` from a timestamp (±2s window, matching the existing
/// deep-link semantics) and renders `content` with the result. Falls back to
/// nothing visible if the entry can't be found — the navigator typically
/// dismisses the sheet shortly after.
private struct EntryByTimestampView<Content: View>: View {
    let timestamp: Date
    @ViewBuilder let content: (DoseEntry) -> Content

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if let entry = lookup() {
            content(entry)
        } else {
            EmptyView()
        }
    }

    private func lookup() -> DoseEntry? {
        let lower = timestamp.addingTimeInterval(-2)
        let upper = timestamp.addingTimeInterval(2)
        var descriptor = FetchDescriptor<DoseEntry>(
            predicate: #Predicate { $0.timestamp >= lower && $0.timestamp <= upper }
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
            takenColors: Dictionary(
                uniqueKeysWithValues: substanceColors.map { ($0.hexColor, $0.substance) }
            )
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
                    dismissAllOnComplete: dismissAllOnComplete
                ),
                replacingTop: true
            )
        } else if dismissAllOnComplete {
            navigator.dismissAll()
        } else {
            navigator.dismiss()
        }
    }
}

/// Hosts the time-adjust mini sheet used from `DayDetailView`.
private struct TimeAdjustHost: View {
    @Bindable var entry: DoseEntry
    @Environment(\.appNavigator) private var navigator

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "Time",
                    selection: $entry.timestamp,
                    displayedComponents: [.date, .hourAndMinute]
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
                }
            }
        }
        .presentationDetents([.medium])
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
