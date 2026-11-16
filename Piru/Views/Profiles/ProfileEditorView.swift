import SwiftUI

/// What the editor is changing, held in one place so the fields below are
/// separate views that each read only their part.
@Observable
@MainActor
final class ProfileDraft {
    /// What the avatar shows; the editor's segmented control.
    enum Style: Hashable {
        case monogram
        case emoji
        case photo
    }

    var name: String
    var style: Style
    /// The letters typed for a monogram; empty means "from the name".
    var letters: String
    var emoji: String
    /// The photo's file in ``ProfilePhotoStore``, kept while another style
    /// is chosen so switching back finds it.
    var photo: String?
    var color: ProfileColor
    /// The owner's name, asked for while adding someone when the owner still
    /// carries the default "Me", since every other journal shows the owner
    /// by it ("With Me and Bob"). `nil` when the owner already has a name.
    var ownerName: String?

    init(profile: PiruProfile?, defaultColor: ProfileColor) {
        let avatar = profile?.avatar
        name = profile?.name ?? ""
        style = avatar?.photo != nil ? .photo : avatar?.kind == .emoji ? .emoji : .monogram
        letters = avatar?.kind == .monogram ? avatar?.text ?? "" : ""
        emoji = avatar?.kind == .emoji ? avatar?.text ?? "" : ""
        photo = avatar?.photo
        color = profile?.color ?? defaultColor
    }

    /// Under a photo, the emoji or letters last chosen, for wherever the
    /// photo can't draw.
    var avatar: ProfileAvatar {
        let letterAvatar = letters.isEmpty ? ProfileAvatar.monogram(for: name) : .monogram(text: letters)
        switch style {
        case .emoji:
            return ProfileAvatar.emoji(emoji) ?? .monogram(for: name)
        case .monogram:
            return letterAvatar
        case .photo:
            return (ProfileAvatar.emoji(emoji) ?? letterAvatar).withPhoto(photo)
        }
    }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Add a person, or change one: name, monogram or emoji, color. A profile
/// other than the owner can be deleted here, with its journal.
struct ProfileEditorView: View {
    /// `nil` adds a new profile.
    let editing: PiruProfile?

