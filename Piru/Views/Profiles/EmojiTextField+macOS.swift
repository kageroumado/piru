import AppKit
import SwiftUI

/// A one-emoji field that opens the Character Viewer when it appears. Typing
/// another emoji replaces the one there.
struct EmojiTextField: View {
    @Binding var text: String
    let placeholder: String

    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .focused($focused)
            .onChange(of: text) { _, new in
                let newest = new.last(where: \.isEmojiGlyph).map(String.init) ?? ""
                if newest != new { text = newest }
            }
            .task {
                focused = true
                NSApp.orderFrontCharacterPalette(nil)
            }
    }
}
