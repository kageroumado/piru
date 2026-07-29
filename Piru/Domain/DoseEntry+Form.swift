import Foundation

/// The form facets a logged dose names, and what the app is willing to claim
/// about them. Lives in the app target (not `Shared/`) because it reads the
/// ``PSID`` facet vocabulary; the widgets render titles, never curves, so they
/// have no use for it.
extension DoseEntry {
    /// Whether this dose names a pharmaceutical form whose kinetics the app
    /// deliberately does not model — any release form other than the standard one.
    ///
    /// Extended-release, depot, and transdermal systems are either complicated
    /// (Concerta's OROS is zero-order ascending; Ritalin LA is bimodal beads;
    /// Jornay PM is delayed-onset overnight) or sensitive (opioid ER, depot
    /// antipsychotics), and no source we carry holds a duration for any of them.
    /// Authoring one would mean translating an FDA label's PK into our subjective
    /// phase ladder — our interpretation wearing the label's authority, on exactly
    /// the drugs where being wrong costs the most.
    ///
    /// So the app declines. It says *what* the dose was (``productName``) and
    /// *when* it was taken (a timestamp marker), and draws no curve — rather than
    /// answering with the base form's, which is what every fallback would
    /// otherwise do. See `Specs/psid-identity-consumption.md` LB-5.
    ///
    /// **`IR` does not count.** Immediate release *is* the base form's kinetics —
    /// that is what "immediate release" means, and the base ladder every source
    /// publishes is measured on it. Treating it as unmodeled meant "Adderall IR"
    /// drew no curve while a bare "Adderall" drew one, for the same dose of the
    /// same drug; a tester reported exactly that. A bare "Adderall"/"Ritalin" is
    /// the unspecified form — the PSID `0` sentinel — and likewise keeps its curve.
    ///
    /// `nonisolated` so the off-main timeline derive can ask without hopping; it
    /// reads only the entry's own stored string.
    nonisolated var namesUnmodeledForm: Bool {
        guard let releaseForm, !releaseForm.isEmpty else { return false }
        return !Self.modeledReleaseForms.contains(releaseForm.uppercased())
    }

    /// Release forms whose kinetics the base duration ladder already describes.
    ///
    /// `0` is the PSID unspecified sentinel (compared literally rather than via
    /// `PSID.unspecifiedFacet`, which is main-actor isolated). `IR` is immediate
    /// release. Everything else — `XR`, `DEP`, and any future extended/delayed
    /// system — stays unmodeled and renders as a timestamp marker.
    nonisolated static let modeledReleaseForms: Set<String> = ["0", "IR"]
}
