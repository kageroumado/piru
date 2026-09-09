import Foundation
import SwiftData

/// Skips a launch-time pass over the dose log when the store cannot have
/// changed since that pass last ran. The token is the app build, the
/// persistent store generation (``DoseLogService/storeGeneration``), and the
/// dose count (widget writes cannot bump the generation); a pass that ran
/// under the current token found everything it looks for already handled,
/// so the full-log fetch it would open with is skipped. Every pass keeps its
/// own idempotent body, so a stale or missing token only costs the scan.
///
/// The same gate serves a foreground re-activation: the token is read fresh
/// each time (one `COUNT` query), so a dose logged from the widget while the
/// app was away changes it and the pass runs again.
@MainActor
enum LaunchPassGate {
    static func token(container: ModelContainer) -> String {
        let count = (try? container.mainContext.fetchCount(FetchDescriptor<DoseEntry>())) ?? -1
        return "\(LaunchCacheInputs.appBuild)|\(DoseLogService.storeGeneration)|\(count)"
    }

    /// Run `pass` unless it already ran under this launch's token, and record
    /// the token once it has.
    static func run(_ name: String, container: ModelContainer, defaults: UserDefaults = .standard, pass: () -> Void) {
        let key = "launchPass.\(name).token"
        let token = token(container: container)
        guard defaults.string(forKey: key) != token else { return }
        pass()
        defaults.set(token, forKey: key)
    }
}
