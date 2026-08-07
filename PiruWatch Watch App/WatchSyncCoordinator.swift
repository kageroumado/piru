import Foundation
import Observation
import os
import WatchConnectivity

private let watchLog = Logger(subsystem: "dev.yumeji.piru.watchkitapp", category: "WatchSync")

/// The watch half of the sync (`Specs/apple-watch-companion.md`). Reads the favorites/recents
/// manifest the phone pushes (OS-persisted in `receivedApplicationContext`, so it survives the
/// watch sleeping) and queues each logged dose for **guaranteed** delivery via `transferUserInfo`.
/// The watch holds no store — WCSession's own OS state is the only persistence it needs.
///
/// `@Observable` so the UI re-renders when a new manifest arrives or a transfer confirms.
/// Delegate callbacks arrive on a background queue and hop to the main actor.
@MainActor
@Observable
final class WatchSyncCoordinator: NSObject {
    static let shared = WatchSyncCoordinator()

    /// Latest favorites/recents from the phone; nil until the first context arrives.
    private(set) var manifest: QuickLogManifest?
    /// Doses handed to the OS transfer queue but not yet confirmed delivered — drives the
    /// "logged · syncing" readout.
    private(set) var pendingCount: Int = 0
    /// When the last dose was queued, for a brief on-screen confirmation.
    private(set) var lastLoggedAt: Date?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        loadManifest(from: session.receivedApplicationContext)
        pendingCount = session.outstandingUserInfoTransfers.count
        watchLog.notice("activate: manifestItems=\(self.manifest?.items.count ?? -1) reachable=\(session.isReachable)")
    }

    /// Queue a watch-logged dose for guaranteed delivery to the phone.
    func log(_ payload: WatchDosePayload) {
        guard let userInfo = payload.userInfo() else { return }
        WCSession.default.transferUserInfo(userInfo)
        pendingCount += 1
        lastLoggedAt = Date()
        // Count only — never the substance/amount (this is a device log).
        watchLog.notice("queued dose for phone; pending=\(self.pendingCount)")
    }

    private func loadManifest(from context: [String: Any]) {
        guard let manifest = QuickLogManifest(applicationContext: context) else { return }
        self.manifest = manifest
    }

    private func apply(_ manifest: QuickLogManifest) {
        watchLog.notice("didReceiveContext: items=\(manifest.items.count)")
        self.manifest = manifest
    }
}

extension WatchSyncCoordinator: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith _: WCSessionActivationState,
        error _: Error?,
    ) {
        // Decode off the delegate queue: the context dictionary isn't Sendable, the
        // manifest is — so only the manifest crosses onto the main actor.
        guard let manifest = QuickLogManifest(applicationContext: session.receivedApplicationContext) else { return }
        Task { @MainActor in self.apply(manifest) }
    }

    nonisolated func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let manifest = QuickLogManifest(applicationContext: applicationContext) else { return }
        Task { @MainActor in self.apply(manifest) }
    }

    nonisolated func session(
        _: WCSession,
        didFinish _: WCSessionUserInfoTransfer,
        error _: Error?,
    ) {
        Task { @MainActor in self.pendingCount = max(0, self.pendingCount - 1) }
    }
}
