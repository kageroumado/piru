import SwiftData
import SwiftUI

/// Owns the Journal's *derived* state — per-entry resolution, the grouped
/// buckets, the color map, the category facets, and the tag list — so it lives
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
    /// Distinct tags across all entries, most-used first, for the filter menu.
    private(set) var tags: [String] = []
    /// Routes present in the data (declaration order), for the filter menu.
    private(set) var routes: [RouteOfAdministration] = []
    private(set) var colorMap: [String: Color] = [:]

    /// The current filter result, plus the grouping buckets derived from it.
    private(set) var filtered: [DoseEntry] = []
    private(set) var sessionDays: [SessionDay] = []
    private(set) var substanceGroups: [(name: String, entries: [DoseEntry])] = []
    private(set) var categoryGroups: [(category: SubstanceCategory, entries: [DoseEntry])] = []

    /// The Day list is *windowed*: only the most recent `sessionWindow` sessions
    /// are turned into `SessionCard`s + rendered `Section`s, so a 149-session
    /// history doesn't build (and animate in) every card on first appear. The
    /// view extends the window as the user scrolls to the bottom. `true` while
    /// older sessions remain unbuilt — drives the load-more sentinel.
    private(set) var hasMoreSessions = false
    // First page is small so the Journal's first appear builds a handful of
    // session cards (each carrying a PK graph) instead of 25 — the eager build
    // of the full window was the bulk of the Journal first-render hang. The view
    // grows the window on scroll, so deeper history is one scroll away.
    private static let sessionPageSize = 12
    private var sessionWindow = sessionPageSize

    /// Same guard for the grouping pass (bucketing + day-card formatting).
    private var lastGroupsSignature: Int?

    /// Bumped every time `derived` is *published with a change* (the phase-1
    /// prefix resolve, and the phase-2 tail when it resolved anything new). Folded
    /// into ``rebuildGroups``'s signature so a regroup that ran against an empty or
    /// stale `derived` — e.g. the search `.task` firing its `regroup()` while the
    /// entries `.task` is still suspended at the cold-launch batch-cache `await` —
    /// is *superseded* once the real states land, instead of poisoning
    /// `lastGroupsSignature` and short-circuiting the graphs-bearing rebuild.
    private var derivedRevision = 0

    /// Per-entry content fingerprint from the last derive, keyed by identity.
    /// The diff engine compares each entry's current fingerprint against this to
    /// decide what to re-resolve — so a new dose against five years of history
    /// resolves *one* entry, not the whole table. See ``rebuildDerived``.
    private var fingerprints: [PersistentIdentifier: Int] = [:]
    /// Signature of the color assignments the `derived` states were resolved
    /// under. A recolor changes every entry's `colorHex`, so it forces a full
    /// re-resolve (rare — only when the user assigns a substance color).
    private var lastColorSignature: Int?

    /// Monotonic token so a newer ``rebuildDerived`` supersedes an older one
    /// that's still suspended at an `await` (the cold-launch batch-cache wait, or
    /// a tail yield). The stale derive bails at its next checkpoint rather than
    /// clobbering published state with a half-resolved or out-of-date map.
    private var deriveGeneration = 0

    /// Hard cap on the synchronous derive prefix. The prefix normally covers
    /// *exactly* the visible window's sessions (so their cards paint with full
    /// graphs, no flash), but a pathologically large single session could make
    /// that span the whole history — this bounds the synchronous burst and lets
    /// the overflow resolve in the yielding tail.
    private static let maxSyncPrefix = 400

    func refreshColorMap(_ colors: [SubstanceColor]) {
        colorMap = Array(colors).colorMap
    }

    /// Extend the Day list by one page of older sessions. Clearing the groups
    /// signature forces the next `rebuildGroups` to re-bucket with the larger
    /// window (the window is folded into the signature, so this is also safe to
    /// no-op if nothing else changed).
    func growSessionWindow() {
        guard hasMoreSessions else { return }
        sessionWindow += Self.sessionPageSize
        lastGroupsSignature = nil
    }

    /// Collapse the Day list back to the first page — called when the filter,
    /// search, or grouping changes so a fresh result starts at the top, not at
    /// whatever depth the previous scroll had reached.
    func resetSessionWindow() {
        guard sessionWindow != Self.sessionPageSize else { return }
        sessionWindow = Self.sessionPageSize
        lastGroupsSignature = nil
    }

    /// The session keys of the first `limit` distinct sessions in newest-first
    /// entry order — the sessions `rebuildGroups` materializes into the visible
    /// Day window. A session-less straggler keys on its own id (matching the
    /// grouping's `entry.session?.id ?? entry.id`), so each counts as one.
    private static func windowSessionKeys(_ entries: [DoseEntry], limit: Int) -> Set<PersistentIdentifier> {
        var keys = Set<PersistentIdentifier>()
        keys.reserveCapacity(limit)
        for entry in entries {
            if keys.count >= limit { break }
            keys.insert(entry.session?.persistentModelID ?? entry.persistentModelID)
        }
        return keys
    }

    /// The fields `derived` actually depends on, hashed cheaply (no SQL / PK).
    /// Drives the diff: an entry whose fingerprint is unchanged keeps its cached
    /// `EntryDerived` instead of re-resolving the substance + timeline.
    private static func fingerprint(_ entry: DoseEntry) -> Int {
        var hasher = Hasher()
        hasher.combine(entry.timestamp)
        hasher.combine(entry.amount)
        hasher.combine(entry.substance)
        hasher.combine(entry.route)
        hasher.combine(entry.unit)
        return hasher.finalize()
    }

    /// Resolve a single entry's category + timeline inputs (the expensive part:
    /// the `SubstanceLibrary` lookup and PK-state synthesis).
    private func resolveEntry(_ entry: DoseEntry, hexMap: [String: String]) -> EntryDerived {
        let category = SubstanceLibrary.timelineLookup(entry.substance)?.category ?? .other
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
        return EntryDerived(category: category, state: state, marker: marker)
    }

    /// Incrementally resolve each entry's category, timeline inputs, and color.
    /// Run when entries or colors change — never on a filter tap.
    ///
    /// A **diff engine**: it fingerprints every entry (cheap — no SQL/PK), then
    /// re-resolves only the entries that are new or whose fingerprint changed and
    /// drops the ones that disappeared, reusing the cached `EntryDerived` for the
    /// rest. So logging one dose into a five-year history does one expensive
    /// resolve, not thousands. A color change is the one fast-path exception:
    /// it alters every state's `colorHex`, so it re-resolves the whole set (rare).
    /// - Parameter onPrefixReady: Invoked once the newest-first prefix (the
    ///   visible Day window) has been resolved and published, so the caller can
    ///   regroup and paint the cards before the tail finishes. Not called when a
    ///   newer derive has already superseded this one.
    func rebuildDerived(
        entries: [DoseEntry],
        colors: [SubstanceColor],
        onPrefixReady: () -> Void = {},
    ) async {
        deriveGeneration += 1
        let gen = deriveGeneration

        // Resolve against the lightweight batch cache (category, dose-ranges,
        // durations, half-life). Awaiting the off-main prefill started at launch
        // turns the per-entry resolves into dict hits instead of ~50 cold heavy
        // SQL reads on the main actor. A newer derive may land while we wait.
        await SubstanceStore.shared.ensureAllLoaded()
        guard gen == deriveGeneration else { return }

        let colorSignature = colors.reduce(into: Hasher()) { h, c in
            h.combine(c.substance)
            h.combine(c.hexColor)
        }.finalize()
        let colorsChanged = colorSignature != lastColorSignature
        let hexMap = Array(colors).hexColorMap

        var newDerived: [PersistentIdentifier: EntryDerived] = colorsChanged ? [:] : derived
        newDerived.reserveCapacity(entries.count)
        var newFingerprints: [PersistentIdentifier: Int] = [:]
        newFingerprints.reserveCapacity(entries.count)
        var resolvedCount = 0

        /// Resolve one newest-first slice into the working map, reusing the cached
        /// `EntryDerived` for entries byte-identical to the last derive.
        func resolve(_ slice: ArraySlice<DoseEntry>) {
            for entry in slice {
                let id = entry.persistentModelID
                let fp = Self.fingerprint(entry)
                newFingerprints[id] = fp
                if !colorsChanged, fingerprints[id] == fp, newDerived[id] != nil {
                    continue
                }
                newDerived[id] = resolveEntry(entry, hexMap: hexMap)
                resolvedCount += 1
            }
        }

        // Partition into the entries the visible window's cards need (resolved
        // synchronously, so those cards paint with full graphs) and the rest
        // (resolved in the yielding tail). Membership is by session — matching
        // how `rebuildGroups` buckets and windows — so the prefix covers exactly
        // the painted sessions even when one spans many doses or sessions
        // interleave in time, instead of a flat entry count that could
        // under-cover and flash an empty graph. Capped so a single huge session
        // can't make the synchronous burst span the whole history.
        //
        // Best-effort: `windowKeys` is derived from the *unfiltered* `entries`,
        // while `rebuildGroups` windows the *filtered* result. With no filter
        // (the launch / common path) they coincide and the painted cards get
        // their graphs synchronously. Under an active search/tag/category filter
        // the painted window may be older sessions whose entries fall in the
        // yielding tail — those cards briefly show markers until phase 2 lands.
        // Acceptable: it only bites on a cold derive or color change *while a
        // filter is active* (a re-derive with unchanged colors seeds `newDerived`
        // from the already-resolved `derived`, so nothing flashes), and the tail
        // always converges. Matching the filter here would couple the model to
        // the view's filter predicate for a one-frame cosmetic win.
        let windowKeys = Self.windowSessionKeys(entries, limit: sessionWindow)
        var prefixEntries: [DoseEntry] = []
        var tailEntries: [DoseEntry] = []
        for entry in entries {
            let key = entry.session?.persistentModelID ?? entry.persistentModelID
            if windowKeys.contains(key), prefixEntries.count < Self.maxSyncPrefix {
                prefixEntries.append(entry)
            } else {
                tailEntries.append(entry)
            }
        }

        // Phase 1 — the visible window, resolved synchronously. Publish it so the
        // Day cards paint immediately. When colors didn't change, `newDerived`
        // still carries the previous tail entries (outside the window), so the
        // list never shows holes while phase 2 catches up.
        resolve(prefixEntries[...])
        let prefixChanged = colorsChanged || resolvedCount > 0
        let prefixResolved = resolvedCount
        if prefixChanged {
            derived = newDerived
            derivedRevision += 1
            onPrefixReady()
        }

        // Phase 2 — the tail, in yielding chunks so a long history never hogs a
        // frame. Bail at each checkpoint if a newer derive superseded us.
        if !tailEntries.isEmpty {
            var index = 0
            let chunkSize = 200
            while index < tailEntries.count {
                let end = min(index + chunkSize, tailEntries.count)
                resolve(tailEntries[index ..< end])
                index = end
                await Task.yield()
                guard gen == deriveGeneration else { return }
            }
        }

        // Drop entries that no longer exist (deletions / merges away) — any key
        // carried over from the old map that isn't in the current entry set.
        let removed = newDerived.keys.filter { newFingerprints[$0] == nil }
        for id in removed {
            newDerived[id] = nil
        }

        // Nothing actually changed — bail before touching published state so a
        // no-op trigger doesn't invalidate the views downstream.
        if !colorsChanged, resolvedCount == 0, removed.isEmpty {
            return
        }

        derived = newDerived
        fingerprints = newFingerprints
        lastColorSignature = colorSignature
        // Bump the revision when the *tail* (resolved after the phase-1 regroup)
        // changed `derived`, so the caller's final `rebuildGroups` — and any later
        // regroup — rebuilds the affected cards instead of no-opping on a stale
        // signature. The revision (not a blunt `lastGroupsSignature = nil`) is what
        // distinguishes "derived changed, rebuild" from "same filters, skip", so a
        // windowed Day grouping whose visible cards are unchanged still settles to
        // a byte-identical `sessionDays` cheaply (SessionCardView is `Equatable`),
        // while a non-windowed grouping showing tail entries re-buckets correctly.
        if resolvedCount > prefixResolved || !removed.isEmpty {
            derivedRevision += 1
        }
        rebuildFacets(entries: entries)
    }

    /// Recompute the category facets + tag list from the (already resolved)
    /// `derived` map and the entries. Cheap aggregation — no SQL/PK — so running
    /// it on every derive is fine even though only a diff was resolved.
    private func rebuildFacets(entries: [DoseEntry]) {
        var seen = Set<SubstanceCategory>()
        var cats: [SubstanceCategory] = []
        var tagCounts: [String: Int] = [:]
        var seenRoutes = Set<RouteOfAdministration>()
        for entry in entries {
            if let category = derived[entry.persistentModelID]?.category, seen.insert(category).inserted {
                cats.append(category)
            }
            for tag in entry.tags {
                tagCounts[tag, default: 0] += 1
            }
            seenRoutes.insert(entry.route)
        }
        categories = cats.sorted { $0.rawValue < $1.rawValue }
        tags = tagCounts.sorted { $0.value > $1.value }.map(\.key)
        routes = RouteOfAdministration.allCases.filter(seenRoutes.contains)
    }

    /// Re-filter and re-bucket. Pure grouping work — timelines come from
    /// `derived`, so no PK recompute. Guarded so an identical filter/grouping
    /// selection doesn't re-bucket.
    func rebuildGroups(
        entries: [DoseEntry],
        grouping: JournalGrouping,
        searchText: String,
        filterTags: Set<String>,
        filterCategories: Set<SubstanceCategory>,
        filterRoutes: Set<RouteOfAdministration>,
        stackRedoses: Bool,
        entriesSignature: Int,
    ) {
        var sigHasher = Hasher()
        sigHasher.combine(grouping)
        sigHasher.combine(searchText)
        sigHasher.combine(filterTags)
        sigHasher.combine(filterCategories)
        sigHasher.combine(filterRoutes)
        // Fold the entries fingerprint in so a change that affects *grouping*
        // but not per-entry resolution — a session split/merge, a moved
        // timestamp — still re-buckets. (The derive step may legitimately no-op
        // on such a change, since `EntryDerived` doesn't depend on session.)
        sigHasher.combine(entriesSignature)
        // The Day window is part of the signature so `growSessionWindow()` /
        // `resetSessionWindow()` re-bucket, while an unrelated re-entry no-ops.
        sigHasher.combine(sessionWindow)
        // The derive revision so a regroup that ran against an empty/stale
        // `derived` (the cold-launch race: search `.task` regroups before the
        // entries `.task` resolves the prefix) is superseded once the real states
        // land — otherwise the matching signature short-circuits the rebuild and
        // the cards keep their empty graphs until an unrelated change forces a
        // re-bucket.
        sigHasher.combine(derivedRevision)
        let signature = sigHasher.finalize()
        guard signature != lastGroupsSignature else { return }
        lastGroupsSignature = signature

        // Only the Day grouping is windowed; reset the flag so the load-more
        // sentinel never lingers under Recent / Substance / Category.
        hasMoreSessions = false

        let calendar = Calendar.current
        let result = filteredEntries(
            entries: entries,
            searchText: searchText,
            filterTags: filterTags,
            filterCategories: filterCategories,
            filterRoutes: filterRoutes,
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

            // Window the build: `order` is newest-first, so the first
            // `sessionWindow` keys are the most recent sessions. Only those
            // become cards (and, downstream, rendered `Section`s + prewarmed
            // graphs). Bucketing the *whole* history above keeps a session's
            // doses complete even when sessions overlap in time; we just stop
            // materializing once the window is full. The view grows the window
            // on scroll.
            let windowed = order.prefix(sessionWindow)
            hasMoreSessions = order.count > windowed.count

            var cards: [SessionCard] = []
            cards.reserveCapacity(windowed.count)
            for key in windowed {
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

            // Calendar-display bucketing — deliberately plain `startOfDay`, not
            // `calendar.sessionDayStart`. The day header names a calendar date
            // and the cards under it show raw timestamps, so the two must agree:
            // a fresh 2 AM session under the previous day's header would
            // contradict its own times. Late-night doses still roll into the
            // prior evening's card the natural way — gap-based session
            // clustering keeps them in the session that started that evening.
            // Session-day bucketing that honors the user's day-cutoff hour
            // (`sessionDayStart`) lives where days are *counted*, not displayed:
            // DataExportImport, PDFReportGenerator, ActiveSessionManager, and
            // the Insights stats.
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
        filterTags: Set<String>,
        filterCategories: Set<SubstanceCategory>,
        filterRoutes: Set<RouteOfAdministration>,
    ) -> [DoseEntry] {
        var result = entries

        // Within a facet the selected values OR together (any matching tag);
        // across facets they AND (must match tag *and* category *and* route).
        if !filterTags.isEmpty {
            result = result.filter { entry in
                entry.tags.contains(where: filterTags.contains)
            }
        }

        if !filterRoutes.isEmpty {
            result = result.filter { filterRoutes.contains($0.route) }
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

        if !filterCategories.isEmpty {
            result = result.filter { entry in
                guard let category = derived[entry.persistentModelID]?.category else { return false }
                return filterCategories.contains(category)
            }
        }

        return result
    }
}
