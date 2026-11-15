import SwiftData
import SwiftUI

/// Whose journal each person in a PsychonautWiki file goes into: the file's
/// unnamed owner is you, and every named person maps to a profile, a new
/// profile, or Skip. Each experience then imports as one session per person,
/// linked as shared (``DataExportImport/importPsyLog(data:context:customStore:routing:)``).
struct PsyLogImportSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appNavigator) private var navigator
    @Environment(\.profileDirectory) private var directory
    @State private var model = PsyLogImportModel(
        pending: PsyLogImportRequest.current?.pending,
        profiles: ProfileDirectory.shared.profiles,
    )

    var body: some View {
        NavigationStack {
            List {
                if let pending = model.pending {
                    PsyLogImportSummary(
                        peopleCount: pending.consumers.count,
                        experienceCount: pending.experienceCount,
                    )
                    Section {
                        ForEach(pending.consumers) { consumer in
                            PsyLogConsumerRow(
                                consumer: consumer,
                                target: model.binding(for: consumer),
                            )
                        }
                    } header: {
                        Text("Put each person's doses in")
                    } footer: {
                        Text("Doses taken together become one shared session per person. A person set to Skip is left out.")
                    }
                }
            }
            .themedPage()
            .navigationTitle("Import")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        PsyLogImportRequest.finish(.cancelled)
                        navigator.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        runImport()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Import")
                    .disabled(!model.importsAnything || model.isImporting)
                }
            }
        }
        .interactiveDismissDisabled(model.isImporting)
        // A swipe-down is a cancel, so the screen that picked the file hears
        // back either way.
        .onDisappear { PsyLogImportRequest.finish(.cancelled) }
    }

    private func runImport() {
        if let message = model.run(context: modelContext, directory: directory) {
            PsyLogImportRequest.finish(.failed(message))
        } else {
            PsyLogImportRequest.finish(.imported)
        }
        navigator.dismiss()
    }
}

/// The choices on the people sheet, and the import they settle into.
@Observable
@MainActor
final class PsyLogImportModel {
    let pending: PsyLogPendingImport?
    /// Each named person's choice by ``PsyLogConsumer/key``.
    private(set) var choices: [String: PsyLogConsumerTarget]
    private(set) var isImporting = false

    init(pending: PsyLogPendingImport?, profiles: [PiruProfile]) {
        self.pending = pending
        choices = PsyLogImportMapping.defaults(for: pending?.consumers ?? [], profiles: profiles)
    }

    /// Whether the import would bring in anything: the owner always imports;
    /// named people only when not skipped.
    var importsAnything: Bool {
        pending?.consumers.contains { consumer in
            guard let key = consumer.key else { return true }
            return choices[key] != .skip
        } ?? false
    }

    func binding(for consumer: PsyLogConsumer) -> Binding<PsyLogConsumerTarget>? {
        guard let key = consumer.key else { return nil }
        return Binding(
            get: { self.choices[key] ?? .skip },
            set: { self.choices[key] = $0 },
        )
    }

    /// Creates the new profiles asked for and imports into every chosen store.
    /// Returns the failure to show, or `nil` on success.
    func run(context: ModelContext, directory: ProfileDirectory) -> String? {
        guard let pending, !isImporting else { return nil }
        isImporting = true
        defer { isImporting = false }
        do {
            let routing = try PsyLogImportMapping.routing(for: choices, consumers: pending.consumers, directory: directory)
            try DataExportImport.importJSON(data: pending.data, context: context, psyLogRouting: routing)
            DataExportImport.refreshLiveStores(container: context.container)
            return nil
        } catch {
            return DataExportImport.importErrorMessage(for: error)
        }
    }
}

// MARK: - Sections

private struct PsyLogImportSummary: View {
    let peopleCount: Int
    let experienceCount: Int

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(peopleCount == 1 ? "This file has doses for one person" : "This file has doses for \(peopleCount) people")
                    .cardTitle()
                Text("^[\(experienceCount) experience](inflect: true)")
                    .captionSecondary()
            }
            .padding(.vertical, Spacing.xs)
            .listRowBackground(CardBackground())
        }
    }
}

/// One person in the file: their name (or Unnamed, for the file's owner),
/// how many doses they have, and where those doses go.
private struct PsyLogConsumerRow: View {
    let consumer: PsyLogConsumer
    /// `nil` for the owner, whose doses always go into the active profile.
    let target: Binding<PsyLogConsumerTarget>?
    @Environment(\.profileDirectory) private var directory

    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                if let name = consumer.name {
                    Text(verbatim: name)
                } else {
                    Text("Unnamed")
                }
                Text("^[\(consumer.doseCount) dose](inflect: true)")
                    .captionSecondary()
            }
            Spacer(minLength: Spacing.md)
            if let target {
                PsyLogTargetMenu(name: consumer.name ?? "", target: target)
            } else {
                HStack(spacing: Spacing.sm) {
                    ProfileAvatarView(directory.activeProfile, diameter: 22)
                    Text("You")
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
        .listRowBackground(CardBackground())
        .accessibilityElement(children: .combine)
    }
}

/// The choice for one named person: any profile, a new one, or Skip.
private struct PsyLogTargetMenu: View {
    let name: String
    @Binding var target: PsyLogConsumerTarget
    @Environment(\.profileDirectory) private var directory

    var body: some View {
        Menu {
            Picker(selection: $target) {
                ForEach(directory.profiles) { profile in
                    Label {
                        Text(verbatim: profile.name)
                    } icon: {
                        ProfileAvatarImage.image(for: profile)
                    }
                    .tag(PsyLogConsumerTarget.profile(profile.id))
                }
            } label: {
                Text("Profiles")
            }
            .pickerStyle(.inline)
            Picker(selection: $target) {
                Label("New Profile", systemImage: "person.crop.circle.badge.plus")
                    .tag(PsyLogConsumerTarget.newProfile)
                Label("Skip", systemImage: "nosign")
                    .tag(PsyLogConsumerTarget.skip)
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            label
        }
        .menuOrder(.fixed)
        .accessibilityLabel(Text("Put \(name)'s doses in"))
    }

    private var label: some View {
        HStack(spacing: Spacing.sm) {
            switch target {
            case let .profile(id):
                if let profile = directory.profile(id: id) {
                    ProfileAvatarView(profile, diameter: 22)
                    Text(verbatim: profile.name)
                }
            case .newProfile:
                Text("New Profile")
            case .skip:
                Text("Skip")
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(target == .skip ? AnyShapeStyle(Theme.secondaryLabel) : AnyShapeStyle(Theme.accent))
    }
}
