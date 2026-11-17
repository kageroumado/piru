import Foundation
import Observation
import UniformTypeIdentifiers

/// A pairing code or a share that just arrived, held until the inbox sheet
/// settles it. Links and files reach it through ``handle(_:)``.
@Observable
@MainActor
final class ShareInbox {
    static let shared = ShareInbox()

    enum Item: Equatable {
        /// A scanned or tapped pairing code, waiting for a yes.
        case pairing(PairingCode)
        case paired(PiruPerson)
        /// A share that opened, waiting for a yes.
        case share(ShareReceiver.Opened)
        case received(ShareReceiver.Outcome, title: String?, startDate: Date)
        case failed(String)
    }

    var item: Item?

    /// Take `url` when it is a pairing link or a `.pirushare` file: open it,
    /// switch to the journal it was sent to, and present the inbox. `false`
    /// for any other link.
    func handle(_ url: URL, directory: ProfileDirectory = .shared) -> Bool {
        if let code = PairingCode(url: url) {
            show(.pairing(code))
            return true
        }
        guard url.isFileURL, url.pathExtension.lowercased() == UTType.piruShare.preferredFilenameExtension else {
            return false
        }
        let data = Self.read(url)
        do {
            let opened = try ShareReceiver.open(data ?? Data(), directory: directory)
            if opened.recipientProfileID == directory.activeProfileID {
                show(.share(opened))
            } else {
                Task(name: "Open share in its journal") {
                    await ProfileSwitcher.switchTo(opened.recipientProfileID, directory: directory)
                    show(.share(opened))
                }
            }
        } catch {
            show(.failed(error.localizedDescription))
        }
        return true
    }

    func accept(_ opened: ShareReceiver.Opened) {
        do {
            let outcome = try ShareReceiver.accept(opened)
            item = .received(outcome, title: opened.share.side.title, startDate: opened.share.side.startDate)
        } catch {
            item = .failed(error.localizedDescription)
        }
    }

    func pair(_ code: PairingCode, replacingKey: Bool = false) {
        do {
            item = try .paired(ShareReceiver.pair(with: code, replacingKey: replacingKey))
        } catch {
            item = .failed(error.localizedDescription)
        }
    }

    private func show(_ item: Item) {
        self.item = item
        AppNavigator.shared.present(.shareInbox)
    }

    /// The file's bytes, then the file itself removed: a copy the system put
    /// in the app's Inbox would otherwise show in Files.
    private static func read(_ url: URL) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let data = size <= ShareEnvelope.maxFileBytes ? try? Data(contentsOf: url) : nil
        if isInboxCopy(url) {
            try? FileManager.default.removeItem(at: url)
        }
        return data
    }

    /// Whether `url` is a copy made for the app to read and then delete: a file whose folder,
    /// or that folder's parent, is an Inbox (iOS `Documents/Inbox`, `tmp/<bundle>-Inbox`,
    /// Android `cache/Inbox/<id>`). Judged on the resolved path, so `Inbox/..` names nothing.
    static func isInboxCopy(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let folders = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents.dropLast()
        return folders.suffix(2).contains { $0 == "Inbox" || $0.hasSuffix("-Inbox") }
    }
}
