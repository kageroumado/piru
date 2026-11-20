import Foundation
import Observation
import SwiftData

// MARK: - Staged Chip Counts

/// A staged chip's identity within one substance: route + unit + the amount at
/// display resolution (so the editor's `31.700000000000003 → "31.7"` round-trip
/// still matches its chip). Keys a value snapshot of staged counts.
struct StagedChipKey: Hashable {
    let route: RouteOfAdministration
    let unit: String
    let amountKey: Int
}

/// One chip across the whole tray: the staged row's substance identity plus
/// the chip within it. What a My Meds pill records per dose it staged.
struct StagedChipUnit: Hashable {
    let identity: String
    let chip: StagedChipKey
    /// The combination product the chip's row was staged from, `nil` for a
    /// dose staged on its own: a product's component is a row of its own.
    var combinationName: String?
}

/// A value snapshot of one substance's staged chip counts. Passed to
/// ``SubstanceCardView`` so a card reflects staged state through a *comparable*
/// input instead of reading the live `DoseTrayModel` — reading the model would
/// re-render **every** card on any staging change, re-diffing thousands of chip
/// buttons and context menus per logging session. With a value snapshot, only
/// the card whose slice actually changed re-renders (its `.equatable()` skips
/// the rest).
struct StagedChipCounts: Equatable {
    fileprivate let counts: [StagedChipKey: Int]
    static let empty = StagedChipCounts(counts: [:])

    /// Staged count for one chip, matched at display resolution.
    func count(route: RouteOfAdministration, amount: Double, unit: String) -> Int {
        counts[StagedChipKey(route: route, unit: unit, amountKey: DoseTrayModel.displayKey(amount))] ?? 0
    }
}

// MARK: - Tray Model

/// Staging state for the quick-log tray. Owned by `QuickLogView` so dose chips
/// can reflect what's staged; rendered by ``TrayStagedListCard`` and
/// ``TrayCommitBar``.
@Observable
final class DoseTrayModel {
    var staged: [StagedDose] = []
    var time: TrayTime = .now
    var tags: Set<String> = []
    var location: PickedLocation?
    /// What was eaten before this dose. Tray-wide like the location, but committed
    /// only onto oral doses: it is the stomach an oral dose waits in.
    var meal: MealState?
    /// The profile this log is for when it is someone other than the active
    /// one (the For chip); `nil` logs into the active profile's journal. Lasts
    /// one log: ``takeRecipient()`` clears it at commit.
    var recipientID: UUID?
    /// Every staged dose the user has opened inline — multiple can stay
    /// expanded at once, so a complex stack can be composed in one pass.
    var expandedItemIDs: Set<UUID> = []

    /// Haptic triggers — bumped on discrete staging events so the view can
    /// attach `.sensoryFeedback` without coupling feedback to every tap.
    private(set) var stageTick = 0
    private(set) var incrementTick = 0
    /// Bumped when a My Meds pill takes its doses back out of the tray.
    private(set) var unstageTick = 0

    /// What each My Meds pill's taps put in the tray, keyed by the pill's
    /// ``DailyCategoryGroup/id``: units per chip. A second tap subtracts
    /// exactly this, so a dose added by any other path — another substance,
    /// one more unit of a med the pill also staged — stays put.
    private var pillContributions: [String: [StagedChipUnit: Int]] = [:]

    /// Stored — *not* computed from `staged` — so a view reading it (the
    /// toolbar's close button, the dock's face selection in `QuickLogView.body`)
    /// subscribes to *this* flag rather than the whole `staged` array. Maintained
    /// only at the count-change sites (`stage` append / `stageDraft` / `remove`),
    /// and only when the value actually flips, so stepping a dose's amount or
    /// re-tapping a chip, which mutate `staged` but not its count, doesn't
    /// re-run `QuickLogView.body`. `isCommittable` stays computed: it depends on
    /// per-dose amounts and the one body that reads it is ``TrayCommitBar``'s,
    /// which must re-render on those edits anyway.
    private(set) var isEmpty = true

