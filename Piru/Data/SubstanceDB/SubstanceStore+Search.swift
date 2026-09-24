import Foundation

/// One ranked search hit: the resolved substance plus the name the query
/// actually matched.
///
/// `matchedAlias` is the load-bearing half. A user searching "Concerta" gets
/// substance 459 (Methylphenidate) — correct, but the typed string matters
/// too: carrying the alias out lets the search row echo what it matched and
/// lets a staged dose record the *product* the user actually named
/// (`Specs/psid-identity-consumption.md` D.1).
struct SubstanceMatch: Identifiable {
    let substance: Substance
    /// The catalog alias the query named, in its display casing ("Concerta",
    /// "Vyvanse"). `nil` when the query matched the canonical name, when it only
    /// matched loosely (contains/fuzzy — too weak a signal that the user meant
    /// *that* alias), or when the alias has no display form on record.
    let matchedAlias: String?

    var id: String {
        substance.name.lowercased()
    }

    /// What to title this hit: the user's word when they named one, else the
    /// catalog's. The subtitle side is the caller's business.
    var displayName: String {
        matchedAlias ?? substance.displayTitle
    }
}

extension SubstanceStore {
    // MARK: - Search

    /// Ranked search: exact name → alias → prefix → contains → fuzzy, keeping
    /// the matched alias on each hit.
    ///
    /// Resolves from the warm batch cache (no per-result SQL). Synchronous entry
    /// kept for tests and non-interactive callers; the interactive search field
    /// uses ``searchMatchesAsync(_:limit:)`` so the ranking never runs on the
    /// main thread.
    func searchMatches(_ query: String, limit: Int = 50) -> [SubstanceMatch] {
        Self.rankedSearch(
            query, nameIndex: nameIndex, aliasIndex: aliasIndex,
            aliasDisplayIndex: aliasDisplayIndex,
            idToSubstance: batchByIDIndex(), limit: limit,
        )
    }

    /// Off-main ranked search: snapshot the (Sendable) indexes on the main actor,
    /// then rank + resolve on a background task. The keystroke handler awaits this
    /// instead of calling `searchMatches` directly, so neither the index scan /
    /// fuzzy pass nor result resolution stalls the keyboard. The snapshots are
    /// copy-on-write dictionaries, so handing them to the detached task is cheap.
    func searchMatchesAsync(_ query: String, limit: Int = 50) async -> [SubstanceMatch] {
        await ensureAllLoaded()
        let names = nameIndex
        let aliases = aliasIndex
        let aliasDisplay = aliasDisplayIndex
        let byID = batchByIDIndex()
        return await Task.detached(priority: .userInitiated) {
            Self.rankedSearch(
                query, nameIndex: names, aliasIndex: aliases,
                aliasDisplayIndex: aliasDisplay, idToSubstance: byID, limit: limit,
            )
        }.value
    }

    /// Pure ranking over the index snapshots — runnable on any thread. Tiers run
    /// exact → prefix → contains → fuzzy, and each tier is sorted by a total order
    /// (shorter key first, then lexicographic) because the indexes are
    /// dictionaries, whose iteration order changes from launch to launch.
    nonisolated static func rankedSearch(
        _ query: String,
        nameIndex: [String: Int64],
        aliasIndex: [String: Int64],
        aliasDisplayIndex: [String: String],
        idToSubstance: [Int64: Substance],
        limit: Int,
    ) -> [SubstanceMatch] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        var exactIDs: [Int64] = []
        var prefixIDs: [Int64] = []
        var containsIDs: [Int64] = []
        var seen = Set<Int64>()
        // id → the normalized alias the query named. Only exact and prefix hits
        // register: a *contains* match ("in" hitting "Ritalin") is no evidence the
        // user meant that alias, and titling a row from it would put words in
        // their mouth. Fuzzy never registers — it only scans `nameIndex`.
        var aliasHits: [Int64: String] = [:]

        /// Keep the shortest match per id, ties broken lexicographically.
        /// `aliasIndex` is a dictionary, so its iteration order is unspecified —
        /// without a total order here, "rital" could title a row "Ritalin SR" on
        /// one keystroke and "Ritalin LA" on the next. Shortest-wins also happens
        /// to be the intuitive answer ("rital" → "Ritalin").
        func noteAlias(_ key: String, _ id: Int64) {
            guard let existing = aliasHits[id] else { aliasHits[id] = key; return }
            if (key.count, key) < (existing.count, existing) { aliasHits[id] = key }
        }

