import SwiftData
import SwiftUI

// MARK: - Window Toolbar

extension View {
    /// The actions the iOS tab bar's bottom accessory carries, in the window
    /// toolbar: the live session, the dock's shortcut slots and "Record an entry".
    /// macOS has no bottom accessory, and the tabs sit in the toolbar's center.
    func macWindowActions() -> some View {
        modifier(MacWindowActions())
    }
}

private struct MacWindowActions: ViewModifier {
    /// Due meds and the record button's help label, refreshed off the body.
    @State private var dockStatus = MacDockStatus()

    func body(content: Content) -> some View {
        content
            .background { MacDockStatusUpdater(status: dockStatus) }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    MacToolbarActions(status: dockStatus)
                }
            }
    }
}

// MARK: - Dock Status

/// What the accessory's idle face derives — the due meds behind the "+" badge
/// and the center label — held for the toolbar's "Record an entry" button.
@Observable @MainActor
private final class MacDockStatus {
    var context = DockLabelContext()

    var dueCount: Int {
        context.dueMedNames.count
    }

    /// The accessory's center label, or nil when it has nothing to say.
    func label(_ labels: [DockLabel]) -> String? {
        let resolved = DockLabel.resolve(labels, in: context)
        return resolved == DockLabel.unavailable ? nil : resolved
    }
}

/// Recomputes ``MacDockStatus`` once a minute, whenever the meds list changes
/// and after every logged dose — the accessory label's own cadence. A
/// zero-size leaf, so its query and clock never re-run the window body.
private struct MacDockStatusUpdater: View {
    let status: MacDockStatus

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DailyDoseItem.sortOrder) private var items: [DailyDoseItem]
    @State private var now = Date.now

    var body: some View {
        Color.clear
            .task(id: recomputeKey) {
                await SubstanceStore.shared.ensureAllLoaded()
                guard !Task.isCancelled else { return }
                status.context = DockLabelContext.derive(items: items, in: modelContext, now: now)
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    now = .now
                }
            }
    }

    private var recomputeKey: String {
        "\(Int(now.timeIntervalSinceReferenceDate / 60))|\(items.count)|\(DoseLogService.shared.revision)"
    }
}

// MARK: - Toolbar Actions

/// The accessory's actions in its own order: the live session (its pill face),
/// the shortcut slots, then "Record an entry" (its "+").
private struct MacToolbarActions: View {
    let status: MacDockStatus

    @Environment(\.appNavigator) private var navigator
    @Environment(\.modelContext) private var modelContext
    @State private var preferences = DockPreferences.shared

    var body: some View {
        if ActiveSessionManager.shared.hasActiveSession {
            Button(action: showSession) {
                MacSessionPill()
            }
            .accessibilityLabel(Text("Session"))
        }

        if !preferences.shortcuts.isEmpty {
            Menu {
                ForEach(preferences.shortcuts) { shortcut in
                    MacShortcutButton(shortcut: shortcut)
                }
            } label: {
                Label("Shortcuts", systemImage: "bolt")
            }
        }

        Button("Record an entry", systemImage: "plus", action: record)
            .badge(status.dueCount)
            .keyboardShortcut("n", modifiers: .command)
            .help(status.label(preferences.labels).map { Text(verbatim: $0) } ?? Text("Record an entry"))
            .accessibilityInputLabels([Text("Record an entry"), Text("Record"), Text("Add")])
    }

    private func record() {
        OnboardingTips.logDoseInvoked()
        guard navigator.sheetStack.isEmpty else { return }
        navigator.present(.quickLog(routine: nil))
    }

    private func showSession() {
        guard navigator.sheetStack.isEmpty else { return }
        navigator.revealOrPresentSessionDetail(currentSessionID: mostRecentSessionID(in: modelContext))
    }
}

/// The accessory's live-session pill in the toolbar: the mini timeline, the
/// substance names and elapsed/remaining times, ticking once a minute.
private struct MacSessionPill: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            SessionAccessoryInfo(
                states: ActiveSessionManager.shared.activeSubstanceStates,
                currentTime: context.date,
                placement: nil,
            )
        }
        .frame(maxWidth: 260)
    }
}

/// One dock shortcut slot as a menu item. A favorite shows its substance's
/// display name, resolved once the substance cache is warm.
private struct MacShortcutButton: View {
    let shortcut: DockShortcut

    @Environment(\.appNavigator) private var navigator
    @Environment(\.modelContext) private var modelContext
    @State private var favoriteTitle: String?

    var body: some View {
        Button {
            shortcut.perform(navigator: navigator, modelContext: modelContext)
        } label: {
            Label(title, systemImage: shortcut.favoriteSubstance == nil ? shortcut.systemImage : "star")
        }
        .disabled(shortcut.requiresActiveSession && !ActiveSessionManager.shared.hasActiveSession)
        .task(id: shortcut) {
            guard let substance = shortcut.favoriteSubstance else { return }
            await SubstanceStore.shared.ensureAllLoaded()
            guard !Task.isCancelled else { return }
            favoriteTitle = CustomSubstanceStore.shared.displayName(for: substance)
        }
    }

    private var title: String {
        if let substance = shortcut.favoriteSubstance {
            return favoriteTitle ?? substance
        }
        return shortcut.fixedTitle.map { String(localized: $0) } ?? ""
    }
}
