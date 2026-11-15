import SwiftData
import SwiftUI

extension EnvironmentValues {
    @Entry var profileDirectory: ProfileDirectory = .shared
}

/// Hands the active profile's store to everything below it, and rebuilds that
/// whole tree when the active profile changes: every `@Query`, `@State` and
/// view model is made again against the new store, so nothing on screen can
/// still show the previous person's journal.
struct ProfileRoot<Content: View>: View {
    @Environment(\.profileDirectory) private var directory
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .id(directory.activeProfileID)
            .modelContainer(directory.activeContainer)
    }
}
