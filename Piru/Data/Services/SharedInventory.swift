import Foundation
import Observation
import SwiftData

/// A dose one profile logged against an item another profile owns and shares
/// with it. Read from that profile's store; never written anywhere.
nonisolated struct ForeignDose: Hashable, Sendable {
    let profileID: UUID
    let entryID: UUID
    let amount: Double
    let unit: String
    let timestamp: Date
}

extension ForeignDose {
    var snapshot: InventoryMath.DoseSnapshot {
        InventoryMath.DoseSnapshot(amount: amount, unit: unit, timestamp: timestamp)
    }
}

/// Inventory shared between profiles.
///
/// A shared item lives in its owner's store and lists the other profiles that
/// draw from it in ``InventoryItem/sharedWith``. Its stock is the owner's
/// matching doses plus each of those profiles' matching doses, all since its
/// `trackingStart`, each converted with its own unit exactly as the owner's are.
///
/// ## Precedence
/// A profile's dose goes to an item of its own first. A shared item counts a
/// sharee's dose only when the sharee has no item of their own that would take
/// it (``InventoryMath/owner(isomer:productName:at:among:)`` over their own
/// items finds nothing), so one dose never draws down two stocks. Among
/// several items shared with the same person, the usual form routing picks
/// one: most specific, then oldest.
///
/// ## How it stays current
/// ``refresh()`` reads every profile's store off the main actor, routes the
/// sharees' doses to the shared items, keeps them in ``foreignDoses(for:)``
/// (which every inventory recompute adds to the owner's own doses), and
/// rewrites each shared item's ``InventoryItem/currentQuantity`` in its
/// owner's store. It runs at launch, on every dose-log change in any profile,
/// on a profile switch, and after sharing changes. A crossed threshold alerts
/// the owner, whoever's dose crossed it.
@Observable
@MainActor
final class SharedInventory {
    static let shared = SharedInventory()

    /// A shared item and the profile whose store holds it.
    struct Entry: Identifiable {
        let ownerID: UUID
        let item: InventoryItem

        var id: UUID {
            item.id
        }
    }

    /// A low-stock alert a refresh raised: the item, and the profile it was
    /// raised under.
    struct Alert: Equatable {
        let profileID: UUID
        let itemID: UUID
    }

    /// Every shared item on the device, read from its owner's store.
    private(set) var entries: [Entry] = []

    @ObservationIgnored private let directory: ProfileDirectory
    @ObservationIgnored private var refreshing: Task<[Alert], Never>?
    @ObservationIgnored private var listener: Task<Void, Never>?
    /// The shared items the last refresh wrote, so an item that stops being
    /// shared is rewritten once more without its sharees' doses.
    @ObservationIgnored private var lastWritten: Set<ItemKey> = []

    init(directory: ProfileDirectory = .shared) {
        self.directory = directory
    }

    // MARK: - Reading

    /// The items other profiles share with the active one, each in its
    /// owner's store.
    var sharedIn: [Entry] {
        let active = directory.activeProfileID
        return entries.filter { entry in
            entry.ownerID != active && entry.item.isLive && directory.profile(id: entry.ownerID) != nil
                && entry.item.sharedWith.contains(active)
        }
    }

    /// The owner of a shared-in item, when `item` is one.
    func owner(of item: InventoryItem) -> PiruProfile? {
        guard let entry = sharedIn.first(where: { $0.item === item }) else { return nil }
        return directory.profile(id: entry.ownerID)
    }

    /// The tracked item to show for a substance in the active profile: one of
    /// its own (`own`) first, else one shared with it. Same choice as
    /// ``InventoryService/find(substance:preferringSalt:among:)``.
    func displayItem(substance: String, preferringSalt saltForm: String?, own: [InventoryItem]) -> InventoryItem? {
        InventoryService.find(substance: substance, preferringSalt: saltForm, among: own)
            ?? InventoryService.find(substance: substance, preferringSalt: saltForm, among: sharedIn.map(\.item))
    }

    /// The item a route names: the active profile's own, else one shared with
    /// it, which lives in its owner's store (show it with that store's
    /// context, `item.modelContext`, so its edits land there).
    func item(id: UUID, in context: ModelContext) -> InventoryItem? {
        var descriptor = FetchDescriptor<InventoryItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let own = try? context.fetch(descriptor).first { return own }
        return sharedIn.first { $0.item.id == id }?.item
    }

