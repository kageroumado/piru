import Foundation
import Observation
import SwiftData
import SwiftUI

/// Another person's side of a shared experience, ready to draw: their doses as
/// rows, their curve in their substance colors (the peek) and in their profile
/// color (the session screen's section). Built from their own doses and body
/// weight only.
struct SharedParticipant: Identifiable, Equatable {
    let snapshot: SharedSessionSnapshot
    let rows: [DayEntryDisplay]
    let states: [ActiveSubstanceState]
    let markers: [DoseMarker]
    let personStates: [ActiveSubstanceState]
    let personMarkers: [DoseMarker]
    /// "2C-B 20 mg", one per dose, for the section's compact rows.
    let doseLines: [String]

    var id: UUID {
        snapshot.profileID
    }
}

/// Who else was in a session, read from the other profiles' stores.
///
/// Two reads, both off the main actor and both cached on the stores'
/// generations (``DoseLogService/storeGeneration(for:)``), so reopening is
/// instant and a commit to any store invalidates what it touched:
///
/// - ``participants(for:)``: one experience in full, for the session screen
///   and the peek.
/// - ``refreshIndex()``: which of the active profile's sessions are shared and
///   with whom, for the Journal's avatar marks
///   (``participantsBySession``), which rows read without a fetch.
///
/// Nothing here writes to the active profile's store or feeds its timeline,
/// curves, interactions or insights: another person's doses exist only as the
/// values this type hands to the shared-session views.
@Observable
@MainActor
final class SharedExperienceStore {
    static let shared = SharedExperienceStore()

    /// The active profile's shared sessions: session id → the other profiles
    /// that logged a dose in the same experience, in profile order.
    private(set) var participantsBySession: [UUID: [UUID]] = [:]

    @ObservationIgnored private let directory: ProfileDirectory
    @ObservationIgnored private let generation: (UUID) -> Int
    @ObservationIgnored private var experiences: [UUID: CachedExperience] = [:]
    @ObservationIgnored private var linksByProfile: [UUID: CachedLinks] = [:]
    @ObservationIgnored private var indexKey: IndexKey?

    private struct Member: Hashable {
        let id: UUID
        let generation: Int
        let color: ProfileColor
    }

    private struct ExperienceKey: Hashable {
        let active: UUID
        let others: [Member]
    }

    private struct CachedExperience {
        let key: ExperienceKey
        let participants: [SharedParticipant]
    }

    private struct CachedLinks {
        let generation: Int
        let links: [SharedExperienceReader.LinkedSession]
    }

    private struct IndexKey: Hashable {
        let active: UUID
        let members: [Member]
    }

    init(
        directory: ProfileDirectory = .shared,
        generation: @escaping (UUID) -> Int = { DoseLogService.storeGeneration(for: $0) },
    ) {
        self.directory = directory
        self.generation = generation
    }

    // MARK: - One experience

    /// The other people in `experienceID` who logged a dose, in profile order,
    /// when the cache still matches every store; `nil` when it must be read.
    func cachedParticipants(for experienceID: UUID) -> [SharedParticipant]? {
        guard let cached = experiences[experienceID], cached.key == experienceKey() else { return nil }
        return cached.participants
    }

    /// The other people in `experienceID` who logged a dose, in profile order.
    func participants(for experienceID: UUID) async -> [SharedParticipant] {
        let key = experienceKey()
        if let cached = experiences[experienceID], cached.key == key { return cached.participants }
        var snapshots: [SharedSessionSnapshot] = []
        for member in key.others {
            guard let container = directory.container(for: member.id, writable: false) else { continue }
            if let snapshot = await SharedExperienceReader.session(
                experienceID: experienceID, profileID: member.id, in: container,
            ), !snapshot.doses.isEmpty {
                snapshots.append(snapshot)
            }
        }
        await SubstanceStore.shared.ensureAllLoaded()
        let colors = Dictionary(uniqueKeysWithValues: key.others.map { ($0.id, $0.color) })
        let participants = snapshots.map { Self.participant(from: $0, color: colors[$0.profileID] ?? .rose) }
        // A switch or a commit while reading leaves the result for a key that
        // is already gone; hand it back, but cache only what is still current.
        if experienceKey() == key {
            experiences[experienceID] = CachedExperience(key: key, participants: participants)
        }
        return participants
    }

