import Foundation
import GRDB

/// Effect resolution: the two effect tables and how each one is rendered in the
/// language being read.
///
/// `effects` is one row per canonical PsychonautWiki term with a `vocab_id`;
/// `subjective_effects` is one row per language, richer and messier. Both
/// resolve their label through `effect_vocab_labels`, which is what lets a row
/// written in one language be read in another.
extension SubstanceStore {
    /// SQL scalar resolving a row of `effects` (table aliased `e`) to its
    /// localized label via the controlled vocabulary (Track 1). For Chinese it
    /// returns the `effect_vocab_labels` label for the exact variant, then any
    /// broader zh label, then the raw English `e.text` fallback — so a zh user
    /// sees translated effects on *every* substance, even ones whose source data
    /// was English-only, because the label was translated once at the vocabulary
    /// level. For English it is simply `e.text` (already the canonical PW name).
    nonisolated static func localizedEffectLabelSQL(_ language: ContentLanguage) -> String {
        guard language.isChinese else { return "e.text" }
        return """
        COALESCE(
            (SELECT lbl.label FROM effect_vocab_labels lbl
              WHERE lbl.vocab_id = e.vocab_id AND lbl.language = '\(language.rawValue)'),
            (SELECT lbl.label FROM effect_vocab_labels lbl
              WHERE lbl.vocab_id = e.vocab_id AND lbl.language LIKE 'zh%' LIMIT 1),
            e.text)
        """
    }

    func resolvedEffects(db: Database, substanceID: Int64, language: ContentLanguage) throws -> [String] {
        try String.fetchAll(db, sql: """
            SELECT DISTINCT \(Self.localizedEffectLabelSQL(language)) AS text
              FROM effects e
              JOIN sources src ON src.id = e.source_id
             WHERE e.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
             ORDER BY text
        """, arguments: [substanceID])
    }

    /// SQL scalar resolving a `subjective_effects` row (aliased `se`) to its
    /// label in `language`, via the controlled vocabulary and falling back to
    /// the raw stored name.
    ///
    /// Rows are stored once per language, so a substance whose only effect
    /// source writes Chinese has nothing an English reader can be shown until
    /// the vocabulary bridges it. Pair this with ``subjectiveLanguageFilterSQL``
    /// — on its own the COALESCE would fall through to a Han `se.name`.
    nonisolated static func subjectiveLabelSQL(_ language: ContentLanguage) -> String {
        guard language.isChinese else {
            return """
            COALESCE(
                (SELECT lbl.label FROM effect_vocab_labels lbl
                  WHERE lbl.vocab_id = se.vocab_id AND lbl.language = 'en'),
                se.name)
            """
        }
        return """
        COALESCE(
            (SELECT lbl.label FROM effect_vocab_labels lbl
              WHERE lbl.vocab_id = se.vocab_id AND lbl.language = '\(language.rawValue)'),
            (SELECT lbl.label FROM effect_vocab_labels lbl
              WHERE lbl.vocab_id = se.vocab_id AND lbl.language LIKE 'zh%' LIMIT 1),
            se.name)
        """
    }

    /// Which rows can be *rendered* in `language`: the ones written in it, plus
    /// the ones the vocabulary can translate into it.
    nonisolated static func subjectiveLanguageFilterSQL(_ language: ContentLanguage) -> String {
        guard language.isChinese else {
            // Every vocab_id carries an English label by construction, so a
            // vocab hit is enough on its own.
            return "AND (se.language IN ('en', 'und') OR se.vocab_id IS NOT NULL)"
        }
        return """
        AND (se.language LIKE 'zh%'
             OR EXISTS (SELECT 1 FROM effect_vocab_labels l2
                         WHERE l2.vocab_id = se.vocab_id AND l2.language LIKE 'zh%'))
        """
    }

    func resolvedSubjectiveEffects(db: Database, substanceID: Int64, language: ContentLanguage) throws -> [SubjectiveEffect] {
        let label = Self.subjectiveLabelSQL(language)
        let ownLanguage = language.isChinese ? "se.language LIKE 'zh%'" : "se.language IN ('en', 'und')"

        func fetch(_ langFilter: String) throws -> [SubjectiveEffect] {
            let rows = try Row.fetchAll(db, sql: """
                SELECT \(label) AS effect_name,
                       COALESCE(MAX(CASE WHEN \(ownLanguage) THEN se.description END), '') AS effect_description
                  FROM subjective_effects se
                  JOIN sources src ON src.id = se.source_id
                 WHERE se.substance_id = ?
                   AND src.slug IN (\(enabledSourceListSQL))
                   \(langFilter)
                 GROUP BY effect_name
                 ORDER BY effect_name
            """, arguments: [substanceID])
            return rows.map { SubjectiveEffect(name: $0["effect_name"], description: $0["effect_description"]) }
        }
        // A description is only carried when the row was written in the language
        // being rendered — a bridged row's prose is still in its own language,
        // and a Han paragraph under an English effect name is worse than none.
        return try fetch(Self.subjectiveLanguageFilterSQL(language))
    }
}
