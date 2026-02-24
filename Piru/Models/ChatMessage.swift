import Foundation
import SwiftData

@Model
final class ChatMessage {
    var id: UUID
    var role: String
    var content: String
    var timestamp: Date
    var model: String?
    var conversationID: UUID

    init(
        role: String,
        content: String,
        model: String? = nil,
        conversationID: UUID
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = .now
        self.model = model
        self.conversationID = conversationID
    }
}
