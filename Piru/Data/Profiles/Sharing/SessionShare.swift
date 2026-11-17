import Foundation

/// What one person sends: who they are and their side of one shared
/// experience. The receiver replaces everything it had from them for that
/// experience with this, so a re-send after more doses updates in place and a
/// dose deleted on their phone disappears here.
nonisolated struct SessionShare: Codable, Equatable, Sendable {
    static let version = 1

    /// How the sender shows on the receiving phone. The receiver picks its own
    /// color for them.
    struct Card: Codable, Equatable, Sendable {
        let name: String
        let avatar: ProfileAvatar
    }

    struct Side: Codable, Equatable, Sendable {
        let experienceID: UUID
        /// The sender's session id: the receiver stores their side under it,
        /// so every re-send lands on the same session.
        let sessionID: UUID
        let title: String?
        let summary: String?
        let startDate: Date
        let doses: [SharedDoseSnapshot]
        let notes: [SharedNoteSnapshot]
        /// Their body weight, for their curve.
        let weightKg: Double?
    }

    let version: Int
    let sentAt: Date
    let sender: Card
    let side: Side

    init(sender: Card, side: Side, sentAt: Date = .now) {
        version = Self.version
        self.sentAt = sentAt
        self.sender = sender
        self.side = side
    }

    init(sender: Card, snapshot: SharedSessionSnapshot, experienceID: UUID, sentAt: Date = .now) {
        self.init(
            sender: sender,
            side: Side(
                experienceID: experienceID,
                sessionID: snapshot.sessionID,
                title: snapshot.title,
                summary: snapshot.summary,
                startDate: snapshot.startDate,
                doses: snapshot.doses,
                notes: snapshot.notes,
                weightKg: snapshot.weightKg,
            ),
            sentAt: sentAt,
        )
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> SessionShare {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SessionShare.self, from: data)
    }
}
