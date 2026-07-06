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

    /// Request read access to heart rate and blood pressure. Prompts only when undetermined; a thrown
    /// error is a request failure (not a denial), so previously-granted access keeps working.
    /// Returns `false` only when HealthKit is unavailable on the device.
    @discardableResult
    func requestAccess() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            logger.error("Vitals authorization request failed: \(error.localizedDescription, privacy: .public)")
        }
        return true
    }

    /// Request read access to weight **and** vitals in a single system prompt.
    /// Onboarding calls this so the one "Use Apple Health" tap surfaces a single
    /// Health sheet listing body weight, heart rate, and blood pressure — rather
    /// than prompting again later when the session overlay is turned on.
    func requestAccessWithBodyMass() async {
        guard isAvailable else { return }
        let read = readTypes.union([HKQuantityType(.bodyMass)])
        do {
            try await store.requestAuthorization(toShare: [], read: read)
        } catch {
            logger.error("Combined authorization request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Whether requesting access would actually surface a system prompt — i.e. at
    /// least one vitals type is still undetermined (never asked). Returns `false`
    /// once the user has answered (granted *or* denied), so callers can prompt
    /// exactly once on first use and never nag afterward. This is the only honest
    /// "have we asked yet?" signal HealthKit exposes for read access.
    func shouldRequestAccess() async -> Bool {
        guard isAvailable else { return false }
        let store = store
        let read = readTypes
        return await withCheckedContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: [], read: read) { status, _ in
                continuation.resume(returning: status == .shouldRequest)
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
