import Foundation

/// A cheap content fingerprint of the substance-color assignments, for
/// `task(id:)` tokens that must refresh on a recolor — color edits mutate
/// `hexColor` in place, so a `.count` key misses them, and they don't funnel
/// through ``DoseLogService`` (which covers only the dose log itself).
///
/// Dose-history refresh tokens use ``DoseLogService/revision`` instead:
/// hashing entries in `body` pays an O(history) scan per pass and subscribes
/// the view to every field of every dose.
enum ColorsFingerprint {
    static func make(_ colors: [SubstanceColor]) -> Int {
        var hasher = Hasher()
        for color in colors {
            hasher.combine(color.substance)
            hasher.combine(color.hexColor)
        }
        return hasher.finalize()
    }
}
