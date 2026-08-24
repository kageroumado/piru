import Foundation

/// Shared durations for small UI choreography, so the same gesture never
/// carries three different timings across screens.
enum UITiming {
    /// How long a "Copied" confirmation shows before reverting.
    static let copiedFlash: Duration = .seconds(1.6)

    /// How long a UIKit popover/sheet teardown needs before a follow-up
    /// present reliably lands — an immediate present races the dismissal
    /// (the root is still "presenting") and gets silently dropped. The value
    /// is a timing guess by necessity: UIKit offers no completion signal for
    /// another presentation's teardown, so this stays generous rather than
    /// minimal.
    static let presentationTeardown: Duration = .milliseconds(450)
}
