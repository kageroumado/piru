import Foundation
import HealthKit
import os

/// Reads heart rate and blood pressure from HealthKit (read-only) for a session's time window.
///
/// Mirrors ``HealthKitBodyMass`` and the same read-permission gotcha: iOS never reports whether an
/// app's *read* access to a type is granted (that would leak whether the data exists), so we never
/// trust a status — we just attempt the query. An empty result means "no access OR no data", which
/// callers treat as a soft, recoverable state and render as **nothing** on screen.
@MainActor
@Observable
final class HealthKitVitals {
    static let shared = HealthKitVitals()

    private let logger = Logger(subsystem: "dev.yumeji.piru", category: "HealthKitVitals")
    @ObservationIgnored private let store = HKHealthStore()

    private var heartRateType: HKQuantityType {
        HKQuantityType(.heartRate)
    }
    private var restingHeartRateType: HKQuantityType {
        HKQuantityType(.restingHeartRate)
    }
    private var systolicType: HKQuantityType {
        HKQuantityType(.bloodPressureSystolic)
    }
    private var diastolicType: HKQuantityType {
        HKQuantityType(.bloodPressureDiastolic)
    }
    private var bloodPressureType: HKCorrelationType {
        HKCorrelationType(.bloodPressure)
    }

    /// Whether HealthKit exists on this device at all (false on iPad, etc.).
    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private init() {}

    /// The read set every request/status check uses. Blood pressure is requested
    /// via its two **component** quantity types (systolic + diastolic), never the
    /// correlation type: HealthKit aborts with "Authorization to read the
    /// following types is disallowed: HKCorrelationTypeIdentifierBloodPressure"
    /// if a correlation type is put in a read-authorization request. The
    /// permission sheet still groups the two components under one "Blood Pressure"
    /// row, and the correlation type is only used to build the query.
    private var readTypes: Set<HKObjectType> {
        [heartRateType, restingHeartRateType, systolicType, diastolicType]
    }

