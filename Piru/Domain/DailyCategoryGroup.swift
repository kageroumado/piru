import Foundation

// MARK: - Daily routine grouping

/// "Prescriptions" reconceived: pre-set daily drugs (meds, supplements,
/// anything routine) as first-class cards whose item-chips stage into the
/// same tray as everything else. Holds value snapshots only — see
/// ``DailyMedSnapshot``.
struct DailyCategoryGroup: Identifiable {
    let id: String
    let title: String
    let icon: String
    let items: [DailyMedSnapshot]
    let remaining: [DailyMedSnapshot]
    /// The members whose earliest uncovered slot has opened *in this group* —
    /// a med at 8:00 and 20:00 is due on the Morning pill in the morning and
    /// never on Evening's until its second slot opens. Empty for PRN meds.
    let due: [DueNowSlot]

    var isDue: Bool {
        !due.isEmpty
    }

    /// The earliest open slot, as minutes from midnight; `nil` when only
    /// anytime meds are due.
    var dueSlotMinutes: Int? {
        due.compactMap(\.slotMinutes).min()
    }
}

/// One uncovered med slot that is due right now — the "what should I take
/// *now*?" answer behind a My Meds pill's due
/// state and the tab-bar accessory badge. Derived per (med × earliest
/// uncovered slot); a med never has more than one. Carries a
/// ``DailyMedSnapshot`` because the My Meds pills cache these.
struct DueNowSlot: Identifiable {
    /// `identityKey|slot` — stable across rebuilds.
    let id: String
    let item: DailyMedSnapshot
    /// Minutes from midnight, or `nil` for an "anytime" med (due all day).
    let slotMinutes: Int?

    /// How far ahead of a slot's set time it starts counting as "due now".
    static let dueSoonLeadMinutes = 60
}
