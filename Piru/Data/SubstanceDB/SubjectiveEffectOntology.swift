import Foundation
import GRDB
import os

private nonisolated let logger = Logger(subsystem: "dev.yumeji.piru", category: "SubjectiveEffects")

/// One SubFxOnEx concept — a rollup (a top-level group, one per domain) or an
/// atomic effect under a rollup. Read from `subjective_effect_concepts`.
nonisolated struct SubjectiveEffectConcept: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let slug: String
    let domain: String
    let isRollup: Bool
    let parentID: String?
    let position: Int
    let definition: String?
}

/// A search hit: the concept plus the alias label that matched, when the match
/// came through an alias rather than the concept's own name.
nonisolated struct SubjectiveEffectHit: Identifiable, Hashable, Sendable {
    let concept: SubjectiveEffectConcept
    let matchedAlias: String?
    var id: String {
        concept.id
    }
}

/// The session-note descriptor vocabulary, loaded once from the bundled DB and
/// held in memory: 21 rollups, their atomic concepts, and the alias index the
/// chip search runs over. ~500 concepts + ~1,200 aliases, so the whole thing is
/// a few hundred kilobytes and two queries.
///
/// Loaded lazily on first use, synchronously — the tables are tiny and the
/// first read is on the note sheet's open, where a spinner would cost more
/// than the query. Call ``load()`` early (a `.task`) to pay it off-path.
@MainActor
@Observable
final class SubjectiveEffectOntology {
    static let shared = SubjectiveEffectOntology()

    private(set) var isLoaded = false
    private var rollupList: [SubjectiveEffectConcept] = []
    private var atomicsByParent: [String: [SubjectiveEffectConcept]] = [:]
    private var byID: [String: SubjectiveEffectConcept] = [:]
    /// `(normalized label, display label, concept id)`, sorted by label.
    private var aliasIndex: [(normalized: String, label: String, effectID: String)] = []

    /// Every rollup in the release's display order.
    var rollups: [SubjectiveEffectConcept] {
        load()
        return rollupList
    }

    /// The atomic concepts under a rollup, in display order.
    func atomics(under rollup: SubjectiveEffectConcept) -> [SubjectiveEffectConcept] {
        load()
        return atomicsByParent[rollup.id] ?? []
    }

    func concept(id: String) -> SubjectiveEffectConcept? {
        load()
        return byID[id]
    }

    /// The rollup a concept belongs to (itself, for a rollup).
    func rollup(of concept: SubjectiveEffectConcept) -> SubjectiveEffectConcept? {
        guard let parentID = concept.parentID else { return concept.isRollup ? concept : nil }
        return byID[parentID]
    }

    /// Display name for a stored descriptor id; the id itself when it no longer
    /// resolves, so an old note never shows a blank chip.
    func name(for id: String) -> String {
        concept(id: id)?.name ?? id
    }

    /// Rank concepts for a chip-search query: exact name, name prefix, alias
    /// prefix, name contains, alias contains. Rollups are searchable too (they
    /// are legitimate descriptors — "body load" is a chip of its own).
    func search(_ query: String, limit: Int = 30) -> [SubjectiveEffectHit] {
        load()
        let q = Self.normalize(query)
        guard !q.isEmpty else { return [] }
        var scored: [String: (score: Int, alias: String?)] = [:]
        func consider(_ id: String, score: Int, alias: String?) {
            if let current = scored[id], current.score <= score { return }
            scored[id] = (score, alias)
        }
        for concept in byID.values {
            let name = Self.normalize(concept.name)
            if name == q {
                consider(concept.id, score: 0, alias: nil)
            } else if name.hasPrefix(q) {
                consider(concept.id, score: 1, alias: nil)
            } else if name.contains(q) {
                consider(concept.id, score: 3, alias: nil)
            }
        }
        for alias in aliasIndex {
            if alias.normalized.hasPrefix(q) {
                consider(alias.effectID, score: 2, alias: alias.label)
            } else if alias.normalized.contains(q) {
                consider(alias.effectID, score: 4, alias: alias.label)
            }
        }
        return scored
            .compactMap { id, entry -> (SubjectiveEffectHit, Int)? in
                guard let concept = byID[id] else { return nil }
                return (SubjectiveEffectHit(concept: concept, matchedAlias: entry.alias), entry.score)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0.concept.name < rhs.0.concept.name
            }
            .prefix(limit)
            .map(\.0)
    }

    /// The release's label normalization (`subfxonex-normalization-v1`): NFKD,
    /// combining marks stripped, lowercase, every dash to ASCII `-`, underscores
    /// to spaces, whitespace collapsed. Applied to queries so a typed
    /// "Closed–eye" matches the stored "closed-eye".
    nonisolated static func normalize(_ raw: String) -> String {
        var s = raw.decomposedStringWithCompatibilityMapping
        s = s.unicodeScalars.filter { !$0.properties.isDiacritic }.map { String($0) }.joined()
        // Greek letters are spelled out before lowercasing, or Δ would become δ.
        for (symbol, word) in [("Δ", "delta"), ("δ", "delta"), ("α", "alpha"), ("β", "beta")] {
            s = s.replacingOccurrences(of: symbol, with: word)
        }
        s = s.lowercased()
        for dash in ["‐", "‑", "‒", "–", "—", "―", "−"] {
            s = s.replacingOccurrences(of: dash, with: "-")
        }
        s = s.replacingOccurrences(of: "_", with: " ")
        return s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: - Load

    /// Read both tables once. A database without them (an OTA update from
    /// before the vocabulary shipped) loads as empty rather than failing.
    func load() {
        guard !isLoaded else { return }
        isLoaded = true
        do {
            let (concepts, aliases) = try SubstanceStore.shared.substancesDB.read { db -> ([SubjectiveEffectConcept], [(String, String, String)]) in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT id, name, slug, domain, kind, parent_id, position, definition
                      FROM subjective_effect_concepts
                     ORDER BY position, name
                """)
                let concepts = rows.map { row in
                    SubjectiveEffectConcept(
                        id: row["id"], name: row["name"], slug: row["slug"], domain: row["domain"],
                        isRollup: (row["kind"] as String) == "rollup",
                        parentID: row["parent_id"], position: row["position"], definition: row["definition"],
                    )
                }
                let aliasRows = try Row.fetchAll(db, sql: """
                    SELECT normalized_label, label, effect_id
                      FROM subjective_effect_concept_aliases
                     ORDER BY normalized_label
                """)
                let aliases = aliasRows.map { ($0["normalized_label"] as String, $0["label"] as String, $0["effect_id"] as String) }
                return (concepts, aliases)
            }
            byID = Dictionary(concepts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            rollupList = concepts.filter(\.isRollup)
            atomicsByParent = Dictionary(grouping: concepts.filter { !$0.isRollup && $0.parentID != nil }, by: { $0.parentID! })
            aliasIndex = aliases.map { (normalized: $0.0, label: $0.1, effectID: $0.2) }
        } catch {
            logger.error("Subjective-effect vocabulary unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }
}
