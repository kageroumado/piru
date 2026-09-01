import Foundation
import SwiftUI

/// The note sheet's edit state — one draft object rather than a pile of
/// `@State`, so the sheet's own state stays a couple of UI toggles.
@MainActor
@Observable
final class SessionNoteDraft {
    let session: Session
    /// The note being edited, or nil when composing.
    let existing: SessionNote?
    let kind: SessionNote.Kind

    var timestamp: Date
    var text: String
    var shulgin: Int?
    var mood: Int?
    var energy: Int?
    var descriptors: [String]
    /// Heart rate captured for `timestamp` — the note's own value when editing,
    /// otherwise the nearest Health sample within ±2 min once fetched.
    var heartRate: Double?
    /// Heart-rate samples for the session window, fetched once so the sample
    /// nearest an *edited* timestamp resolves without another read.
    private var samples: [HeartRateSample] = []

    /// ±2 minutes: the nearest sample counts as "at this note".
    nonisolated static let heartRateWindow: TimeInterval = 2 * 60

    init(session: Session, existing: SessionNote?, kind: SessionNote.Kind) {
        self.session = session
        self.existing = existing
        self.kind = existing?.kind ?? kind
        timestamp = existing?.timestamp ?? .now
        text = existing?.text ?? ""
        shulgin = existing?.shulgin
        mood = existing?.mood
        energy = existing?.energy
        descriptors = existing?.descriptors ?? []
        heartRate = existing?.heartRate
    }

    var isEditing: Bool {
        existing != nil
    }

    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || shulgin != nil || mood != nil || energy != nil
            || !descriptors.isEmpty
    }

    // MARK: - Heart rate

    /// Read the session's heart-rate samples (when the overlay is on) and pick
    /// the one nearest the draft's timestamp. Editing the timestamp later
    /// re-picks from the same samples (``refreshHeartRate()``).
    func loadHeartRate(showSessionVitals: Bool, provided: SessionVitals?) async {
        if let provided {
            samples = provided.heartRate
        } else {
            guard showSessionVitals, HealthKitVitals.shared.isAvailable else { return }
            let end = max(Date.now, timestamp).addingTimeInterval(Self.heartRateWindow)
            let start = session.startDate.addingTimeInterval(-VitalsAnalysis.baselineLookback)
            samples = await HealthKitVitals.shared.vitals(from: start, to: end).heartRate
        }
        // An existing note keeps the value it recorded; only a fresh draft fills in.
        if existing == nil { refreshHeartRate() }
    }

    /// The sample nearest `timestamp` within the window, or nil.
    func refreshHeartRate() {
        heartRate = Self.nearestHeartRate(to: timestamp, in: samples)
    }

    nonisolated static func nearestHeartRate(to date: Date, in samples: [HeartRateSample], window: TimeInterval = heartRateWindow) -> Double? {
        samples
            .filter { !$0.isWorkout && abs($0.date.timeIntervalSince(date)) <= window }
            .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }?
            .bpm
    }

    // MARK: - Save

    /// Write the draft: update the note being edited, or insert a new one.
    func save() {
        if let existing {
            SessionNoteService.update(
                existing, timestamp: timestamp, text: text,
                shulgin: shulgin, mood: mood, energy: energy,
                descriptors: descriptors, heartRate: heartRate,
            )
        } else {
            SessionNoteService.add(
                to: session, timestamp: timestamp, text: text,
                shulgin: shulgin, mood: mood, energy: energy,
                descriptors: descriptors, heartRate: heartRate, kind: kind,
            )
        }
    }

    func delete() {
        guard let existing else { return }
        SessionNoteService.delete(existing)
    }
}
