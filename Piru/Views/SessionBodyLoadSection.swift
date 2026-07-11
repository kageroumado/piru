import SwiftUI

/// The status line under an "in your body" row: either a live elimination
/// readout or a "fully eliminated" marker. `nil` (no status) renders a compact
/// single-line row — used when nothing in the section is still circulating.
enum BodyLoadStatus {
    /// Still circulating: "26% eliminated · clear ~5 AM" with a trailing "N mg left".
    case eliminating(percent: Int, clear: String, remaining: Double)
    /// Fully cleared, shown for visual consistency when other rows are still active.
    case cleared
}

/// The two-line content of one "in your body" row — dot · name · intake count on
/// top with the uncolored session total, and a status line beneath. Shared by the
/// live ``SessionBodyLoadSection`` (inside its expandable curve) and the session
/// share image (static), so the two renderings can never drift apart.
struct BodyLoadRowLabel: View {
    let dotColor: Color
    let name: String
    let count: Int
    let total: Double
    let unit: String
    let status: BodyLoadStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 8) {
                nameCluster
                Spacer(minLength: 8)
                trailingReadout
            }
            statusLine
        }
    }

    /// Dot · name · optional intake-count pill (`2×`). The count is a small neutral
    /// capsule rather than a tiny inline word so a redose count reads as a badge,
    /// not a stray glyph riding beside the name.
    private var nameCluster: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(dotColor)
                .accessibilityHidden(true)
            Text(name)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            if count > 1 {
                Text(verbatim: "\(count)×")
                    .monospacedDigit()
                    .capsuleChip(tint: Theme.secondaryLabel)
            }
        }
    }

    /// The quantity, deliberately quieter than the entry rows' hero number — the
    /// totals section restates the same doses, so it shouldn't carry equal weight.
    /// An active substance shows "remaining / total unit" so the still-circulating
    /// amount leads; a cleared/static one shows the total alone.
    @ViewBuilder
    private var trailingReadout: some View {
        switch status {
        case let .eliminating(_, _, remaining):
            cumulativeReadout(remaining: remaining)
        case .cleared, nil:
            MeasurementLabel(amount: total, unit: unit, numberStyle: .body, unitStyle: .caption)
        }
    }

    /// "33 / 110 mg" — remaining (primary, rounded) over the session total
    /// (secondary), unit trailing. Compact so seven glyphs don't take on the mass
    /// of the hero readout.
    private func cumulativeReadout(remaining: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(remaining.doseFormatted)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
            Text(verbatim: " / ")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.tertiary)
            Text(total.doseFormatted)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .monospacedDigit()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(remaining.doseFormatted) of \(total.doseFormatted) \(unit) remaining"))
    }

    /// The secondary line, in the dose row's meta size (`.subheadline`, secondary):
    /// the eliminated share and clear-by time on the left, the still-circulating
    /// amount trailing — aligned with where a dose row keeps its strength chip.
    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case let .eliminating(percent, clear, _):
            // The still-circulating amount now leads the trailing readout
            // ("33 / 110 mg"), so this line carries only the eliminated share and
            // the clear-by projection.
            Text("\(percent)% eliminated · clear ~\(clear)")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
        case .cleared:
            Text("Fully eliminated")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
        case nil:
            EmptyView()
        }
    }
}

/// The "in your body" data for a session: which substances are still circulating
/// (with elimination state) and which have fully cleared, plus the clear-by
/// projection. Computed once and rendered by both the live section and the share
/// image, so the data behind them stays identical.
struct SessionBodyLoadModel {
    struct Active: Identifiable {
        let active: ActiveSubstance
        let displayName: String
        /// Doses logged this session (not just those still circulating).
        let count: Int
        /// The session's summed amount.
        let sessionTotal: Double

        var id: String {
            active.name
        }
    }

    struct Cleared: Identifiable {
        let displayName: String
        let color: Color
        let total: Double
        let unit: String
        let count: Int

        var id: String {
            displayName
        }
    }

    var active: [Active] = []
    var cleared: [Cleared] = []

    var isEmpty: Bool {
        active.isEmpty && cleared.isEmpty
    }

    /// Group the session's doses per canonical substance (the calculator's own
    /// keying) and join with the live body-load result. Cheap for a session's
    /// handful of doses — the library lookups behind it are cached.
    @MainActor
    static func make(entries: [DoseEntry], colorMap: [String: Color]) -> SessionBodyLoadModel {
        struct Group {
            var name: String
            var total = 0.0
            var unit: String
            var count = 0
        }
        var groups: [String: Group] = [:]
        for entry in entries {
            let canonical = SubstanceLibrary.timelineLookup(entry.substance)?.name ?? entry.substance
            let key = canonical.lowercased()
            if var group = groups[key] {
                group.total += entry.amount
                group.count += 1
                groups[key] = group
            } else {
                groups[key] = Group(name: canonical, total: entry.amount, unit: entry.unit, count: 1)
            }
        }

        var model = SessionBodyLoadModel()
        var covered = Set<String>()
        for active in ActiveSubstanceCalculator.compute(from: entries, colorMap: colorMap) {
            let key = active.name.lowercased()
            covered.insert(key)
            let group = groups[key]
            // Screen-only cap: a substance the calculator still tracks but that's
            // ≥95% eliminated reads as "fully eliminated" here rather than
            // "96% eliminated · clear ~soon". Purely a display choice — the shared
            // ActiveSubstanceCalculator is untouched.
            if active.eliminatedFraction >= clearedThreshold {
                model.cleared.append(Cleared(
                    displayName: CustomSubstanceStore.shared.displayName(for: active.name),
                    color: active.color,
                    total: group?.total ?? active.totalDosed,
                    unit: group?.unit ?? active.unit,
                    count: group?.count ?? active.doses.count,
                ))
            } else {
                model.active.append(Active(
                    active: active,
                    displayName: CustomSubstanceStore.shared.displayName(for: active.name),
                    count: group?.count ?? active.doses.count,
                    sessionTotal: group?.total ?? active.totalDosed,
                ))
            }
        }
        // Substances the calculator dropped entirely (fully worn off), re-dosed at
        // least twice — single doses that have cleared show nothing.
        let dropped = groups
            .filter { key, group in group.count > 1 && !covered.contains(key) }
            .map { _, group in
                Cleared(
                    displayName: CustomSubstanceStore.shared.displayName(for: group.name),
                    color: colorMap[group.name.lowercased()] ?? Theme.accent,
                    total: group.total,
                    unit: group.unit,
                    count: group.count,
                )
            }
        model.cleared = (model.cleared + dropped).sorted { $0.displayName < $1.displayName }
        return model
    }

