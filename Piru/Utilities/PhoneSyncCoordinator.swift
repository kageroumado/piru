import Foundation
import os
import SwiftData
import WatchConnectivity

private let watchLog = Logger(subsystem: "dev.yumeji.piru", category: "WatchSync")

/// The phone half of the Apple Watch sync (`Specs/apple-watch-companion.md`). Owns the
/// `WCSession` on the iPhone: it **pushes** the favorites/recents manifest to the watch via
/// `updateApplicationContext` (latest-wins, survives the watch sleeping) and **receives**
/// watch-logged doses via `transferUserInfo`, inserting each through `WatchDoseReceiver` →
/// `DoseLogService.log`. The phone stays the single source of truth; the watch never mutates
/// the store.
///
/// `WCSessionDelegate` callbacks arrive on a background queue, so each hops to the main actor
/// before touching SwiftData or the session state.
@MainActor
final class PhoneSyncCoordinator: NSObject {
    static let shared = PhoneSyncCoordinator()

    private var container: ModelContainer?
    private var changeObserver: Task<Void, Never>?

    /// Bind the coordinator to the store and activate the session. No-op on devices without
    /// WatchConnectivity (iPad, Mac). Idempotent.
    func configure(container: ModelContainer) {
        guard WCSession.isSupported() else { return }
        self.container = container
        let session = WCSession.default
        session.delegate = self
        session.activate()

        // Re-push the manifest whenever the dose log changes, so a dose logged on the phone
        // (or just received from the watch) keeps the wrist's recents current.
        changeObserver?.cancel()
        changeObserver = Task { [weak self] in
            for await _ in DoseLogService.shared.changes {
                self?.pushManifest()
            }
        }
    }

    // MARK: - Phone → Watch

    /// Build the current manifest and hand it to the OS to deliver to the watch. Latest-wins:
    /// a newer context silently replaces an undelivered one, which is exactly right for a
    /// snapshot of "your current favorites/recents."
    func pushManifest() {
        guard let context = container?.mainContext else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let colors = (try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? []
        var hexMap: [String: String] = [:]
        for color in colors {
            hexMap[color.substance.lowercased()] = color.hexColor
        }

        let manifest = QuickLogManifestBuilder.build(
            in: context,
            generatedAt: Date(),
            colorHex: { SubstancePalette.hex(for: $0, hexMap: hexMap) },
            favoriteDefault: Self.favoriteDefault(for:),
            step: { substance, route, unit, amount in
                // Same increment the quick-log dock uses: niceStep off the library
                // reference dose when known, else the magnitude fallback.
                let reference = StagedDose.lookupReferenceDose(
                    substance: SubstanceLibrary.lookup(substance), route: route, unit: unit,
                )
                return DoseStepping.step(referenceDose: reference, amount: amount)
            },
        )
        guard let payload = manifest.applicationContext() else { return }
        do {
            try session.updateApplicationContext(payload)
            watchLog.notice("pushManifest ok: items=\(manifest.items.count) paired=\(session.isPaired) installed=\(session.isWatchAppInstalled) reachable=\(session.isReachable)")
        } catch {
            watchLog.error("pushManifest FAILED: \(error.localizedDescription) items=\(manifest.items.count) paired=\(session.isPaired) installed=\(session.isWatchAppInstalled)")
        }
    }

    /// Resolve a favorited substance's default dose from the library, for a favorite with no
    /// recent chip. nil (skip the tile) when the substance or its common range is unknown.
    private static func favoriteDefault(for favorite: FavoriteSubstance) -> QuickLogManifestBuilder.FavoriteDefault? {
        guard let substance = SubstanceLibrary.lookup(favorite.substance) else { return nil }
        let route = substance.defaultRoute
        guard let common = substance.doseRange(for: route)?.common else { return nil }
        let amount = (common.lowerBound + common.upperBound) / 2
        return .init(amount: amount, unit: substance.defaultUnit, route: route, displayName: favorite.substance)
    }

    // MARK: - Watch → Phone

    private func receive(_ payload: WatchDosePayload) {
        guard let context = container?.mainContext else { return }
        let outcome = WatchDoseReceiver.ingest(payload, in: context)
        // Count/outcome only — never the substance or amount (this is a device log).
        watchLog.notice("received watch dose → \(String(describing: outcome), privacy: .public)")
        // The received dose is a new recent; the change signal from `DoseLogService.log`
        // already re-pushes the manifest via `changeObserver`.
    }
}

// MARK: - WCSessionDelegate

extension PhoneSyncCoordinator: WCSessionDelegate {
    nonisolated func session(
        _: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error _: Error?,
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in self.pushManifest() }
    }

    nonisolated func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        // Decode off the delegate queue: the dictionary isn't Sendable, but the resulting
        // payload is — so only the payload crosses onto the main actor.
        guard let payload = WatchDosePayload(userInfo: userInfo) else { return }
        Task { @MainActor in self.receive(payload) }
    }

    /// Required on iOS: after a session deactivates (the user switched paired watches),
    /// reactivate so the new watch is served.
    nonisolated func sessionDidBecomeInactive(_: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
