import Foundation
import Observation

/// The device's power posture, for the decoration layer's frame cadence:
/// Low Power Mode halves the scene's frame rate, and a serious thermal state
/// stops it. Both are the user's or the system's explicit request to spend
/// less, and an animated wallpaper is the first thing that should comply.
@Observable
@MainActor
final class SkinPower {
    static let shared = SkinPower()

    private(set) var isLowPower: Bool
    /// The thermal state is `.serious` or `.critical`.
    private(set) var isThermallyConstrained: Bool

    private init() {
        let info = ProcessInfo.processInfo
        isLowPower = info.isLowPowerModeEnabled
        isThermallyConstrained = Self.constrained(info.thermalState)
        let center = NotificationCenter.default
        center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SkinPower.shared.isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        }
        center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                SkinPower.shared.isThermallyConstrained = Self.constrained(ProcessInfo.processInfo.thermalState)
            }
        }
    }

    nonisolated static func constrained(_ state: ProcessInfo.ThermalState) -> Bool {
        state == .serious || state == .critical
    }
}