    /// Eliminated fraction at or above which this screen calls a substance fully
    /// cleared (display-only; see ``make``).
    private static let clearedThreshold = 0.95

    /// Clock/weekday time the summed multi-dose curve drops to ~3% of the total
    /// dosed — a forward scan matching the curve's superposition math.
    static func clearText(for active: ActiveSubstance) -> String {
        let ke = PKModel.ke(fromHalfLifeMinutes: active.halfLifeMinutes)
        let ka = SubstanceEliminationCurve.estimateKa(for: active.name, ke: ke)
        guard let clear = projectedDate(remainingFraction: 0.03, active: active, ke: ke, ka: ka) else {
            return String(localized: "soon")
        }
        return milestoneText(clear)
    }

    private static func projectedDate(remainingFraction target: Double, active: ActiveSubstance, ke: Double, ka: Double) -> Date? {
        let horizonMinutes = active.halfLifeMinutes * 10
        let stepMinutes = max(1.0, active.halfLifeMinutes / 200)
        let now = Date.now
        var minutesAhead = 0.0
        while minutesAhead <= horizonMinutes {
            let when = now.addingTimeInterval(minutesAhead * 60)
            var remaining = 0.0
            for dose in active.doses {
                let elapsed = when.timeIntervalSince(dose.timestamp) / 60
                guard elapsed >= 0 else { continue }
                remaining += dose.amount * PKModel.fractionRemainingInBody(at: elapsed, ke: ke, ka: ka)
            }
            if remaining <= target * active.totalDosed { return when }
            minutesAhead += stepMinutes
        }
        return nil
    }

    /// Clock time for a same-day milestone; weekday + hour once it crosses into
    /// another day ("Fri 6 AM") — minutes are dropped there both because they're
    /// false precision that far out and because the full "Fri 6:54 AM" overflows
    /// the meta line next to the trailing "N mg left".
    private static func milestoneText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour())
    }
}

/// "In your body" — the session's per-substance aggregates. Merges what used to
/// be the bare cumulative-totals rows with live elimination state: total dosed,
/// what's still circulating, clearance projections, and the elimination curve
/// one tap away (a rotating chevron marks every active row as expandable). Totals
/// are the "dosed" side of the body-load equation, so the two former sections are
/// one story here. For a past session (everything cleared) it degrades to re-dose
/// totals alone; a session of single doses that have all worn off shows nothing.
struct SessionBodyLoadSection: View {
    let entries: [DoseEntry]
    let colorMap: [String: Color]

    /// Which substances have their elimination curve expanded in place.
    @State private var expanded: Set<String> = []
    /// Guards the one-time default expansion of the first substance.
    @State private var didSeedExpansion = false

    var body: some View {
        let model = SessionBodyLoadModel.make(entries: entries, colorMap: colorMap)
        if !model.isEmpty {
            Section {
                ForEach(model.active) { row in
                    activeRow(row)
                }
                ForEach(model.cleared) { row in
                    BodyLoadRowLabel(
                        dotColor: row.color,
                        name: row.displayName,
                        count: row.count,
                        total: row.total,
                        unit: row.unit,
                        status: model.active.isEmpty ? nil : .cleared,
                    )
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Total in Your Body")
            } footer: {
                if !model.active.isEmpty {
                    Text("Estimates from population half-lives — individual clearance varies.")
                }
            }
            // Open the first substance's curve by default, so the fold — and the
            // graph behind it — is discoverable without a tap.
            .onAppear {
                guard !didSeedExpansion else { return }
                didSeedExpansion = true
                if let first = model.active.first { expanded.insert(first.id) }
            }
        }
    }

    /// A native `DisclosureGroup` — the same fold affordance the recovery guide
    /// uses — so the curve reads as expandable, not as a navigation row. The
    /// always-visible label is the shared ``BodyLoadRowLabel``; expanding it
    /// reveals the substance's elimination curve.
    private func activeRow(_ row: SessionBodyLoadModel.Active) -> some View {
        DisclosureGroup(isExpanded: expansion(row.id)) {
            SubstanceEliminationCurve(active: row.active)
                .padding(.top, 4)
        } label: {
            BodyLoadRowLabel(
                dotColor: row.active.color,
                name: row.displayName,
                count: row.count,
                total: row.sessionTotal,
                unit: row.active.unit,
                status: .eliminating(
                    percent: Int(row.active.eliminatedFraction * 100),
                    clear: SessionBodyLoadModel.clearText(for: row.active),
                    remaining: row.active.totalRemaining,
                ),
            )
        }
        .tint(Theme.secondaryLabel)
        .accessibilityHint(Text("Shows the elimination curve"))
    }

    private func expansion(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isOpen in
                if isOpen { expanded.insert(id) } else { expanded.remove(id) }
            },
        )
    }
}