    /// The profiles other than the owner that draw from `item`, in registry order.
    func sharees(of item: InventoryItem) -> [PiruProfile] {
        let ids = Set(item.sharedWith)
        return directory.profiles.filter { ids.contains($0.id) }
    }

    // MARK: - Foreign doses

    /// An item, by the store file that holds it and its id: two stores may
    /// hold items with one id (a journal imported into a second profile).
    nonisolated struct StoreItemKey: Hashable, Sendable {
        let storePath: String
        let itemID: UUID
    }

    /// The doses each shared item's sharees logged against it, by item. Kept
    /// for the whole process and replaced per store on each refresh.
    private static var foreign: [StoreItemKey: [ForeignDose]] = [:]

    /// The doses other profiles logged against `item`; empty for an item
    /// nobody shares. Every recompute adds these to the item's own doses.
    static func foreignDoses(for item: InventoryItem) -> [ForeignDose] {
        guard !foreign.isEmpty, let path = storePath(of: item) else { return [] }
        return foreign[StoreItemKey(storePath: path, itemID: item.id)] ?? []
    }

    /// The profile whose store holds `item`, or `nil` with one profile or for
    /// a store outside `directory`.
    static func profileID(owningStoreOf item: InventoryItem, directory: ProfileDirectory = .shared) -> UUID? {
        guard directory.hasMultipleProfiles, let path = storePath(of: item) else { return nil }
        return directory.profiles.first { canonicalPath(directory.storeURL(for: $0)) == path }?.id
    }

