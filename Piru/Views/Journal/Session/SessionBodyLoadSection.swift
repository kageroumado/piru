import SwiftUI

/// The status line under an "in your body" row: either a live elimination
/// readout or a "fully eliminated" marker. `nil` (no status) renders a compact
/// single-line row — used when nothing in the section is still circulating.
enum BodyLoadStatus {
    /// Still circulating: "26% eliminated · clear ~5 AM" with a trailing "N mg left".
    case eliminating(percent: Int, clear: String, remaining: Double)
    /// Fully cleared, shown for visual consistency when other rows are still active.
    /// `hasActiveMetabolite` qualifies the text when a longer-lived metabolite may persist.
    case cleared(hasActiveMetabolite: Bool = false)
    /// No half-life is known for this substance, so nothing about its clearance
    /// can be stated. Distinct from ``cleared``: the calculator drops a dose for
    /// two different reasons — worn off, and unmodelable — and calling the second
    /// one "fully eliminated" told a tester their 20-minute-old dose was gone.
    case unmodeled
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
                    .capsuleChip(text: Theme.secondaryLabel, fill: Theme.secondaryLabel)
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
        case .cleared, .unmodeled, nil:
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
        case let .cleared(hasActiveMetabolite):
            Text(hasActiveMetabolite
                ? "Fully eliminated · active metabolite may persist"
                : "Fully eliminated")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
        case .unmodeled:
            Text("No half-life data")
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
        /// Unit `sessionTotal` and `remaining` are denominated in — the unit the
        /// doses were *logged* in, not the library's default for the substance.
        /// Mirrors `Cleared.unit`; without it this row printed grams with an "mg"
        /// suffix.
        let unit: String
        /// Amount still circulating, converted into `unit`. Held here rather than
        /// read off `active.totalRemaining` so the numerator and the denominator
        /// of the readout can never be in different units.
        let remaining: Double

