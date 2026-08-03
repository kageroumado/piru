import Foundation

/// Preparations whose pharmacology belongs to a molecule the library carries
/// separately.
///
/// A plant or a preparation has no Kᵢ. Cannabis is dosed in grams of flower and
/// logged as its own thing, which is the right identity for a *journal* — but
/// every receptor number ever measured "for cannabis" was measured on Δ9-THC.
/// Filing those rows under the preparation produces two failures at once:
///
/// 1. **A false attribution.** Cannabis shipped a CB1 Kᵢ of 40.7 nM and 25 %
///    intrinsic activity whose own note read "Original Felder/Showalter
///    measurement" — Felder 1995 and Showalter 1996 assayed THC. The citation
///    on those rows resolved to a *nursing-ethics bibliography*
///    (PMID 8632377), and nothing caught it because the checker only gates on a
///    confident wrong-substance match.
/// 2. **A duplicate on every comparison.** With THC's own efficacy value loaded,
///    the CB1 ladder drew one molecule twice — 25 % labelled Cannabis and 36.1 %
///    labelled THC, adjacent and nearly overlapping, reading as two compounds
///    that disagree.
///
/// So the preparation keeps its own entry for dose, duration, effects and
/// logging, and **borrows** its pharmacology. One molecule, one set of numbers,
/// named as what it is.
enum ActiveIngredient {
    /// Preparation → the molecule its pharmacology is actually measured on.
    /// Keyed lowercase; resolve through ``resolve(_:)`` rather than reading this.
    ///
    /// Deliberately short. An entry belongs here only when the preparation's
    /// psychoactivity is carried by **one** molecule that the library holds as
    /// its own substance. Ayahuasca does not qualify — its effect is the
    /// DMT × β-carboline MAOI interaction, so no single row could stand for it.
    private static let map: [String: String] = [
        "cannabis": "THC",
    ]

    /// The molecule to read pharmacology from, or `nil` when the substance
    /// speaks for itself (which is almost everything).
    static func resolve(_ substanceName: String) -> String? {
        map[substanceName.lowercased()]
    }

    /// The name to query pharmacology under — the active ingredient when there
    /// is one, otherwise the substance itself. The single call every
    /// pharmacology read should go through.
    static func pharmacologyName(for substanceName: String) -> String {
        resolve(substanceName) ?? substanceName
    }
}
