import Foundation

/// The release forms a substance's dose ladder and duration profile describe.
///
/// Every ladder and duration the app carries is measured on the base form: the
/// unspecified product (the PSID `0` sentinel) or immediate release (`IR`),
/// which *is* the base form's kinetics. Every other code — `XR`, `DEP`, and any
/// future extended or delayed system — names a formulation none of those
/// numbers were written for.
enum BaseReleaseForm {
    /// Release-form codes the base ladder describes. `0` is compared literally
    /// rather than via `PSID.unspecifiedFacet`, which is main-actor isolated.
    nonisolated static let codes: Set<String> = ["0", "IR"]

    /// Whether `releaseForm` is one the base ladder describes. A missing or
    /// empty form is the unspecified product and counts.
    nonisolated static func contains(_ releaseForm: String?) -> Bool {
        guard let releaseForm, !releaseForm.isEmpty else { return true }
        return codes.contains(releaseForm.uppercased())
    }
}

/// The one classifier behind every dose tier the app shows: the entry detail
/// pill, the edit readout, journal rows, the quick-log picker and tray, and the
/// Insights tier breakdown.
extension Substance {
    /// The ladder a dose in this form is judged against, or `nil` when no ladder
    /// describes it.
    ///
    /// The route's ladder is narrowed to the salt and isomer, and exists only
    /// for a base release form (``BaseReleaseForm``). An extended-release
    /// product spreads its dose over the day: 36 mg of Concerta is a morning
    /// dose, and the immediate-release ladder would call it "strong". The app
    /// holds no ladder for those forms and authors none, since a prescription
    /// product's therapeutic range reads as dosing advice. So such a dose has
    /// no tier, exactly like a dose of unknown amount.
    func tierLadder(
        for route: RouteOfAdministration, saltForm: String?, isomer: String?, releaseForm: String?,
    ) -> DoseRange? {
        guard BaseReleaseForm.contains(releaseForm),
              let range = doseRange(for: route, saltForm: saltForm, isomer: isomer),
              range.hasAnyValue else { return nil }
        return range
    }

    /// Where `amount` of this substance sits on its ``tierLadder(for:saltForm:isomer:releaseForm:)``,
    /// converted to the ladder's unit first. `nil` when no ladder describes the dose.
    func doseLevel(
        of amount: Double, unit: String,
        route: RouteOfAdministration, saltForm: String?, isomer: String?, releaseForm: String?,
    ) -> DoseLevel? {
        guard let range = tierLadder(for: route, saltForm: saltForm, isomer: isomer, releaseForm: releaseForm) else {
            return nil
        }
        let ladderUnit = self.unit(for: route, saltForm: saltForm, isomer: isomer)
        let normalized = unit.caseInsensitiveCompare(ladderUnit) == .orderedSame
            ? amount
            : (convert(amount: amount, from: unit, toRoute: route, saltForm: saltForm) ?? amount)
        return range.level(for: normalized)
    }
}

extension DoseEntry {
    /// This dose's tier on `substance`'s ladder — `nil` for an unknown amount or
    /// a form no ladder describes. See ``Substance/tierLadder(for:saltForm:isomer:releaseForm:)``.
    @MainActor
    func doseLevel(on substance: Substance) -> DoseLevel? {
        guard !isUnknownDose else { return nil }
        return substance.doseLevel(
            of: amount, unit: unit,
            route: route, saltForm: saltForm, isomer: isomer, releaseForm: releaseForm,
        )
    }
}