    /// Request read access to the whole Health integration — body weight, heart
    /// rate, and blood pressure — in a **single** system prompt. This is the only
    /// authorization entry point: every opt-in surface (onboarding, the Apple
    /// Health settings screen, the session discovery banner) calls it, so the user
    /// only ever sees one combined Health sheet listing all three, never a
    /// weight-only or vitals-only prompt. Prompts only for still-undetermined types;
    /// a thrown error is a request failure (not a denial), so already-granted access
    /// keeps working. No-op when HealthKit is unavailable.
    func requestFullAccess() async {
        guard isAvailable else { return }
        let read = readTypes.union([HKQuantityType(.bodyMass)])
        let store = store
        let logger = logger
        // HealthKit validates the request *synchronously* and raises an ObjC
        // `NSException` (not a Swift error) when it's unhappy — a device-specific
        // failure mode a `try`/`catch` can't reach, so it would terminate the app
        // (see the b28–30 TestFlight crashes). Drive the completion-based API and
        // wrap the throwing synchronous call in the ObjC catcher; a raised
        // exception degrades to "access not granted" instead of a crash.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var thrown: NSError?
            let started = PiruCatchNSException({
                store.requestAuthorization(toShare: [], read: read) { _, error in
                    if let error {
                        logger.error("Combined authorization request failed: \(error.localizedDescription, privacy: .public)")
                    }
                    continuation.resume()
                }
            }, &thrown)
            if !started {
                logger.error("HealthKit authorization raised an exception: \(thrown?.localizedDescription ?? "unknown", privacy: .public)")
                continuation.resume()
            }
        }
    }

    /// Whether tapping "Connect" would actually surface a prompt — i.e. weight,
    /// heart rate, or resting heart rate is still undetermined. Once the user has
    /// answered them all, requesting only flashes an empty sheet that immediately
    /// dismisses, so callers hide the Connect affordance when this returns false.
    ///
    /// **Blood pressure is deliberately excluded from this check.** On iOS 26.5 its
    /// read status is stuck at `.shouldRequest` forever (FB22735935), which would
    /// keep Connect visible permanently even after everything grantable is granted;
    /// BP recovery is handled by the Settings ▸ Privacy ▸ Health guidance instead.
    func connectWouldPrompt() async -> Bool {
        guard isAvailable else { return false }
        let store = store
        let logger = logger
        let promptable: Set<HKObjectType> = [heartRateType, restingHeartRateType, HKQuantityType(.bodyMass)]
        // Same synchronous-`NSException` hazard as `requestFullAccess()` — this is
        // what crashed on merely opening Settings ▸ Apple Health. Treat a raised
        // exception as "nothing to prompt for" so the Connect affordance just hides.
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            var thrown: NSError?
            let started = PiruCatchNSException({
                store.getRequestStatusForAuthorization(toShare: [], read: promptable) { status, _ in
                    continuation.resume(returning: status == .shouldRequest)
                }
            }, &thrown)
            if !started {
                logger.error("HealthKit status check raised an exception: \(thrown?.localizedDescription ?? "unknown", privacy: .public)")
                continuation.resume(returning: false)
            }
        }
    }

    /// All vitals for a session window. Returns ``SessionVitals/empty`` when nothing is readable;
    /// the three reads run concurrently.
    func vitals(from start: Date, to end: Date) async -> SessionVitals {
        guard isAvailable, end > start else { return .empty }
        async let hr = heartRateSamples(from: start, to: end)
        async let bp = bloodPressureReadings(from: start, to: end)
        async let resting = latestRestingHeartRate()
        return await SessionVitals(heartRate: hr, bloodPressure: bp, restingHeartRate: resting)
    }

    // MARK: - Queries

    //
    // Each completion handler runs on HealthKit's own serial queue, not the main actor — so it
    // captures only the Sendable `logger` + `continuation`, never `self`, and rebuilds any HKUnit /
    // HKQuantityType it needs inside the handler (those are not Sendable) rather than capturing them.

    private func heartRateSamples(from start: Date, to end: Date) async -> [HeartRateSample] {
        let type = heartRateType
        let logger = logger
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: [sort],
            ) { _, samples, error in
                if let error {
                    logger.error("Heart-rate query failed: \(error.localizedDescription, privacy: .public)")
                }
                let unit = HKUnit.count().unitDivided(by: .minute())
                let out = (samples as? [HKQuantitySample])?.map {
                    HeartRateSample(date: $0.startDate, bpm: $0.quantity.doubleValue(for: unit))
                } ?? []
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }

    private func bloodPressureReadings(from start: Date, to end: Date) async -> [BloodPressureReading] {
        let type = bloodPressureType
        let logger = logger
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKCorrelationQuery(
                type: type, predicate: predicate, samplePredicates: nil,
            ) { _, correlations, error in
                if let error {
                    logger.error("Blood-pressure query failed: \(error.localizedDescription, privacy: .public)")
                }
                let systolicType = HKQuantityType(.bloodPressureSystolic)
                let diastolicType = HKQuantityType(.bloodPressureDiastolic)
                let mmHg = HKUnit.millimeterOfMercury()
                let out: [BloodPressureReading] = (correlations ?? []).compactMap { correlation in
                    guard
                        let sys = (correlation.objects(for: systolicType).first as? HKQuantitySample)?
                        .quantity.doubleValue(for: mmHg),
                        let dia = (correlation.objects(for: diastolicType).first as? HKQuantitySample)?
                        .quantity.doubleValue(for: mmHg)
                    else { return nil }
                    return BloodPressureReading(date: correlation.startDate, systolic: sys, diastolic: dia)
                }
                .sorted { $0.date < $1.date }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }

    /// Most-recent resting-heart-rate sample in bpm, or nil if none is readable.
    private func latestRestingHeartRate() async -> Double? {
        let type = restingHeartRateType
        let logger = logger
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort],
            ) { _, samples, error in
                if let error {
                    logger.error("Resting-HR query failed: \(error.localizedDescription, privacy: .public)")
                }
                let unit = HKUnit.count().unitDivided(by: .minute())
                let bpm = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: bpm)
            }
            store.execute(query)
        }
    }
}
