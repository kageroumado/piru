import Foundation

/// A substance whose primary (first-listed or sole) metabolic pathway is CYP2D6, and whether that
/// metabolism creates a qualitatively different drug (prodrug pattern) or just clears the parent.
nonisolated struct CYP2D6Info: Equatable {
    /// The CYP2D6 step produces a divergent metabolite — the parent is a prodrug and the
    /// metabolite is the active species (codeine→morphine, tramadol→M1). When true the note says
    /// CYP2D6 activates the substance; when false, that it clears it.
    let hasProdrugPattern: Bool

    static func from(metabolismRows rows: [SubstanceStore.MetabolismHit]) -> CYP2D6Info? {
        let cyp2d6Rows = rows.filter { isCYP2D6Primary($0.enzyme) }
        guard !cyp2d6Rows.isEmpty else { return nil }
        // A CYP2D6 step is a prodrug pattern when the metabolite is active AND
        // either divergent-mechanism OR ≥5× more potent than the parent. The
        // potency gate catches codeine→morphine (scaled, 200×) and
        // oxycodone→oxymorphone (scaled, 10–40×), where the parent is a weak
        // opioid and the metabolite is the real drug.
        let hasProdrugPattern = cyp2d6Rows.contains { row in
            row.metaboliteActive == true
                && (row.metaboliteMechanismVsParent == .divergent
                    || (row.metabolitePotencyVsParentPct ?? 100) >= 500)
        }
        return CYP2D6Info(hasProdrugPattern: hasProdrugPattern)
    }

    /// CYP2D6 is a primary pathway when it appears at the leading position of the
    /// freeform enzyme string — "CYP2D6", "CYP2D6 (major)", "CYP2D6 / CYP3A4".
    /// A string like "CYP3A4 / CYP2D6" lists it as a minor contributor.
    static func isCYP2D6Primary(_ enzyme: String) -> Bool {
        let trimmed = enzyme.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("CYP2D6")
    }
}
