import Foundation
import SwiftData
import SwiftUI

@Model
final class UserColor {
    @Attribute(.unique) var hex: String
    var name: String
    var createdAt: Date

    init(hex: String, name: String) {
        self.hex = hex
        self.name = name
        self.createdAt = .now
    }

    var color: Color { Color(hex: hex) }
}
