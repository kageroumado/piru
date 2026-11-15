import SwiftUI

/// "For [avatar] Me": whose journal the staged doses go into, shown once a
/// second profile exists. Picking someone else lasts for this one log; the
/// next quick log starts on the active profile again.
struct TrayRecipientRow: View {
    @Bindable var model: DoseTrayModel
    @Environment(\.profileDirectory) private var directory

    var body: some View {
        if directory.hasMultipleProfiles {
            let recipient = directory.profile(id: model.recipientID ?? directory.activeProfileID) ?? directory.activeProfile
            let isOther = recipient.id != directory.activeProfileID
            HStack(spacing: Spacing.md) {
                Text("For")
                    .sectionLabel()
                    .foregroundStyle(Theme.secondaryLabel)
                    .accessibilityHidden(true)
                TrayRecipientChip(recipient: recipient, isOther: isOther, selection: selection)
                if isOther {
                    Text("Goes into \(recipient.name)'s journal")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.snappy, value: model.recipientID)
            .sensoryFeedback(.selection, trigger: model.recipientID)
        }
    }

    private var selection: Binding<UUID> {
        Binding(
            get: { model.recipientID ?? directory.activeProfileID },
            set: { model.recipientID = $0 == directory.activeProfileID ? nil : $0 },
        )
    }
}

/// The chip: the recipient's avatar and name ("Me" for the active profile),
/// tinted while it names someone else. The Menu is overlaid as the tap target
/// so the chip's width animates in one SwiftUI pass, as the When chip does.
private struct TrayRecipientChip: View {
    let recipient: PiruProfile
    let isOther: Bool
    @Binding var selection: UUID
    @Environment(\.profileDirectory) private var directory

    var body: some View {
        HStack(spacing: 6) {
            ProfileAvatarView(recipient, diameter: 22)
            Text(isOther ? recipient.name : String(localized: "Me"))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
        }
        .sectionLabel()
        .fixedSize()
        .padding(.leading, 4)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .background(
            isOther ? AnyShapeStyle(Theme.accent.opacity(Theme.Opacity.tint)) : AnyShapeStyle(Color.platformSecondarySystemFill),
            in: Capsule(),
        )
        .foregroundStyle(isOther ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary))
        .accessibilityHidden(true)
        .overlay {
            Menu {
                Picker(selection: $selection) {
                    ForEach(directory.profiles) { profile in
                        // Names, never "Me": the owner is named Me until renamed,
                        // so a second "Me" for the active profile would read twice.
                        Label {
                            Text(verbatim: profile.name)
                        } icon: {
                            ProfileAvatarImage.image(for: profile)
                        }
                        .tag(profile.id)
                    }
                } label: {
                    Text("Log For")
                }
                .pickerStyle(.inline)
            } label: {
                Color.clear.contentShape(Capsule())
            }
            .menuOrder(.fixed)
            .accessibilityLabel(Text("Log for: \(isOther ? recipient.name : String(localized: "Me"))"))
            .accessibilityInputLabels([Text("Log for"), Text("For")])
        }
    }
}
