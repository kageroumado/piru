import Foundation

/// Depot PK parameters for one injectable hormone ester (Estradiol Cypionate,
/// Testosterone Enanthate, …), from the bundled `ester_pk` table.
///
/// Feeds the Injection Levels tool's three-compartment serum-level curve
/// (``PKModel/DepotParameters``). The amplitude `d` is a population value that the
/// tool then calibrates to the user's own lab results — the model predicts a
/// concentration from logged doses; it never recommends a dose or a level.
struct EsterPKRecord: Equatable, Identifiable, Sendable {
    /// Stable key, e.g. `"estradiol_cypionate"`.
    let esterID: String
    /// Analyte key: `"estradiol"` or `"testosterone"`.
    let analyte: String
    /// Canonical parent substance name (e.g. `"Estradiol"`).
    let parent: String
    /// PSID FAMILY of the parent, for matching a logged IM/SC dose to its ester.
    let parentUID: String?
    /// User-facing ester name (`"Cypionate"`, `"Enanthate"`, …).
    let label: String
    /// The depot rate constants + amplitude (rates per day), or `nil` for a
    /// catalog-only ester (e.g. Undecylate) that ships no validated curve — real
    /// and loggable, but the tool declines to draw it rather than guess one.
    let parameters: PKModel.DepotParameters?
    /// Provenance confidence: `"high"`, `"medium"`, `"low"`, or `"none"` (no curve).
    let confidence: String
    /// Attribution string shown on the tool's provenance card.
    let provenance: String
    /// Routes the parameters apply to (`["IM"]` or `["IM","SC"]`).
    let routes: [String]

    var id: String {
        esterID
    }

    /// Whether this ester carries a validated curve the tool can draw.
    var isModelable: Bool {
        parameters != nil
    }
}

extension SubstanceStore {
    /// Depot PK for one ester by its stable id, or `nil` when the bundled DB
    /// carries no such ester.
    func esterPK(forEsterID id: String) -> EsterPKRecord? {
        esterPKIndex[id]
    }

    /// Every **modelable** ester the DB carries for an analyte (`"estradiol"`),
    /// ester-id-ordered for a stable picker. The Injection Levels tool draws only
    /// these — a catalog-only ester (no curve) is excluded here so the tool never
    /// offers one it can't project. Empty when the analyte has no shipped curves.
    func estersForAnalyte(_ analyte: String) -> [EsterPKRecord] {
        esterPKIndex.values
            .filter { $0.analyte == analyte && $0.isModelable }
            .sorted { $0.esterID < $1.esterID }
    }

    /// The analytes that have any modelable ester PK data, alphabetized. The tool
    /// offers an analyte only when it can actually draw a curve for it.
    func analytesWithEsterData() -> [String] {
        Set(esterPKIndex.values.filter(\.isModelable).map(\.analyte)).sorted()
    }

    /// Every ester whose parent PSID FAMILY matches `uid` — modelable or not — how a
    /// logged Estradiol IM/SC/oral dose finds the esters it could be. Includes
    /// catalog-only esters (Undecylate) so they can be logged, titled, and searched
    /// even though the tool won't draw them.
    func esters(forParentUID uid: String) -> [EsterPKRecord] {
        esterPKIndex.values
            .filter { $0.parentUID == uid }
            .sorted { $0.esterID < $1.esterID }
    }

    /// Whether `label` names an injectable ester of the substance family `uid` —
    /// distinguishes an ester on `saltForm` ("Valerate") from a mineral salt so a
    /// title can fold in the ester ("Estradiol Valerate") without touching salts.
    func isEster(_ label: String?, forParentUID uid: String?) -> Bool {
        guard let label, !label.isEmpty, let uid else { return false }
        return esters(forParentUID: uid).contains { $0.label == label }
    }
}