        var id: String {
            "\(active.name)|\(unit)"
        }
    }

    struct Cleared: Identifiable {
        let displayName: String
        let color: Color
        let total: Double
        let unit: String
        let count: Int
        /// `true` when the row is here because no half-life is known, not
        /// because the dose wore off.
        var unmodeled: Bool = false
        /// The parent is cleared but a longer-lived active metabolite may persist.
        var hasActiveMetabolite: Bool = false

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
            /// Every `productName` the group's doses were logged under — the
            /// user's own word for the substance (a brand, or a Chinese alias
            /// like 美金刚). Empty string stands for "logged under the canonical
            /// name", so a mixed group can't be titled by one product.
            var products: Set<String> = []
        }
        var groups: [String: Group] = [:]
        for entry in entries {
            let canonical = SubstanceLibrary.lookup(entry.substance)?.name ?? entry.substance
            let key = canonical.lowercased()
            let product = entry.productName?.trimmingCharacters(in: .whitespaces) ?? ""
            if var group = groups[key] {
                // Convert into the unit this group already established rather
                // than adding raw magnitudes — 500 mg + 1 g is 1500 mg, not 501
                // of anything. An inconvertible unit (mL, IU) can't be summed at
                // all, so it contributes its count but not its amount.
                if let amount = DoseUnit.convert(entry.amount, from: entry.unit, to: group.unit) {
                    group.total += amount
                }
                group.count += 1
                group.products.insert(product)
                groups[key] = group
            } else {
                groups[key] = Group(
                    name: canonical, total: entry.amount, unit: entry.unit,
                    count: 1, products: [product],
                )
            }
        }

        /// Title a group the way the dose rows above it do. Those resolve
        /// through `DoseTitle`, which honors the user's own word for the
        /// substance, so a dose logged as 美金刚 (or Concerta) titles this
        /// group by that name rather than the canonical one.
        ///
        /// A group mixing products (Concerta + Ritalin) keeps the canonical
        /// name — one brand can't title a total that isn't all that brand. A
        /// personal relabel still outranks both, via `displayName`'s own
        /// precedence.
        func title(canonical: String, products: Set<String>?) -> String {
            let shared = products.flatMap { $0.count == 1 ? $0.first : nil }
            let product = (shared?.isEmpty == false) ? shared : nil
            return CustomSubstanceStore.shared.displayName(for: canonical, fallback: product)
        }

        /// Whether anything can be said about this substance's clearance. The
        /// calculator skips a dose it cannot model, so without this check the
        /// two reasons for being skipped are indistinguishable downstream.
        func hasHalfLife(_ name: String) -> Bool {
            guard let substance = SubstanceLibrary.lookup(name) else { return false }
            return PKResolver.halfLifeMinutes(substance: substance, entryName: name) != nil
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
                    displayName: title(canonical: active.name, products: group?.products),
                    color: active.color,
                    total: group?.total ?? active.totalDosed,
                    unit: group?.unit ?? active.unit,
                    count: group?.count ?? active.doses.count,
                    hasActiveMetabolite: SubstanceLibrary.hasActiveMetabolite(active.name),
                ))
            } else {
                // `group` counts every dose in the session; `active` counts only
                // those still circulating, so the two can settle on different
                // units when the session's first dose was skipped. Convert into
                // the displayed one.
                let unit = group?.unit ?? active.unit
                let remaining = DoseUnit.convert(active.totalRemaining, from: active.unit, to: unit)
                    ?? active.totalRemaining
                model.active.append(Active(
                    active: active,
                    displayName: title(canonical: active.name, products: group?.products),
                    count: group?.count ?? active.doses.count,
                    sessionTotal: group?.total ?? active.totalDosed,
                    unit: unit,
                    remaining: remaining,
                ))
            }
        }
        // Substances the calculator dropped. Two different reasons, and they must
        // not read alike: a dose that wore off, and a substance with no half-life
        // to model at all. A single dose that has cleared shows nothing, but an
        // unmodelable one always does — otherwise a substance you just took
        // silently vanishes from the section.
        let dropped = groups
            .filter { key, _ in !covered.contains(key) }
            .compactMap { _, group -> Cleared? in
                let unmodeled = !hasHalfLife(group.name)
                guard unmodeled || group.count > 1 else { return nil }
                return Cleared(
                    displayName: title(canonical: group.name, products: group.products),
                    color: colorMap[group.name.lowercased()] ?? Theme.accent,
                    total: group.total,
                    unit: group.unit,
                    count: group.count,
                    unmodeled: unmodeled,
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
    /// the meta line next to the trailing "N mg left". Also used by the dose
    /// detail's "effects ended · cleared" receipt so milestones read alike.
    ///
    /// Past the coming week the weekday name stops identifying a date and starts
    /// misnaming one: a long-acting drug clearing ~81 days out (fluoxetine's
    /// 16-day t½) rendered "Sun 1 PM", which reads as *this* Sunday — an
    /// eleven-week error stated with total confidence. Beyond that horizon the
    /// calendar date is the only honest form, and the hour is dropped with it
    /// (a to-the-hour claim months out is noise).
    static func milestoneText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        let daysAhead = calendar.dateComponents([.day], from: .now, to: date).day ?? 0
        guard daysAhead < 6 else {
            return date.formatted(.dateTime.month(.abbreviated).day())
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
    /// Section header — the session screen's per-substance aggregate reads
    /// "Total in Your Body"; the dose detail reuses the section for a single
    /// dose, where there is no "total" to speak of.
    var header: LocalizedStringKey = "Total in Your Body"
    /// When `true` the section renders only while something is still
    /// circulating — a fully cleared dose shows nothing at all rather than a
    /// "cleared" placeholder row (the dose detail's behavior).
    var activeOnly = false

    /// Which substances have their elimination curve expanded in place.
    @State private var expanded: Set<String> = []
    /// Guards the one-time default expansion of the first substance.
    @State private var didSeedExpansion = false

    var body: some View {
        let model = SessionBodyLoadModel.make(entries: entries, colorMap: colorMap)
        if !model.isEmpty, !(activeOnly && model.active.isEmpty) {
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
                        status: row.unmodeled
                            ? .unmodeled
                            : (model.active.isEmpty ? nil : .cleared(hasActiveMetabolite: row.hasActiveMetabolite)),
                    )
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(header)
            } footer: {
                if !model.active.isEmpty {
                    Text("An estimate of how much of each substance is still in your body. This doesn't always correspond to how strong the effects feel, or to how long it stays detectable.")
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
            SubstanceEliminationCurve(active: row.active, displayName: row.displayName)
                .padding(.top, 4)
        } label: {
            BodyLoadRowLabel(
                dotColor: row.active.color,
                name: row.displayName,
                count: row.count,
                total: row.sessionTotal,
                unit: row.unit,
                status: .eliminating(
                    percent: Int(row.active.eliminatedFraction * 100),
                    clear: SessionBodyLoadModel.clearText(for: row.active),
                    remaining: row.remaining,
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
