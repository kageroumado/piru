import SwiftUI

/// "Bob's · ~3 doses left" under a shared-in item's title: the owner's avatar
/// and name, then the row's own detail when it has one.
struct SharedOwnerTag: View {
    let owner: PiruProfile
    var detail: String?

    /// "Bob's", or "Shared" for an owner still called by the default "Me",
    /// which would read as the viewer in a possessive.
    static func attribution(for owner: PiruProfile) -> String {
        owner.isOwner && owner.name == ProfileRegistry.defaultOwnerName
            ? String(localized: "Shared")
            : String(localized: "\(owner.name)'s")
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ProfileAvatarView(owner, diameter: 18)
            Group {
                if let detail {
                    Text(verbatim: "\(Self.attribution(for: owner)) · \(detail)")
                } else {
                    Text(verbatim: Self.attribution(for: owner))
                }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.secondaryLabel)
            .lineLimit(1)
        }
    }
}

/// The editor's "Shared with" section: every other profile, each with its
/// avatar and a checkmark when it draws from this stock. Shown to the owner
/// only, and only once there is someone to share with.
struct InventorySharingSection: View {
    let others: [PiruProfile]
    @Binding var selection: Set<UUID>

    var body: some View {
        Section {
            ForEach(others) { profile in
                Button {
                    if selection.contains(profile.id) {
                        selection.remove(profile.id)
                    } else {
                        selection.insert(profile.id)
                    }
                } label: {
                    HStack(spacing: Spacing.md) {
                        ProfileAvatarView(profile, diameter: 26)
                        Text(verbatim: profile.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selection.contains(profile.id) {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection.contains(profile.id) ? .isSelected : [])
            }
        } header: {
            Text("Shared with")
        } footer: {
            Text("Their doses come off this stock too. Only you can change who shares it or delete it.")
        }
        .listRowBackground(CardBackground())
    }
}

/// Who draws from a shared item, under its amount: the owner's avatar and
/// name on a shared-in item, or the people it is shared with on the owner's.
struct SharedStockLine: View {
    let owner: PiruProfile?
    let sharees: [PiruProfile]

    var body: some View {
        if let owner {
            HStack(spacing: Spacing.xs) {
                ProfileAvatarView(owner, diameter: 18)
                Group {
                    if owner.isOwner, owner.name == ProfileRegistry.defaultOwnerName {
                        Text("Shared with you")
                    } else {
                        Text("Shared by \(owner.name)")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .lineLimit(1)
            }
        } else if !sharees.isEmpty {
            HStack(spacing: Spacing.xs) {
                HStack(spacing: -6) {
                    ForEach(sharees) { profile in
                        ProfileAvatarView(profile, diameter: 18)
                    }
                }
                Text("Shared with \(sharees.map(\.name).formatted(.list(type: .and)))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(1)
            }
        }
    }
}
