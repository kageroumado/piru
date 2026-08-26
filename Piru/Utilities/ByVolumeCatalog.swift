import Foundation
import os

/// The by-volume dose-input capabilities from the bundled DB's `by_volume_dosing`
/// and `drink_presets` — which substances are measured as a concentration applied
/// to a volume, the density that converts it, and the tappable presets.
///
/// Loaded once by ``SubstanceStore`` at index build and held in a lock-guarded
/// static rather than queried per call, because its caller — ``Substance/byVolumeDosing``
/// — is a computed property on a value type with no store reference, read from view
/// bodies while a list scrolls. Before the load lands ``capability(forAnyOf:)``
/// returns `nil`, which is exactly the state of a substance that has no row: the
/// dose form shows its plain mass field.
nonisolated enum ByVolumeCatalog {
    /// Keyed by lowercased canonical name **and** by every alias, so a dose logged
    /// as "Ethanol" finds the row written against "Alcohol".
    private static let table = OSAllocatedUnfairLock<[String: ByVolumeDosing]>(initialState: [:])

    /// Install the capabilities read from `by_volume_dosing`. Called once per store init.
    static func load(_ capabilities: [String: ByVolumeDosing]) {
        table.withLock { $0 = capabilities }
    }

    /// The capability for the first of `names` that names a by-volume substance —
    /// pass a canonical name followed by its aliases, in any casing.
    static func capability(forAnyOf names: [String]) -> ByVolumeDosing? {
        table.withLock { loaded in
            for name in names {
                if let capability = loaded[name.lowercased()] { return capability }
            }
            return nil
        }
    }
}