    /// The profile to log for, handed to the commit and reset to the active
    /// profile, so a choice of someone else never outlives the log it was for.
    func takeRecipient() -> UUID? {
        defer { recipientID = nil }
        return recipientID
    }

    /// Re-sync the stored ``isEmpty`` after a count change, notifying only on a
    /// real flip (an `@Observable` set always notifies, even for an equal value).
    private func syncEmptiness() {
        let nowEmpty = staged.isEmpty
        if nowEmpty != isEmpty { isEmpty = nowEmpty }
    }

    /// Every staged dose carries a number, or has declared it has none.
    var isCommittable: Bool {
        !staged.isEmpty && staged.allSatisfy { $0.isUnknownAmount || $0.totalAmount > 0 }
    }

    /// How many of a given chip are staged (drives the chip's count badge).
    func quantity(substance: String, productName: String? = nil, route: RouteOfAdministration, amount: Double, unit: String) -> Int {
        // Resolve the library record the same way the daily-item staging does, so a
        // faceted med (Concerta) counts on its own row. A dose staged *without* a
        // library record — a custom substance the catalog can't resolve — keys by
        // bare name instead, so match that identity too. The two are disjoint (a
        // uid-bearing key is never a lowercased name), so this can't false-match.
        let resolved = Self.stagedIdentity(substance: substance, productName: productName, librarySubstance: SubstanceLibrary.lookup(substance.lowercased()), route: route)
        let nameOnly = Self.stagedIdentity(substance: substance, productName: productName, librarySubstance: nil, route: route)
        guard let index = staged.firstIndex(where: {
            ($0.identityKey == resolved || $0.identityKey == nameOnly) && $0.route == route && $0.unit == unit
                && $0.combinationName == nil
        }) else { return 0 }
        return staged[index].components.first { Self.sameAmount($0.amount, amount) }?.count ?? 0
    }

    /// Snapshot every staged chip count, bucketed by lowercased substance name,
    /// as ``StagedChipCounts`` value types. Built once per staging change (the
    /// card list reads this in `body`); each card then takes only its own slice,
    /// so a card whose staged state is unchanged is skipped by its `.equatable()`
    /// instead of re-diffing all its chips. Keyed identically to ``quantity`` —
    /// `(substance, route, unit, amount-at-display-resolution)`.
    func stagedCountsBySubstance() -> [String: StagedChipCounts] {
        // Bucketed by substance *identity* (== a card's `id`), so a Concerta chip's
        // staged count shows on the Concerta card, not a plain Methylphenidate one.
        // A product's component counts on the product's card, never on its
        // substance's: that substance's chip stages a row of its own.
        var byIdentity: [String: [StagedChipKey: Int]] = [:]
        for dose in staged where dose.combinationName == nil {
            let identity = dose.identityKey
            var keyed = byIdentity[identity] ?? [:]
            for component in dose.components {
                let key = StagedChipKey(route: dose.route, unit: dose.unit, amountKey: Self.displayKey(component.amount))
                keyed[key, default: 0] += component.count
            }
            byIdentity[identity] = keyed
        }
        return byIdentity.mapValues { StagedChipCounts(counts: $0) }
    }

    /// Match two chip amounts at their *display* resolution. A numeric key, never
    /// a `doseFormatted` **string** comparison: this runs inside `body` via the
    /// card's count badge, and a string compare allocates a formatted string per
    /// component on every staged-chip lookup. Mirrors `doseFormatted`'s
    /// magnitude-dependent rounding (0 dp ≥100, 1 dp ≥10, else 2 dp), so the
    /// editor's text round-trip of 31.700000000000003 → "31.7" → 31.7 still
    /// matches its chip.
    private static func sameAmount(_ lhs: Double, _ rhs: Double) -> Bool {
        displayKey(lhs) == displayKey(rhs)
    }

