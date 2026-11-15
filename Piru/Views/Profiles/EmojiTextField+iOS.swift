import SwiftUI
import UIKit

/// A one-emoji field that opens on the emoji keyboard and takes focus when it
/// appears. Typing another emoji replaces the one there.
struct EmojiTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeUIView(context: Context) -> EmojiInputTextField {
        let field = EmojiInputTextField()
        field.placeholder = placeholder
        field.text = text
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.autocorrectionType = .no
        field.returnKeyType = .done
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // After the segmented control's switch has laid the field out.
        Task { @MainActor in field.becomeFirstResponder() }
        return field
    }

    func updateUIView(_ field: EmojiInputTextField, context _: Context) {
        if field.text != text { field.text = text }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        @objc
        func changed(_ field: UITextField) {
            // The newest emoji wins, so a second tap on the keyboard swaps it.
            let newest = (field.text ?? "").last(where: \.isEmojiGlyph).map(String.init) ?? ""
            if field.text != newest { field.text = newest }
            text.wrappedValue = newest
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            field.resignFirstResponder()
        }
    }
}

/// A text field whose keyboard is the emoji keyboard. `textInputMode` is the
/// one public way to choose a keyboard; the identifier keeps the choice from
/// being remembered as the system default.
final class EmojiInputTextField: UITextField {
    override var textInputContextIdentifier: String? {
        ""
    }

    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }
}
