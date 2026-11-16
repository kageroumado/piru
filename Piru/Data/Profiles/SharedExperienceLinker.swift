import Foundation
import SwiftData

/// Joins and splits shared experiences: a session in the active profile and
/// another profile's session from the same time, carrying one
/// ``Session/sharedExperienceID``.
@MainActor
enum SharedExperienceLinker {
    enum AddResult: Equatable {
        /// Their session now carries the experience id.
        case linked
        /// Their overlapping session was already in this experience.
        case alreadyLinked
        /// They logged nothing around this session's time.
        case noOverlap
    }

    /// How far apart two sessions may be and still be one night: the gap the
    /// clustering always joins doses across.
    static let tolerance = SessionClustering.Constants.floor

    // MARK: - Matching

    /// The time a session covers: its first dose to its last.
    static func window(of session: Session) -> DateInterval {
        let end = max(session.lastDoseDate ?? session.startDate, session.startDate)
        return DateInterval(start: session.startDate, end: end)
    }

    /// The candidate whose doses fall within ``tolerance`` of `window`,
    /// preferring the one that started closest to it; `nil` when none does.
    static func overlapping(_ window: DateInterval, in candidates: [Session]) -> Session? {
        let reach = DateInterval(start: window.start.addingTimeInterval(-tolerance), end: window.end.addingTimeInterval(tolerance))
        return candidates
            .filter { reach.intersects(self.window(of: $0)) }
            .min { abs($0.startDate.timeIntervalSince(window.start)) < abs($1.startDate.timeIntervalSince(window.start)) }
    }

    /// `context`'s sessions near enough to `window` to overlap it. A session
    /// spans at most the clustering horizon, so starts older than that are
    /// never fetched.
    static func overlappingSession(_ window: DateInterval, in context: ModelContext) -> Session? {
        let earliest = window.start.addingTimeInterval(-tolerance - SessionClustering.Constants.horizon)
        let latest = window.end.addingTimeInterval(tolerance)
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.startDate >= earliest && $0.startDate <= latest })
        let candidates = ((try? context.fetch(descriptor)) ?? []).filter { !($0.doses ?? []).isEmpty }
        return overlapping(window, in: candidates)
    }

    // MARK: - Adding

    /// Link `profileID`'s session from the time of `session` into its shared
    /// experience, minting the id when neither side has one. Their store is
    /// read first and opened for writing only when there is a session to link.
    @discardableResult
    static func add(_ profileID: UUID, to session: Session, directory: ProfileDirectory = .shared) throws -> AddResult {
        guard profileID != directory.activeProfileID,
              let readable = directory.container(for: profileID, writable: false),
              overlappingSession(window(of: session), in: readable.mainContext) != nil,
              let writable = directory.container(for: profileID, writable: true),
              let theirs = overlappingSession(window(of: session), in: writable.mainContext)
        else { return .noOverlap }

        if let mine = session.sharedExperienceID, theirs.sharedExperienceID == mine { return .alreadyLinked }

        let experience: UUID
        switch (session.sharedExperienceID, theirs.sharedExperienceID) {
        case let (mine?, previous?):
            // Two experiences become one: everyone in theirs joins this one.
            experience = mine
            try retag(previous, to: mine, directory: directory)
        case let (mine?, nil):
            experience = mine
        case let (nil, existing?):
            experience = existing
        case (nil, nil):
            experience = UUID()
        }

        theirs.sharedExperienceID = experience
        try ProfileScope.$pinned.withValue(profileID) { try writable.mainContext.save() }
        DoseLogService.shared.changed(in: profileID)

        if session.sharedExperienceID != experience {
            session.sharedExperienceID = experience
            try session.modelContext?.save()
            DoseLogService.shared.changed(in: directory.activeProfileID)
        }
        SharedExperienceStore.shared.invalidate()
        return .linked
    }

    /// Move every session carrying `old`, in every profile, to `new`.
    private static func retag(_ old: UUID, to new: UUID, directory: ProfileDirectory) throws {
        for profile in directory.profiles {
            guard let readable = directory.container(for: profile.id, writable: false),
                  !sessions(in: old, context: readable.mainContext).isEmpty,
                  let writable = directory.container(for: profile.id, writable: true)
            else { continue }
            for session in sessions(in: old, context: writable.mainContext) {
                session.sharedExperienceID = new
            }
            try ProfileScope.$pinned.withValue(profile.id) { try writable.mainContext.save() }
            DoseLogService.shared.changed(in: profile.id)
        }
    }

    // MARK: - Removing

    /// Take `profileID`'s sessions out of `experienceID`. When nobody but the
    /// active profile is left in it, the active profile's sessions leave it
    /// too, so a shared experience of one never lingers.
    static func remove(_ profileID: UUID, from experienceID: UUID, directory: ProfileDirectory = .shared) throws {
        if let writable = directory.container(for: profileID, writable: true) {
            let theirs = sessions(in: experienceID, context: writable.mainContext)
            if !theirs.isEmpty {
                for session in theirs {
                    session.sharedExperienceID = nil
                }
                try ProfileScope.$pinned.withValue(profileID) { try writable.mainContext.save() }
                DoseLogService.shared.changed(in: profileID)
            }
        }

        let active = directory.activeProfileID
        let othersRemain = directory.profiles.contains { profile in
            guard profile.id != active, let container = directory.container(for: profile.id, writable: false) else { return false }
            return !sessions(in: experienceID, context: container.mainContext).isEmpty
        }
        if !othersRemain {
            let context = directory.activeContainer.mainContext
            let mine = sessions(in: experienceID, context: context)
            if !mine.isEmpty {
                for session in mine {
                    session.sharedExperienceID = nil
                }
                try context.save()
                DoseLogService.shared.changed(in: active)
            }
        }
        SharedExperienceStore.shared.invalidate()
    }

    // MARK: - Reading

    /// Whether `profileID` has a session in `experienceID`.
    static func isLinked(_ profileID: UUID, to experienceID: UUID, directory: ProfileDirectory = .shared) -> Bool {
        guard let container = directory.container(for: profileID, writable: false) else { return false }
        return !sessions(in: experienceID, context: container.mainContext).isEmpty
    }

    private static func sessions(in experienceID: UUID, context: ModelContext) -> [Session] {
        let target: UUID? = experienceID
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.sharedExperienceID == target })
        return (try? context.fetch(descriptor)) ?? []
    }
}
