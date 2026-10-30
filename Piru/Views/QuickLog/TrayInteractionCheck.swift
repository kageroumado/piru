import Foundation
import SwiftData

/// The interactions the quick-log tray states before Log is pressed.
///
/// Two kinds of pair, held to different floors. Doses staged together are
/// co-administered, so any pair among them at ``InteractionProminence/notable``
/// or above is stated. A staged dose against one already in the body is stated
/// only when it is `dangerous`: the tray is a place to record, the journal is
/// the place to review, and a logged dose is out of sight here — so that row
/// names the dose it means (``InteractionCounterpart/trayLine``).
///
/// The gate itself is the checker's ``InteractionPolicy/warn``: a pair whose
/// curves never meet, or with a confidently trivial dose on either side, is
/// gone before either floor is applied.
enum TrayInteractionCheck {
    /// How long before the filed time a logged dose is read at all. The same
    /// window the daily-dose log checks against; ``InteractionChecker/activeEntries(from:at:)``
    /// then keeps only what is still running.
    static let lookback: TimeInterval = 48 * 3_600

    /// - Parameters:
    ///   - names: The staged doses' substance names.
    ///   - history: Logged doses, in any order; only those in ``lookback``
    ///     before `time` are read.
    ///   - time: When the staged doses are being filed — the When chip, so a
    ///     backdated dose meets what was running then.
    static func warnings(staged names: [String], history: [DoseEntry], at time: Date) -> [InteractionResult] {
        guard !names.isEmpty else { return [] }
        let earliest = time.addingTimeInterval(-lookback)
        let window = history.filter { !$0.isDeleted && $0.timestamp >= earliest }
        let active = InteractionChecker.activeEntries(from: window, at: time)
        guard names.count >= 2 || !active.isEmpty else { return [] }

        let stagedNames = Set(names.map { $0.lowercased() })
        return InteractionChecker.checkBatch(names, against: active, policy: .warn, at: time).filter { result in
            let isStagedPair = stagedNames.contains(result.substanceA.lowercased())
                && stagedNames.contains(result.substanceB.lowercased())
            if isStagedPair { return result.prominence >= .notable }
            return result.counterpart != nil && result.severity == .dangerous
        }
    }
}

extension InteractionCounterpart {
    /// The logged dose a tray warning is about, as one line: "with Alcohol
    /// 20 g · 1h ago". Elapsed time is counted to now, like the When chip.
    var trayLine: String {
        let ago = Date.now.timeIntervalSince(timestamp).durationHM
        guard !isUnknownAmount else {
            return String(localized: "with \(title) · \(ago) ago")
        }
        let dose = "\(amount.doseFormatted) \(unit.unitDisplay(for: amount))"
        return String(localized: "with \(title) \(dose) · \(ago) ago")
    }
}