    @Environment(\.profileDirectory) private var directory
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProfileDraft?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let draft {
                ProfileEditorForm(draft: draft, editing: editing, onDeleted: { dismiss() })
            } else {
                // A view to hang the title and `.task` on: an empty Group
                // takes neither.
                Color.clear
            }
        }
        .themedPage()
        .navigationTitle(editing == nil ? Text("New Profile") : Text(verbatim: editing?.name ?? ""))
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: save) {
                    editing == nil ? Text("Add") : Text("Save")
                }
                .disabled(!(draft?.canSave ?? false))
            }
        }
        .alert("Couldn't Save Profile", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } },
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            if draft == nil {
                let new = ProfileDraft(profile: editing, defaultColor: .next(after: directory.profiles.map(\.color)))
                if editing == nil, directory.owner.name == ProfileRegistry.defaultOwnerName {
                    new.ownerName = ""
                }
                draft = new
            }
        }
    }

    /// Gives the owner the name typed in "Your Name"; the default monogram
    /// follows the new name, a chosen one stays.
    private func renameOwner(to name: String?) throws {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return }
        var owner = directory.owner
        if owner.avatar == .monogram(for: owner.name) {
            owner.avatar = .monogram(for: trimmed)
        }
        owner.name = trimmed
        try directory.update(owner)
    }

    private func save() {
        guard let draft else { return }
        do {
            if var profile = editing {
                profile.name = draft.name
                profile.avatar = draft.avatar
                profile.color = draft.color
                try directory.update(profile)
            } else {
                try renameOwner(to: draft.ownerName)
                try directory.addProfile(name: draft.name, avatar: draft.avatar, color: draft.color)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The editor's sections.
private struct ProfileEditorForm: View {
    @Bindable var draft: ProfileDraft
    let editing: PiruProfile?
    let onDeleted: () -> Void
    @FocusState private var nameFocused: Bool

    var body: some View {
        List {
            Group {
                Section {
                    HStack {
                        Spacer()
                        ProfileAvatarView(avatar: draft.avatar, color: draft.color, diameter: 72)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Name") {
                    TextField("Name", text: $draft.name)
                        .wordsAutocapitalize()
                        .focused($nameFocused)
                }
                AvatarSection(draft: draft)
                ColorSection(selection: $draft.color)
                if draft.ownerName != nil {
                    OwnerNameSection(draft: draft)
                }
                if let editing, !editing.isOwner {
                    DeleteProfileSection(profile: editing, onDeleted: onDeleted)
                }
            }
            .listRowBackground(CardBackground())
        }
        // A new person starts at their name.
        .task { if editing == nil { nameFocused = true } }
    }
}

private struct AvatarSection: View {
    @Bindable var draft: ProfileDraft

    var body: some View {
        Section {
            Picker("Avatar", selection: $draft.style) {
                Text("Letters").tag(ProfileDraft.Style.monogram)
                Text("Emoji").tag(ProfileDraft.Style.emoji)
                #if !os(Android)
                    Text("Photo").tag(ProfileDraft.Style.photo)
                #endif
            }
            .pickerStyle(.segmented)
            switch draft.style {
            case .photo:
                #if !os(Android)
                    ProfilePhotoPickerRow(photo: $draft.photo)
                #endif
            case .monogram:
                TextField("From the name", text: $draft.letters)
                    .neverAutocapitalize()
                    .onChange(of: draft.letters) { _, letters in
                        let trimmed = String(letters.filter { $0.isLetter || $0.isNumber }.prefix(2))
                        if trimmed != letters { draft.letters = trimmed }
                    }
            case .emoji:
                #if os(iOS) || os(macOS)
                    EmojiTextField(text: $draft.emoji, placeholder: String(localized: "One emoji"))
                #else
                    TextField("One emoji", text: $draft.emoji)
                        .onChange(of: draft.emoji) { _, text in
                            let one = ProfileAvatar.emoji(text)?.text ?? ""
                            if one != text { draft.emoji = one }
                        }
                #endif
            }
        } header: {
            Text("Avatar")
        }
    }
}

/// The eight profile colors as swatches, the chosen one ringed.
private struct ColorSection: View {
    @Binding var selection: ProfileColor

    var body: some View {
        Section("Color") {
            HStack(spacing: 0) {
                ForEach(ProfileColor.allCases, id: \.self) { color in
                    Button {
                        selection = color
                    } label: {
                        Circle()
                            .fill(color.p3.color)
                            .frame(width: 28, height: 28)
                            .padding(Spacing.xs)
                            .overlay {
                                if color == selection {
                                    Circle().strokeBorder(Theme.accent, lineWidth: 2)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(color.name))
                    .accessibilityAddTraits(color == selection ? .isSelected : [])
                }
            }
        }
    }
}

private struct DeleteProfileSection: View {
    let profile: PiruProfile
    let onDeleted: () -> Void
    @State private var confirming = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            Button("Delete Profile", role: .destructive) { confirming = true }
        }
        .confirmationDialog(
            Text("Delete \(profile.name)?"),
            isPresented: $confirming,
            titleVisibility: .visible,
        ) {
            Button("Delete \(profile.name) and Their Journal", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(profile.name)'s journal goes with the profile: every dose, session, note and med logged for them.")
        }
        .alert("Couldn't Delete Profile", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } },
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func delete() {
        Task(name: "Delete profile") {
            do {
                try await ProfileSwitcher.delete(profile.id)
                onDeleted()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

extension ProfileColor {
    /// The color's name, for VoiceOver.
    var name: LocalizedStringKey {
        switch self {
        case .rose: "Rose"
        case .plum: "Plum"
        case .violet: "Violet"
        case .indigo: "Indigo"
        case .ocean: "Ocean"
        case .teal: "Teal"
        case .forest: "Forest"
        case .amber: "Amber"
        }
    }
}

/// "Your Name", shown while adding someone when the owner is still "Me".
private struct OwnerNameSection: View {
    @Bindable var draft: ProfileDraft

    var body: some View {
        Section {
            TextField("Your Name", text: Binding(
                get: { draft.ownerName ?? "" }, set: { draft.ownerName = $0 },
            ))
            .wordsAutocapitalize()
        } header: {
            Text("Your Name")
        } footer: {
            Text("Other profiles show you by this name.")
        }
    }
}
