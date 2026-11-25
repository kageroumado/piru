import Foundation
import Observation
import os
import WatchConnectivity

private let watchLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Piru", category: "WatchSync")

/// The watch half of the sync. Reads the favorites/recents
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
    /// A med slot ticked or unticked here.
    private struct Hold: Codable, Equatable {
        var taken: Bool
        var at: Date
        /// The change's number (``WatchMedChange``).
        var change: Int
        /// The dose a tick queued, which an untick names so the phone removes exactly it.
        var entryID: UUID?
    }

    /// Med slots ticked or unticked here, held so a row never flips back while its change
    /// is on the way: until a manifest that answers the change arrives
    /// (``QuickLogManifest/handledMedChange``). From then the phone has the last word, a
    /// refusal or a later change of its own included. Kept in defaults: a change can be
    /// delivered long before it is answered, and the app relaunched in between. One
    /// whose transfer failed unseen is never answered: it shows for its own day only
    /// (``isTaken(_:in:)``), and goes when a later change is answered.
    private var holds = UserDefaults.standard.data(forKey: WatchSyncCoordinator.holdsKey)
        .flatMap { try? JSONDecoder().decode([String: Hold].self, from: $0) } ?? [:] {
        didSet {
            guard holds != oldValue else { return }
            UserDefaults.standard.set(try? JSONEncoder().encode(holds), forKey: Self.holdsKey)
        }
    }

    private static let holdsKey = "watchMedHolds"

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        loadManifest(from: session.receivedApplicationContext)
        refreshPendingCount()
        watchLog.notice("activate: manifestItems=\(self.manifest?.items.count ?? -1) reachable=\(session.isReachable)")
    }

    /// Whether `slot` of `day` is taken: as ticked or unticked here that day, else as the
    /// phone says.
    func isTaken(_ slot: ManifestMedSlot, in day: ManifestMedDay) -> Bool {
        if let hold = holds[slot.id], day.contains(hold.at) { return hold.taken }
        return slot.taken
    }

    /// Queue one dose for each of `slots` not taken yet, each checking off its own slot
    /// on the phone. False when none was queued.
    func take(_ slots: [ManifestMedSlot], in day: ManifestMedDay) -> Bool {
        guard let manifest else { return false }
        let now = Date()
        var queued = false
        for slot in slots where !isTaken(slot, in: day) {
            let change = WatchMedChange.next()
            let payload = slot.makePayload(id: UUID(), timestamp: now, change: change, journalGeneration: manifest.journalGeneration)
            guard log(payload) else { continue }
            holds[slot.id] = Hold(taken: true, at: now, change: change, entryID: payload.id)
            queued = true
        }
        return queued
    }

    /// Untick `slot`: withdraw its dose if it is still queued here, and ask the phone to
    /// remove the dose that ticked it. False when it wasn't taken.
    func untake(_ slot: ManifestMedSlot, in day: ManifestMedDay) -> Bool {
        guard let manifest, isTaken(slot, in: day) else { return false }
        let entryID = holds[slot.id].flatMap { day.contains($0.at) && $0.taken ? $0.entryID : nil }
        if let entryID {
            for transfer in WCSession.default.outstandingUserInfoTransfers
                where WatchDosePayload(userInfo: transfer.userInfo)?.id == entryID {
                transfer.cancel()
            }
        }
        let now = Date()
        let change = WatchMedChange.next()
        // Sent even after a cancel: the dose may have left the queue first.
        let untake = WatchMedUntake(
            medSlot: slot.id, entryID: entryID, change: change, timestamp: now, journalGeneration: manifest.journalGeneration,
        )
        guard let userInfo = untake.userInfo() else { return false }
        WCSession.default.transferUserInfo(userInfo)
        holds[slot.id] = Hold(taken: false, at: now, change: change)
        refreshPendingCount()
        watchLog.notice("queued untake for phone; pending=\(self.pendingCount)")
        return true
    }

    /// Queue a watch-logged dose for guaranteed delivery to the phone.
    func log(_ payload: WatchDosePayload) -> Bool {
        guard let manifest,
              JournalResetGeneration.accepts(payload, generation: manifest.journalGeneration ?? 0),
              let userInfo = payload.userInfo() else { return false }
        WCSession.default.transferUserInfo(userInfo)
        pendingCount += 1
        lastLoggedAt = Date()
        // Count only — never the substance/amount (this is a device log).
        watchLog.notice("queued dose for phone; pending=\(self.pendingCount)")
        return true
    }

    private func refreshPendingCount() {
        let generation = JournalResetGeneration.current()
        pendingCount = WCSession.default.outstandingUserInfoTransfers.filter {
            guard let payload = WatchDosePayload(userInfo: $0.userInfo) else { return false }
            return JournalResetGeneration.accepts(payload, generation: generation)
        }.count
    }

    private func loadManifest(from context: [String: Any]) {
        guard let manifest = QuickLogManifest(applicationContext: context) else { return }
        apply(manifest)
    }

    private func apply(_ manifest: QuickLogManifest) {
        let generation = manifest.journalGeneration ?? 0
        guard JournalResetGeneration.accepts(manifest, after: self.manifest, minimumGeneration: JournalResetGeneration.current()) else { return }
        if generation > JournalResetGeneration.current() {
            UserDefaults.standard.set(generation, forKey: JournalResetGeneration.key)
            for transfer in WCSession.default.outstandingUserInfoTransfers {
                if let payload = WatchDosePayload(userInfo: transfer.userInfo),
                   !JournalResetGeneration.accepts(payload, generation: generation) {
                    transfer.cancel()
                }
            }
            pendingCount = 0
            lastLoggedAt = nil
            holds = [:]
        }
        // A count behind the phone's takes up from it (``WatchMedChange/record(_:in:)``).
        if let handled = manifest.handledMedChange, handled > WatchMedChange.last() { WatchMedChange.record(handled) }
        // A hold lets go once the manifest answers its change.
        holds = holds.filter { !manifest.answers(medChange: $0.value.change) }
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
        didFinish userInfoTransfer: WCSessionUserInfoTransfer,
        error: Error?,
    ) {
        // A med change that never reached the phone is never answered: its hold lets go,
        // and the phone's state shows again. Decoded off the delegate queue, so only
        // its number crosses onto the main actor.
        let userInfo = userInfoTransfer.userInfo
        let failed = error == nil ? nil : WatchDosePayload(userInfo: userInfo)?.medChange ?? WatchMedUntake(userInfo: userInfo)?.medChange
        Task { @MainActor in
            if let failed { self.holds = self.holds.filter { $0.value.change != failed } }
            self.refreshPendingCount()
        }
    }
}
