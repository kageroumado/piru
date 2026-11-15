import Foundation
import SwiftData

/// Whose journal a quick log writes into: the profile on screen, or someone
/// picked with the For chip for this one log. Either way the doses go through
/// the one batch path, ``DoseLogService/logBatch(_:colors:in:beforeSave:deferredBookkeeping:)``;
/// for someone else it runs pinned to their profile, so their store, their
/// reminders and their inventory take the dose, and the live session and Live
/// Activity on screen never do.
@MainActor
struct DoseRecipient {
    let profileID: UUID
    let context: ModelContext
    /// The recipient's substance colors, for minting a first-time substance's row.
    let colors: [SubstanceColor]
    /// The recipient's own recent doses, which their dose notifications weigh.
    let recentEntries: [DoseEntry]
    let isActive: Bool

    /// How far back another profile's doses are read, as the quick log reads
    /// the active profile's (``QuickLogContentModel/recentEntriesSpan``).
    private static let recentWindow = QuickLogContentModel.recentEntriesSpan

    /// The profile on screen, with the quick log's own snapshots.
    static func active(context: ModelContext, colors: [SubstanceColor], recentEntries: [DoseEntry]) -> DoseRecipient {
        DoseRecipient(
            profileID: ProfileScope.currentID,
            context: context,
            colors: colors,
            recentEntries: recentEntries,
            isActive: true,
        )
    }

    /// Someone else's journal, opened for writing, or `nil` for an unknown
    /// profile or the active one.
    static func other(_ id: UUID, directory: ProfileDirectory = .shared) -> DoseRecipient? {
        guard id != directory.activeProfileID,
              let container = directory.container(for: id, writable: true) else { return nil }
        let context = container.mainContext
        return DoseRecipient(
            profileID: id,
            context: context,
            colors: (try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? [],
            recentEntries: recentDoses(in: context),
            isActive: false,
        )
    }

    /// Someone else's doses from the last week, newest first, read without
    /// opening their store for writing: what the tray's interaction check
    /// weighs a dose for them against. Empty for an unknown profile.
    static func recentDoses(of id: UUID, directory: ProfileDirectory = .shared) -> [DoseEntry] {
        guard let container = directory.container(for: id, writable: false) else { return [] }
        return recentDoses(in: container.mainContext)
    }

    private static func recentDoses(in context: ModelContext) -> [DoseEntry] {
        let cutoff = Date.now.addingTimeInterval(-recentWindow)
        let recent = FetchDescriptor<DoseEntry>(
            predicate: #Predicate { $0.timestamp >= cutoff },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)],
        )
        return (try? context.fetch(recent)) ?? []
    }

    /// Logs `batch` into this journal. For someone else, the sessions their
    /// doses join or open are linked to `liveSession` (the active profile's
    /// running session, if any) as one shared experience.
    func log(
        _ batch: [(entry: DoseEntry, substance: Substance?)],
        liveSession: Session?,
        beforeSave: @escaping () -> Void = {},
        deferredBookkeeping: @escaping @MainActor () -> Void = {},
    ) {
        let commit = {
            DoseLogService.shared.logBatch(
                batch,
                colors: colors,
                in: context,
                beforeSave: {
                    beforeSave()
                    if !isActive, let liveSession {
                        SharedExperienceLink.link(batch.compactMap(\.entry.session), to: liveSession)
                    }
                },
                deferredBookkeeping: deferredBookkeeping,
            )
        }
        guard !isActive else { return commit() }
        ProfileScope.$pinned.withValue(profileID, operation: commit)
        if let liveSession, liveSession.hasChanges {
            try? liveSession.modelContext?.save()
        }
    }
}

/// Sessions in different profiles' stores that are one shared experience
/// carry the same `Session.sharedExperienceID`.
@MainActor
enum SharedExperienceLink {
    /// Joins `sessions` to `live`: they take its shared experience, which is
    /// minted (or taken from one of them) when it has none yet. A session
    /// already part of another shared experience keeps that one.
    static func link(_ sessions: [Session], to live: Session) {
        guard !sessions.isEmpty else { return }
        let shared = live.sharedExperienceID ?? sessions.lazy.compactMap(\.sharedExperienceID).first ?? UUID()
        if live.sharedExperienceID == nil { live.sharedExperienceID = shared }
        for session in sessions where session.sharedExperienceID == nil {
            session.sharedExperienceID = shared
        }
    }
}
