import SwiftUI

/// A read-only look at another person's side of a shared session: their curve,
/// doses, title and notes, with a way into their journal and a way out of the
/// shared session.
struct SharedSessionPeekView: View {
    let experienceID: UUID
    let profileID: UUID

    @Environment(\.profileDirectory) private var directory
    @Environment(\.appNavigator) private var navigator
    @State private var participant: SharedParticipant?
    @State private var loaded = false
    @State private var removeError: String?

    var body: some View {
        Group {
            if let profile = directory.profile(id: profileID), let participant = shownParticipant {
                SharedSessionPeekContent(
                    profile: profile,
                    participant: participant,
                    onOpenJournal: { openJournal(profile: profile, sessionID: participant.snapshot.sessionID) },
                    onRemove: { remove() },
                )
            } else if loaded {
                ContentUnavailableView("No Entries", systemImage: "pill")
            } else {
                ProgressView()
            }
        }
        .task(id: DoseLogService.shared.revision) {
            participant = await SharedExperienceStore.shared.participants(for: experienceID).first { $0.id == profileID }
            loaded = true
        }
        .alert(
            "Couldn't Remove",
            isPresented: Binding(get: { removeError != nil }, set: { if !$0 { removeError = nil } }),
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: removeError ?? "")
        }
    }

    private var shownParticipant: SharedParticipant? {
        participant ?? SharedExperienceStore.shared.cachedParticipants(for: experienceID)?.first { $0.id == profileID }
    }

    /// Switch to their profile and open their session there.
    private func openJournal(profile: PiruProfile, sessionID: UUID) {
        let snapshot = NavigatorSnapshot(selectedTab: .journal, paths: [.journal: [.session(id: sessionID)]])
        guard let url = DeepLink.encode(snapshot) else { return }
        navigator.dismiss()
        ProfileSwitcher.open(DeepLink.tagging(url, profile: profile.id)) { url in
            guard let outcome = DeepLink.decode(url) else { return }
            AppNavigator.shared.apply(outcome)
        }
    }

    private func remove() {
        do {
            try SharedExperienceLinker.remove(profileID, from: experienceID)
            navigator.dismiss()
        } catch {
            removeError = error.localizedDescription
        }
    }
}

/// The peek's list, from finished values only.
private struct SharedSessionPeekContent: View {
    let profile: PiruProfile
    let participant: SharedParticipant
    let onOpenJournal: () -> Void
    let onRemove: () -> Void

    @AppStorage("stackRedoses", store: UserDefaults(suiteName: AppIdentity.appGroup)) private var stackRedoses = true

    private var snapshot: SharedSessionSnapshot {
        participant.snapshot
    }

    private var dateText: String {
        snapshot.startDate.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: Spacing.lg) {
                    ProfileAvatarView(profile, diameter: 36)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(verbatim: profile.name)
                            .font(.headline)
                        Text(verbatim: snapshot.title.map { "\($0) · \(dateText)" } ?? dateText)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
            }

            if !participant.states.isEmpty || !participant.markers.isEmpty {
                Section {
                    TimelineGraphView(
                        substances: participant.states,
                        currentTime: .now,
                        compact: false,
                        markers: participant.markers,
                        stackRedoses: stackRedoses,
                        dayBounded: true,
                        chartFrame: true,
                    )
                    .frame(height: 170)
                    .allowsHitTesting(false)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                ForEach(participant.rows, id: \.core.entryID) { row in
                    EntryRowView(display: row, showsChevron: false)
                }
            }

            if snapshot.summary != nil || !snapshot.notes.isEmpty {
                Section("Notes") {
                    if let summary = snapshot.summary {
                        Text(verbatim: summary)
                    }
                    ForEach(snapshot.notes) { note in
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(note.timestamp, format: .dateTime.hour().minute())
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryLabel)
                            Text(verbatim: note.text)
                        }
                    }
                }
            }

            Section {
                Button("Open \(profile.name)'s Journal", action: onOpenJournal)
                Button("Unlink \(profile.name)'s Session", role: .destructive, action: onRemove)
            } footer: {
                Text("Every dose stays in both journals. This session stops showing \(profile.name) beside yours.")
            }
        }
        .insetGroupedListStyle()
        .navigationTitle(Text("\(profile.name)'s Session"))
        .inlineNavigationTitle()
    }
}
