import Foundation

/// One hand-curated reference dose for a known substance. Used by
/// `GroundTruthCheck` to flag library values that disagree with published
/// pharmacology by more than `tolerancePercent`.
struct GroundTruthEntry {
    /// Lowercased substance name or alias to match against.
    let name: String
    /// Route this entry applies to (matches `RouteOfAdministration.rawValue`).
    let route: String
    /// Unit the expected dose is denominated in.
    let unit: String
    /// Expected `heavy` dose value, in `unit`.
    let expectedHeavy: Double
    /// Acceptable deviation as a fraction (`0.5` = ±50%).
    let tolerancePercent: Double
    /// Citation for the expected value, surfaced in the report.
    let source: String
}

/// Hand-curated reference doses used to spot-check the library against
/// well-known pharmacology. Each entry is tagged with its provenance so the
/// audit report can show *why* a particular bound exists.
enum GroundTruth {
    static let entries: [GroundTruthEntry] = [
        GroundTruthEntry(name: "alcohol", route: "oral", unit: "g",
                         expectedHeavy: 60, tolerancePercent: 0.5,
                         source: "NIAAA — heavy session ~4 drinks × 14 g ethanol"),
        GroundTruthEntry(name: "caffeine", route: "oral", unit: "mg",
                         expectedHeavy: 500, tolerancePercent: 0.5,
                         source: "FDA — daily safe maximum"),
        GroundTruthEntry(name: "bupropion", route: "oral", unit: "mg",
                         expectedHeavy: 450, tolerancePercent: 0.3,
                         source: "FDA labeling — Wellbutrin XL max 450 mg/day"),
        GroundTruthEntry(name: "ibuprofen", route: "oral", unit: "mg",
                         expectedHeavy: 800, tolerancePercent: 0.3,
                         source: "FDA labeling — single-dose Rx maximum"),
        GroundTruthEntry(name: "paracetamol", route: "oral", unit: "mg",
                         expectedHeavy: 1000, tolerancePercent: 0.3,
                         source: "FDA labeling — single-dose maximum"),
        GroundTruthEntry(name: "melatonin", route: "oral", unit: "mg",
                         expectedHeavy: 10, tolerancePercent: 1.0,
                         source: "AASM clinical guidelines"),
        GroundTruthEntry(name: "sertraline", route: "oral", unit: "mg",
                         expectedHeavy: 200, tolerancePercent: 0.3,
                         source: "FDA labeling — Zoloft max 200 mg/day"),
        GroundTruthEntry(name: "lisinopril", route: "oral", unit: "mg",
                         expectedHeavy: 40, tolerancePercent: 0.5,
                         source: "FDA labeling — Prinivil max 40 mg/day"),
        GroundTruthEntry(name: "metformin", route: "oral", unit: "mg",
                         expectedHeavy: 2000, tolerancePercent: 0.3,
                         source: "FDA labeling — max 2550 mg/day"),
        GroundTruthEntry(name: "vitamin d3", route: "oral", unit: "IU",
                         expectedHeavy: 10000, tolerancePercent: 0.5,
                         source: "Endocrine Society — daily upper intake"),
        GroundTruthEntry(name: "levothyroxine", route: "oral", unit: "µg",
                         expectedHeavy: 300, tolerancePercent: 0.5,
                         source: "FDA labeling — typical max replacement dose"),
        GroundTruthEntry(name: "diphenhydramine", route: "oral", unit: "mg",
                         expectedHeavy: 100, tolerancePercent: 0.5,
                         source: "OTC labeling — max single 50 mg, deliriant ~300 mg"),
        GroundTruthEntry(name: "modafinil", route: "oral", unit: "mg",
                         expectedHeavy: 400, tolerancePercent: 0.5,
                         source: "FDA labeling — Provigil max 400 mg/day"),
        GroundTruthEntry(name: "armodafinil", route: "oral", unit: "mg",
                         expectedHeavy: 250, tolerancePercent: 0.5,
                         source: "FDA labeling — Nuvigil max 250 mg/day"),
        GroundTruthEntry(name: "adderall", route: "oral", unit: "mg",
                         expectedHeavy: 30, tolerancePercent: 0.5,
                         source: "FDA labeling — typical ADHD daily max"),
        GroundTruthEntry(name: "methylphenidate", route: "oral", unit: "mg",
                         expectedHeavy: 80, tolerancePercent: 0.5,
                         source: "FDA labeling — Concerta max 72 mg/day"),
        GroundTruthEntry(name: "ketamine", route: "insufflation", unit: "mg",
                         expectedHeavy: 200, tolerancePercent: 0.5,
                         source: "PsychonautWiki — heavy insufflated dose"),
        GroundTruthEntry(name: "ketamine", route: "oral", unit: "mg",
                         expectedHeavy: 400, tolerancePercent: 0.5,
                         source: "PsychonautWiki — heavy oral dose"),
        GroundTruthEntry(name: "mdma", route: "oral", unit: "mg",
                         expectedHeavy: 200, tolerancePercent: 0.3,
                         source: "PsychonautWiki / TripSit — heavy oral"),
        GroundTruthEntry(name: "lsd", route: "oral", unit: "µg",
                         expectedHeavy: 400, tolerancePercent: 0.5,
                         source: "PsychonautWiki — heavy oral"),
        GroundTruthEntry(name: "psilocin", route: "oral", unit: "mg",
                         expectedHeavy: 25, tolerancePercent: 0.5,
                         source: "PsychonautWiki — heavy oral"),
        GroundTruthEntry(name: "cannabis", route: "inhalation", unit: "mg",
                         expectedHeavy: 10, tolerancePercent: 1.0,
                         source: "PsychonautWiki — heavy inhaled THC"),
        GroundTruthEntry(name: "nicotine", route: "oral", unit: "mg",
                         expectedHeavy: 10, tolerancePercent: 0.5,
                         source: "PsychonautWiki — heavy oral nicotine"),
        GroundTruthEntry(name: "diazepam", route: "oral", unit: "mg",
                         expectedHeavy: 30, tolerancePercent: 0.5,
                         source: "PsychonautWiki — heavy oral"),
        GroundTruthEntry(name: "alprazolam", route: "oral", unit: "mg",
                         expectedHeavy: 4, tolerancePercent: 0.5,
                         source: "FDA labeling — Xanax max 4 mg/day for panic"),
        GroundTruthEntry(name: "codeine", route: "oral", unit: "mg",
                         expectedHeavy: 240, tolerancePercent: 0.5,
                         source: "TripSit — heavy oral"),
        GroundTruthEntry(name: "tramadol", route: "oral", unit: "mg",
                         expectedHeavy: 400, tolerancePercent: 0.5,
                         source: "FDA labeling — max 400 mg/day"),
        GroundTruthEntry(name: "oxycodone", route: "oral", unit: "mg",
                         expectedHeavy: 60, tolerancePercent: 0.5,
                         source: "TripSit / PsychonautWiki — heavy opioid-naive"),
        GroundTruthEntry(name: "dxm", route: "oral", unit: "mg",
                         expectedHeavy: 700, tolerancePercent: 0.3,
                         source: "DXM dosing FAQ — fourth-plateau threshold"),
        GroundTruthEntry(name: "gbl", route: "oral", unit: "g",
                         expectedHeavy: 4, tolerancePercent: 0.5,
                         source: "PsychonautWiki — heavy oral GBL"),
    ]
}
