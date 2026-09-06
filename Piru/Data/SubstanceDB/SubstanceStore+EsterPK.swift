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
    /// The depot rate constants + amplitude (rates per day).
    let parameters: PKModel.DepotParameters
    /// Provenance confidence: `"high"`, `"medium"`, or `"low"`.
    let confidence: String
    /// Attribution string shown on the tool's provenance card.
    let provenance: String
    /// Routes the parameters apply to (`["IM"]` or `["IM","SC"]`).
    let routes: [String]

    var id: String {
        esterID
    }
}

extension SubstanceStore {
    /// Depot PK for one ester by its stable id, or `nil` when the bundled DB
    /// carries no such ester.
    func esterPK(forEsterID id: String) -> EsterPKRecord? {
        esterPKIndex[id]
    }

    /// Every ester the DB carries for an analyte (`"estradiol"`), ester-id-ordered
    /// for a stable picker. Empty when the analyte has no shipped parameters.
    func estersForAnalyte(_ analyte: String) -> [EsterPKRecord] {
        esterPKIndex.values
            .filter { $0.analyte == analyte }
            .sorted { $0.esterID < $1.esterID }
    }

    /// The analytes that have any shipped ester PK data, alphabetized. The tool
    /// offers an analyte only when it can actually draw a curve for it.
    func analytesWithEsterData() -> [String] {
        Set(esterPKIndex.values.map(\.analyte)).sorted()
    }

    /// The esters whose parent PSID FAMILY matches `uid` — how a logged Estradiol
    /// IM dose finds the esters it could be.
    func esters(forParentUID uid: String) -> [EsterPKRecord] {
        esterPKIndex.values
            .filter { $0.parentUID == uid }
            .sorted { $0.esterID < $1.esterID }
    }
}
