import SwiftUI

/// Settles what ``ShareInbox`` holds: pair with a scanned code, accept a share,
/// and say where it went.
struct ShareInboxView: View {
    var body: some View {
        Group {
            switch ShareInbox.shared.item {
            case let .pairing(code):
                PairPrompt(code: code)
            case let .paired(person):
                PairedNotice(person: person)
            case let .share(opened):
                IncomingShare(opened: opened)
            case let .received(outcome, title, startDate):
                ReceivedNotice(outcome: outcome, title: title, startDate: startDate)
            case let .failed(message):
                ContentUnavailableView("Couldn't Open", systemImage: "exclamationmark.triangle", description: Text(verbatim: message))
            case nil:
                ContentUnavailableView("Nothing Here", systemImage: "tray")
            }
        }
        .themedPage()
        .inlineNavigationTitle()
    }
}

/// A person's avatar and name, large, over a line of what happens next.
private struct InboxHeader: View {
    let avatar: ProfileAvatar
    let color: ProfileColor
    let title: Text
    let detail: Text

    var body: some View {
        VStack(spacing: Spacing.md) {
            ProfileAvatarView(avatar: avatar, color: color, diameter: 64)
            title
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            detail
                .foregroundStyle(Theme.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
    }
}

private struct PairPrompt: View {
    let code: PairingCode
    @Environment(\.profileDirectory) private var directory

    var body: some View {
        List {
            Section {
                InboxHeader(
                    avatar: code.avatar, color: directory.color(forNewPerson: code.personID),
                    title: Text("Pair with \(code.name)?"),
                    detail: Text("You'll be able to send each other sessions. Each of you sees only what the other sends."),
                )
            }
            .listRowBackground(Color.clear)
            Section {
                Button("Pair") { ShareInbox.shared.pair(code) }
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(CardBackground())
        }
        .navigationTitle("Pair")
    }
}

private struct PairedNotice: View {
    let person: PiruPerson
    @Environment(\.appNavigator) private var navigator

    var body: some View {
        List {
            Section {
                InboxHeader(
                    avatar: person.profile.avatar, color: person.profile.color,
                    title: Text("Paired with \(person.profile.name)"),
                    detail: Text("If \(person.profile.name) hasn't scanned your code yet, show it now so they can send you sessions too."),
                )
            }
            .listRowBackground(Color.clear)
            Section {
                Button("Show Your Code") { navigator.present(.pairing, replacingTop: true) }
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(CardBackground())
        }
        .navigationTitle("Paired")
    }
}

private struct IncomingShare: View {
    let opened: ShareReceiver.Opened
    @Environment(\.profileDirectory) private var directory

    var body: some View {
        let side = opened.share.side
        let name = opened.share.sender.name
        List {
            Section {
                InboxHeader(
                    avatar: opened.share.sender.avatar,
                    color: color,
                    title: Text("\(name) shared a session"),
                    detail: Text(summary(side)),
                )
            }
            .listRowBackground(Color.clear)
            Section {
                Button("Add to Your Journal") { ShareInbox.shared.accept(opened) }
                    .frame(maxWidth: .infinity)
            } footer: {
                if opened.sender == .new {
                    Text("You haven't paired with \(name). Adding pairs you, so you can share back.")
                } else {
                    Text("Shows beside your session from the same time. Their doses stay out of your own curves and stats.")
                }
            }
            .listRowBackground(CardBackground())
        }
        .navigationTitle("Shared Session")
    }

    private var color: ProfileColor {
        directory.color(forNewPerson: opened.senderID)
    }

    private func summary(_ side: SessionShare.Side) -> String {
        let when = side.startDate.formatted(.dateTime.weekday(.wide).hour().minute())
        let doses = String(localized: "\(side.doses.count) doses")
        if let title = side.title, !title.isEmpty {
            return "\(title) · \(when) · \(doses)"
        }
        return "\(when) · \(doses)"
    }
}

private struct ReceivedNotice: View {
    let outcome: ShareReceiver.Outcome
    let title: String?
    let startDate: Date
    @Environment(\.appNavigator) private var navigator

    var body: some View {
        let name = outcome.person.profile.name
        List {
            Section {
                InboxHeader(
                    avatar: outcome.person.profile.avatar, color: outcome.person.profile.color,
                    title: Text("Added \(name)'s session"),
                    detail: outcome.linkedSessionID == nil
                        ? Text("You logged nothing around then. Once you do, ask \(name) to send it again.")
                        : Text("It shows beside your session from the same time."),
                )
            }
            .listRowBackground(Color.clear)
            if let sessionID = outcome.linkedSessionID {
                Section {
                    Button("Open Session") { open(sessionID) }
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(CardBackground())
            }
        }
        .navigationTitle("Shared Session")
    }

    private func open(_ sessionID: UUID) {
        let snapshot = NavigatorSnapshot(selectedTab: .journal, paths: [.journal: [.session(id: sessionID)]])
        navigator.dismiss()
        guard let url = DeepLink.encode(snapshot), let outcome = DeepLink.decode(url) else { return }
        navigator.apply(outcome)
    }
}
