import Foundation
import SwiftData
import UniformTypeIdentifiers

nonisolated extension UTType {
    /// A sealed session share, `.pirushare`.
    static let piruShare = UTType(exportedAs: "glass.kagerou.piru.share")
}

enum SessionSharingError: Error, LocalizedError, Equatable {
    case nothingToSend
    case noRecipients
    case notForThisDevice
    case damaged
    case newerVersion
    case fromYourself
    case keyChanged(name: String)
    case ownCode

    var errorDescription: String? {
        switch self {
        case .nothingToSend: String(localized: "This session has no doses to share.")
        case .noRecipients: String(localized: "Choose someone to share with.")
        case .notForThisDevice: String(localized: "This share was sent to someone else.")
        case .damaged: String(localized: "This share is damaged or was changed after it was sent.")
        case .newerVersion: String(localized: "This share was made by a newer Piru. Update to open it.")
        case .fromYourself: String(localized: "This share came from one of your own journals.")
        case let .keyChanged(name):
            String(localized: "\(name)'s code has changed since you paired. Scan their code again to keep sharing.")
        case .ownCode: String(localized: "That's your own code. Scan the other person's.")
        }
    }
}

// MARK: - Sending

/// Seals the active profile's side of a session to the people chosen, as a
/// `.pirushare` file for the share sheet.
@MainActor
enum ShareSender {
    /// The folder the files are written to; cleared on every new send.
    static var outbox: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PiruShares", isDirectory: true)
    }

    static let fileName = "Piru Session.pirushare"

    static func prepare(
        session: Session,
        to people: [PiruPerson],
        directory: ProfileDirectory = .shared,
        identities: ShareIdentityStore = .shared,
    ) async throws -> URL {
        let recipients = people.compactMap { person in person.key.map { (id: person.id, key: $0) } }
        guard !recipients.isEmpty else { throw SessionSharingError.noRecipients }
        guard !(session.doses ?? []).isEmpty else { throw SessionSharingError.nothingToSend }

        let profile = directory.activeProfile
        let identity = try identities.identity(for: profile.id)
        let experience: UUID
        if let existing = session.sharedExperienceID {
            experience = existing
        } else {
            experience = UUID()
            session.sharedExperienceID = experience
            DoseLogService.shared.changed()
        }
        // The reader sees committed state only.
        try session.modelContext?.save()

        guard let snapshot = await SharedExperienceReader.session(
            experienceID: experience, profileID: profile.id, in: directory.activeContainer,
        ), !snapshot.doses.isEmpty else { throw SessionSharingError.nothingToSend }

        let share = SessionShare(
            sender: SessionShare.Card(name: profile.name, avatar: profile.avatar.withPhoto(nil)),
            snapshot: snapshot,
            experienceID: experience,
        )
        let envelope = try ShareEnvelope.seal(share.encoded(), from: identity, to: recipients)
        try? FileManager.default.removeItem(at: outbox)
        let folder = outbox.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName)
        try envelope.encoded().write(to: url, options: .atomic)
        return url
    }
}

// MARK: - Receiving

/// Opens a `.pirushare` and files it: the sender's side goes into their
/// person's store, and the session of the recipient's from the same time
/// joins its shared experience.
@MainActor
enum ShareReceiver {
    /// Where the sender stands with this device.
    enum Sender: Equatable {
        case paired(PiruPerson)
        /// Nobody here has paired with them yet.
        case new
    }

    /// A share that opened: what it holds, whose journal it was sealed to, and
    /// who sent it.
    struct Opened: Equatable {
        let share: SessionShare
        let senderID: UUID
        let senderKey: Data
        /// The local profile it was sealed to.
        let recipientProfileID: UUID
        let sender: Sender
    }

    /// Open `data` with the identity of whichever local profile it names,
    /// preferring the active one.
    static func open(
        _ data: Data,
        directory: ProfileDirectory = .shared,
        identities: ShareIdentityStore = .shared,
    ) throws -> Opened {
        let envelope: ShareEnvelope
        do {
            envelope = try ShareEnvelope.decode(data)
        } catch ShareEnvelope.EnvelopeError.newerVersion {
            throw SessionSharingError.newerVersion
        } catch {
            throw SessionSharingError.damaged
        }
        let named = Set(envelope.recipients.map(\.id))
        let candidates = [directory.activeProfileID] + directory.profiles.map(\.id).filter { $0 != directory.activeProfileID }
        guard let recipient = candidates.lazy.compactMap({ id in
            identities.existingIdentity(for: id).flatMap { named.contains($0.personID) ? (id, $0) : nil }
        }).first else { throw SessionSharingError.notForThisDevice }

        let isOwnJournal = directory.profiles.contains { identities.existingIdentity(for: $0.id)?.personID == envelope.sender.id }
        guard !isOwnJournal else { throw SessionSharingError.fromYourself }

        let sender: Sender
        if let person = directory.person(id: envelope.sender.id) {
            guard person.publicKey == envelope.sender.key else { throw SessionSharingError.keyChanged(name: person.profile.name) }
            sender = .paired(person)
        } else {
            sender = .new
        }

        let plaintext: Data
        let share: SessionShare
        do {
            plaintext = try envelope.open(with: recipient.1)
            share = try SessionShare.decode(plaintext)
        } catch {
            throw SessionSharingError.damaged
        }
        guard share.version <= SessionShare.version else { throw SessionSharingError.newerVersion }

        return Opened(
            share: share, senderID: envelope.sender.id, senderKey: envelope.sender.key,
            recipientProfileID: recipient.0, sender: sender,
        )
    }

