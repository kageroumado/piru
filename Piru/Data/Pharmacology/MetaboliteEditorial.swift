import Foundation

/// Curated one-liners for **divergent** active metabolites — the cases where a
/// metabolite acts on a *different* axis than its parent, so a potency ratio says
/// nothing useful and the generic "acts differently, not simply stronger or
/// weaker" says nearly nothing at all.
///
/// The statement resolver keeps divergent metabolites out of the "Also Active"
/// headline (they are reference pharmacology, not a duration fact), so these
/// render as calm lines inside the **Metabolism** disclosure. Each sentence is
/// the real payload: what the metabolite actually does, and — where it is the
/// point — that how much you form is genetic. This is the tramadol case, the one
/// the feature most wants to serve and served worst.
///
/// Voice matches ``CombinationMetabolite/formationNote``: states what forms,
/// states what it does, states the consequence, stops. No dosing, no advice to
/// use — the metabolite names itself in the sentence, so the note needs no
/// interpolated parent and reads as description.
///
/// Keyed by `(parent, metabolite)` against the canonical names as stored in the
/// bundled DB, matched case-insensitively and loosely (punctuation- and
/// space-insensitive substring) so a curator string like
/// `"O-desmethyltramadol (M1)"` or `"MDA (3,4-methylenedioxyamphetamine)"` still
/// resolves.
nonisolated enum MetaboliteEditorial {
    struct DivergentNote {
        let parent: String
        let metabolite: String
        let note: LocalizedStringResource
    }

    /// The curated sentence for a divergent metabolite, if one exists. `parent`
    /// is the substance's canonical name; `metabolite` is the raw
    /// `metabolite_name` from the row.
    static func divergentNote(parent: String, metabolite: String) -> LocalizedStringResource? {
        let parentKey = normalize(parent)
        let metaboliteKey = normalize(metabolite)
        return notes.first {
            normalize($0.parent) == parentKey && metaboliteKey.contains(normalize($0.metabolite))
        }?.note
    }

    /// Lowercase, strip everything but a–z/0–9 — so "O-desmethyltramadol (M1)"
    /// and "odesmethyltramadol" compare equal.
    private static func normalize(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    static let notes: [DivergentNote] = [
        // The flagship. Tramadol is a weak opioid plus an SNRI; the opioid effect
        // most people feel is the metabolite's, and the CYP2D6 gene decides how
        // much of it there is.
        .init(
            parent: "Tramadol",
            metabolite: "O-desmethyltramadol",
            note: "Tramadol is itself a weak opioid that also raises serotonin and noradrenaline. Most of the opioid effect people feel comes from this metabolite — and how much you make of it depends on a CYP2D6 gene, so the same dose can be a real opioid for one person and almost none for another.",
        ),
        // mCPP is anxiogenic/dysphoric — the opposite of "trazodone, continued".
        .init(
            parent: "Trazodone",
            metabolite: "meta-chlorophenylpiperazine",
            note: "mCPP acts on serotonin in a different way than trazodone — it tends to feel activating or anxious rather than sedating, which is part of why trazodone's later hours can feel unlike its calm onset.",
        ),
        // Noribogaine carries the long tail on a different mechanism.
        .init(
            parent: "Ibogaine",
            metabolite: "noribogaine",
            note: "Noribogaine is long-lived and acts differently from ibogaine — it leans more on serotonin reuptake and κ-opioid signaling, and it is a large part of the extended after-effect rather than a continuation of the peak.",
        ),
        // Normeperidine is a convulsant, not a painkiller — the reason meperidine
        // is not used for ongoing pain.
        .init(
            parent: "Pethidine",
            metabolite: "normeperidine",
            note: "Normeperidine isn't a painkiller — it's a stimulating metabolite that builds up with repeated or high doses and lowers the seizure threshold. It's why meperidine isn't used for long-term pain.",
        ),
        // Dextrorphan is the stronger NMDA blocker — the dissociative axis.
        .init(
            parent: "Dextromethorphan",
            metabolite: "dextrorphan",
            note: "Dextrorphan blocks NMDA receptors more strongly than DXM itself does — it's the more dissociative species, and the main reason the character shifts at higher doses rather than simply lasting longer.",
        ),
        // Meprobamate is a barbiturate-like downer in its own right.
        .init(
            parent: "Carisoprodol",
            metabolite: "meprobamate",
            note: "Meprobamate is a long-lived, barbiturate-like sedative in its own right — it acts more like a classic downer than carisoprodol, and much of the sedation and the dependence potential come from it rather than the parent.",
        ),
        // Nortriptyline is a marketed drug; noradrenergic shift.
        .init(
            parent: "Amitriptyline",
            metabolite: "nortriptyline",
            note: "Nortriptyline is a marketed antidepressant in its own right, and it leans more on noradrenaline than amitriptyline does — so the metabolite's character is more activating than the parent's.",
        ),
        // Desipramine, same shape.
        .init(
            parent: "Imipramine",
            metabolite: "desipramine",
            note: "Desipramine is a marketed antidepressant in its own right, and more noradrenergic than imipramine — so as it forms, the effect shifts toward the more activating end.",
        ),
        .init(
            parent: "Clomipramine",
            metabolite: "N-desmethylclomipramine",
            note: "The desmethyl metabolite shifts clomipramine's strongly serotonergic action toward noradrenaline, so the two don't act quite alike — the balance moves as the metabolite accumulates.",
        ),
        // Norquetiapine adds NRI/antidepressant activity quetiapine lacks.
        .init(
            parent: "Quetiapine",
            metabolite: "norquetiapine",
            note: "Norquetiapine adds effects quetiapine largely lacks — noradrenaline reuptake inhibition and antidepressant-like activity — so it contributes a different character than the parent's sedation.",
        ),
        // HNK barely touches NMDA; separate, non-dissociative axis.
        .init(
            parent: "Ketamine",
            metabolite: "hydroxynorketamine",
            note: "This metabolite (HNK) barely touches the NMDA receptor ketamine acts on — it's studied for a separate, non-dissociative antidepressant effect, so it isn't simply ketamine continuing.",
        ),
        // MDA — more psychedelic, longer-lived. Descriptive, no encouragement.
        .init(
            parent: "MDMA",
            metabolite: "MDA",
            note: "MDA is an active drug of its own — more amphetamine-like and more hallucinogenic than MDMA, and longer-lived — so the later hours can feel qualitatively different from the peak.",
        ),
        // Norbuprenorphine acts more like a full agonist and drives respiratory effect.
        .init(
            parent: "Buprenorphine",
            metabolite: "norbuprenorphine",
            note: "Norbuprenorphine acts differently from buprenorphine — it behaves more like a full opioid agonist and contributes to respiratory effects, which buprenorphine's own ceiling doesn't fully predict.",
        ),
        // Cetirizine — the sedation fades into a plain antihistamine.
        .init(
            parent: "Hydroxyzine",
            metabolite: "cetirizine",
            note: "Cetirizine — a common non-drowsy antihistamine — is hydroxyzine's main metabolite. It's far less sedating, so hydroxyzine's calming effect gives way to a plainer antihistamine as it converts.",
        ),
        // Norephedrine adds sympathomimetic tone (vasoconstriction, BP rise)
        // that amphetamine's central action doesn't predict.
        .init(
            parent: "Amphetamine",
            metabolite: "norephedrine",
            note: "Norephedrine (phenylpropanolamine) is a peripheral sympathomimetic — it raises blood pressure and narrows blood vessels more than amphetamine's central action would predict. It adds cardiovascular load the parent's CNS profile doesn't warn about.",
        ),
        // 7-Aminoclonazepam is pharmacologically inactive — the standard
        // urinary marker.
        .init(
            parent: "Clonazepam",
            metabolite: "7-aminoclonazepam",
            note: "7-aminoclonazepam has no meaningful activity at GABA-A — it's an inactive metabolite used as a urinary marker for clonazepam exposure, not a contributor to the drug's effect.",
        ),
        // Norfenfluramine is the serotonin releaser that drove fenfluramine's
        // weight-loss action (and its cardiac valve damage).
        .init(
            parent: "Fenfluramine",
            metabolite: "norfenfluramine",
            note: "Norfenfluramine is a more potent serotonin releaser than fenfluramine itself — it drives much of the pharmacological effect, including the 5-HT₂B agonism linked to cardiac valve damage in the 1990s weight-loss era.",
        ),
        // N-succinyl-nor-mephedrone — a Phase II conjugate with unknown activity.
        .init(
            parent: "Mephedrone",
            metabolite: "N-succinyl-nor-mephedrone",
            note: "This unusual Phase II conjugate retains the nor-mephedrone core — whether it has pharmacological activity is unknown, but its long plasma half-life means it lingers well past mephedrone's short duration.",
        ),
        // Cotinine is the long-lived marker, not a nicotinic agonist.
        .init(
            parent: "Nicotine",
            metabolite: "cotinine",
            note: "Cotinine has negligible nicotinic activity — it's the standard biomarker for tobacco exposure, not a continuation of nicotine's effect. Its long half-life (~16 hours) is why it's detectable in blood and urine days after the last cigarette.",
        ),
    ]
}
