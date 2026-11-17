import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import Piru

/// One phone: its profiles and stores, and its own Keychain.
@MainActor
private struct Phone {
    let directory: ProfileDirectory
    let identities = ShareIdentityStore(storage: InMemoryShareIdentityStorage())

    init(ownerName: String) throws {
        directory = try makeScratchProfileDirectory().0
        var owner = directory.owner
        owner.name = ownerName
        try directory.update(owner)
    }

    var context: ModelContext {
        directory.activeContainer.mainContext
    }

    func code() throws -> PairingCode {
        try PairingCode(identity: identities.identity(for: directory.activeProfileID), profile: directory.activeProfile)
    }

    func pair(with other: Phone) throws {
        try ShareReceiver.pair(with: other.code(), directory: directory, identities: identities)
    }

    @discardableResult
    func session(at start: Date, doses: [(String, Double, Double)]) throws -> Session {
        let session = Session(startDate: start)
        context.insert(session)
        for (substance, amount, hours) in doses {
            let entry = DoseEntry(substance: substance, amount: amount, unit: "mg", timestamp: start.addingTimeInterval(hours * 3_600))
            context.insert(entry)
            entry.session = session
        }
        session.refreshDoseBounds()
        try context.save()
        return session
    }

    func send(_ session: Session, to people: [PiruPerson]) async throws -> Data {
        let url = try await ShareSender.prepare(session: session, to: people, directory: directory, identities: identities)
        return try Data(contentsOf: url)
    }

    func open(_ data: Data) throws -> ShareReceiver.Opened {
        try ShareReceiver.open(data, directory: directory, identities: identities)
    }
}

@Suite("Profiles — sharing across phones", .serialized)
@MainActor
struct SessionSharingTests {
    private let night = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Envelope

    @Test
    func `A sealed share opens only for the people it names, and only intact`() throws {
        let sender = ShareIdentity.make()
        let bob = ShareIdentity.make()
        let carol = ShareIdentity.make()
        let mallory = ShareIdentity.make()
        let envelope = try ShareEnvelope.seal(
            Data("hello".utf8), from: sender, to: [(bob.personID, bob.publicKey), (carol.personID, carol.publicKey)],
        )
        let decoded = try ShareEnvelope.decode(envelope.encoded())
        #expect(try decoded.open(with: bob) == Data("hello".utf8))
        #expect(try decoded.open(with: carol) == Data("hello".utf8))
        #expect(throws: ShareEnvelope.EnvelopeError.notForYou) { try decoded.open(with: mallory) }

        var body = decoded.body
        body[body.startIndex + 20] ^= 0x01
        let tampered = ShareEnvelope(format: decoded.format, version: decoded.version, sender: decoded.sender, recipients: decoded.recipients, body: body)
        #expect(throws: ShareEnvelope.EnvelopeError.damaged) { try tampered.open(with: bob) }

        // Claiming someone else's key fails the auth-mode seal.
        let forged = ShareEnvelope(
            format: decoded.format, version: decoded.version,
            sender: .init(id: decoded.sender.id, key: mallory.publicKey.rawRepresentation),
            recipients: decoded.recipients, body: decoded.body,
        )
        #expect(throws: ShareEnvelope.EnvelopeError.damaged) { try forged.open(with: bob) }
    }

    @Test
    func `A recipient cannot pass another recipient a body of their own`() throws {
        let alice = ShareIdentity.make()
        let bob = ShareIdentity.make()
        let carol = ShareIdentity.make()
        let envelope = try ShareEnvelope.seal(
            Data("from alice".utf8), from: alice,
            to: [(bob.personID, bob.publicKey), (carol.personID, carol.publicKey)],
        )
        // Bob opens his own key, as any recipient can, and seals a new body under it.
        let header = ShareEnvelope.header(sender: envelope.sender, version: envelope.version)
        let mine = try #require(envelope.recipients.first { $0.id == bob.personID })
        var hpke = try HPKE.Recipient(
            privateKey: bob.privateKey, ciphersuite: .Curve25519_SHA256_ChachaPoly, info: Data("piru-share/1".utf8),
            encapsulatedKey: mine.enc, authenticatedBy: alice.publicKey,
        )
        let contentKey = try SymmetricKey(
            data: hpke.open(mine.sealedKey, authenticating: ShareEnvelope.keyAAD(header: header, body: envelope.body)),
        )
        let compressed = try (Data("from bob".utf8) as NSData).compressed(using: .zlib) as Data
        let body = try ChaChaPoly.seal(compressed, using: contentKey, authenticating: header).combined
        let forged = ShareEnvelope(
            format: envelope.format, version: envelope.version, sender: envelope.sender,
            recipients: envelope.recipients, body: body,
        )
        #expect(throws: ShareEnvelope.EnvelopeError.damaged) { try forged.open(with: carol) }
        #expect(try envelope.open(with: carol) == Data("from alice".utf8))
    }

