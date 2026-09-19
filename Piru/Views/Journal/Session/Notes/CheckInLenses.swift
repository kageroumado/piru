import Foundation

/// Which questions a check-in puts in front of someone, given what they took.
///
/// The Shulgin scale measures how strong an experience is — a psychedelic's
/// question. "Did it work?" measures whether a medication performed the way it
/// usually does — a different question, and the one an ADHD reader opens the
/// app with. Asking both of everyone would mean four controls where two carry
/// meaning, so the class decides.
///
/// The chips are ids from the same SubFxOnEx vocabulary the Descriptors picker
/// offers in full: a check-in shortcut, not a second store. Anything chosen
/// here is an ordinary descriptor afterwards — the note rows, the trip report
/// and every export already read them.
enum CheckInLenses {
    /// The questions one class asks.
    struct LensSet {
        /// "Did it work?" — a medication's question.
        var worked = false
        /// The Shulgin scale — a psychedelic's question.
        var intensity = false
        var mood = true
        var energy = true
        /// Desire to be around people. On for the classes people take *for*
        /// company — an empathogen above all, and a stimulant often enough.
        var social = false
        /// Descriptor slugs offered as a visible chip row: the effects someone
        /// takes this class *for*.
        var highlights: [String] = []
        /// Descriptor slugs behind the "Any side effects?" disclosure.
        var sideEffects: [String] = []
    }

    static func lenses(for category: SubstanceCategory) -> LensSet {
        switch category {
        case .stimulant, .eugeroic, .nootropic, .ampakine:
            LensSet(
                worked: true,
                social: true,
                highlights: ["increased-focus", "motivation-enhancement", "talkativeness", "social-openness"],
                sideEffects: [
                    "anxiety", "restlessness", "bruxism", "jaw-tension", "loss-of-appetite",
                    "palpitations", "irritability", "difficulty-falling-asleep", "tremor", "dry-mouth",
                ],
            )
        case .empathogen:
            LensSet(
                intensity: true,
                social: true,
                highlights: ["empathy-enhancement", "social-openness", "euphoria", "emotional-warmth"],
                sideEffects: [
                    "bruxism", "jaw-tension", "anxiety", "nausea", "temperature-fluctuation",
                    "dry-mouth", "restlessness",
                ],
            )
        case .psychedelic:
            LensSet(
                intensity: true,
                highlights: ["geometric-imagery", "euphoria", "awe", "time-dilation"],
                sideEffects: ["anxiety", "nausea", "confusion", "paranoia", "muscle-tension", "dizziness"],
            )
        case .deliriant:
            // No highlights: nobody takes a deliriant *for* something, and a
            // row of pleasant effects here would be an invitation the
            // pharmacology does not support. The chips are what to watch.
            LensSet(
                intensity: true,
                sideEffects: [
                    "complex-visual-hallucination", "amnesia", "confusion", "blurred-vision",
                    "dry-mouth", "urinary-retention", "palpitations", "anxiety",
                ],
            )
        case .dysdelic:
            LensSet(
                intensity: true,
                highlights: ["ego-dissolution", "derealization", "time-dilation"],
                sideEffects: ["dysphoria", "confusion", "anxiety", "incoordination", "nausea", "dizziness"],
            )
        case .dissociative:
            LensSet(
                intensity: true,
                highlights: ["euphoria", "ego-dissolution", "physical-comfort", "time-dilation"],
                sideEffects: ["nausea", "dizziness", "confusion", "nystagmus", "memory-impairment", "vomiting"],
            )
        case .opioid, .analgesic:
            LensSet(
                worked: true,
                highlights: ["pain-relief", "euphoria", "warmth", "calmness"],
                sideEffects: ["itching", "nausea", "constipation", "drowsiness", "vomiting", "dizziness"],
            )
        case .benzodiazepine:
            LensSet(
                worked: true,
                highlights: ["anxiety-relief", "calmness", "muscle-relaxation", "sedation"],
                sideEffects: [
                    "amnesia", "drowsiness", "incoordination", "impaired-balance",
                    "confusion", "dizziness",
                ],
            )
        case .gabapentinoid:
            LensSet(
                worked: true,
                highlights: ["anxiety-relief", "pain-relief", "calmness", "euphoria"],
                sideEffects: [
                    "dizziness", "drowsiness", "incoordination", "blurred-vision",
                    "nausea", "dry-mouth",
                ],
            )
        case .depressant, .orexinAntagonist, .antihistamine:
            LensSet(
                worked: true,
                highlights: ["anxiety-relief", "calmness", "muscle-relaxation", "sedation"],
                sideEffects: ["drowsiness", "dizziness", "memory-impairment", "confusion", "dry-mouth"],
            )
        case .cannabinoid:
            LensSet(
                intensity: true,
                highlights: ["euphoria", "calmness", "increased-appetite", "time-dilation"],
                sideEffects: ["anxiety", "paranoia", "dry-mouth", "dizziness", "memory-impairment", "palpitations"],
            )
        default:
            LensSet(
                worked: true,
                highlights: [],
                sideEffects: ["nausea", "drowsiness", "dizziness", "dry-mouth", "restlessness"],
            )
        }
    }

