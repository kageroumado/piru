import SwiftData
import SwiftUI

/// Session menu ▸ Add People: the other profiles, each linkable by the session
/// they logged around the same time. Someone with no such session gets a plain
/// line saying so, and nothing else.
struct AddPeopleView: View {
    let sessionID: UUID

    @Environment(\.profileDirectory) private var directory
    @Environment(\.modelContext) private var modelContext
    @State private var model = AddPeopleModel()

    var body: some View {
        List {
            Section {
                ForEach(directory.profiles.filter { $0.id != directory.activeProfileID }) { profile in
                    AddPersonRow(
                        profile: profile,
                        state: model.states[profile.id] ?? .unknown,
                        onAdd: { model.add(profile.id, sessionID: sessionID, context: modelContext) },
                    )
                }
            } footer: {
                Text("Links the session each person logged around the same time.")
            }
        }
        .insetGroupedListStyle()
        .navigationTitle(Text("Add People"))
        .inlineNavigationTitle()
        .task { model.load(sessionID: sessionID, context: modelContext) }
        .alert(
            "Couldn't Add",
            isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } }),
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: model.error ?? "")
        }
    }
}

/// What the Add People sheet knows about each person and does on a tap.
@Observable
@MainActor
final class AddPeopleModel {
    enum PersonState: Equatable {
        case unknown
        case inSession
        case noOverlap
    }

    var states: [UUID: PersonState] = [:]
    var error: String?

    func load(sessionID: UUID, context: ModelContext) {
        guard let experience = session(sessionID, in: context)?.sharedExperienceID else { return }
        for profile in ProfileDirectory.shared.profiles where SharedExperienceLinker.isLinked(profile.id, to: experience) {
            states[profile.id] = .inSession
        }
    }

    func add(_ profileID: UUID, sessionID: UUID, context: ModelContext) {
        guard let session = session(sessionID, in: context) else { return }
        do {
            switch try SharedExperienceLinker.add(profileID, to: session) {
            case .linked, .alreadyLinked: states[profileID] = .inSession
            case .noOverlap: states[profileID] = .noOverlap
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func session(_ id: UUID, in context: ModelContext) -> Session? {
        var descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

private struct AddPersonRow: View {
    let profile: PiruProfile
    let state: AddPeopleModel.PersonState
    let onAdd: () -> Void

    var body: some View {
        Button {
            if state != .inSession { onAdd() }
        } label: {
            HStack(spacing: Spacing.lg) {
                ProfileAvatarView(profile, diameter: 30)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(verbatim: profile.name)
                        .foregroundStyle(.primary)
                    if state == .noOverlap {
                        Text("\(profile.name) has no session around this time.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
                Spacer(minLength: Spacing.md)
                if state == .inSession {
                    Text("In this session")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(state == .inSession ? .isSelected : [])
    }
}
