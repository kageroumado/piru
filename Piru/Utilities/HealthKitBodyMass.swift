import Foundation
import HealthKit
import os

/// Reads the user's body mass from HealthKit (read-only) and pushes it into ``UserProfileStore``.
///
/// **The read-permission gotcha this is built around:** iOS deliberately never tells an app whether
/// its *read* access to a type is granted or was revoked (revealing that would leak whether the data
/// exists). `HKHealthStore.authorizationStatus(for:)` reports only *share/write* status. So we cannot
/// observe a revocation — the user can turn Piru off in Settings ▸ Health and we'd never be notified,
/// and on a reinstall / new device our stored weight is gone with no signal.
///
/// So reads never trust a status: ``syncLatest()`` attempts the query. A sample means access is live;
/// an empty result means no access or no data (we can't tell which), which the UI surfaces with an
/// "open Settings" affordance. Body-weight authorization is requested only through the combined Health
/// prompt in ``HealthKitVitals/requestFullAccess()``, so a user always sees one Health sheet.
@MainActor
@Observable
final class HealthKitBodyMass {
    static let shared = HealthKitBodyMass()

    /// Outcome of a sync attempt, kept observable so the Settings row can reflect the last result.
    enum SyncResult: Equatable {
        case updated(kg: Double)
        /// Query returned nothing — either access is off or Health has no body-mass sample. We can't
        /// distinguish the two for reads, so the UI offers "check access in Settings".
        case noData
        case unavailable
    }

    @ObservationIgnored private let store = HKHealthStore()
    private var bodyMassType: HKQuantityType {
        HKQuantityType(.bodyMass)
    }

    /// Last sync outcome, for the Settings UI. Nil until the user tries.
    private(set) var lastResult: SyncResult?

    /// Whether HealthKit exists on this device at all (false on a device without Health, e.g. iPad),
    /// and the open journal is the device owner's: Health's body mass is the owner's.
    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable() && ProfileScope.isOwner
    }

    private init() {}

    /// Silently read the latest body mass without prompting. Use on launch/appear to keep a
    /// HealthKit-sourced weight fresh; never prompts, so it's safe to call unconditionally.
    @discardableResult
    func syncLatest() async -> SyncResult {
        guard isAvailable else {
            lastResult = .unavailable
            return .unavailable
        }
        let generation = JournalResetGeneration.current()
        let result: SyncResult
        if let kg = await latestBodyMassKg() {
            guard generation == JournalResetGeneration.current() else { return .noData }
            UserProfileStore.shared.setHealthKitWeight(kg)
            result = .updated(kg: kg)
        } else {
            result = .noData
        }
        lastResult = result
        return result
    }

    /// Most-recent body-mass sample in kilograms, or nil if none is readable (no access, no data, or
    /// an error). A read with access denied returns an empty result, not an error — that's why nil
    /// means "no access OR no data" and is treated as a soft, recoverable state by the UI.
    private func latestBodyMassKg() async -> Double? {
        let type = bodyMassType
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            // HealthKit runs this handler on its own serial queue, not the main actor — so it captures
            // only the Sendable `continuation`, never `self`, keeping it off the actor.
            let query = HKSampleQuery(
                sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort],
            ) { _, samples, error in
                if let error {
                    Logger.healthKitBodyMass.error("Body-mass query failed: \(error.localizedDescription, privacy: .public)")
                }
                let kg = (samples?.first as? HKQuantitySample)?
                    .quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: kg)
            }
            store.execute(query)
        }
    }
}
