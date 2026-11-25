import SwiftUI
import WatchKit

/// The phone's My Meds checklist on the wrist: today's due slots, earliest first, each
/// ticked with one tap and unticked with a second, as on the phone. Two or more
/// supplements fold into one Supplements row, collapsed, with Take All — the phone
/// card's fold.
struct MyMedsWatchView: View {
    @Environment(WatchSyncCoordinator.self) private var sync

    var body: some View {
        // Re-read every minute, so a screen left open across Day Starts At turns over.
        TimelineView(.everyMinute) { context in
            if let day = sync.manifest?.medDay(containing: context.date), !day.slots.isEmpty {
                MedChecklist(day: day)
            } else {
                ContentUnavailableView("No meds today", systemImage: "pills")
            }
        }
        .navigationTitle("My Meds")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A nested supplement's card, drawn as the list draws its own rows. Its shape is the
/// row's own (`ContainerRelativeShape`): a 42 mm watch rounds its rows less than a
/// 46 mm one, so no fixed radius fits both. Its gray is measured from a capture,
/// 34/255, since no fill style names the list's platter.
private enum RowPlatter {
    static let shape = ContainerRelativeShape()
    static let fill = Color(white: 34 / 255)
    /// How far a nested card sits inside the outer rows, on each side.
    static let nestedInset: CGFloat = 10
}

/// One day's slots: the loud meds, then the Supplements group.
private struct MedChecklist: View {
    let day: ManifestMedDay

    @Environment(WatchSyncCoordinator.self) private var sync
    @State private var supplementsExpanded = false

    var body: some View {
        // The fold only pays for itself with 2+ quiet slots — a single quiet med is a
        // plain row, as on the phone.
        let collapseQuiet = day.slots.count(where: \.isQuiet) >= 2
        let loudSlots = collapseQuiet ? day.slots.filter { !$0.isQuiet } : day.slots
        let quietSlots = collapseQuiet ? day.slots.filter(\.isQuiet) : []
        let quietTaken = quietSlots.count { sync.isTaken($0, in: day) }
        // What Take All takes: a skipped slot is left alone, as a row of it can't be tapped.
        let quietOpen = quietSlots.filter { !sync.isTaken($0, in: day) && !$0.skipped }
        List {
            ForEach(loudSlots) { slot in
                MedSlotRow(slot: slot, taken: sync.isTaken(slot, in: day)) { toggle(slot) }
            }
            if !quietSlots.isEmpty {
                SupplementsRow(takenCount: quietTaken, total: quietSlots.count, expanded: $supplementsExpanded)
                if supplementsExpanded {
                    ForEach(quietSlots) { slot in
                        MedSlotRow(slot: slot, taken: sync.isTaken(slot, in: day), nested: true) { toggle(slot) }
                    }
                }
                // Closes the group, never between Supplements and its rows. Its pill is
                // the row's own background, as wide as the rows right above it: the
                // Supplements row, or the supplements' inset cards when they show. No
                // prominent button style: it leaves the gray platter at both ends.
                if !quietOpen.isEmpty {
                    Button { take(quietOpen) } label: {
                        Label("Take All", systemImage: "checkmark")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                    }
                    // 5.2:1 under the white label.
                    .listRowBackground(
                        Capsule()
                            .fill(Color.logButton)
                            .padding(.horizontal, supplementsExpanded ? RowPlatter.nestedInset : 0),
                    )
                }
            }
        }
    }

    private func take(_ slots: [ManifestMedSlot]) {
        guard sync.take(slots, in: day) else { return }
        WKInterfaceDevice.current().play(.success)
    }

    /// Tick an open slot, untick a taken one.
    private func toggle(_ slot: ManifestMedSlot) {
        guard sync.isTaken(slot, in: day) else { return take([slot]) }
        guard sync.untake(slot, in: day) else { return }
        WKInterfaceDevice.current().play(.click)
    }
}

/// One slot: its check, the med, then its dose and time. A tap ticks it, a second
/// unticks it. A slot skipped on the phone can't be ticked here, as on the phone card:
/// the skip is sticky, so a dose would tick another of the med's slots. A supplement
/// inside the expanded group is `nested`: its card is inset on both sides.
private struct MedSlotRow: View {
    let slot: ManifestMedSlot
    let taken: Bool
    var nested = false
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: taken ? "checkmark.circle.fill" : slot.skipped ? "minus.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(taken ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(slot.displayName)
                        .font(.headline)
                        .foregroundStyle(taken ? .secondary : .primary)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, nested ? RowPlatter.nestedInset : 0)
            // One element: name, then dose, time and state — instead of an unlabeled
            // check and two stops.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(slot.displayName)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(taken ? Text("Removes this entry") : slot.skipped ? Text("Skipped for today") : Text("Records this entry"))
        }
        .disabled(slot.skipped && !taken)
        .listRowBackground(
            nested ? RowPlatter.shape.fill(RowPlatter.fill).padding(.horizontal, RowPlatter.nestedInset) : nil,
        )
    }

    private var accessibilityValue: String {
        let state = if taken {
            String(localized: "Taken")
        } else if slot.skipped {
            String(localized: "Skipped")
        } else {
            String(localized: "Not taken yet")
        }
        return "\(spokenSubtitle), \(state)"
    }

    /// The subtitle with a comma for its middle dot, which VoiceOver would
    /// otherwise read aloud.
    private var spokenSubtitle: String {
        let dose = "\(WatchDoseFormat.amount(slot.amount)) \(slot.unit)"
        return slot.slotMinutes.map { "\(dose), \(WatchDoseFormat.time($0))" } ?? dose
    }

    private var subtitle: String {
        let dose = "\(WatchDoseFormat.amount(slot.amount)) \(slot.unit)"
        return slot.slotMinutes.map { "\(dose) · \(WatchDoseFormat.time($0))" } ?? dose
    }
}

/// The collapsed Supplements group: a fractional ring, the taken count, and the
/// disclosure chevron. Tapping it expands the group.
private struct SupplementsRow: View {
    let takenCount: Int
    let total: Int
    @Binding var expanded: Bool

    var body: some View {
        Button {
            withAnimation(.snappy) { expanded.toggle() }
        } label: {
            HStack(spacing: 10) {
                ring
                VStack(alignment: .leading, spacing: 1) {
                    Text("Supplements")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("\(takenCount) of \(total) taken")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel("Supplements")
        .accessibilityValue("\(takenCount) of \(total) taken")
        .accessibilityHint(expanded ? Text("Collapses the list") : Text("Expands the list"))
    }

    private var ring: some View {
        ZStack {
            if takenCount == total {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
            } else {
                Circle()
                    .stroke(.secondary.opacity(0.4), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: total == 0 ? 0 : CGFloat(takenCount) / CGFloat(total))
                    .stroke(.green, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}
