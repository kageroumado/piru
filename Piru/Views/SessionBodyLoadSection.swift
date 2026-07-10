import SwiftUI

/// "In your body" — the session's per-substance aggregates. Merges what used to
/// be the bare cumulative-totals rows with live elimination state: total dosed,
/// what's still circulating, clearance projections, and the elimination curve
/// one tap away (a rotating chevron marks every row as expandable). Totals are
/// the "dosed" side of the body-load equation, so the two former sections are
/// one story here. For a past session (everything cleared) it degrades to
/// re-dose totals alone; a session of single doses that have all worn off shows
/// nothing. Headerless — the cumulative-total hero and curve name the card
/// themselves.
struct SessionBodyLoadSection: View {
    let entries: [DoseEntry]
    let colorMap: [String: Color]

    /// Which substances have their elimination curve expanded in place.
    @State private var expanded: Set<String> = []
    /// Guards the one-time default expansion of the first substance.
    @State private var didSeedExpansion = false

    var body: some View {
        let model = makeModel()
        if !model.active.isEmpty || !model.totalsOnly.isEmpty {
            Section {
                ForEach(model.active) { row in
                    activeRow(row)
                }
                ForEach(model.totalsOnly) { row in
                    totalsRow(row)
                }
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

    // MARK: - Active row

    /// A native `DisclosureGroup` — the same fold affordance the recovery guide
    /// uses — so the curve reads as expandable, not as a navigation row. The
    /// always-visible label mirrors a dose row: dot · name on the left, the big
    /// rounded session total on the right (immediately before the chevron); the
    /// live remaining amount rides the meta line's trailing edge, where a dose
    /// row keeps its strength chip.
    private func activeRow(_ row: ActiveRow) -> some View {
        DisclosureGroup(isExpanded: expansion(row.id)) {
            SubstanceEliminationCurve(active: row.active)
                .padding(.top, 4)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(row.active.color)
                        .accessibilityHidden(true)
                    Text(row.displayName)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(row.sessionTotal.doseFormatted) \(row.active.unit)")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(row.totalLevel?.labelColor ?? .primary)
                        .lineLimit(1)
                }
                metaLine(row)
            }
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

    /// The secondary line under the hero, in the dose row's meta size
    /// (`.subheadline`, secondary): the eliminated share and clear-by time on the
    /// left, the still-circulating amount ("N mg left") trailing — aligned with
    /// where a dose row keeps its strength chip.
    private func metaLine(_ row: ActiveRow) -> some View {
        let percent = Int(row.active.eliminatedFraction * 100)
        return HStack(spacing: 8) {
            Text("\(percent)% eliminated · clear ~\(clearText(for: row.active))")
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(row.active.totalRemaining.doseFormatted) \(row.active.unit) left")
                .lineLimit(1)
                .layoutPriority(1)
        }
        .font(.subheadline)
        .foregroundStyle(Theme.secondaryLabel)
    }

    // MARK: - Totals-only row (past / fully-cleared substance)

    /// A substance that's no longer measurably in the body (or has no half-life
    /// data): just its re-dose total, level-tinted, in the dose rows' language.
    private func totalsRow(_ row: TotalsRow) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(row.color)
                .accessibilityHidden(true)
            Text(row.displayName)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            Text(verbatim: "\(row.count)×")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .monospacedDigit()
            Spacer(minLength: 8)
            Text("\(row.total.doseFormatted) \(row.unit)")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(row.level?.labelColor ?? .primary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Projection

    /// Clock/weekday time the summed multi-dose curve drops to ~3% of the total
    /// dosed — a forward scan matching the curve's superposition math.
    private func clearText(for active: ActiveSubstance) -> String {
        let ke = PKModel.ke(fromHalfLifeMinutes: active.halfLifeMinutes)
        let ka = SubstanceEliminationCurve.estimateKa(for: active.name, ke: ke)
        guard let clear = projectedDate(remainingFraction: 0.03, active: active, ke: ke, ka: ka) else {
            return String(localized: "soon")
        }
        return milestoneText(clear)
    }

    private func projectedDate(remainingFraction target: Double, active: ActiveSubstance, ke: Double, ka: Double) -> Date? {
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

    /// Clock time for a same-day milestone; weekday-prefixed once it crosses into
    /// another day ("Fri 6:54 AM").
    private func milestoneText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    // MARK: - Model

    private struct ActiveRow: Identifiable {
        let active: ActiveSubstance
        let displayName: String
        /// Doses logged this session (not just those still circulating).
        let count: Int
        /// The session's summed amount and its strength classification.
        let sessionTotal: Double
        let totalLevel: DoseLevel?

        var id: String {
            active.name
        }
    }

    private struct TotalsRow: Identifiable {
        let displayName: String
        let color: Color
        let total: Double
        let unit: String
        let count: Int
        let level: DoseLevel?

        var id: String {
            displayName
        }
    }

    private struct Model {
        var active: [ActiveRow] = []
        var totalsOnly: [TotalsRow] = []
    }

    /// Group the session's doses per canonical substance (the calculator's own
    /// keying), join with the live body-load result, and classify each total
    /// against the substance's dose ladder. Cheap for a session's handful of
    /// doses — the library lookups behind it are cached.
    private func makeModel() -> Model {
        struct Group {
            var name: String
            var total = 0.0
            var unit: String
            var count = 0
            var route: RouteOfAdministration
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
                groups[key] = Group(name: canonical, total: entry.amount, unit: entry.unit, count: 1, route: entry.route)
            }
        }

        func level(for group: Group) -> DoseLevel? {
            SubstanceLibrary.lookupByNameOrAlias(group.name)?
                .doseRange(for: group.route)?
                .level(for: group.total)
        }

        var model = Model()
        var covered = Set<String>()
        for active in ActiveSubstanceCalculator.compute(from: entries, colorMap: colorMap) {
            let key = active.name.lowercased()
            covered.insert(key)
            let group = groups[key]
            model.active.append(ActiveRow(
                active: active,
                displayName: CustomSubstanceStore.shared.displayName(for: active.name),
                count: group?.count ?? active.doses.count,
                sessionTotal: group?.total ?? active.totalDosed,
                totalLevel: group.flatMap(level(for:)),
            ))
        }
        model.totalsOnly = groups
            .filter { key, group in group.count > 1 && !covered.contains(key) }
            .map { _, group in
                TotalsRow(
                    displayName: CustomSubstanceStore.shared.displayName(for: group.name),
                    color: colorMap[group.name.lowercased()] ?? Theme.accent,
                    total: group.total,
                    unit: group.unit,
                    count: group.count,
                    level: level(for: group),
                )
            }
            .sorted { $0.displayName < $1.displayName }
        return model
    }
}
