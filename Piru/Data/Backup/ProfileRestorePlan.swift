import Foundation

/// How one of a backup's profiles lands on a restore, as the user chose.
nonisolated enum ProfileRestoreChoice: Hashable, Sendable {
    /// Into the profile here, which keeps its name, avatar and color.
    case keepThisDevice
    /// Into the profile here, which takes the backup's name, avatar and color.
    case useBackup
    /// As a profile of its own, beside everyone here.
    case newProfile
}

/// A backup profile the user settles before a restore touches anything.
nonisolated struct ProfileRestoreConflict: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// The same profile as one here, shown differently.
        case details
        /// The backup's own profile, made on another device: by default its
        /// journal goes into this device's owner.
        case otherOwner
    }

    let kind: Kind
    /// The profile as the backup has it.
    let incoming: PiruProfile
    /// The profile here it restores into by default.
    let local: PiruProfile

    var id: UUID {
        incoming.id
    }

    /// What the user can pick, the default first.
    var choices: [ProfileRestoreChoice] {
        switch kind {
        case .details: [.keepThisDevice, .useBackup]
        case .otherOwner: local.looksLike(incoming) ? [.keepThisDevice, .newProfile] : [.keepThisDevice, .useBackup, .newProfile]
        }
    }
}

/// Where each of a backup's profiles goes on this device. Profiles match by
/// id: a backup profile with an id here restores into that profile, the
/// legacy owner id into this device's owner, and any other id becomes a new
/// profile. The backup's own profile from another device restores into this
/// device's owner unless the user adds it as a new profile. A profile here
/// that the backup shows differently, by name, avatar or color, keeps how it
/// looks unless the user takes the backup's.
nonisolated struct ProfileRestorePlan: Sendable {
    struct Step: Sendable {
        let incoming: PiruProfile
        /// The profile id here its journal goes into.
        let target: UUID
        /// Whether the target takes the backup's name, avatar and color, or,
        /// for a new profile, is made from them.
        let takesDetails: Bool
    }

    let steps: [Step]
    let conflicts: [ProfileRestoreConflict]

    /// `local` is this device's profiles, the owner first; `reserved` holds
    /// ids a new profile can't take (paired people's).
    init(
        registry: [PiruProfile],
        local: [PiruProfile],
        reserved: Set<UUID>,
        choices: [UUID: ProfileRestoreChoice],
    ) {
        let owner = local[0]
        var seen = Set<UUID>()
        var incomingOwnerSeen = false
        var steps: [Step] = []
        var conflicts: [ProfileRestoreConflict] = []
        for incoming in registry where seen.insert(incoming.id).inserted {
            let isIncomingOwner = incoming.isOwner && !incomingOwnerSeen
            if isIncomingOwner { incomingOwnerSeen = true }
            let localID = incoming.id == PiruProfile.legacyOwnerID ? owner.id : incoming.id
            if let match = local.first(where: { $0.id == localID }) {
                let differs = !match.looksLike(incoming)
                if differs { conflicts.append(ProfileRestoreConflict(kind: .details, incoming: incoming, local: match)) }
                let takes = differs && choices[incoming.id] == .useBackup
                steps.append(Step(incoming: incoming, target: match.id, takesDetails: takes))
            } else if isIncomingOwner {
                conflicts.append(ProfileRestoreConflict(kind: .otherOwner, incoming: incoming, local: owner))
                switch choices[incoming.id] ?? .keepThisDevice {
                case .keepThisDevice:
                    steps.append(Step(incoming: incoming, target: owner.id, takesDetails: false))
                case .useBackup:
                    steps.append(Step(incoming: incoming, target: owner.id, takesDetails: true))
                case .newProfile:
                    let id = reserved.contains(incoming.id) ? UUID() : incoming.id
                    steps.append(Step(incoming: incoming, target: id, takesDetails: true))
                }
            } else {
                let id = reserved.contains(incoming.id) ? UUID() : incoming.id
                steps.append(Step(incoming: incoming, target: id, takesDetails: true))
            }
        }
        self.steps = steps
        self.conflicts = conflicts
    }

    /// The profile id here each backup profile id restores into.
    var targets: [UUID: UUID] {
        Dictionary(steps.map { ($0.incoming.id, $0.target) }, uniquingKeysWith: { first, _ in first })
    }

    /// The backup's own profile's target: where the file's top level goes.
    var ownerTarget: UUID? {
        steps.first { $0.incoming.isOwner }?.target
    }
}