    /// A short, plain line shown when a side effect is checked: what the
    /// sources report for the class, and the accompanying signs that are a
    /// reason to get help now.
    ///
    /// Every line describes the class and leaves the person's own symptom
    /// unjudged: Piru has the log, and a log cannot tell a listed effect from an
    /// emergency or say when a symptom ends. No line names something to take.
    static func note(for slug: String) -> LocalizedStringResource? {
        switch slug {
        case "anxiety": "Commonly reported with this class. The timeline can't say how long yours will last — company and a quieter room are worth having."
        case "restlessness": "Commonly reported here. Some people find moving a little easier than sitting still."
        case "bruxism", "jaw-tension": "Jaw clenching is commonly reported. Something to chew spares your teeth."
        case "loss-of-appetite": "Commonly reported with this class. Something small now still counts."
        case "difficulty-falling-asleep": "Commonly reported while a stimulating dose is active. The curve is an estimate and can't say when you will sleep."
        case "palpitations": "Piru can't assess heart symptoms. With chest pain, shortness of breath or fainting, call emergency services."
        case "irritability": "Commonly reported on the way down. Worth noting when it started."
        case "tremor": "Commonly reported with this class. A severe tremor, or one that comes with confusion or a high temperature, is a reason to get help now."
        case "nausea": "Commonly reported early on. Small sips rather than gulps."
        case "vomiting": "Small sips once it settles. Vomiting while very drowsy is an emergency — stay on your side and get help."
        case "paranoia": "Commonly reported with this class. A familiar person or place helps more than arguing with the thought."
        case "confusion": "Piru can't tell a passing muddle from a serious one. Confusion that deepens, or comes with a high temperature, is a reason to get help now."
        case "dizziness": "Sit or lie down so a fall can't happen. Fainting, or dizziness with chest pain, is a reason to get help now."
        case "memory-impairment": "Record what you can now. Piru can't tell what caused a gap or whether the memory returns."
        case "amnesia": "This class can stop memories forming while it is active. What you write down now is the record."
        case "incoordination", "impaired-balance": "Coordination goes before you notice it has. Stairs and the kitchen are where that lands."
        case "blurred-vision": "Listed for this class. Piru can't tell what is causing a change in vision or when it ends — sudden loss of vision or eye pain needs urgent care."
        case "complex-visual-hallucination": "Seeing things that aren't there is listed for this class. If you can't tell what is real, get someone with you. Piru can't predict when it ends."
        case "urinary-retention": "This class can block the signal to the bladder. Not being able to pass urine at all is a reason to get help now rather than wait for the timeline."
        case "dysphoria": "Feeling bad is a listed effect of this class. It still deserves attention — Piru can't tell whether a symptom is harmless."
        case "itching": "Opioids release histamine, and itching is commonly reported. Piru can't tell that from an allergy — swelling of the mouth or throat, or trouble breathing, is an emergency."
        case "temperature-fluctuation": "Feeling hot and cold is commonly reported. A high temperature that rest and cooling don't bring down is an emergency."
        default: nil
        }
    }
}

// MARK: - The form for one session

/// The check-in sheet's shape for one session: which questions to ask, which
/// substances asked for each, and the chips on offer.
///
/// Built from the session's **distinct** substances, so three doses of the same
/// medication ask one question rather than three, and two stimulants ask one
/// rather than two. The note carries one value per question, which is the same
/// answer the schema gives.
struct CheckInForm {
    var asksWorked = false
    var asksIntensity = false
    /// Substance names behind each question, for the trailing tag.
    var workedNames: [String] = []
    var intensityNames: [String] = []
    var showsMood = true
    var showsEnergy = true
    var showsSocial = false
    var highlights: [String] = []
    var sideEffects: [String] = []
    /// How many distinct substances the session carries. One means every
    /// question can only be about that one, so nothing needs naming.
    var distinctSubstances = 0

    /// What a session whose doses resolve no substance at all asks: the sheet
    /// as it was before any of this — intensity, mood, energy, descriptors.
    /// A custom substance or a typo should widen the questions, never narrow
    /// them to nothing.
    static let unresolved = CheckInForm(asksIntensity: true, distinctSubstances: 0)

    @MainActor
    static func build(for session: Session) -> CheckInForm {
        var form = CheckInForm(showsMood: false, showsEnergy: false)
        var seen = Set<String>()
        for dose in session.orderedDoses {
            guard let substance = SubstanceLibrary.lookup(dose.substance) else { continue }
            guard seen.insert(substance.name.lowercased()).inserted else { continue }
            let lenses = CheckInLenses.lenses(for: substance.category)
            let title = substance.displayTitle
            if lenses.worked {
                form.asksWorked = true
                if !form.workedNames.contains(title) { form.workedNames.append(title) }
            }
            if lenses.intensity {
                form.asksIntensity = true
                if !form.intensityNames.contains(title) { form.intensityNames.append(title) }
            }
            form.showsMood = form.showsMood || lenses.mood
            form.showsEnergy = form.showsEnergy || lenses.energy
            form.showsSocial = form.showsSocial || lenses.social
            form.highlights += lenses.highlights.filter { !form.highlights.contains($0) }
            form.sideEffects += lenses.sideEffects.filter { !form.sideEffects.contains($0) }
        }
        form.distinctSubstances = seen.count
        return seen.isEmpty ? .unresolved : form
    }

    /// The names to print beside a question, or nil when the session has only
    /// one substance and there is nothing to disambiguate.
    func tag(_ names: [String]) -> String? {
        guard distinctSubstances > 1, !names.isEmpty else { return nil }
        return names.joined(separator: " · ")
    }
}