    /// The amount in hundredths, rounded at `doseFormatted`'s resolution for
    /// its magnitude. The rounded value is put back into hundredths at every
    /// magnitude, so the key is the amount itself: keyed as a bare
    /// `value × scale`, 4, 40 and 400 would all be 400 and a 400 mg chip
    /// would count as one more 40.
    ///
    /// Total over every `Double`: a non-finite value keys as 0, and the scaled
    /// value is clamped into a range `Int` holds before converting, because
    /// `Int(_:)` traps past `Int.max`. Amounts that large are all one chip.
    fileprivate static func displayKey(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        let magnitude = Swift.abs(value)
        let scale: Double = magnitude >= 100 ? 1 : magnitude >= 10 ? 10 : 100
        let limit = 1e15
        let rounded = min(max((value * scale).rounded(), -limit), limit)
        return Int(rounded * (100 / scale))
    }

    /// Stage a daily-set med as a chip, carrying its product so a Concerta med
    /// logs as Concerta — the tray derives the release form/isomer from it,
    /// same as search.
    func stage(dailyItem item: DailyDoseItem, colorLookup: [String: P3Color]) {
        stage(dailyMed: DailyMedSnapshot(item), colorLookup: colorLookup)
    }

    /// Stage a daily-set med from the My Meds pills' value snapshot. A med
    /// saved as a combination product stages the product: its amount is a
    /// count of units, or a volume in mL for a liquid.
    func stage(dailyMed item: DailyMedSnapshot, colorLookup: [String: P3Color]) {
        if let product = CustomSubstanceStore.shared.combination(named: item.substance) {
            stage(product: product, amount: item.amount, colorLookup: colorLookup)
            for index in staged.indices where staged[index].combinationName == product.name {
                staged[index].isFromDailySet = true
                staged[index].isBackgroundMed = item.isBackgroundMed
            }
            return
        }
        stage(
            substance: item.substance,
            route: item.route,
            amount: item.amount,
            unit: item.unit,
            tint: SubstancePalette.tint(for: item.substance, tintMap: colorLookup),
            librarySubstance: SubstanceLibrary.lookup(item.substance.lowercased()),
            productName: item.productName,
            isFromDailySet: true,
            isBackgroundMed: item.isBackgroundMed,
        )
    }

    // MARK: My Meds pills

    /// Whether a My Meds pill reads as staged: it staged something, and all of
    /// it is still in the tray. A pill whose doses were partly removed by hand
    /// reads as unstaged, and its next tap stages what is missing.
    func isPillStaged(_ pillID: String) -> Bool {
        guard let contribution = pillContributions[pillID], !contribution.isEmpty else { return false }
        return contribution.allSatisfy { unit, count in stagedCount(of: unit) >= count }
    }

    /// One tap on a My Meds pill. A staged pill (``isPillStaged(_:)``) takes
    /// back exactly what it staged; otherwise it stages each of `meds` not
    /// already in the tray from any source — so two pills sharing a med never
    /// stage it twice — and records those units as its own.
    func togglePill(_ pillID: String, meds: [DailyMedSnapshot], colorLookup: [String: P3Color]) {
        if isPillStaged(pillID) {
            unstagePill(pillID)
        } else {
            stagePill(pillID, meds: meds, colorLookup: colorLookup)
        }
    }

    /// Stage the members of a pill that are missing from the tray, adding them
    /// to whatever of the pill's earlier contribution is still there.
    func stagePill(_ pillID: String, meds: [DailyMedSnapshot], colorLookup: [String: P3Color]) {
        var contribution = presentContribution(of: pillID)
        for med in meds {
            let units = Self.chipUnits(for: med)
            guard !units.keys.allSatisfy({ stagedCount(of: $0) > 0 }) else { continue }
            stage(dailyMed: med, colorLookup: colorLookup)
            for (unit, count) in units {
                contribution[unit, default: 0] += count
            }
        }
        pillContributions[pillID] = contribution.isEmpty ? nil : contribution
    }

