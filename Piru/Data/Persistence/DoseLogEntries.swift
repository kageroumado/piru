import Foundation
import SwiftData

/// The whole dose log of one store, newest first, read once per commit.
///
/// A screen that needs every dose reads ``entries(in:)`` where it would hold
/// an unbounded `@Query`. The query re-fetches and re-sorts the whole table
/// on the main actor after every save, once per view that holds one; this
/// reads the identifiers in store order and keeps the model objects it has
/// already handed out, so a commit costs one identifier fetch however many
/// screens read it.
///
/// What it returns is current for a (context, ``DoseLogService/revision``)
/// pair. Every path that adds, removes, edits or imports doses bumps the
/// revision, deleting the journal bumps it, and a profile switch both bumps
/// it and brings another context. Reading the revision here subscribes the
/// calling view to it, so a body that reads ``entries(in:)`` re-evaluates on
/// the next commit.
///
/// An edit or a delete bumps the revision before autosave writes it, so each
/// read also applies what the context still holds unsaved: a deleted dose is
/// left out, and an inserted or changed one is placed by its current time.
@MainActor
final class DoseLogEntries {
    static let shared = DoseLogEntries()

    private weak var context: ModelContext?
    private var revision: Int?
    private var entries: [DoseEntry] = []
    private var byID: [PersistentIdentifier: DoseEntry] = [:]

    /// More new or moved rows than this are read in one fetch instead of one
    /// by one: a first read, an import, a restore.
    private static let incrementalLimit = 32

    /// Newest first, with each dose's `session` prefetched: grouping reads
    /// `entry.session` for every dose, and unfetched that is one fault each.
    private static var descriptor: FetchDescriptor<DoseEntry> {
        var descriptor = FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.relationshipKeyPathsForPrefetching = [\.session]
        return descriptor
    }

    /// Every dose in `context`'s store, newest first.
    func entries(in context: ModelContext) -> [DoseEntry] {
        let revision = DoseLogService.shared.revision
        if self.context === context, self.revision == revision {
            return entries
        }
        if self.context !== context {
            entries = []
            byID = [:]
        }
        self.context = context
        self.revision = revision
        refresh(in: context)
        return entries
    }

    /// Forgets what was read, so the next read fetches again whatever the
    /// revision says: for a wipe, whose deleted rows must not be handed out
    /// in the moment before its caller signals the change.
    func invalidate() {
        revision = nil
    }

    private func refresh(in context: ModelContext) {
        #if DEBUG && !os(Android)
            PerfProbe.count("doseLog.refresh")
        #endif
        #if os(Android)
            // The Android store keeps every model in memory, where a fetch is
            // a filter and a sort over objects already read.
            readAll(in: context)
        #else
            // The saved rows' identifiers, in SQL order; what is unsaved is
            // applied below, so the read never sorts the table in memory.
            var saved = FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
            saved.includePendingChanges = false
            let pending = Self.pendingDoses(in: context)
            guard pending.count <= Self.incrementalLimit,
                  let identifiers = try? context.fetchIdentifiers(saved),
                  identifiers.count(where: { byID[$0] == nil }) <= Self.incrementalLimit
            else {
                readAll(in: context)
                return
            }
            var live: [PersistentIdentifier: DoseEntry] = [:]
            live.reserveCapacity(identifiers.count + pending.count)
            var ordered: [DoseEntry] = []
            ordered.reserveCapacity(identifiers.count + pending.count)
            let pendingObjects = Set(pending.map(ObjectIdentifier.init))
            for identifier in identifiers {
                guard let entry = byID[identifier] ?? context.model(for: identifier) as? DoseEntry,
                      !entry.isDeleted, !pendingObjects.contains(ObjectIdentifier(entry)) else { continue }
                live[identifier] = entry
                ordered.append(entry)
            }
            for entry in pending where !entry.isDeleted {
                let timestamp = entry.timestamp
                var low = 0
                var high = ordered.count
                while low < high {
                    let mid = (low + high) / 2
                    if ordered[mid].timestamp > timestamp { low = mid + 1 } else { high = mid }
                }
                ordered.insert(entry, at: low)
                live[entry.persistentModelID] = entry
            }
            byID = live
            entries = ordered
        #endif
    }

    #if !os(Android)
        /// The doses `context` holds inserted or changed and not yet saved.
        private static func pendingDoses(in context: ModelContext) -> [DoseEntry] {
            guard context.hasChanges else { return [] }
            var seen = Set<ObjectIdentifier>()
            return (context.insertedModelsArray + context.changedModelsArray)
                .compactMap { $0 as? DoseEntry }
                .filter { seen.insert(ObjectIdentifier($0)).inserted }
        }
    #endif

    private func readAll(in context: ModelContext) {
        #if DEBUG && !os(Android)
            PerfProbe.count("doseLog.readAll")
        #endif
        entries = (try? context.fetch(Self.descriptor)) ?? []
        byID = Dictionary(entries.map { ($0.persistentModelID, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
