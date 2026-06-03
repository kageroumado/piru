import SwiftData
import SwiftUI

/// Owns the Journal's *derived* state — per-entry resolution, the grouped
/// buckets, the colour map, the category facets, and the tag list — so it lives
/// outside the view's `body` instead of in a web of `@State` caches.
///
/// The view passes in its `@Query` results plus the current filter/grouping
/// selection; the model recomputes only when its signature actually changes and
/// publishes ready-to-render values, which SwiftUI diffs as a single observable
/// source of truth. This replaces the former shadow-`@State` model — six caches
/// + two signature ints + `rebuild*` calls scattered across `.task`/`.onChange`
/// — that `data.md` warns against ("don't cache derived collections in `@State`
/// without owning invalidation"), and that forced multi-pass body re-evaluation
/// (write-`@State` → body → write-`@State` → body) on every mutation.
@Observable
@MainActor
final class JournalModel {
    /// Per-entry category + timeline inputs, resolved once. This is the only
    /// place that hits `SubstanceLibrary` / computes PK inputs; filtering and
    /// regrouping then read from here instead of re-resolving on every tap.
    struct EntryDerived {
        let category: SubstanceCategory
        let state: ActiveSubstanceState?
        let marker: DoseMarker?
    }

    private(set) var derived: [PersistentIdentifier: EntryDerived] = [:]
    /// Categories present in the data, for the filter menu.
    private(set) var categories: [SubstanceCategory] = []
    /// Distinct tags across all entries, most-used first, for the chip bar.
    private(set) var tags: [String] = []
    private(set) var colorMap: [String: Color] = [:]

    /// The current filter result, plus the grouping buckets derived from it.
    private(set) var filtered: [DoseEntry] = []
    private(set) var sessionDays: [SessionDay] = []
    private(set) var substanceGroups: [(name: String, entries: [DoseEntry])] = []
    private(set) var categoryGroups: [(category: SubstanceCategory, entries: [DoseEntry])] = []

    /// Signature of the inputs `derived` was last built from — skips the
    /// redundant rebuild the appear-`.task` and the `entriesSignature`-`.task`
    /// would both run at launch, and the rebuild on every list re-appear when
    /// nothing changed.
    private var lastDerivedSignature: Int?
    /// Same guard for the grouping pass (bucketing + day-card formatting).
    private var lastGroupsSignature: Int?

    func refreshColorMap(_ colors: [SubstanceColor]) {
        colorMap = Array(colors).colorMap
    }

    /// Resolve each entry's category, timeline inputs, colour, and tags once.
    /// Run when entries or colours change — never on a filter tap. `entriesSignature`
    /// is the view's entries fingerprint; the colour count is folded in here so a
    /// recolour also invalidates.
    func rebuildDerived(entries: [DoseEntry], colors: [SubstanceColor], entriesSignature: Int) {
        var sigHasher = Hasher()
        sigHasher.combine(entriesSignature)
        sigHasher.combine(colors.count)
        let signature = sigHasher.finalize()
        guard signature != lastDerivedSignature else { return }
        lastDerivedSignature = signature

        let hexMap = Array(colors).hexColorMap
        var map: [PersistentIdentifier: EntryDerived] = [:]
        map.reserveCapacity(entries.count)
        var seen = Set<SubstanceCategory>()
        var cats: [SubstanceCategory] = []
        var tagCounts: [String: Int] = [:]
        for entry in entries {
            let category = SubstanceLibrary.lookupByNameOrAlias(entry.substance)?.category ?? .other
            if seen.insert(category).inserted { cats.append(category) }
            let hex = SubstancePalette.hex(for: entry.substance, hexMap: hexMap)
            let state = ActiveSubstanceState.from(entry: entry, colorHex: hex)
            let marker = state == nil
                ? DoseMarker(
                    substanceName: entry.substance,
                    timestamp: entry.timestamp,
                    colorHex: hex,
                    amount: entry.amount,
                    unit: entry.unit,
                )
                : nil
            map[entry.persistentModelID] = EntryDerived(category: category, state: state, marker: marker)
            for tag in entry.tags { tagCounts[tag, default: 0] += 1 }
        }
        derived = map
        categories = cats.sorted { $0.rawValue < $1.rawValue }
        tags = tagCounts.sorted { $0.value > $1.value }.map(\.key)
    }