    /// Take a pill's contribution back out: subtract each recorded unit from
    /// its chip, never past what the chip still holds, and drop rows left
    /// with nothing in them. Units staged by any other path are untouched.
    func unstagePill(_ pillID: String) {
        guard let contribution = pillContributions.removeValue(forKey: pillID) else { return }
        var removedAny = false
        for (unit, count) in contribution {
            guard let rowIndex = staged.firstIndex(where: { Self.matches($0, unit) }),
                  let componentIndex = staged[rowIndex].components.firstIndex(where: { Self.displayKey($0.amount) == unit.chip.amountKey })
            else { continue }
            let available = staged[rowIndex].components[componentIndex].count
            let removing = min(count, available)
            guard removing > 0 else { continue }
            removedAny = true
            if removing == available {
                staged[rowIndex].components.remove(at: componentIndex)
            } else {
                staged[rowIndex].components[componentIndex].count -= removing
            }
            if staged[rowIndex].components.isEmpty {
                expandedItemIDs.remove(staged[rowIndex].id)
                staged.remove(at: rowIndex)
            }
        }
        guard removedAny else { return }
        unstageTick += 1
        syncEmptiness()
    }

    /// The pill's recorded units, each capped at what the tray still holds.
    private func presentContribution(of pillID: String) -> [StagedChipUnit: Int] {
        (pillContributions[pillID] ?? [:]).reduce(into: [:]) { result, entry in
            let present = min(entry.value, stagedCount(of: entry.key))
            if present > 0 { result[entry.key] = present }
        }
    }

    /// Units staged on one chip, across every row carrying its identity.
    private func stagedCount(of unit: StagedChipUnit) -> Int {
        staged
            .filter { Self.matches($0, unit) }
            .flatMap(\.components)
            .filter { Self.displayKey($0.amount) == unit.chip.amountKey }
            .reduce(0) { $0 + $1.count }
    }

    private static func matches(_ dose: StagedDose, _ unit: StagedChipUnit) -> Bool {
        dose.identityKey == unit.identity && dose.route == unit.chip.route && dose.unit == unit.chip.unit
            && dose.combinationName == unit.combinationName
    }

    /// The chips ``stage(dailyMed:colorLookup:)`` files a med under, with how
    /// many units of each: one chip for a med of one substance (its resolved
    /// identity, route, unit and amount), one per component for a combination
    /// product — a count of its amount per unit for a solid, one chip of
    /// volume × amount per mL for a liquid.
    static func chipUnits(for med: DailyMedSnapshot) -> [StagedChipUnit: Int] {
        guard let product = CustomSubstanceStore.shared.combination(named: med.substance) else {
            let identity = stagedIdentity(
                substance: med.substance,
                productName: med.productName,
                librarySubstance: SubstanceLibrary.lookup(med.substance.lowercased()),
                route: med.route,
            )
            let chip = StagedChipKey(route: med.route, unit: med.unit, amountKey: displayKey(med.amount))
            return [StagedChipUnit(identity: identity, chip: chip): 1]
        }
        let isLiquid = product.isLiquidCombination
        let volume = CombinationComponent.volumeML(for: med.amount)
        let count = isLiquid ? 1 : CombinationComponent.units(for: med.amount)
        var units: [StagedChipUnit: Int] = [:]
        for component in product.components ?? [] {
            let library = SubstanceLibrary.lookup(component.substance)
            let identity = stagedIdentity(
                substance: library?.name ?? component.substance, productName: nil,
                librarySubstance: library, route: component.route,
            )
            let amount = isLiquid ? component.amount(inVolumeML: volume) : component.amountPerUnit
            let chip = StagedChipKey(route: component.route, unit: component.unit, amountKey: displayKey(amount))
            units[StagedChipUnit(identity: identity, chip: chip, combinationName: product.name), default: 0] += count
        }
        return units
    }

