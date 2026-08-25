import Foundation

/// **How long a benzodiazepine stays** — this one's elimination half-life placed
/// against the clinical compounds people already have a feel for.
///
/// Equivalence is *potency*, and potency is not strength: two milligrams of
/// alprazolam and ten of diazepam are the same nominal dose and behave nothing
/// alike, because what separates them is how long each is still there. A ladder
/// from triazolam at ~2 h to diazepam at ~46 h says that; an equivalence table
/// hides it.
///
/// Subtype selectivity (α1/α2/α3/α5) would be the *better* signature and the DB
/// cannot feed it — 2 of 66 benzodiazepines carry a full set. Don't reintroduce
/// it as an axis until that changes.
enum BenzoDurationLadder {
    /// The compounds the ladder is drawn against: prescribed benzodiazepines
    /// spanning the range, chosen for recognition rather than coverage. A reader
    /// placing an unfamiliar compound needs rungs they already know, so a
    /// research chemical never anchors the scale even when it would widen it.
    static let referenceNames = [
        "Triazolam", "Midazolam", "Alprazolam", "Lorazepam", "Clonazepam", "Diazepam",
    ]

    /// One rung: a compound and its elimination half-life.
    struct Rung: Identifiable, Hashable {
        let name: String
        let halfLifeMinutes: Double
        let role: Role

        var id: String {
            name
        }
    }

    enum Role: Hashable, Sendable {
        /// A ladder compound the reader is expected to recognize.
        case reference
        /// The compound whose page this is — marked on the ladder rather than
        /// pulled out of it, so the comparison stays visible.
        case subject
        /// An active metabolite of the subject that outlasts it, sitting at its
        /// own half-life. This is a *rung*, not a footnote: "diazepam becomes
        /// nordazepam, which is active and lasts longer" is a sentence, and a
        /// longer bar one row down is the same claim without the sentence.
        case metabolite
    }

    /// The ladder for `substance`, ascending by half-life: the reference
    /// compounds, the substance itself, and any active metabolite that outlasts
    /// it.
    ///
    /// Returns empty unless the substance has a half-life of its own — a ladder
    /// whose subject has no rung is six facts about other drugs.
    ///
    /// The metabolite rungs are what make this honest for the compounds it
    /// matters most for. Flurazepam's own half-life is ~2.5 h, which places it
    /// beside triazolam, and it is in practice one of the longest-acting
    /// benzodiazepines there is because N-desalkylflurazepam runs ~75 h.
    /// Diazepam and clorazepate both run through nordazepam the same way.
    static func rungs(
        for substance: Substance,
        metabolites: [ActiveMetabolite] = [],
        lookup: (String) -> Substance?,
    ) -> [Rung] {
        guard let own = substance.halfLifeMinutes, own > 0 else { return [] }
        var byName: [String: Rung] = [:]
        for name in referenceNames {
            guard let reference = lookup(name), let halfLife = reference.halfLifeMinutes, halfLife > 0
            else { continue }
            byName[reference.displayTitle] = Rung(
                name: reference.displayTitle,
                halfLifeMinutes: halfLife,
                role: .reference,
            )
        }
        for metabolite in metabolites {
            guard let halfLife = metabolite.halfLifeMinutes, halfLife > own else { continue }
            // `displayName`, not `name`: the raw column holds "nordazepam
            // (N-desmethyldiazepam)", which reads as noise on a ladder of
            // capitalized one-word compounds.
            let name = metabolite.displayName
            byName[name] = Rung(name: name, halfLifeMinutes: halfLife, role: .metabolite)
        }
        // Last, so it wins any name collision: on alprazolam's own page the
        // alprazolam rung is marked rather than listed twice.
        byName[substance.displayTitle] = Rung(
            name: substance.displayTitle,
            halfLifeMinutes: own,
            role: .subject,
        )
        return byName.values.sorted {
            $0.halfLifeMinutes == $1.halfLifeMinutes
                ? $0.name < $1.name
                : $0.halfLifeMinutes < $1.halfLifeMinutes
        }
    }
}
