import Foundation

/// `<=` and `>=` on `Date`, defined in this module so they shadow Foundation's.
///
/// Never delete these, and keep this file in every target that compares dates (the app, both
/// extensions, and the watch app and PiruTests through `Shared` membership exceptions; a module that
/// `@testable import`s Piru without its own copy sees two `<=` and fails to type-check). The 27.2 SDKs declare
/// Foundation's `Date.<=` and `Date.>=` `@backDeployed(before: iOS 27.2, …)`, so a call to them
/// weak-imports Foundation's symbol and jumps to it on any OS that reports 27.2. Early 27.2 betas
/// report 27.2 without exporting the symbol, and the app crashes at the first comparison. A
/// declaration in the current module shadows the imported one with the same signature, so every
/// `date <= other` in these targets resolves here and the binary imports nothing.
/// `pipeline/check-weak-imports.py` fails a build that weak-imports either symbol again.
///
/// The bodies are Foundation's own, so results are identical, NaN intervals included.
nonisolated extension Date {
    static func <= (lhs: Date, rhs: Date) -> Bool {
        lhs.isOnOrBefore(rhs)
    }

    static func >= (lhs: Date, rhs: Date) -> Bool {
        lhs.isOnOrAfter(rhs)
    }

    /// Whether this date is earlier than or the same instant as `other`.
    func isOnOrBefore(_ other: Date) -> Bool {
        timeIntervalSinceReferenceDate <= other.timeIntervalSinceReferenceDate
    }

    /// Whether this date is later than or the same instant as `other`.
    func isOnOrAfter(_ other: Date) -> Bool {
        timeIntervalSinceReferenceDate >= other.timeIntervalSinceReferenceDate
    }
}