    /// Stage a chip. Same substance + route + unit + product merges into the
    /// existing row: re-staging the same amount increments its count ("took
    /// two pills"), a different amount joins as a new component ("a 150 and a
    /// 182") — always one entry of the summed total at commit, never two.
    /// `count` stages that many of the chip at once (two tablets of a
    /// combination). `combinationName` labels the row with the product it
    /// came from and is part of the merge key: a component never merges into
    /// another product's row or into a dose staged on its own, so each product
    /// keeps its own rows, quantity and logged entries.
    func stage(
        substance: String,
        route: RouteOfAdministration,
        amount: Double,
        unit: String,
        tint: P3Color?,
        librarySubstance: Substance?,
        productName: String? = nil,
        saltForm: String? = nil,
        isFromDailySet: Bool = false,
        isBackgroundMed: Bool = false,
        volumeML: Double? = nil,
        abv: Double? = nil,
        drinkName: String? = nil,
        emoji: String? = nil,
        count: Int = 1,
        combinationName: String? = nil,
    ) {
        let identity = Self.stagedIdentity(substance: substance, productName: productName, librarySubstance: librarySubstance, route: route, saltForm: saltForm)
        if let index = stagedIndex(identity: identity, route: route, unit: unit, combinationName: combinationName) {
            if let componentIndex = staged[index].components.firstIndex(where: { Self.sameAmount($0.amount, amount) }) {
                staged[index].components[componentIndex].count += count
            } else {
                staged[index].components.append(.init(amount: amount, count: count))
            }
            incrementTick += 1
        } else {
            var dose = StagedDose(
                substanceName: substance,
                amount: amount,
                unit: unit,
                route: route,
                saltForm: saltForm ?? librarySubstance?.saltForms(for: route).first,
                isomer: Self.seedIsomer(productName: productName, librarySubstance: librarySubstance, route: route),
                productName: productName,
                tint: tint,
                librarySubstance: librarySubstance,
                isFromDailySet: isFromDailySet,
                isBackgroundMed: isBackgroundMed,
            )
            dose.components = [.init(amount: amount, count: count)]
            dose.volumeML = volumeML
            dose.abv = abv
            dose.drinkName = drinkName
            dose.emoji = emoji
            dose.combinationName = combinationName
            staged.append(dose)
            stageTick += 1
            syncEmptiness()
        }
    }

    /// Stage a combination product: one chip per component, `quantity` units
    /// of each ("two co-codamol" is 2 × 500 mg paracetamol and 2 × 30 mg
    /// codeine), every row labeled with the product's name. Rows merge like any
    /// other chip, so picking the product again adds another unit to each. A
    /// component whose substance the library no longer knows stages under its
    /// raw name, as a custom substance does.
    ///
    /// A liquid product (``CustomSubstanceEntry/isLiquidCombination``) stages
    /// by volume instead: `quantity` is ignored and it takes
    /// ``CombinationComponent/defaultVolumeML``; see
    /// ``stage(combination:volumeML:colorLookup:)``.
    func stage(combination: CustomSubstanceEntry, quantity: Int = 1, colorLookup: [String: P3Color] = [:]) {
        if combination.isLiquidCombination {
            stage(combination: combination, volumeML: CombinationComponent.defaultVolumeML, colorLookup: colorLookup)
            return
        }
        guard quantity > 0 else { return }
        for component in combination.components ?? [] {
            let library = SubstanceLibrary.lookup(component.substance)
            let name = library?.name ?? component.substance
            stage(
                substance: name,
                route: component.route,
                amount: component.amountPerUnit,
                unit: component.unit,
                tint: SubstancePalette.tint(for: name, tintMap: colorLookup),
                librarySubstance: library,
                count: quantity,
                combinationName: combination.name,
            )
        }
    }

