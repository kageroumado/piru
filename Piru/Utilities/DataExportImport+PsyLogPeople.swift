import Foundation
import SwiftData

// MARK: - The people in a file

/// One person a PsyLog file holds doses for: the file's owner, whose doses
/// carry no `consumerName`, or someone the journal named.
nonisolated struct PsyLogConsumer: Identifiable, Hashable, Sendable {
    /// The name folded for matching; `nil` for the owner.
    let key: String?
    /// The name as the file first spells it; `nil` for the owner.
    let name: String?
    let doseCount: Int

    var id: String {
        key.map { "name:\($0)" } ?? "owner"
    }

    var isOwner: Bool {
        key == nil
    }

    /// Names match case-insensitively: "alice" in one experience and "Alice"
    /// in another are one person.
    static func key(for name: String?) -> String? {
        name.map { $0.lowercased() }
    }
}

nonisolated extension PsyLogFile {
    /// Everyone the file has doses for: the owner first when they took any,
    /// then each named person in the order the file first mentions them.
    var consumers: [PsyLogConsumer] {
        var counts: [String?: Int] = [:]
        var spelling: [String: String] = [:]
        var order: [String?] = []
        for ingestion in experiences.flatMap(\.ingestions) {
            let key = PsyLogConsumer.key(for: ingestion.consumerName)
            if counts[key] == nil { order.append(key) }
            counts[key, default: 0] += 1
            if let key, spelling[key] == nil { spelling[key] = ingestion.consumerName }
        }
        let owner = order.contains(nil) ? [String?.none] : []
        return (owner + order.filter { $0 != nil }).map { key in
            PsyLogConsumer(key: key, name: key.flatMap { spelling[$0] }, doseCount: counts[key] ?? 0)
        }
    }

    /// Whether any dose names who took it — the files that ask, before
    /// importing, whose journal each person's doses go into.
    var namesAnyone: Bool {
        experiences.contains { $0.ingestions.contains { $0.consumerName != nil } }
    }
}

// MARK: - Mapping people to profiles

/// Where one named person's doses go.
nonisolated enum PsyLogConsumerTarget: Hashable, Sendable {
    case profile(UUID)
    /// A new profile with the person's name, a monogram and the next color.
    case newProfile
    case skip
}

/// Which store each consumer's doses import into, once the mapping is settled.
@MainActor
struct PsyLogRouting {
    /// The profile the importing context belongs to, which takes the file
    /// owner's unnamed doses.
    let owner: UUID
    /// Each named person's profile by ``PsyLogConsumer/key``. A name with no
    /// entry is skipped.
    let named: [String: UUID]
    /// Opens the other profiles' stores; `nil` routes nobody but the owner.
    let directory: ProfileDirectory?

    /// The file owner's doses only, into the profile the code runs for.
    static func ownerOnly(_ owner: UUID = ProfileScope.currentID) -> PsyLogRouting {
        PsyLogRouting(owner: owner, named: [:], directory: nil)
    }

    func profile(forConsumer name: String?) -> UUID? {
        guard let key = PsyLogConsumer.key(for: name) else { return owner }
        return named[key]
    }

    /// A store to write a profile's part into; the owner's is the importing
    /// context and never asked for here.
    func context(for profile: UUID) -> ModelContext? {
        directory?.container(for: profile, writable: true)?.mainContext
    }
}

enum PsyLogImportMapping {
    /// The first choice offered for a named person: the profile with that name,
    /// matched case-insensitively, else a new profile.
    nonisolated static func defaultTarget(for consumer: PsyLogConsumer, profiles: [PiruProfile]) -> PsyLogConsumerTarget {
        guard let key = consumer.key else { return .skip }
        if let match = profiles.first(where: { $0.name.lowercased() == key }) {
            return .profile(match.id)
        }
        return .newProfile
    }

    /// The default choice for every named person in `consumers`, by key.
    nonisolated static func defaults(for consumers: [PsyLogConsumer], profiles: [PiruProfile]) -> [String: PsyLogConsumerTarget] {
        var targets: [String: PsyLogConsumerTarget] = [:]
        for consumer in consumers {
            guard let key = consumer.key else { continue }
            targets[key] = defaultTarget(for: consumer, profiles: profiles)
        }
        return targets
    }

    /// Settles `choices` into a routing, creating the profiles asked for. The
    /// file owner goes to the active profile; a person with no choice, or a
    /// profile that no longer exists, is skipped.
    @MainActor
    static func routing(
        for choices: [String: PsyLogConsumerTarget],
        consumers: [PsyLogConsumer],
        directory: ProfileDirectory,
    ) throws -> PsyLogRouting {
        var named: [String: UUID] = [:]
        for consumer in consumers {
            guard let key = consumer.key, let name = consumer.name else { continue }
            switch choices[key] ?? .skip {
            case let .profile(id):
                if directory.profile(id: id) != nil { named[key] = id }
            case .newProfile:
                named[key] = try directory.addProfile(name: name).id
            case .skip:
                continue
            }
        }
        return PsyLogRouting(owner: directory.activeProfileID, named: named, directory: directory)
    }
}

// MARK: - Everyone's export

extension DataExportImport {
    /// Every profile's journal for an Everyone export: the active profile's
    /// doses unnamed, everyone else's under their name. Other profiles' stores
    /// open read-only.
    @MainActor
    static func everyone(activeContext: ModelContext, directory: ProfileDirectory = .shared) -> [PsyLogPerson] {
        var people = [PsyLogPerson(name: nil, context: activeContext)]
        for profile in directory.profiles where profile.id != directory.activeProfileID {
            guard let container = directory.container(for: profile.id, writable: false) else { continue }
            people.append(PsyLogPerson(name: profile.name, context: container.mainContext))
        }
        return people
    }
}