    private static func storePath(of item: InventoryItem) -> String? {
        guard let url = item.modelContext?.container.configurations.first?.url else { return nil }
        return canonicalPath(url)
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    // MARK: - Writing

    /// Run a write to `item` as its owner: pinned to the profile whose store
    /// holds it (so a crossed threshold alerts that profile), then saved when
    /// that store is not the one on screen.
    static func write(to item: InventoryItem, directory: ProfileDirectory = .shared, _ body: () -> Void) {
        let owner = profileID(owningStoreOf: item, directory: directory) ?? ProfileScope.currentID
        ProfileScope.$pinned.withValue(owner) { body() }
        if owner != directory.activeProfileID {
            try? item.modelContext?.save()
        }
    }

    /// Change who draws from `item`. Only its owner may: the caller is the
    /// active profile's editor, and `item` lives in the active store.
    func setSharing(_ item: InventoryItem, with profiles: [UUID]) async {
        let others = profiles.filter { $0 != directory.activeProfileID && directory.profile(id: $0) != nil }
        guard Set(others) != Set(item.sharedWith) else { return }
        item.sharedWith = others
        try? item.modelContext?.save()
        await refresh()
    }

    /// A profile was deleted: no item in any store still names it.
    func profileDeleted(_ id: UUID) async {
        for profile in directory.profiles {
            guard FileManager.default.fileExists(atPath: directory.storeURL(for: profile).path),
                  let reader = directory.container(for: profile.id, writable: false)
            else { continue }
            let names = ((try? reader.mainContext.fetch(FetchDescriptor<InventoryItem>())) ?? [])
                .contains { $0.sharedWith.contains(id) }
            guard names, let container = directory.container(for: profile.id, writable: true) else { continue }
            let context = container.mainContext
            for item in (try? context.fetch(FetchDescriptor<InventoryItem>())) ?? [] where item.sharedWith.contains(id) {
                item.sharedWith.removeAll { $0 == id }
            }
            try? context.save()
        }
        await refresh()
    }

    // MARK: - Refreshing

    /// Refresh on every dose-log change in any profile (and on a profile
    /// switch, which ticks the same stream), starting now. Idempotent.
    func start() {
        guard listener == nil else { return }
        let changes = DoseLogService.shared.changeStream()
        listener = Task(name: "Shared inventory") { [weak self] in
            await self?.refresh()
            for await _ in changes {
                // Coalesce a burst and stay clear of the logging sheet's dismissal.
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    /// Re-read every store and rewrite every shared item's stock. A call made
    /// while one runs waits for it, then runs again, so the last caller always
    /// sees a pass that started after its change. Returns the low-stock
    /// alerts the pass raised.
    @discardableResult
    func refresh(notify: Bool = true) async -> [Alert] {
        while let running = refreshing {
            _ = await running.value
        }
        let task = Task(name: "Refresh shared inventory") {
            let alerts = await self.performRefresh(notify: notify)
            // Cleared by the pass itself, so a waiter never finds a finished one.
            self.refreshing = nil
            return alerts
        }
        refreshing = task
        return await task.value
    }

    private func performRefresh(notify: Bool) async -> [Alert] {
        guard directory.hasMultipleProfiles else {
            clear()
            return []
        }
        let known = Set(directory.profiles.map(\.id))
        let stores = directory.profiles.compactMap { profile -> Store? in
            guard FileManager.default.fileExists(atPath: directory.storeURL(for: profile).path),
                  let container = directory.container(for: profile.id, writable: false)
            else { return nil }
            return Store(profileID: profile.id, container: container)
        }
        let scan = await Self.scan(stores, known: known)
        let routed = Self.route(scan, known: known)

        let paths = Dictionary(uniqueKeysWithValues: directory.profiles.map {
            ($0.id, Self.canonicalPath(directory.storeURL(for: $0)))
        })
        let ownPaths = Set(paths.values)
        Self.foreign = Self.foreign.filter { !ownPaths.contains($0.key.storePath) }
        for (key, doses) in routed {
            guard let path = paths[key.profileID] else { continue }
            Self.foreign[StoreItemKey(storePath: path, itemID: key.itemID)] = doses
        }

        let shared = Set(scan.items.filter { !$0.sharees(known: known).isEmpty }.map(\.key))
        let alerts = writeBack(shared.union(lastWritten), notify: notify)
        lastWritten = shared
        return alerts
    }

    /// Rewrite the stock of `keys` in their owners' stores, each pinned to its
    /// owner, and collect the shared ones into ``entries``.
    private func writeBack(_ keys: Set<ItemKey>, notify: Bool) -> [Alert] {
        var alerts: [Alert] = []
        var next: [Entry] = []
        for (ownerID, ownerKeys) in Dictionary(grouping: keys, by: \.profileID) {
            guard directory.profile(id: ownerID) != nil,
                  let container = directory.container(for: ownerID, writable: true)
            else { continue }
            let ids = Set(ownerKeys.map(\.itemID))
            ProfileScope.$pinned.withValue(ownerID) {
                let context = container.mainContext
                let items = ((try? context.fetch(FetchDescriptor<InventoryItem>())) ?? []).filter { ids.contains($0.id) }
                guard !items.isEmpty else { return }
                // Every sibling of each substance, so form routing sees them all.
                let fired = InventoryService.recompute(forSubstances: Set(items.map(\.substance)), in: context, notify: notify)
                alerts += fired.map { Alert(profileID: ProfileScope.currentID, itemID: $0) }
                if context.hasChanges { try? context.save() }
                next += items.filter { !$0.sharedWith.isEmpty }.map { Entry(ownerID: ownerID, item: $0) }
            }
        }
        entries = next.sorted { $0.item.createdAt < $1.item.createdAt }
        return alerts
    }

    private func clear() {
        if !entries.isEmpty { entries = [] }
        let paths = Set(directory.profiles.map { Self.canonicalPath(directory.storeURL(for: $0)) })
        Self.foreign = Self.foreign.filter { !paths.contains($0.key.storePath) }
        lastWritten = []
    }
}

// MARK: - Cross-store scan

extension SharedInventory {
    /// A shared item by its owner and id.
    nonisolated struct ItemKey: Hashable, Sendable {
        let profileID: UUID
        let itemID: UUID
    }

    /// One profile's store, to read off the main actor.
    nonisolated struct Store: Sendable {
        let profileID: UUID
        let container: ModelContainer
    }

    /// An inventory item as read from some profile's store.
    nonisolated struct ItemRecord: Sendable {
        let profileID: UUID
        let id: UUID
        let substance: String
        let saltForm: String?
        let isomer: String?
        let productName: String?
        let trackingStart: Date
        let createdAt: Date
        let sharedWith: [UUID]

        var key: ItemKey {
            ItemKey(profileID: profileID, itemID: id)
        }

        /// The profiles this item is shared with that still exist, its owner aside.
        func sharees(known: Set<UUID>) -> [UUID] {
            sharedWith.filter { $0 != profileID && known.contains($0) }
        }
    }

    /// A dose as read from some profile's store.
    nonisolated struct DoseRecord: Sendable {
        let profileID: UUID
        let id: UUID
        let substance: String
        let substanceUID: String?
        let saltForm: String?
        let isomer: String?
        let productName: String?
        let amount: Double
        let unit: String
        let timestamp: Date
    }

    /// Every store's items, and the doses of each profile something is shared
    /// with, since the earliest `trackingStart` among the items shared with it.
    /// Reads committed state on ``DatabaseActor``.
    @DatabaseActor
    static func scan(_ stores: [Store], known: Set<UUID>) -> (items: [ItemRecord], doses: [DoseRecord]) {
        var items: [ItemRecord] = []
        for store in stores {
            let context = ModelContext(store.container)
            for item in (try? context.fetch(FetchDescriptor<InventoryItem>())) ?? [] {
                items.append(ItemRecord(
                    profileID: store.profileID, id: item.id, substance: item.substance, saltForm: item.saltForm,
                    isomer: item.isomer, productName: item.productName, trackingStart: item.trackingStart,
                    createdAt: item.createdAt,
                    sharedWith: (try? JSONDecoder().decode([UUID].self, from: item.sharedWithData)) ?? [],
                ))
            }
        }
        var since: [UUID: Date] = [:]
        for item in items {
            for sharee in item.sharees(known: known) {
                since[sharee] = min(since[sharee] ?? item.trackingStart, item.trackingStart)
            }
        }
        var doses: [DoseRecord] = []
        for store in stores {
            guard let start = since[store.profileID] else { continue }
            let context = ModelContext(store.container)
            let fetched = (try? context.fetch(FetchDescriptor<DoseEntry>(predicate: #Predicate { $0.timestamp >= start }))) ?? []
            // A dose of unknown amount cannot be drawn down from stock.
            for dose in fetched where !dose.isUnknownDose {
                doses.append(DoseRecord(
                    profileID: store.profileID, id: dose.id, substance: dose.substance, substanceUID: dose.substanceUID,
                    saltForm: dose.saltForm, isomer: dose.isomer, productName: dose.productName,
                    amount: dose.amount, unit: dose.unit, timestamp: dose.timestamp,
                ))
            }
        }
        return (items, doses)
    }

    /// Each shared item's doses from its sharees: a sharee's dose that matches
    /// a shared item's identity (substance, salt, then form routing) goes to
    /// it, unless the sharee has an item of their own that would take the dose.
    static func route(_ scan: (items: [ItemRecord], doses: [DoseRecord]), known: Set<UUID>) -> [ItemKey: [ForeignDose]] {
        var keys: [String: String] = [:]
        func matchKey(_ name: String) -> String {
            if let key = keys[name] { return key }
            let key = InventoryMath.matchKey(for: name)
            keys[name] = key
            return key
        }
        func group(_ item: ItemRecord) -> InventoryMath.SaltedKey {
            InventoryMath.SaltedKey(key: matchKey(item.substance), saltForm: item.saltForm)
        }

        let shared = scan.items.filter { !$0.sharees(known: known).isEmpty }
        guard !shared.isEmpty else { return [:] }
        let itemsByProfile = Dictionary(grouping: scan.items, by: \.profileID)
        var routed: [ItemKey: [ForeignDose]] = [:]
        for (profile, doses) in Dictionary(grouping: scan.doses, by: \.profileID) {
            let inbound = Dictionary(grouping: shared.filter { $0.profileID != profile && $0.sharees(known: known).contains(profile) }, by: group)
            guard !inbound.isEmpty else { continue }
            let own = Dictionary(grouping: itemsByProfile[profile] ?? [], by: group)
            for dose in doses {
                let key = InventoryMath.SaltedKey(key: dose.substanceUID ?? matchKey(dose.substance), saltForm: dose.saltForm)
                guard let candidates = inbound[key] else { continue }
                if let mine = own[key],
                   InventoryMath.owner(isomer: dose.isomer, productName: dose.productName, at: dose.timestamp, among: mine) != nil {
                    continue
                }
                guard let target = InventoryMath.owner(
                    isomer: dose.isomer, productName: dose.productName, at: dose.timestamp, among: candidates,
                ) else { continue }
                routed[target.key, default: []].append(ForeignDose(
                    profileID: profile, entryID: dose.id, amount: dose.amount, unit: dose.unit, timestamp: dose.timestamp,
                ))
            }
        }
        return routed
    }
}

extension SharedInventory.ItemRecord: InventoryRoutable {}

private extension InventoryItem {
    /// Still in a store: not deleted, not detached by a save after deletion.
    var isLive: Bool {
        modelContext != nil && !isDeleted
    }
}