    /// Stage `volumeML` of a liquid combination product: one row per
    /// component, each at volume × its amount per mL in its own unit (0.25 mL
    /// of 2 g/mL morphine is 0.5 g). Each row records the volume and the
    /// per-mL amount (``StagedDose/volumeML`` / ``StagedDose/abv``), which the
    /// committed entries keep and the editor's volume field rescales from.
    /// Picking the product again adds its volume to each row. Rows merge only
    /// with this product's own rows, so a component that another product or a
    /// lone dose shares stays a row of its own.
    func stage(combination: CustomSubstanceEntry, volumeML: Double, colorLookup: [String: P3Color] = [:]) {
        guard volumeML.isFinite, volumeML > 0 else { return }
        let volume = min(volumeML, CombinationComponent.maximumVolumeML)
        for component in combination.components ?? [] {
            let library = SubstanceLibrary.lookup(component.substance)
            let name = library?.name ?? component.substance
            let amount = component.amount(inVolumeML: volume)
            let identity = Self.stagedIdentity(substance: name, productName: nil, librarySubstance: library, route: component.route)
            let existing = stagedIndex(identity: identity, route: component.route, unit: component.unit, combinationName: combination.name)
            let previous = existing.map { (volumeML: staged[$0].volumeML, perML: staged[$0].abv) }
            stage(
                substance: name,
                route: component.route,
                amount: amount,
                unit: component.unit,
                tint: SubstancePalette.tint(for: name, tintMap: colorLookup),
                librarySubstance: library,
                combinationName: combination.name,
            )
            guard let index = existing ?? staged.indices.last else { continue }
            let recordsVolume = Self.recordsCombinationVolume(component: component, library: library)
            if let previous {
                // Merged into this product's row: the volumes add only while
                // that row still records one at the same strength.
                if recordsVolume, let previousML = previous.volumeML, let perML = previous.perML,
                   Self.sameAmount(perML, component.amountPerUnit) {
                    staged[index].volumeML = previousML + volume
                } else {
                    staged[index].volumeML = nil
                    staged[index].abv = nil
                }
            } else if recordsVolume {
                staged[index].volumeML = volume
                staged[index].abv = component.amountPerUnit
            }
        }
    }

    /// Set the volume of a liquid combination already in the tray: every row
    /// staged from `combinationName` that records a volume is re-derived as
    /// `volumeML` × its amount per mL. The editor's volume field calls this,
    /// so one volume moves every component of the product together.
    func setVolume(_ volumeML: Double, ofCombination combinationName: String) {
        guard volumeML.isFinite, volumeML > 0 else { return }
        let volume = min(volumeML, CombinationComponent.maximumVolumeML)
        for index in staged.indices where staged[index].combinationName == combinationName {
            guard staged[index].isLiquidCombinationRow, let perML = staged[index].abv else { continue }
            staged[index].components = [.init(amount: ByVolumeDosing.mass(volumeML: volume, concentrationPerML: perML))]
            staged[index].volumeML = volume
            staged[index].isUnknownAmount = false
        }
    }

    /// Open a liquid combination's product row for editing, so its volume
    /// field is on screen the moment the product is picked: a liquid is staged
    /// at a placeholder 1 mL that the user is about to change. The tray draws
    /// the whole product on its lead row (``leadRowID(ofCombination:)``).
    func openVolume(ofCombination combinationName: String) {
        guard let lead = leadRowID(ofCombination: combinationName) else { return }
        openForEditing(lead)
    }

    // MARK: Combination products

    /// Stage `amount` of a combination product: a count of units for a solid
    /// product, a volume in mL for a liquid one.
    func stage(product: CustomSubstanceEntry, amount: Double, colorLookup: [String: P3Color] = [:]) {
        if product.isLiquidCombination {
            stage(combination: product, volumeML: CombinationComponent.volumeML(for: amount), colorLookup: colorLookup)
        } else {
            stage(combination: product, quantity: CombinationComponent.units(for: amount), colorLookup: colorLookup)
        }
    }

    /// The first row staged from `combinationName`. The tray draws the whole
    /// product, every component beneath one quantity control, on this row and
    /// skips the product's other rows.
    func leadRowID(ofCombination combinationName: String) -> UUID? {
        staged.first { $0.combinationName == combinationName }?.id
    }

    /// How much of a product is staged: units for a solid, read off the lead
    /// component's count at its amount per unit; mL for a liquid. `nil` when
    /// nothing of it is staged or its rows no longer say.
    func stagedQuantity(of product: CustomSubstanceEntry) -> Double? {
        guard let lead = staged.first(where: { $0.combinationName == product.name }) else { return nil }
        if product.isLiquidCombination { return lead.volumeML }
        guard let component = product.components?.first(where: {
            Self.stagedName(of: $0) == lead.substanceName && $0.unit == lead.unit
        }),
            let units = lead.components.first(where: { Self.sameAmount($0.amount, component.amountPerUnit) })?.count
        else { return nil }
        return Double(units)
    }

