import SwiftUI

// MARK: - Pinned search bar

/// The single pinned field — present in every detent, so SwiftUI animates it
/// in place as the sheet resizes and the content morphs beneath it. A clear
/// button trails the field once text exists; a full-size glass cancel appears
/// beside the field while searching. Dictation is the keyboard's own mic key —
/// the app never touches the microphone.
///
/// `searchFocused` stays owned by ``QuickLogDock`` (its handlers release focus
/// on cancel, detent drags, and custom-substance presentation), so it arrives
/// as a `@FocusState.Binding` rather than being declared here.
struct DockSearchBar: View {
    @Binding var searchText: String
    let searchActive: Bool
    @FocusState.Binding var searchFocused: Bool
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.secondaryLabel)
                    .accessibilityHidden(true)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                #if canImport(UIKit)
                    .textInputAutocapitalization(.never)
                #endif
                    .focused($searchFocused)
                    .accessibilityLabel("Search substances")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: QuickLogDockMetrics.fieldHeight)
            .background(Color.platformSecondarySystemFill, in: Capsule())

            if searchActive {
                // Same fill and height as the field — the pair reads as one
                // control system, not two materials (glass here clashed with
                // the field's flat fill and shrank the glyph).
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .screenTitle()
                        .foregroundStyle(Theme.secondaryLabel)
                        .frame(width: QuickLogDockMetrics.fieldHeight, height: QuickLogDockMetrics.fieldHeight)
                        .background(Color.platformSecondarySystemFill, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel search")
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: searchActive)
        .animation(.snappy, value: searchText.isEmpty)
    }
}