    @Test
    func `Anything that isn't a share is refused before opening`() {
        #expect(throws: ShareEnvelope.EnvelopeError.notAShare) { try ShareEnvelope.decode(Data("{}".utf8)) }
        #expect(throws: ShareEnvelope.EnvelopeError.notAShare) { try ShareEnvelope.decode(Data([0xFF, 0x00])) }
    }

    @Test
    func `A body that inflates past the cap is refused`() throws {
        let sender = ShareIdentity.make()
        let bob = ShareIdentity.make()
        let bomb = Data(count: ShareEnvelope.maxBodyBytes + 1)
        let envelope = try ShareEnvelope.seal(bomb, from: sender, to: [(bob.personID, bob.publicKey)])
        #expect(try envelope.encoded().count < 100_000)
        #expect(throws: ShareEnvelope.EnvelopeError.damaged) { try envelope.open(with: bob) }
        #expect(throws: ShareEnvelope.EnvelopeError.damaged) {
            try ShareEnvelope.decode(Data(count: ShareEnvelope.maxFileBytes + 1))
        }
    }

    /// A share sealed on Android by the app's own envelope code (swift-crypto's HPKE over
    /// BoringSSL, the body deflated by zlib) to a test identity, captured from an Android
    /// emulator. The format is frozen across both apps, so this file must open here unchanged.
    @Test
    func `A share sealed on Android opens on an iPhone`() throws {
        let iphone = try ShareIdentity(
            personID: #require(UUID(uuidString: "9F8E7D6C-5B4A-4321-8FED-CBA987654321")),
            privateKey: Curve25519.KeyAgreement.PrivateKey(
                rawRepresentation: #require(Data(base64Encoded: "PhmvctO4zQK+1BanqrIQWTQlIGaezDdMbELoiwdsQc8=")),
            ),
        )
        let envelope = try ShareEnvelope.decode(Data(Self.androidShare.utf8))
        #expect(envelope.sender.id == UUID(uuidString: "0F1E2D3C-4B5A-4978-8695-A4B3C2D1E0F9"))
        let doses = (0 ..< 80).map { index in
            #"{"dose":\#(index),"substance":"2C-B","amount":\#(index * 5),"unit":"mg","note":"Colors up at the kitchen disco."}"#
        }
        #expect(try envelope.open(with: iphone) == Data("[\(doses.joined(separator: ","))]".utf8))
    }

    private static let androidShare = #"""
    {"body":"kFJz0Z9fGW02gHE44xfkGB3hUOstMMxZwUe0xyMtXthHs1exMYxJxV\/ZZgq07bvf4lV5vjM4+85wIqUjfTMsAaewjyBnSbEByU5d3fcPJrEXmov7Fj8Cg34OYBZm5rHMS1bM\/U7mIU8rKL19WpywlGjFct0tG55IUqU4tNL5QYFaGoDWSyEWS9nAq4E3BY2K1nD7gz2SQpGQX53uwvn0bZsgjS7e9Zp\/+ejTYMxtUmDicVzeNJ6lLyxGuSaCcYeeaD9aSRt3fjB+VX6yaal2yh626CxVmpMQ0GphJQBavZjrle24pfpBeN7xRobQ\/+k3bloKgcPbzIyjoGA2tUaxHJREzwxIDnkXS6NP8IosHq+TNMIvob49MO6g\/TBilHjoO3zPDob9SfzPyg3Hpii53Wy5Poc7oG7OVPURxkRpQvrHCMyBHuM5xBvPerk2M73P043d5vg9xqhARoZM0a7V2ERF9r3Jv3M+u82\/\/vhu5bFRT8O0J2N6+cjI\/8MbSUpYZ0ILb8lQ4aGBqByuFVD+j+31LzbyqK8QuXZAeiHuo64zb5ySavBUEGtghpJecFLQ\/xeRgz4IhgsOf6Ye0MowDcZHxlrmPZ4A2z8zB0ysn2Y9cDDjMo+ZTNGDhrmeybtDSJsUKAMCVIpHTwrsQeXg9oU3g++13DXlr+h0pRv6PU0fyd9btDhOLYnpWg==","format":"piru-share","recipients":[{"enc":"yuveFrRjJb7ccWJpXW+ijGHHZ9dKaltEndmKQkyvw0o=","id":"9F8E7D6C-5B4A-4321-8FED-CBA987654321","sealedKey":"KCZaeB3vV2padrLBx+FSGO\/SpSCd838QYGiuLABHUUTvjCnnEnOQxBzV5as+CQBR"}],"sender":{"id":"0F1E2D3C-4B5A-4978-8695-A4B3C2D1E0F9","key":"fCcIuj+UAJqBsz1nCZLbq7biNcv7kkLflIhlRRMc53o="},"version":1}
    """#

    // MARK: - Pairing codes

    @Test
    func `A pairing code survives its link and rejects a broken one`() throws {
        let identity = ShareIdentity.make()
        let profile = PiruProfile.defaultOwner(name: "Kiri")
        let code = PairingCode(identity: identity, profile: profile)
        let parsed = try #require(PairingCode(url: code.url))
        #expect(parsed == code)

        let emoji = try PairingCode(personID: identity.personID, publicKey: code.publicKey, name: "Bo", avatar: #require(ProfileAvatar.emoji("🦊")))
        #expect(PairingCode(url: emoji.url)?.avatar.text == "🦊")

        var components = try #require(URLComponents(url: code.url, resolvingAgainstBaseURL: false))
        components.queryItems = components.queryItems?.map { $0.name == "k" ? URLQueryItem(name: "k", value: "AAAA") : $0 }
        #expect(try PairingCode(url: #require(components.url)) == nil)
        #expect(try PairingCode(url: #require(URL(string: "piru://journal"))) == nil)
    }

    @Test
    func `A code that gives a paired person a new key needs the explicit re-pair`() throws {
        let kiri = try Phone(ownerName: "Kiri")
        let bob = try Phone(ownerName: "Bob")
        try kiri.pair(with: bob)
        let original = try #require(kiri.directory.people.first).publicKey

        let real = try bob.code()
        let impostor = PairingCode(
            personID: real.personID, publicKey: ShareIdentity.make().publicKey.rawRepresentation,
            name: "Bob", avatar: real.avatar,
        )
        #expect(ShareReceiver.changesKey(impostor, directory: kiri.directory))
        #expect(throws: SessionSharingError.keyChanged(name: "Bob")) {
            try ShareReceiver.pair(with: impostor, directory: kiri.directory, identities: kiri.identities)
        }
        #expect(kiri.directory.people.first?.publicKey == original)

        try ShareReceiver.pair(with: impostor, replacingKey: true, directory: kiri.directory, identities: kiri.identities)
        #expect(kiri.directory.people.first?.publicKey == impostor.publicKey)
    }

    @Test
    func `Scanning your own code pairs nobody`() throws {
        let phone = try Phone(ownerName: "Kiri")
        #expect(throws: SessionSharingError.ownCode) { try ShareReceiver.pair(with: phone.code(), directory: phone.directory, identities: phone.identities) }
        #expect(phone.directory.people.isEmpty)
    }

    // MARK: - Across two phones

    @Test
    func `A shared night lands beside the receiver's session and replaces itself on a re-send`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let kiri = try Phone(ownerName: "Kiri")
        let bob = try Phone(ownerName: "Bob")
        try kiri.pair(with: bob)
        try bob.pair(with: kiri)
        let bobOnKiri = try #require(kiri.directory.people.first)

        let mine = try kiri.session(at: night, doses: [("2C-B", 15, 0), ("2C-B", 5, 1.5)])
        let his = try bob.session(at: night.addingTimeInterval(600), doses: [("LSD", 0.1, 0)])

        let sent = try await kiri.send(mine, to: [bobOnKiri])
        let opened = try bob.open(sent)
        #expect(opened.recipientProfileID == PiruProfile.ownerID)
        guard case let .paired(sender) = opened.sender else { Issue.record("Kiri should be paired"); return }
        #expect(sender.profile.name == "Kiri")
        let outcome = try ShareReceiver.accept(opened, directory: bob.directory)
        #expect(outcome.linkedSessionID == his.id)
        let experience = try #require(mine.sharedExperienceID)
        #expect(his.sharedExperienceID == experience)

        let store = SharedExperienceStore(directory: bob.directory) { _ in Int.random(in: 0 ... .max) }
        var participants = await store.participants(for: experience)
        #expect(participants.map(\.id) == [sender.id])
        #expect(participants.first?.snapshot.doses.map(\.amount) == [15, 5])
        // Their doses stay out of the receiver's own journal.
        #expect(try bob.context.fetchCount(FetchDescriptor<DoseEntry>()) == 1)

        // Kiri deletes the redose and sends again: Bob's copy follows.
        let redose = try #require(mine.orderedDoses.last)
        kiri.context.delete(redose)
        try kiri.context.save()
        let resent = try await kiri.send(mine, to: [bobOnKiri])
        try ShareReceiver.accept(bob.open(resent), directory: bob.directory)
        participants = await store.participants(for: experience)
        #expect(participants.first?.snapshot.doses.map(\.amount) == [15])
        let personStore = try #require(bob.directory.container(for: sender.id, writable: false))
        #expect(try personStore.mainContext.fetchCount(FetchDescriptor<Session>()) == 1)
    }

    @Test
    func `A share from someone unpaired pairs them on accept, so the receiver can share back`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let kiri = try Phone(ownerName: "Kiri")
        let bob = try Phone(ownerName: "Bob")
        try kiri.pair(with: bob)
        let mine = try kiri.session(at: night, doses: [("Caffeine", 100, 0)])
        let bobOnKiri = try #require(kiri.directory.people.first)

        let sent = try await kiri.send(mine, to: [bobOnKiri])
        let opened = try bob.open(sent)
        #expect(opened.sender == .new)
        let outcome = try ShareReceiver.accept(opened, directory: bob.directory)
        #expect(outcome.linkedSessionID == nil)
        #expect(bob.directory.people.map(\.profile.name) == ["Kiri"])

        // Bob can now seal to Kiri.
        let his = try bob.session(at: night, doses: [("Caffeine", 200, 0.2)])
        let reply = try await bob.send(his, to: bob.directory.people)
        let back = try kiri.open(reply)
        if case .paired = back.sender {} else { Issue.record("Bob should be paired on Kiri's phone") }
    }

    @Test
    func `A known person with a new key is refused`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let kiri = try Phone(ownerName: "Kiri")
        let bob = try Phone(ownerName: "Bob")
        try kiri.pair(with: bob)
        try bob.pair(with: kiri)
        let mine = try kiri.session(at: night, doses: [("Caffeine", 100, 0)])
        let bobOnKiri = try #require(kiri.directory.people.first)

        // Kiri's phone forgets its identity and mints a new one under the same person id.
        let identity = try kiri.identities.identity(for: PiruProfile.ownerID)
        let replacement = ShareIdentity(personID: identity.personID, privateKey: Curve25519.KeyAgreement.PrivateKey())
        let envelope = try ShareEnvelope.seal(
            Data("x".utf8), from: replacement, to: [(bobOnKiri.id, #require(bobOnKiri.key))],
        )
        #expect(throws: SessionSharingError.keyChanged(name: "Kiri")) { try bob.open(envelope.encoded()) }
        _ = mine
    }

    @Test
    func `A share sealed to someone else doesn't open`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let kiri = try Phone(ownerName: "Kiri")
        let bob = try Phone(ownerName: "Bob")
        let carol = try Phone(ownerName: "Carol")
        try kiri.pair(with: bob)
        let mine = try kiri.session(at: night, doses: [("Caffeine", 100, 0)])
        let data = try await kiri.send(mine, to: kiri.directory.people)
        #expect(throws: SessionSharingError.notForThisDevice) { try carol.open(data) }
    }
}