    /// Set how many units of a solid product are staged: each component's
    /// share of its row becomes `count` × its amount per unit, so one control
    /// moves every component together. Only this product's rows change.
    func setUnits(_ count: Int, of product: CustomSubstanceEntry) {
        let units = min(max(count, 1), CombinationComponent.maximumUnits)
        for component in product.components ?? [] {
            let name = Self.stagedName(of: component)
            for index in staged.indices where staged[index].combinationName == product.name
                && staged[index].substanceName == name && staged[index].unit == component.unit {
                if let share = staged[index].components.firstIndex(where: { Self.sameAmount($0.amount, component.amountPerUnit) }) {
                    staged[index].components[share].count = units
                } else {
                    staged[index].components.append(.init(amount: component.amountPerUnit, count: units))
                }
                staged[index].isUnknownAmount = false
            }
        }
        incrementTick += 1
    }

    /// Take a whole product out of the tray: every row staged from it.
    func removeCombination(_ combinationName: String) {
        let ids = Set(staged.filter { $0.combinationName == combinationName }.map(\.id))
        guard !ids.isEmpty else { return }
        staged.removeAll { ids.contains($0.id) }
        expandedItemIDs.subtract(ids)
        syncEmptiness()
    }

    /// The name a component stages under: the library's canonical name, or the
    /// raw name of a substance the library doesn't carry.
    static func stagedName(of component: CombinationComponent) -> String {
        SubstanceLibrary.lookup(component.substance)?.name ?? component.substance
    }

    /// Whether a liquid component's row may carry the volume on the by-volume
    /// fields. Those fields already mean something for a substance with its
    /// own by-volume input: alcohol reads `abv` as percent, so it never takes
    /// one, and an injectable ester reads it as concentration in its own unit,
    /// so it takes one only when the component is measured in that unit.
    static func recordsCombinationVolume(component: CombinationComponent, library: Substance?) -> Bool {
        guard let capability = library?.byVolumeDosing else { return true }
        return capability.isMassPerVolume && component.unit == capability.canonicalUnit
    }

    /// The isomer a staged dose should open on: the one its product names, else
    /// the route's default.
    ///
    /// A user who searched "Focalin" has already told us the enantiomer — opening
    /// the picker on racemic Methylphenidate would make them re-answer a question
    /// they answered by typing, and silently mis-classify the dose against the
    /// racemic ladder if they don't notice. Guarded on the option actually
    /// existing for this route, since the alias names a substance-wide fact while
    /// the ladder is per-route (methylphenidate has a D ladder on oral but not
    /// insufflation).
    static func seedIsomer(productName: String?, librarySubstance: Substance?, route: RouteOfAdministration) -> String? {
        guard let productName,
              let named = SubstanceLibrary.isomer(for: productName),
              let substance = librarySubstance,
              substance.isomerOptions(for: route).contains(where: { $0.code == named })
        else { return librarySubstance?.defaultIsomer(for: route) }
        return named
    }

    /// The substance-identity a freshly-staged dose will carry, from the same
    /// facet sources ``StagedDose/identityKey`` derives — so merge dedup keys on
    /// *form* identity, not the canonical name alone. Without this a Concerta
    /// (canonical Methylphenidate + `XR`) staged onto a plain Methylphenidate row
    /// matched by name and summed into it, doubling the dose (they are different
    /// forms and must stay separate rows).
    static func stagedIdentity(
        substance: String,
        productName: String?,
        librarySubstance: Substance?,
        route: RouteOfAdministration,
        saltForm: String? = nil,
    ) -> String {
        QuickLogDose.identityKey(
            substanceUID: librarySubstance?.substanceUID,
            substance: substance,
            isomer: seedIsomer(productName: productName, librarySubstance: librarySubstance, route: route),
            releaseForm: SubstanceLibrary.releaseForm(for: productName ?? substance),
            saltForm: saltForm ?? librarySubstance?.saltForms(for: route).first,
        )
    }

