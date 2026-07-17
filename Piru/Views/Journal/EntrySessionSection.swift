import SwiftUI

/// The session this dose belongs to: its title row (a link only when the session
/// isn't already beneath us in the navigation path), the sibling doses taken
/// alongside, and — when the combination warrants it — the session's worst
/// interaction echoed with its severity chip. The echo names one pair only; the
/// session screen holds the full list.
struct EntrySessionSection: View {
    @Environment(\.appNavigator) private var navigator
    let entry: DoseEntry
    let sessionInteraction: InteractionResult?
    let colorMap: [String: Color]

    private static let maxSiblingRows = 3

    var body: some View {
        if let session = entry.session {
            let siblings = session.orderedDoses.filter { $0.id != entry.id }
            let sessionActive = Self.isActive(session)
            Section("Part of Session") {
                sessionRow(session)
                ForEach(Array(siblings.prefix(Self.maxSiblingRows)), id: \.id) { sibling in
                    EntrySiblingRow(dose: sibling, sessionActive: sessionActive, colorMap: colorMap)
                }
                if siblings.count > Self.maxSiblingRows {
                    Text("+ \(siblings.count - Self.maxSiblingRows) more")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                if let warning = sessionInteraction {
                    EntryInteractionEchoRow(warning: warning)
                }
            }
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: Session) -> some View {
        let label = EntrySessionRowLabel(
            title: session.title ?? Self.formattedSessionDate(session.startDate),
            subtitle: Self.sessionSubtitle(session),
        )
        if sessionInNavigationPath(session) {
            label
        } else {
            NavigationLink(value: PushRoute.session(id: session.id)) {
                label
            }
        }
    }

    /// `true` when the session screen is already below us in this tab's push
    /// path — the usual arrival — so the row carries no link back to it. Deep
    /// links and search land here without the session, and get the link.
    private func sessionInNavigationPath(_ session: Session) -> Bool {
        navigator.path(for: navigator.selectedTab).contains(.session(id: session.id))
    }

    /// "Saturday, July 11" — the session screen's untitled-session title, so the
    /// link previews exactly what pushing it shows.
    static func formattedSessionDate(_ date: Date) -> String {
        let base = Date.FormatStyle.dateTime.day().month(.wide)
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        let dateTitle = date.formatted(sameYear ? base : base.year())
        return "\(date.formatted(.dateTime.weekday(.wide))), \(dateTitle)"
    }

    /// "2 doses · 3h 21m" for an ended session; "2 doses · 44m ago" (since the
    /// first dose) while it's still running.
    static func sessionSubtitle(_ session: Session) -> String {
        let doses = session.orderedDoses
        let countText = doses.count == 1
            ? String(localized: "1 dose")
            : String(localized: "\(doses.count) doses")
        if isActive(session) {
            return "\(countText) · \(EntryDoseFormat.relativeText(from: session.startDate, now: .now))"
        }
        guard let first = doses.first?.timestamp, let last = doses.last?.timestamp,
              last > first else { return countText }
        return "\(countText) · \(last.timeIntervalSince(first).durationHM)"
    }

    /// Whether any dose in the session is still inside its modeled effect window.
    static func isActive(_ session: Session) -> Bool {
        session.orderedDoses.contains { dose in
            guard let state = ActiveSubstanceState.from(entry: dose, colorHex: "000000") else { return false }
            let end = state.doseTimestamp.addingTimeInterval(state.totalMinutes * 60)
            return Date.now >= state.doseTimestamp && Date.now < end
        }
    }
}

/// The session row's two-line label — title over a doses/duration subtitle.
struct EntrySessionRowLabel: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

/// One "with <name> <amount> · <time>" sibling dose taken alongside this one.
struct EntrySiblingRow: View {
    let dose: DoseEntry
    let sessionActive: Bool
    let colorMap: [String: Color]

    var body: some View {
        let name = CustomSubstanceStore.shared.displayName(for: dose.substance)
        let time = sessionActive
            ? EntryDoseFormat.relativeText(from: dose.timestamp, now: .now)
            : dose.timestamp.formatted(date: .omitted, time: .shortened)
        let detail = "\(name) \(dose.amount.doseFormatted) \(dose.unit) · \(time)"
        return HStack(spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(colorMap[dose.substance.lowercased()] ?? Color(hex: PresetColor.defaultHex))
                .accessibilityHidden(true)
            Text("with \(detail)")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

/// One interaction row in the session-safety anatomy: severity triangle in the
/// dot slot, the pair in primary text, the severity as the only colored element,
/// the explanation beneath.
struct EntryInteractionEchoRow: View {
    let warning: InteractionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: warning.severity == .dangerous ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(warning.severity.labelColor)
                    .accessibilityHidden(true)
                Text(verbatim: "\(warning.substanceA) + \(warning.substanceB)")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(String(localized: warning.severity.label).lowercased())
                    .capsuleChip(tint: warning.severity.labelColor)
            }
            Text(warning.description)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
