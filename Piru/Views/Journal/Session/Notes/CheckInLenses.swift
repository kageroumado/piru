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
                highlights: ["increased-focus", "motivation-enhancement", "talkativeness", "social-openness"],
                sideEffects: [
                    "anxiety", "restlessness", "bruxism", "jaw-tension", "loss-of-appetite",
                    "palpitations", "irritability", "difficulty-falling-asleep", "tremor", "dry-mouth",
                ],
            )
        case .empathogen:
            LensSet(
                intensity: true,
                highlights: ["empathy-enhancement", "social-openness", "euphoria", "emotional-warmth"],
                sideEffects: [
                    "bruxism", "jaw-tension", "anxiety", "nausea", "temperature-fluctuation",
                    "dry-mouth", "restlessness",
                ],
            )
        case .psychedelic, .dysdelic, .deliriant:
            LensSet(
                intensity: true,
                highlights: ["geometric-imagery", "euphoria", "awe", "time-dilation"],
                sideEffects: ["anxiety", "nausea", "confusion", "paranoia", "muscle-tension", "dizziness"],
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
        case .benzodiazepine, .depressant, .gabapentinoid, .orexinAntagonist, .antihistamine:
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

    /// A short, plain line shown when a side effect is checked: what it is, and
    /// that it passes. Same register as the comedown guide, which is where this
    /// reader has already met these sentences.
    ///
    /// Only the ones someone is likely to be frightened by have a line; a dry
    /// mouth needs no reassuring. Nothing here is an instruction to take
    /// anything, and nothing promises a timescale the data does not carry.
    static func reassurance(for slug: String) -> LocalizedStringResource? {
        switch slug {
        case "anxiety": "This is the drug, not you. It eases as the dose wears off."
        case "restlessness": "Common here. Moving a little settles it better than sitting still."
        case "bruxism", "jaw-tension": "Jaw clenching is typical. Magnesium and something to chew help."
        case "loss-of-appetite": "Appetite comes back as it wears off. Something small now still counts."
        case "difficulty-falling-asleep": "Expected while it's still active — the curve says until when."
        case "palpitations": "A faster heart is common at this dose. If it stays hard or hurts, get it looked at."
        case "irritability": "Chemical, not character. It lifts as levels drop."
        case "tremor": "Hands shake at this dose and stop on the way down."
        case "nausea": "Usually passes in the first hour. Small sips rather than gulps."
        case "vomiting": "Once it settles, sip water — small and often."
        case "paranoia": "It's the drug talking. It fades with the peak."
        case "confusion": "Thinking gets loose here and comes back. Nothing to fix."
        case "dizziness": "Sit down until it passes. It usually goes with the peak."
        case "memory-impairment": "Gaps here are normal, and the memory comes back after."
        case "itching": "Opioids release histamine — the itch is that, not an allergy."
        case "temperature-fluctuation": "Running hot and cold is part of it. Cool down, and sip steadily rather than a lot at once."
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
