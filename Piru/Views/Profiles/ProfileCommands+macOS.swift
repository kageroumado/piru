import SwiftUI

/// The Mac's Profiles menu: everyone on the device, the active one checked,
/// ⌃1–⌃9 for the first nine. Shown only while there is more than one profile.
struct ProfileCommands: Commands {
    let directory: ProfileDirectory

    var body: some Commands {
        CommandMenu("Profiles") {
            if directory.hasMultipleProfiles {
                ForEach(Array(directory.profiles.prefix(9).enumerated()), id: \.element.id) { index, profile in
                    Toggle(isOn: Binding(
                        get: { directory.activeProfileID == profile.id },
                        set: { isOn in
                            guard isOn else { return }
                            Task(name: "Switch profile") { await ProfileSwitcher.switchTo(profile.id) }
                        },
                    )) {
                        Text(verbatim: profile.name)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .control)
                }
                Divider()
            }
            Button("Manage Profiles…") {
                guard AppNavigator.shared.sheetStack.isEmpty else { return }
                AppNavigator.shared.present(.profiles)
            }
        }
    }
}
