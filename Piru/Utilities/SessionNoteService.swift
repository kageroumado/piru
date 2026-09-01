import Foundation
import os
import SwiftData

private nonisolated let logger = Logger(subsystem: "dev.yumeji.piru", category: "SessionNotes")

/// Mutations on a session's timestamped notes, and the bridge that keeps
/// ``Session/note`` and the `.summary` ``SessionNote`` saying the same thing.
///
/// `Session.note` stays the summary field every existing reader (exports, the
/// PDF report, the share image) already understands; the `.summary` note is its
/// place on the timeline. Both are written on every save, so neither path can
/// drift from the other.
enum SessionNoteService {
    // MARK: - Create / update / delete

    /// Insert a note into `session`'s context. Returns nil (and inserts nothing)
    /// when the draft carries no content.
    @discardableResult
    static func add(
        to session: Session,
        timestamp: Date,
        text: String,
        shulgin: Int? = nil,
        mood: Int? = nil,
        energy: Int? = nil,
        descriptors: [String] = [],
        heartRate: Double? = nil,
        kind: SessionNote.Kind = .observation,
    ) -> SessionNote? {
        guard let context = session.modelContext else {
            logger.error("Refusing to add a note to a session with no model context")
            return nil
        }
        // Built without its session: setting the relationship registers the
        // note with the context, so an empty draft must be rejected before that.
        let note = SessionNote(
            timestamp: timestamp,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            shulgin: shulgin, mood: mood, energy: energy,
            descriptors: descriptors, heartRate: heartRate,
            kind: kind,
        )
        guard note.hasContent else { return nil }
        context.insert(note)
        note.session = session
        if kind == .summary { session.note = note.text.isEmpty ? nil : note.text }
        DoseLogService.shared.changed()
        return note
    }

    /// Apply an edited draft to an existing note. A `.summary` note also writes
    /// its text through to ``Session/note``.
    static func update(
        _ note: SessionNote,
        timestamp: Date,
        text: String,
        shulgin: Int?,
        mood: Int?,
        energy: Int?,
        descriptors: [String],
        heartRate: Double?,
    ) {
        note.timestamp = timestamp
        note.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        note.shulgin = shulgin
        note.mood = mood
        note.energy = energy
        note.descriptors = descriptors
        note.heartRate = heartRate
        if note.kind == .summary, let session = note.session {
            session.note = note.text.isEmpty ? nil : note.text
        }
        DoseLogService.shared.changed()
    }

    static func delete(_ note: SessionNote) {
        guard let context = note.modelContext else { return }
        if note.kind == .summary, let session = note.session {
            session.note = nil
        }
        detachAndDelete(note, in: context)
        DoseLogService.shared.changed()
    }

    /// Drop the note from its session's array before deleting it, so readers of
    /// `session.notes` (and this service's own summary lookup) stop seeing it
    /// without waiting for the context to process the deletion.
    private static func detachAndDelete(_ note: SessionNote, in context: ModelContext) {
        note.session?.notes?.removeAll { $0 === note }
        note.session = nil
        context.delete(note)
    }

    // MARK: - Summary bridge

    /// Set (or clear) the session's summary; blank trims to `nil`. Writes both
    /// ``Session/note`` and the `.summary` note.
    static func setSummary(_ text: String, for session: Session) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? nil : trimmed
        let summary = summaryNote(of: session)
        guard session.note != value || summary?.text != (value ?? "") else { return }
        session.note = value
        if let summary {
            if let value {
                summary.text = value
            } else if let context = summary.modelContext {
                detachAndDelete(summary, in: context)
            }
        } else if let value, let context = session.modelContext {
            context.insert(SessionNote(timestamp: session.startDate, text: value, kind: .summary, session: session))
        }
        DoseLogService.shared.changed()
    }

    static func summaryNote(of session: Session) -> SessionNote? {
        (session.notes ?? []).first { $0.kind == .summary }
    }

    // MARK: - Migration shim

    /// Give a pre-notes session's ``Session/note`` its place on the timeline: a
    /// non-empty summary with no `.summary` note becomes one at `startDate`.
    /// Idempotent — a session already carrying its summary note is untouched.
    @discardableResult
    static func ensureSummaryNote(for session: Session) -> SessionNote? {
        if let existing = summaryNote(of: session) { return existing }
        guard let text = session.note?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let context = session.modelContext else { return nil }
        let note = SessionNote(timestamp: session.startDate, text: text, kind: .summary, session: session)
        context.insert(note)
        return note
    }

    /// Launch pass over every session with a summary — cheap once migrated
    /// (each is a relationship read), so it runs on every launch with no flag.
    static func migrateLegacySummaries(in context: ModelContext) {
        let withNote = FetchDescriptor<Session>(predicate: #Predicate { $0.note != nil })
        guard let sessions = try? context.fetch(withNote) else { return }
        var created = 0
        for session in sessions {
            let hadSummary = summaryNote(of: session) != nil
            if ensureSummaryNote(for: session) != nil, !hadSummary { created += 1 }
        }
        if context.hasChanges {
            try? context.save()
            logger.notice("Session note shim: \(created) summary notes ensured across \(sessions.count) sessions")
        }
    }
}