        if let id = nameIndex[q] {
            exactIDs.append(id); seen.insert(id)
        } else if let id = aliasIndex[q] {
            exactIDs.append(id); seen.insert(id); noteAlias(q, id)
        }
        func byKey(_ lhs: (key: String, id: Int64), _ rhs: (key: String, id: Int64)) -> Bool {
            (lhs.key.count, lhs.key) < (rhs.key.count, rhs.key)
        }
        var namePrefix: [(key: String, id: Int64)] = []
        var nameContains: [(key: String, id: Int64)] = []
        for (key, id) in nameIndex where !seen.contains(id) {
            if key.hasPrefix(q) { namePrefix.append((key, id)) } else if key.contains(q) { nameContains.append((key, id)) }
        }
        for hit in namePrefix.sorted(by: byKey) where seen.insert(hit.id).inserted {
            prefixIDs.append(hit.id)
        }
        for hit in nameContains.sorted(by: byKey) where seen.insert(hit.id).inserted {
            containsIDs.append(hit.id)
        }
        // Collect every alias-prefix candidate first, then claim by (length,
        // lexicographic), so both the ranking and the displayed alias are
        // deterministic and the shortest alias wins.
        for (key, id) in aliasIndex where !seen.contains(id) && key.hasPrefix(q) {
            noteAlias(key, id)
        }
        for (id, _) in aliasHits.sorted(by: { ($0.value.count, $0.value) < ($1.value.count, $1.value) })
            where !seen.contains(id) {
            prefixIDs.append(id); seen.insert(id)
        }
        let aliasContains = aliasIndex.filter { !seen.contains($0.value) && $0.key.contains(q) }
            .map { (key: $0.key, id: $0.value) }
        for hit in aliasContains.sorted(by: byKey) where seen.insert(hit.id).inserted {
            containsIDs.append(hit.id)
        }

        var ranked: [Int64] = exactIDs + prefixIDs + containsIDs
        if ranked.count > limit {
            ranked = Array(ranked.prefix(limit))
        }
        if ranked.count < limit, q.count >= 4 {
            let needed = limit - ranked.count
            ranked.append(contentsOf: fuzzyMatch(q, nameIndex: nameIndex, excluding: seen, limit: needed))
        }
        return ranked.prefix(limit).compactMap { id in
            guard let substance = idToSubstance[id] else { return nil }
            // Normalized → display casing via the catalog's own mapping rather
            // than re-deriving it: `alias_normalized` is the pipeline's
            // normalization (Greek-cap folding and all), which Swift's
            // `lowercased()` does not reproduce.
            let alias = aliasHits[id].flatMap { aliasDisplayIndex[$0] }
            return SubstanceMatch(substance: substance, matchedAlias: alias)
        }
    }

    private nonisolated static func fuzzyMatch(_ query: String, nameIndex: [String: Int64], excluding seen: Set<Int64>, limit: Int) -> [Int64] {
        let maxDist = max(1, Int(Double(query.count) * 0.3))
        let queryChars = Array(query)
        var matches: [(id: Int64, distance: Int, key: String)] = []
        for (key, id) in nameIndex where !seen.contains(id) {
            // Distance is at least the length difference — skip most of the
            // catalog without touching the DP table (or allocating for it).
            guard abs(key.count - queryChars.count) <= maxDist else { continue }
            if let d = levenshtein(queryChars, Array(key), cap: maxDist) {
                matches.append((id, d, key))
            }
        }
        // Ties on distance break by (length, key) so the cut at `limit` is stable.
        return matches
            .sorted { ($0.distance, $0.key.count, $0.key) < ($1.distance, $1.key.count, $1.key) }
            .prefix(limit).map(\.id)
    }

    /// Capped Levenshtein: `nil` as soon as every cell of a DP row exceeds
    /// `cap`, since the distance can only grow from there — the common case
    /// for the ~1,700 non-matching names each fuzzy pass scans.
    private nonisolated static func levenshtein(_ a: [Character], _ b: [Character], cap: Int) -> Int? {
        if a.isEmpty { return b.count <= cap ? b.count : nil }
        if b.isEmpty { return a.count <= cap ? a.count : nil }
        var prev = Array(0 ... b.count)
        var curr = [Int](repeating: 0, count: b.count + 1)
        for i in 1 ... a.count {
            curr[0] = i
            var rowMin = curr[0]
            for j in 1 ... b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
                rowMin = min(rowMin, curr[j])
            }
            if rowMin > cap { return nil }
            swap(&prev, &curr)
        }
        return prev[b.count] <= cap ? prev[b.count] : nil
    }
}
