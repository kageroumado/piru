import Foundation
import SwiftData

/// Maps a `WatchDosePayload` (arriving over WatchConnectivity) onto a `DoseEntry` and
/// inserts it through the **canonical** `DoseLogService.log` path — so a watch dose gets
/// the same session assignment, harm-reduction notifications, and change signal as one
/// logged on the phone. The phone stays the single writer (`Specs/apple-watch-companion.md`).
///
/// ## Idempotency
/// `transferUserInfo` guarantees delivery but can re-deliver; the payload's `id` is the
/// dedup key. `ingest` skips a payload whose id already exists as a `DoseEntry`, so a
/// re-delivered transfer never double-logs. `DoseEntry.id` is app-level unique
/// (`Specs/dose-entry-stable-id.md`), which is exactly what this relies on.
///
/// The `WCSessionDelegate` calls ``ingest(_:in:)``; it is otherwise a pure seam,
/// unit-testable with a simulated payload and no watch.
@MainActor
enum WatchDoseReceiver {
    enum Outcome: Equatable {
        /// A new `DoseEntry` was logged; carries its id.
        case inserted(UUID)
        /// A payload with this id was already logged — skipped.
        case duplicate
    }

    /// Log a watch payload once. Deduped on `payload.id`.
    @discardableResult
    static func ingest(_ payload: WatchDosePayload, in context: ModelContext) -> Outcome {
        let id = payload.id
        var descriptor = FetchDescriptor<DoseEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor), !existing.isEmpty {
            return .duplicate
        }

        // Prior entries feed the redose / cumulative-dose warnings, exactly as the
        // phone quick-log passes them. Fetched before insert so the new dose isn't in it.
        let recents = recentEntries(in: context)
        let entry = makeEntry(from: payload)
        DoseLogService.shared.log(entry, in: context, recentEntries: recents)

        // Fold the dose into the curated recents so a watch-logged drink becomes a
        // phone chip too — parity with the phone quick-log commit. The chip's amount is
        // the same canonical value the entry stored, not the watch's advisory number.
        recordRecent(payload, amount: entry.amount, in: context)
        return .inserted(id)
    }

    /// Reconstruct the `DoseEntry`. The `id` is assigned from the payload (the `DoseEntry`
    /// initializer doesn't take one — it defaults a fresh UUID), which is what makes the
    /// dedup fetch above meaningful. By-volume drink detail is set as first-class fields,
    /// matching the phone quick-log commit (no notes breadcrumb on this path).
    static func makeEntry(from payload: WatchDosePayload) -> DoseEntry {
        let entry = DoseEntry(
            substance: payload.substance,
            amount: canonicalAmount(for: payload),
            unit: payload.unit,
            route: RouteOfAdministration(rawValue: payload.route) ?? .oral,
            saltForm: payload.saltForm,
            isomer: payload.isomer,
            releaseForm: payload.releaseForm,
            productName: payload.productName,
            substanceUID: payload.substanceUID,
            displayNameSnapshot: payload.displayName,
            timestamp: payload.timestamp,
            notes: payload.notes,
            volumeML: payload.volumeML,
            abv: payload.abv,
            drinkName: payload.drinkName,
        )
        entry.id = payload.id
        return entry
    }

    /// The canonical stored amount for a payload. A by-volume drink (volume + ABV present)
    /// is converted to grams with the real `ByVolumeDosing` conversion here, so the logged
    /// value never depends on the watch's display-only estimate; a mass dose is verbatim.
    private static func canonicalAmount(for payload: WatchDosePayload) -> Double {
        if let volumeML = payload.volumeML, let abv = payload.abv, volumeML > 0, abv > 0 {
            return ByVolumeDosing.grams(volumeML: volumeML, abv: abv)
        }
        return payload.amount
    }

    private static func recentEntries(in context: ModelContext) -> [DoseEntry] {
        var descriptor = FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 25
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func recordRecent(_ payload: WatchDosePayload, amount: Double, in context: ModelContext) {
        let fixedOrder = UserDefaults.standard.bool(forKey: QuickLogManager.fixedOrderDefaultsKey)
        QuickLogManager.record(
            [QuickLogManager.LoggedDose(
                substance: payload.substance,
                route: RouteOfAdministration(rawValue: payload.route) ?? .oral,
                amount: amount,
                unit: payload.unit,
                volumeML: payload.volumeML,
                abv: payload.abv,
                drinkName: payload.drinkName,
                emoji: payload.emoji,
                substanceUID: payload.substanceUID,
                isomer: payload.isomer,
                releaseForm: payload.releaseForm,
                saltForm: payload.saltForm,
                productName: payload.productName,
            )],
            fixedOrder: fixedOrder,
            context: context,
        )
    }
}
