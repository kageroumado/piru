import SwiftUI

// The My Meds card's trailing info lines, one view per fact so each
// invalidates on its own inputs. All three share ``MedsInfoLineLayout`` —
// a glyph, up to two caption lines, and a trailing control.

/// "Memantine · 6 days left" — tap opens the restock sheet.
struct RestockInfoLine: View {
    let name: String
    let daysLeft: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            MedsInfoLineLayout(systemImage: "shippingbox", tint: .orange) {
                Text("\(name) · \(daysLeft) days left")
            } trailing: {
                Image(systemName: "chevron.right")
                    .infoLineTrailingSlot()
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens the restock form"))
    }
}

/// "Next: Memantine at 9:00 PM" — tap opens My Meds.
struct NextDueInfoLine: View {
    let name: String
    let timeText: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            MedsInfoLineLayout(systemImage: "clock", tint: Theme.secondaryLabel) {
                Text("Next: \(name) at \(timeText)")
            } trailing: {
                Image(systemName: "chevron.right")
                    .infoLineTrailingSlot()
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens your meds"))
    }
}

/// "Yesterday's evening dose of Memantine wasn't logged" — states the gap,
/// nothing more. Tap opens My Meds; the ✕ hides the notice for that day.
struct MissedYesterdayInfoLine: View {
    let notice: MissedYesterdayNotice
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        MedsInfoLineLayout(systemImage: "calendar.badge.minus", tint: Theme.secondaryLabel) {
            Button(action: onTap) {
                text
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens your meds"))
        } trailing: {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .infoLineTrailingSlot()
                    .minimumHitTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Dismiss"))
            .accessibilityHint(Text("Hides this notice"))
        }
    }

    private var text: Text {
        if notice.count > 1 {
            let nameList = notice.names.formatted(.list(type: .and))
            return Text("Yesterday's \(nameList) weren't logged")
        }
        guard let minutes = notice.slotMinutes else {
            return Text("Yesterday's \(notice.name) wasn't logged")
        }
        return switch MedTimeGroup.group(forMinutes: minutes) {
        case .morning: Text("Yesterday's morning dose of \(notice.name) wasn't logged")
        case .afternoon: Text("Yesterday's afternoon dose of \(notice.name) wasn't logged")
        case .evening: Text("Yesterday's evening dose of \(notice.name) wasn't logged")
        default: Text("Yesterday's night dose of \(notice.name) wasn't logged")
        }
    }
}

/// Glyph · caption text · trailing control, at the slot rows' leading inset so
/// the lines read as part of the checklist rather than a footer. The text may
/// wrap to a second line; the glyph sits on its first baseline and the trailing
/// control stays centered on the whole line.
struct MedsInfoLineLayout<Content: View, Trailing: View>: View {
    let systemImage: String
    let tint: Color
    @ViewBuilder let content: () -> Content
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: Spacing.lg) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.lg) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                content()
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            trailing()
        }
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
    }
}

extension View {
    /// The trailing control's slot on an info line and the card header: one
    /// fixed frame whose glyph hugs the card's trailing edge, where the slot
    /// rows' dose text ends, so a chevron and an ✕ on neighboring lines form
    /// one column. Sized for a fingertip so the dismiss ✕ stays tappable.
    func infoLineTrailingSlot() -> some View {
        font(.caption.weight(.semibold))
            .foregroundStyle(Theme.tertiaryLabel)
            .frame(width: IconSize.iconCompact, height: IconSize.iconCompact, alignment: .trailing)
            .contentShape(Rectangle())
    }
}
