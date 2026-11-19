import SwiftUI

/// How each of a backup's profiles comes back, asked before the restore
/// touches anything: one row per profile that looks different here, or that
/// is another device's own profile.
struct ProfileRestoreSheet: View {
    let conflicts: [ProfileRestoreConflict]
    let onFinish: ([UUID: ProfileRestoreChoice]?) -> Void
    @State private var choices: [UUID: ProfileRestoreChoice] = [:]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(conflicts) { conflict in
                        ProfileRestoreConflictRow(conflict: conflict, choice: binding(for: conflict))
                    }
                } footer: {
                    Text("Profiles match by ID, so a renamed profile is still the same person. Pick how each one comes back.")
                }
            }
            .themedPage()
            .navigationTitle("Restore Profiles")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onFinish(nil)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onFinish(choices)
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Restore")
                }
            }
        }
        // A swipe-down is a cancel, so the restore waiting on the answer hears
        // back either way. The request is answered directly: the presenter has
        // already closed the sheet.
        .onDisappear { ProfileRestoreRequest.shared.finish(nil) }
    }

    private func binding(for conflict: ProfileRestoreConflict) -> Binding<ProfileRestoreChoice> {
        Binding(
            get: { choices[conflict.id] ?? conflict.choices[0] },
            set: { choices[conflict.id] = $0 },
        )
    }
}

private struct ProfileRestoreConflictRow: View {
    let conflict: ProfileRestoreConflict
    @Binding var choice: ProfileRestoreChoice

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                ProfileAvatarView(conflict.incoming, diameter: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: conflict.incoming.name)
                    caption.captionSecondary()
                }
            }
            Picker(selection: $choice) {
                ForEach(conflict.choices, id: \.self) { choice in
                    label(for: choice).tag(choice)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .listRowBackground(CardBackground())
    }

    private var caption: Text {
        switch conflict.kind {
        case .details: Text("Here: \(conflict.local.name)")
        case .otherOwner: Text("From another device")
        }
    }

    private func label(for choice: ProfileRestoreChoice) -> Text {
        switch (conflict.kind, choice) {
        case (.details, .keepThisDevice): Text("Keep This Device's")
        case (.details, _): Text("Use the Backup's")
        case (.otherOwner, .keepThisDevice): Text("Into Your Journal")
        case (.otherOwner, .useBackup): Text("Into Your Journal as \(conflict.incoming.name)")
        case (.otherOwner, .newProfile): Text("As a New Profile")
        }
    }
}

/// Presents the profile question during onboarding, whose cover hides the
/// sheet stack the rest of the app uses.
struct OnboardingProfileRestorePresenter: ViewModifier {
    @State private var request = ProfileRestoreRequest.shared

    func body(content: Content) -> some View {
        content.sheet(item: Binding(
            get: { request.pending.flatMap { $0.presentsInOnboarding ? $0 : nil } },
            set: { if $0 == nil { request.finish(nil) } },
        )) { pending in
            ProfileRestoreSheet(conflicts: pending.conflicts) { request.finish($0) }
        }
    }
}
