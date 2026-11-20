import Foundation

extension PKResolver {
    /// The absorption rate `ka` for a substance named by the caller, fitted to its
    /// oral profile's time-to-peak (onset + come-up midpoints) through
    /// ``PKModel/estimateKa(timeToPeak:ke:)``. Falls back to
    /// ``PKModel/defaultKa(ke:)`` when the substance does not resolve, has no oral
    /// profile, or its profile has no time-to-peak.
    static func ka(forSubstance substanceName: String, ke: Double) -> Double {
        if let substance = SubstanceLibrary.lookup(substanceName.lowercased()),
           let duration = substance.resolveDuration(for: .oral) {
            let timeToPeak = (duration.onset?.midpoint ?? 0) + (duration.comeup?.midpoint ?? 0)
            if timeToPeak > 0 {
                return PKModel.estimateKa(timeToPeak: timeToPeak, ke: ke)
            }
        }
        return PKModel.defaultKa(ke: ke)
    }
}
