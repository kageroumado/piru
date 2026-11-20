import SwiftUI

/// Model-derived clearance status for a journal row.
enum BodyLoadStatus {
    /// Still circulating: "26% eliminated in model · threshold ~5 AM", with "33 / 110 mg" as the trailing readout.
    case eliminating(percent: Int, clear: String, remaining: Double)
    /// Below the model's display threshold; active metabolites may persist.
    case cleared(hasActiveMetabolite: Bool = false)
    /// Insufficient half-life information to estimate clearance.
    case unmodeled
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
        /// Mirrors `Cleared.unit`: in the library's unit this row would print grams
        /// with an "mg" suffix.
        let unit: String
        /// Amount still circulating, converted into `unit`. Held here rather than
        /// read off `active.totalRemaining` so the numerator and the denominator
        /// of the readout can never be in different units.
        let remaining: Double
        /// When the summed curve drops below the clear threshold
        /// (``SessionBodyLoadModel/clearText(for:)``), scanned once when the
        /// model is built rather than on every row render.
        let clearText: String

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

    /// What a cleared row says beside its total: a substance with no known
    /// half-life says so, and one that wore off says it only beside rows that
    /// are still active.
    func status(of row: Cleared) -> BodyLoadStatus? {
        if row.unmodeled { return .unmodeled }
        return active.isEmpty ? nil : .cleared(hasActiveMetabolite: row.hasActiveMetabolite)
    }

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
            /// The group's first dose; every later one is summed in its unit.
            var unitOf: DoseQuantity
            var count = 0
            /// Every `productName` the group's doses were logged under — the
            /// user's own word for the substance (a brand, or a Chinese alias
            /// like 美金刚). Empty string stands for "logged under the canonical
            /// name", so a mixed group can't be titled by one product.
            var products: Set<String> = []
        }
        // One substance in one unit family — the calculator's own keying, so a
        // substance logged in both g and mL is two rows, each in its own unit,
        // never 500 mg + 1 g read as 501 or an mL remainder labeled in grams.
        struct GroupKey: Hashable {
            let name: String
            let family: DoseQuantity.Family
        }
        var groups: [GroupKey: Group] = [:]
        for entry in entries {
            let substance = SubstanceLibrary.lookup(entry.substance)
            guard let dose = substance?.quantity(of: entry) ?? entry.quantity else { continue }
            let canonical = substance?.name ?? entry.substance
            let key = GroupKey(name: canonical.lowercased(), family: dose.family)
            let product = entry.productName?.trimmingCharacters(in: .whitespaces) ?? ""
            if var group = groups[key] {
                // The key's family guarantees the two convert.
                guard let amount = dose.value(inUnitOf: group.unitOf) else { continue }
                group.total += amount
                group.count += 1
                group.products.insert(product)
                groups[key] = group
            } else {
                groups[key] = Group(
                    name: canonical, total: entry.amount, unit: entry.unit, unitOf: dose,
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
            return PKResolver.halfLifeMinutes(substance: substance) != nil
        }

        var model = SessionBodyLoadModel()
        var covered = Set<GroupKey>()
        for active in ActiveSubstanceCalculator.compute(from: entries, colorMap: colorMap) {
            let activeTotal = SubstanceLibrary.lookup(active.name)?.quantity(active.totalRemaining, unit: active.unit)
                ?? DoseQuantity(active.totalRemaining, unit: active.unit)
            let key = GroupKey(name: active.name.lowercased(), family: activeTotal.family)
            covered.insert(key)
            let group = groups[key]
            // Group values below the display threshold without asserting complete clearance.
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
                let remaining = group.flatMap { activeTotal.value(inUnitOf: $0.unitOf) } ?? active.totalRemaining
                model.active.append(Active(
                    active: active,
                    displayName: title(canonical: active.name, products: group?.products),
                    count: group?.count ?? active.doses.count,
                    sessionTotal: group?.total ?? active.totalDosed,
                    unit: unit,
                    remaining: remaining,
                    clearText: clearText(for: active),
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
    private static func clearText(for active: ActiveSubstance) -> String {
        let ke = PKModel.ke(fromHalfLifeMinutes: active.halfLifeMinutes)
        let ka = PKResolver.ka(forSubstance: active.name, ke: ke)
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
    /// the meta line. Also used by the dose detail's "effects ended · cleared"
    /// receipt so milestones read alike.
    ///
    /// Past the coming week the weekday name stops identifying a date and starts
    /// misnaming one: a long-acting drug clearing ~81 days out (fluoxetine's
    /// 16-day t½) would render "Sun 1 PM", which reads as *this* Sunday — an
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
