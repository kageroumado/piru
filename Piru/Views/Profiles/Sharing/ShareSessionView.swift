import SwiftData
import SwiftUI

/// Session menu ▸ Share With: choose paired people, then send the sealed file
/// through the share sheet (AirDrop, Messages, any app).
struct ShareSessionView: View {
    let sessionID: UUID

    @Environment(\.profileDirectory) private var directory
    @Environment(\.appNavigator) private var navigator
    @Environment(\.modelContext) private var modelContext
    @State private var chosen: Set<UUID> = []
    @State private var file: URL?
    @State private var error: String?

    var body: some View {
        List {
            if ShareNameSection.isNeeded(directory.activeProfile) {
                ShareNameSection()
            }
            if directory.people.isEmpty {
                Section {
                    Text("Pair with someone first: you each scan the other's code, once, in person.")
                        .foregroundStyle(Theme.secondaryLabel)
                }
                .listRowBackground(CardBackground())
            } else {
                Section {
                    ForEach(directory.people) { person in
                        ShareRecipientRow(person: person, isChosen: chosen.contains(person.id)) {
                            if chosen.contains(person.id) { chosen.remove(person.id) } else { chosen.insert(person.id) }
                        }
                    }
                } footer: {
                    Text("Sends your doses, notes and body weight from this session, sealed so only they can open it.")
                }
                .listRowBackground(CardBackground())
            }

            Section {
                Button {
                    navigator.present(.pairing)
                } label: {
                    Label("Pair with Someone", systemImage: "qrcode")
                }
            }
            .listRowBackground(CardBackground())

            if let error {
                Section {
                    Text(verbatim: error)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                .listRowBackground(CardBackground())
            }
        }
        .themedPage()
        .navigationTitle("Share With")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if let file, !ShareNameSection.isNeeded(directory.activeProfile) {
                    ShareLink(item: file, preview: SharePreview(Text("Piru Session"))) {
                        Text("Send")
                    }
                } else {
                    Button("Send") {}
                        .disabled(true)
                }
            }
        }
        .task(id: PrepareKey(chosen: chosen, name: directory.activeProfile.name)) { await prepare() }
    }

    private func prepare() async {
        file = nil
        error = nil
        let people = directory.people.filter { chosen.contains($0.id) }
        guard !people.isEmpty, let session = session() else { return }
        do {
            file = try await ShareSender.prepare(session: session, to: people)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private struct PrepareKey: Hashable {
        let chosen: Set<UUID>
        let name: String
    }

    private func session() -> Session? {
        var descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == sessionID })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}

private struct ShareRecipientRow: View {
    let person: PiruPerson
    let isChosen: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: Spacing.lg) {
                ProfileAvatarView(person.profile, diameter: 32)
                Text(verbatim: person.profile.name)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isChosen ? Theme.accent : Theme.secondaryLabel)
                    .imageScale(.large)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}

/// Settings ▸ Profiles ▸ People: everyone paired from another phone, and the
/// way to pair with someone new.
struct PeopleSection: View {
    @Environment(\.profileDirectory) private var directory
    @Environment(\.appNavigator) private var navigator
    @State private var unpairing: PiruPerson?

    var body: some View {
        Section {
            ForEach(directory.people) { person in
                HStack(spacing: Spacing.lg) {
                    ProfileAvatarView(person.profile, diameter: 36)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(verbatim: person.profile.name)
                        Text("Paired \(person.pairedAt.formatted(date: .abbreviated, time: .omitted))")
                            .captionSecondary()
                    }
                }
                .padding(.vertical, Spacing.xxs)
                .swipeActions {
                    Button("Unpair", role: .destructive) { unpairing = person }
                }
                .contextMenu {
                    Button("Unpair", role: .destructive) { unpairing = person }
                }
            }
            Button {
                navigator.present(.pairing)
            } label: {
                Label("Pair with Someone", systemImage: "qrcode")
            }
        } header: {
            Text("People")
        } footer: {
            Text("People on other phones you share sessions with. Unpairing removes the sessions they sent.")
        }
        .listRowBackground(CardBackground())
        .confirmationDialog(
            Text("Unpair \(unpairing?.profile.name ?? "")?"),
            isPresented: Binding(get: { unpairing != nil }, set: { if !$0 { unpairing = nil } }),
            titleVisibility: .visible,
            presenting: unpairing,
        ) { person in
            Button("Unpair", role: .destructive) {
                try? directory.removePerson(id: person.id)
                SharedExperienceStore.shared.invalidate()
                DoseLogService.shared.changed()
            }
        } message: { person in
            Text("The sessions \(person.profile.name) sent are removed from this phone.")
        }
    }
}
