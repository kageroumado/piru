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
/// The robust pattern, implemented here: never trust a status for reads — just *attempt the query*.
/// A successful sample means access is live; an empty result means "no access OR no data" (we can't
/// tell which), which the UI surfaces with a re-request / "open Settings" affordance. `requestAndSync`
/// re-prompts only when status is undetermined (fresh install), and otherwise the caller can deep-link
/// to Settings so a user who revoked access can restore it. This is what makes the Settings button
/// keep working across revocation, reinstall, and new-device.
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

    private let logger = Logger(subsystem: "dev.yumeji.piru", category: "HealthKitBodyMass")
    @ObservationIgnored private let store = HKHealthStore()
    private var bodyMassType: HKQuantityType {
        HKQuantityType(.bodyMass)
    }

    /// Last sync outcome, for the Settings UI. Nil until the user tries.
    private(set) var lastResult: SyncResult?

    /// Whether HealthKit exists on this device at all (false on a device without Health, e.g. iPad).
    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private init() {}

    /// Request read access (prompts only when undetermined) and pull the latest body mass into
    /// ``UserProfileStore``. Safe to call repeatedly — it's how the Settings "Sync"/"Connect Health"
    /// button recovers after a revocation or reinstall.
    @discardableResult
    func requestAndSync() async -> SyncResult {
        guard isAvailable else {
            lastResult = .unavailable
            return .unavailable
        }
        do {
            try await store.requestAuthorization(toShare: [], read: [bodyMassType])
        } catch {
            // A thrown error here is a request failure, not a denial; we still try the read, since a
            // previously-granted permission keeps working even if this request can't re-prompt.
            logger.error("HealthKit authorization request failed: \(error.localizedDescription, privacy: .public)")
        }
        return await syncLatest()
    }

    /// Silently read the latest body mass without prompting. Use on launch/appear to keep a
    /// HealthKit-sourced weight fresh; never prompts, so it's safe to call unconditionally.
    @discardableResult
    func syncLatest() async -> SyncResult {
        guard isAvailable else {
            lastResult = .unavailable
            return .unavailable
        }
        let result: SyncResult
        if let kg = await latestBodyMassKg() {
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
        let logger = logger
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            // HealthKit runs this handler on its own serial queue, not the main actor — so it captures
            // only the Sendable `logger` and `continuation`, never `self`, keeping it off the actor.
            let query = HKSampleQuery(
                sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort],
            ) { _, samples, error in
                if let error {
                    logger.error("Body-mass query failed: \(error.localizedDescription, privacy: .public)")
                }
                let kg = (samples?.first as? HKQuantitySample)?
                    .quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: kg)
            }
            store.execute(query)
        }
    }
}
