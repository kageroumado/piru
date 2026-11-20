import Foundation

extension AttributedString {
    /// Curated prose with inline Markdown emphasis (`**bold**`), parsed; the
    /// string as plain text when it does not parse.
    nonisolated init(markdownOrPlain text: String) {
        self = (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}