    /// What ``accept(_:directory:)`` did.
    struct Outcome: Equatable {
        let person: PiruPerson
        /// The recipient's session the share joined; `nil` when they logged
        /// nothing around that time.
        let linkedSessionID: UUID?
    }

    /// File `opened`: pair with the sender (or refresh their name and avatar),
    /// replace their side of the experience, and link the active profile's
    /// session from the same time. The recipient profile must be active.
    @discardableResult
    static func accept(_ opened: Opened, directory: ProfileDirectory = .shared) throws -> Outcome {
        precondition(opened.recipientProfileID == directory.activeProfileID, "Switch to the recipient before accepting")
        let person = try directory.savePerson(
            personID: opened.senderID,
            name: opened.share.sender.name,
            avatar: opened.share.sender.avatar,
            publicKey: opened.senderKey,
        )
        guard let container = directory.container(for: person.id, writable: true) else {
            throw SessionSharingError.damaged
        }
        try ProfileScope.$pinned.withValue(person.id) {
            try store(opened.share.side, in: container.mainContext)
        }
        DoseLogService.shared.changed(in: person.id)
        let linked = try link(opened.share.side, directory: directory)
        SharedExperienceStore.shared.invalidate()
        return Outcome(person: person, linkedSessionID: linked)
    }

    /// Replace everything `context` holds for `side.experienceID` with `side`.
    static func store(_ side: SessionShare.Side, in context: ModelContext) throws {
        let experience: UUID? = side.experienceID
        let sessionID = side.sessionID
        let previous = try context.fetch(FetchDescriptor<Session>(
            predicate: #Predicate { $0.sharedExperienceID == experience || $0.id == sessionID },
        ))
        for session in previous {
            for dose in session.doses ?? [] {
                context.delete(dose)
            }
            context.delete(session)
        }
        try context.save()

        let session = Session(id: side.sessionID, startDate: side.startDate, title: side.title, note: side.summary)
        session.sharedExperienceID = side.experienceID
        context.insert(session)

        var tints: [String: P3Color] = [:]
        for dose in side.doses {
            let entry = dose.detachedEntry()
            context.insert(entry)
            entry.session = session
            tints[dose.substance.lowercased()] = dose.tint
        }
        let colors = try context.fetch(FetchDescriptor<SubstanceColor>())
        for (substance, tint) in tints {
            if let row = colors.first(where: { $0.substance.lowercased() == substance }) {
                row.set(tint, usesDefault: false)
            } else {
                context.insert(SubstanceColor(substance: substance, tint: tint, usesDefault: false))
            }
        }
        for note in side.notes {
            SessionNoteService.add(to: session, timestamp: note.timestamp, text: note.text)
        }
        session.refreshDoseBounds()

        if let weight = side.weightKg {
            if let record = try context.fetch(FetchDescriptor<UserProfileRecord>()).first {
                record.bodyWeightKg = weight
            } else {
                context.insert(UserProfileRecord(bodyWeightKg: weight))
            }
        }
        try context.save()
    }

    /// Give the active profile's session from the time of `side` its
    /// experience id, folding any experience it already had into that one.
    private static func link(_ side: SessionShare.Side, directory: ProfileDirectory) throws -> UUID? {
        let times = side.doses.map(\.timestamp)
        guard let first = times.min(), let last = times.max() else { return nil }
        let context = directory.activeContainer.mainContext
        guard let mine = SharedExperienceLinker.overlappingSession(DateInterval(start: first, end: last), in: context) else {
            return nil
        }
        switch mine.sharedExperienceID {
        case side.experienceID:
            break
        case let other?:
            try SharedExperienceLinker.retag(other, to: side.experienceID, directory: directory)
        case nil:
            mine.sharedExperienceID = side.experienceID
            try context.save()
            DoseLogService.shared.changed(in: directory.activeProfileID)
        }
        return mine.id
    }

    /// Pair with the person a scanned code names.
    @discardableResult
    static func pair(
        with code: PairingCode,
        directory: ProfileDirectory = .shared,
        identities: ShareIdentityStore = .shared,
    ) throws -> PiruPerson {
        let own = directory.profiles.contains { identities.existingIdentity(for: $0.id)?.personID == code.personID }
        guard !own else { throw SessionSharingError.ownCode }
        return try directory.savePerson(
            personID: code.personID, name: code.name, avatar: code.avatar, publicKey: code.publicKey,
        )
    }
}