    /// Open a staged row for editing on the user's behalf: expands it and, with
    /// `focusesAmount`, asks the editor to focus the amount field (see
    /// ``StagedDose/wantsAmountFocus``).
    func openForEditing(_ id: UUID, focusesAmount: Bool = true) {
        if focusesAmount, let index = staged.firstIndex(where: { $0.id == id }) {
            staged[index].wantsAmountFocus = true
        }
        expandedItemIDs.insert(id)
    }

    /// Stage a draft (from search / the sliders pill) and open it for editing.
    /// Prefilled with the library's common dose when one is known. A draft for
    /// an already-staged substance opens that row instead of duplicating it.
    ///
    /// `focusesAmount` raises the keyboard on the amount field. Search keeps
    /// it on, since the dock is already full height there. The cards behind the
    /// dock pass `false`: the draft opens at the dock's half-height detent,
    /// and a keyboard there makes UIKit expand the sheet to full height, only
    /// to drop back to half the moment a −/+ tap puts the keyboard down. A
    /// draft with no seeded amount still focuses (the editor's own rule).
    func stageDraft(
        substance: String,
        route: RouteOfAdministration,
        unit: String,
        tint: P3Color?,
        librarySubstance: Substance?,
        productName: String? = nil,
        saltForm: String? = nil,
        focusesAmount: Bool = true,
    ) {
        // A by-volume substance (alcohol) must draft in its canonical unit —
        // the drink editor (By Volume / By Mass) gates on it, so a draft
        // arriving as "units" (a recent's chip unit) would silently lose the
        // whole volumetric logger.
        let unit = librarySubstance?.byVolumeDosing?.canonicalUnit ?? unit
        let identity = Self.stagedIdentity(substance: substance, productName: productName, librarySubstance: librarySubstance, route: route, saltForm: saltForm)
        if let index = stagedIndex(identity: identity, route: route, unit: unit, combinationName: nil) {
            openForEditing(staged[index].id, focusesAmount: focusesAmount)
            return
        }
        let saltForm = saltForm ?? librarySubstance?.saltForms(for: route).first
        // By-volume substances (alcohol, an injectable ester) start at zero: the
        // editor seeds the drink or vial from the substance's last by-volume
        // log, which is a better default than a reference dose in grams.
        let isByVolume = librarySubstance?.byVolumeDosing.map { unit == $0.canonicalUnit } ?? false
        let seedAmount = isByVolume
            ? 0
            : (librarySubstance?.referenceDose(route: route, unit: unit, saltForm: saltForm) ?? 0)
        var draft = StagedDose(
            substanceName: substance,
            amount: seedAmount,
            unit: unit,
            route: route,
            saltForm: saltForm,
            isomer: Self.seedIsomer(productName: productName, librarySubstance: librarySubstance, route: route),
            productName: productName,
            tint: tint,
            librarySubstance: librarySubstance,
        )
        draft.wantsAmountFocus = focusesAmount
        staged.append(draft)
        expandedItemIDs.insert(draft.id)
        stageTick += 1
        syncEmptiness()
    }

    func remove(_ item: StagedDose) {
        staged.removeAll { $0.id == item.id }
        expandedItemIDs.remove(item.id)
        syncEmptiness()
    }

    /// Staged rows merge on form *identity* + route + unit + product; the distinct amounts
    /// inside match on their *display* form — the user-perceived identity of
    /// a chip. Exact-double matching breaks when the editor round-trips an
    /// amount through its text field (31.700000000000003 → "31.7" → 31.7).
    ///
    /// Keying on ``StagedDose/identityKey`` — not the bare name — is what keeps a
    /// Concerta (Methylphenidate·XR) and a plain Methylphenidate row from merging
    /// and summing into one doubled dose.
    private func stagedIndex(identity: String, route: RouteOfAdministration, unit: String, combinationName: String?) -> Int? {
        staged.firstIndex {
            $0.identityKey == identity
                && $0.route == route
                && $0.unit == unit
                && $0.combinationName == combinationName
        }
    }
}
