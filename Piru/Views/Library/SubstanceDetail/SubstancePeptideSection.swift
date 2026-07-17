import SwiftUI

/// Peptide / protocol-dosed compounds: clinical-protocol schedule,
/// reconstitution calculator, and handling/storage — surfaced in place of the
/// (suppressed) trip-intensity ladder and duration timeline. The per-route
/// protocol cards and the peptide handling cards live in `PeptideDetailSections`.
struct SubstancePeptideSection: View {
    let substance: Substance

    var body: some View {
        ForEach(substance.routes, id: \.route) { substanceRoute in
            if let pd = substanceRoute.protocolDosing {
                Section("Protocol — \(String(localized: substanceRoute.route.localizedName))") {
                    ProtocolDosingCard(unit: substanceRoute.unit, protocolDosing: pd)
                }
            }
        }

        if let pp = substance.peptideProfile {
            if pp.suppliedForm?.isReconstituted == true {
                Section("Reconstitution calculator") {
                    ReconstitutionCalculatorView(defaultVialMg: pp.typicalVialMg)
                }
            }
            if pp.hasAnyValue {
                Section("Handling & storage") {
                    PeptideHandlingCard(profile: pp, molarMass: substance.molarMass)
                    if let solvent = pp.reconstitutionSolvent {
                        LabeledContent("Reconstitute with") { Text(solvent) }
                            .font(.subheadline)
                    }
                }
            }
        }
    }
}
