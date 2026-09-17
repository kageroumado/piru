import SwiftUI

/// One My Meds pill: a time-of-day group (or a lone PRN med) that is a
/// *shortcut* — one tap stages its whole set into the tray (the
/// eight-supplements use case), idempotent for anything already staged.
/// Long-press to manage meds.
///
/// Three faces. **Plain**: scheduled for later today, or unscheduled.
/// **Due**: a slot has opened — accent outline, the slot time as a second
/// line, and a check circle that fills once the set is staged; a group of
/// quiet supplements due together is this one pill, never a row per med.
/// **Done**: every slot is covered by a dose logged today. The checkmark is
/// informational; the pill stays tappable for re-logs.
///
/// Value inputs only, so a staging change re-evaluates pills, not the list.
struct MedGroupPill: View {
    let group: DailyCategoryGroup
    /// Every member is already in the tray.
    let allStaged: Bool
    let onTap: () -> Void

    @Environment(\.appNavigator) private var navigator

    private var done: Bool {
        group.remaining.isEmpty
    }

    private var count: Int {
        group.items.count
    }

    private var taken: Int {
        count - group.remaining.count
    }

    var body: some View {
        Button(action: onTap, label: { label })
            .buttonStyle(.plain)
            // Otherwise reads "Daily, middle dot, 2"; speak it as a clean
            // label + item count, with the due/logged state as a value.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(group.title)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Stages this group’s meds")
            .accessibilityAddTraits(.isButton)
            .contextMenu {
                Button {
                    navigator.present(.dailyDoseSettings)
                } label: {
                    Label("Manage Meds…", systemImage: "pencil")
                }
            }
    }

    private var label: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: done ? "checkmark" : group.icon)
                .imageScale(.small)
                .accessibilityHidden(true)
            if group.isDue {
                dueLines
                checkCircle
            } else {
                titleLine
            }
        }
        .sectionLabel()
        .padding(.horizontal, 14)
        .padding(.vertical, group.isDue ? 7 : 9)
        .background(fill, in: skinChipShape())
        .overlay { outline }
        .foregroundStyle(foreground)
    }

    /// The due face's two lines: the title, then the slot that opened.
    private var dueLines: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            titleLine
            Text(dueText)
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(secondaryForeground)
        }
    }

    private var checkCircle: some View {
        Image(systemName: allStaged ? "checkmark.circle.fill" : "circle")
            .font(.piru(.title3))
            .foregroundStyle(foreground)
            .contentTransition(.symbolEffect(.replace))
            .padding(.leading, Spacing.xs)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var outline: some View {
        if group.isDue, !allStaged {
            skinChipShape().stroke(Theme.accent, lineWidth: 1.5)
        }
    }

    /// A single-med pill is just the med's name — "· 1" is noise. A slot
    /// with several shows its count, and progress once any of them is taken
    /// ("· 1 of 2", "✓ Morning · 2 of 2"), so the check always has a visible
    /// subject.
    private var titleLine: some View {
        HStack(spacing: Spacing.sm) {
            Text(group.title)
            if count > 1 {
                Group {
                    if taken > 0 {
                        Text("· \(taken) of \(count)")
                    } else {
                        Text(verbatim: "· \(count)")
                    }
                }
                .opacity(0.75)
            }
        }
    }

    private var fill: Color {
        if allStaged { return Theme.accent }
        if done { return Color.successAccent.opacity(Theme.Opacity.tint) }
        return Theme.accent.opacity(Theme.Opacity.tint)
    }

    private var foreground: Color {
        if allStaged { return .white }
        if done { return .successText }
        return Theme.accent
    }

    private var secondaryForeground: Color {
        allStaged ? .white : Theme.secondaryLabel
    }

    /// The due pill's second line: the slot that opened, or "Due now" for an
    /// anytime med (its own title may already be "Anytime").
    private var dueText: String {
        group.dueSlotMinutes.map(Self.timeText) ?? String(localized: "Due now")
    }

    private var accessibilityValue: Text {
        if group.isDue {
            if allStaged { return Text("Staged") }
            let due = group.dueSlotMinutes.map { String(localized: "Due at \(Self.timeText($0))") } ?? String(localized: "Due now")
            guard count > 1 else { return Text(due) }
            let items = String(localized: "^[\(count) item](inflect: true)")
            let value = "\(due), \(items)"
            return Text(value)
        }
        if done { return Text("^[\(count) item](inflect: true), all logged today") }
        if taken > 0 { return Text("\(taken) of \(count) logged today") }
        return Text("^[\(count) item](inflect: true)")
    }

    private static func timeText(_ minutes: Int) -> String {
        let date = Calendar.current.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now,
        ) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