    private func experienceKey() -> ExperienceKey {
        let active = directory.activeProfileID
        return ExperienceKey(
            active: active,
            others: directory.profiles.filter { $0.id != active }.map {
                Member(id: $0.id, generation: generation($0.id), color: $0.color)
            },
        )
    }

    private static func participant(from snapshot: SharedSessionSnapshot, color: ProfileColor) -> SharedParticipant {
        let entries = snapshot.doses.map { $0.detachedEntry() }
        let tints = Dictionary(snapshot.doses.map { ($0.id, $0.tint) }, uniquingKeysWith: { first, _ in first })
        // Their weight, or the population default: never the active profile's.
        let weight = snapshot.weightKg ?? UserProfileStore.defaultWeightKg
        let own = ActiveSubstanceState.timeline(for: entries, weightKg: weight) { tints[$0.id] ?? .neutral }
        let person = ActiveSubstanceState.timeline(for: entries, weightKg: weight) { _ in color.p3 }
        let cores = DayEntryCore.make(from: entries)
        let rows = zip(cores, snapshot.doses).map { DayEntryDisplay(core: $0, color: $1.tint.color) }
        let lines = cores.map { core in
            core.isUnknownDose ? core.displayName : "\(core.displayName) \(core.amount.doseFormatted) \(core.unit)"
        }
        return SharedParticipant(
            snapshot: snapshot,
            rows: rows,
            states: own.states,
            markers: own.markers,
            personStates: person.states,
            personMarkers: person.markers,
            doseLines: lines,
        )
    }

    // MARK: - The Journal's index

    /// Recompute ``participantsBySession`` when any store's generation, the
    /// profile list or the active profile changed since the last read. Each
    /// store is re-read only when its own generation moved.
    func refreshIndex() async {
        guard directory.hasMultipleProfiles else {
            indexKey = nil
            if !participantsBySession.isEmpty { participantsBySession = [:] }
            return
        }
        let active = directory.activeProfileID
        let members = directory.profiles.map { Member(id: $0.id, generation: generation($0.id), color: $0.color) }
        let key = IndexKey(active: active, members: members)
        guard key != indexKey else { return }

        var links: [UUID: [SharedExperienceReader.LinkedSession]] = [:]
        for member in members {
            if let cached = linksByProfile[member.id], cached.generation == member.generation {
                links[member.id] = cached.links
                continue
            }
            guard let container = directory.container(for: member.id, writable: false) else { continue }
            let read = await SharedExperienceReader.linkedSessions(in: container)
            linksByProfile[member.id] = CachedLinks(generation: member.generation, links: read)
            links[member.id] = read
        }
        guard directory.activeProfileID == active else { return }

        var peopleByExperience: [UUID: [UUID]] = [:]
        for member in members where member.id != active {
            let experiences = Set((links[member.id] ?? []).filter(\.hasDoses).map(\.experienceID))
            for experience in experiences {
                peopleByExperience[experience, default: []].append(member.id)
            }
        }
        var index: [UUID: [UUID]] = [:]
        for link in links[active] ?? [] {
            if let people = peopleByExperience[link.experienceID] { index[link.sessionID] = people }
        }
        indexKey = key
        if index != participantsBySession { participantsBySession = index }
    }

    /// Drop every cached read: a link changed in a way no dose generation
    /// records.
    func invalidate() {
        experiences = [:]
        linksByProfile = [:]
        indexKey = nil
    }

    // MARK: - Titles

    /// "With Alice", "With Alice and Bob", "With Alice, Bob and Carol", "With
    /// Alice, Bob and 2 others": every name up to three, then the first two and
    /// a count, joined by the locale's list format.
    static func sectionTitle(names: [String]) -> String {
        let items = names.count <= 3
            ? names
            : Array(names.prefix(2)) + [String(localized: "\(names.count - 2) others")]
        let list = items.formatted(.list(type: .and))
        return String(localized: "With \(list)")
    }
}
