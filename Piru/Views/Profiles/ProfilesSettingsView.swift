import SwiftUI

/// Settings ▸ Profiles: everyone on this device, each with their own journal.
/// A row opens that person's editor; + adds someone.
struct ProfilesSettingsView: View {
    @Environment(\.profileDirectory) private var directory
    @State private var addingProfile = false

    var body: some View {
        List {
            Section {
                ForEach(directory.profiles) { profile in
                    NavigationLink {
                        ProfileEditorView(editing: profile)
                    } label: {
                        ProfileRow(profile: profile)
                    }
                }
            } footer: {
                Text("Each profile is its own journal. Deleting one deletes its journal.")
            }
            .listRowBackground(CardBackground())
        }
        .themedPage()
        .navigationTitle("Profiles")
        .inlineNavigationTitle()
        .navigationDestination(isPresented: $addingProfile) {
            ProfileEditorView(editing: nil)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addingProfile = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("Add Profile"))
            }
        }
    }
}

/// One person: avatar, name, and for the owner what only the owner has.
private struct ProfileRow: View {
    let profile: PiruProfile

    var body: some View {
        HStack(spacing: Spacing.lg) {
            ProfileAvatarView(profile, diameter: 36)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: profile.name)
                if profile.isOwner {
                    Text("This device · Apple Health")
                        .captionSecondary()
                }
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
}
