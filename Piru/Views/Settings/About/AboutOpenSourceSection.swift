import SwiftUI

private enum AboutCodeLinks {
    static let repository = URL(string: "https://github.com/kageroumado/piru")!
}

/// Piru's own license, linking to the repository.
struct AboutOpenSourceSection: View {
    var body: some View {
        Section {
            Link(destination: AboutCodeLinks.repository) {
                CaptionedRowLabel(
                    title: "Open Source",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    caption: Text("Piru's source code is available under the GNU GPL v3."),
                )
            }
        }
    }
}