    /// Re-filter and re-bucket. Pure grouping work — timelines come from
    /// `derived`, so no PK recompute. Guarded so an identical filter/grouping
    /// selection doesn't re-bucket.
    func rebuildGroups(
        entries: [DoseEntry],
        grouping: JournalGrouping,
        searchText: String,
        selectedTag: String?,
        filterCategories: Set<SubstanceCategory>,
        filterDay: Date?,
        stackRedoses: Bool,
    ) {
        var sigHasher = Hasher()
        sigHasher.combine(grouping)
        sigHasher.combine(searchText)
        sigHasher.combine(selectedTag)
        sigHasher.combine(filterCategories)
        sigHasher.combine(filterDay)
        sigHasher.combine(lastDerivedSignature)
        let signature = sigHasher.finalize()
        guard signature != lastGroupsSignature else { return }
        lastGroupsSignature = signature

        let calendar = Calendar.current
        let result = filteredEntries(
            entries: entries,
            searchText: searchText,
            selectedTag: selectedTag,
            filterCategories: filterCategories,
            filterDay: filterDay,
        )
        filtered = result

        switch grouping {
        case .recent:
            break // Uses `filtered` directly, no grouping needed.

        case .byDay:
            // Group the filtered doses by their persisted session (decided at log
            // time), build one card per session, then bucket the cards under day
            // headers by each session's start day. A filtered view simply shows
            // the subset of a session's doses — membership stays correct because
            // it was decided from *all* doses at assignment time, not here.
            var bySession: [PersistentIdentifier: (session: Session?, entries: [DoseEntry])] = [:]
            var order: [PersistentIdentifier] = []
            for entry in result {
                let key = entry.session?.persistentModelID ?? entry.persistentModelID
                if bySession[key] == nil {
                    bySession[key] = (entry.session, [])
                    order.append(key)
                }
                bySession[key]?.entries.append(entry)
            }

            var cards: [SessionCard] = []
            cards.reserveCapacity(order.count)
            for key in order {
                guard let bucket = bySession[key] else { continue }
                let sessionEntries = bucket.entries.sorted { $0.timestamp < $1.timestamp }
                var states: [ActiveSubstanceState] = []
                var markers: [DoseMarker] = []
                for entry in sessionEntries {
                    guard let d = derived[entry.persistentModelID] else { continue }
                    if let state = d.state { states.append(state) }
                    if let marker = d.marker { markers.append(marker) }
                }
                cards.append(SessionCard(session: bucket.session, entries: sessionEntries, states: states, markers: markers))
            }

            let byDay = Dictionary(grouping: cards) { calendar.startOfDay(for: $0.startDate) }
            sessionDays = byDay.sorted { $0.key > $1.key }.map { day, dayCards in
                SessionDay(date: day, sessions: dayCards.sorted { $0.startDate > $1.startDate })
            }

            // Prewarm each session card's PK geometry off-main so the compact
            // graphs render as synchronous cache hits when scrolled into view —
            // no placeholder→graph flip, no per-card detached task.
            TimelineGraphView.prewarm(
                cards.map { (substances: $0.states, markers: $0.markers) },
                stackRedoses: stackRedoses,
                dayBounded: true,
            )

        case .bySubstance:
            let grouped = Dictionary(grouping: result, by: \.substance)
            substanceGroups = grouped.sorted { $0.value.count > $1.value.count }
                .map { (name: $0.key, entries: $0.value) }

        case .byCategory:
            let grouped = Dictionary(grouping: result) { entry in
                derived[entry.persistentModelID]?.category ?? .other
            }
            categoryGroups = SubstanceCategory.allCases.compactMap { cat in
                guard let entries = grouped[cat], !entries.isEmpty else { return nil }
                return (category: cat, entries: entries)
            }
        }
    }

    private func filteredEntries(
        entries: [DoseEntry],
        searchText: String,
        selectedTag: String?,
        filterCategories: Set<SubstanceCategory>,
        filterDay: Date?,
    ) -> [DoseEntry] {
        var result = entries

        if let selectedTag {
            result = result.filter { $0.tags.contains(selectedTag) }
        }

        if !searchText.isEmpty {
            let query = searchText
            if query.hasPrefix("#") {
                let tagQuery = String(query.dropFirst()).lowercased()
                if !tagQuery.isEmpty {
                    result = result.filter { entry in
                        entry.tags.contains { $0.localizedCaseInsensitiveContains(tagQuery) }
                    }
                }
            } else {
                result = result.filter {
                    $0.substance.localizedCaseInsensitiveContains(query) ||
                        ($0.notes?.localizedCaseInsensitiveContains(query) ?? false) ||
                        $0.tags.contains { $0.localizedCaseInsensitiveContains(query) }
                }
            }
        }

        if let day = filterDay {
            let start = Calendar.current.sessionDayStart(for: day)
            let end = start.addingTimeInterval(86_400)
            result = result.filter { $0.timestamp >= start && $0.timestamp < end }
        }

        if !filterCategories.isEmpty {
            result = result.filter { entry in
                guard let category = derived[entry.persistentModelID]?.category else { return false }
                return filterCategories.contains(category)
            }
        }

        return result
    }
}
