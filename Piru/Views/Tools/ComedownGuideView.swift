import SwiftData
import SwiftUI

struct ComedownGuideView: View {
    @Query private var recentEntries: [DoseEntry]

    static let guidedCategories: [SubstanceCategory] = [
        .stimulant, .empathogen, .psychedelic, .dissociative,
        .opioid, .benzodiazepine, .depressant, .cannabinoid,
    ]

    /// Resolved in the `.task`, not per body pass: a per-substance resolve
    /// over the dose log is too expensive to run on every body evaluation.
    @State private var recentCategories: [SubstanceCategory] = []

    init() {
        let cutoff = Date.now.addingTimeInterval(-48 * 3_600)
        _recentEntries = Query(
            filter: #Predicate<DoseEntry> { $0.timestamp >= cutoff },
            sort: \DoseEntry.timestamp,
            order: .reverse,
        )
    }

    /// First-seen guided category per dose, newest-first — the recently
    /// logged classes this guide and Get Help share.
    static func recentGuidedCategories(
        in entries: some Sequence<DoseEntry>, cutoff: Date,
    ) -> [SubstanceCategory] {
        let guided = Set(guidedCategories)
        var seen = Set<SubstanceCategory>()
        var result: [SubstanceCategory] = []
        for entry in entries where entry.timestamp >= cutoff {
            if let sub = SubstanceLibrary.lookup(entry.substance),
               guided.contains(sub.category),
               !seen.contains(sub.category) {
                seen.insert(sub.category)
                result.append(sub.category)
            }
        }
        return result
    }

    var body: some View {
        List {
            Group {
                aboutSection

                if !recentCategories.isEmpty {
                    Section("From your last 48 hours") {
                        ForEach(recentCategories, id: \.self) { cat in
                            ComedownCategoryDisclosure(category: cat)
                        }
                    }
                }

                Section("All categories") {
                    ForEach(Self.guidedCategories.filter { !recentCategories.contains($0) }, id: \.self) { cat in
                        ComedownCategoryDisclosure(category: cat)
                    }
                }

                generalSection
            }
            .listRowBackground(CardBackground())
        }
        .insetGroupedListStyle()
        .themedPage()
        .task(id: DoseLogService.shared.revision) {
            await SubstanceStore.shared.ensureAllLoaded()
            // The query already bounds entries to the 48 h window.
            recentCategories = Self.recentGuidedCategories(in: recentEntries, cutoff: .distantPast)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("What is this?", systemImage: "heart.text.clipboard")
                    .sectionLabel()
                Text("What sources report about the hours after each class wears off. It describes the class, never your condition.")
                    .captionSecondary()
                Text("If someone is hard to wake, breathing slowly, overheating or having a seizure, this is the wrong page — call emergency services.")
                    .captionSecondary()
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    // MARK: - General Tips

    private var generalSection: some View {
        Section("Universal recovery basics") {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                tipRow(icon: "drop.fill", color: .blue, text: "Hydrate — water or electrolyte drinks, sip steadily")
                tipRow(icon: "fork.knife", color: .orange, text: "Eat something nutritious — protein, carbs, and fruit")
                tipRow(icon: "bed.double.fill", color: .indigo, text: "Rest when your body asks for it")
                tipRow(icon: "sun.max.fill", color: .yellow, text: "Fresh air and gentle light")
                tipRow(icon: "figure.walk", color: .green, text: "Light movement or stretching — nothing intense")
                tipRow(icon: "iphone.slash", color: .gray, text: "Put the phone down — screens can amplify restlessness")
                tipRow(icon: "person.2.fill", color: .pink, text: "Reach out to someone you trust if you feel overwhelmed")
            }
            .font(.caption)
            .padding(.vertical, Spacing.xs)
        }
    }

    private func tipRow(icon: String, color: Color, text: LocalizedStringResource) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }

    // MARK: - Guide Data

    struct CategoryGuide {
        let whatsHappening: [LocalizedStringResource]
        let rightNow: [LocalizedStringResource]
        let nextHours: [LocalizedStringResource]
        let avoid: [LocalizedStringResource]
    }

    static func guide(for category: SubstanceCategory) -> CategoryGuide {
        switch category {
        case .stimulant:
            CategoryGuide(
                whatsHappening: [
                    "After a stimulant wears off, fatigue, irritability and low mood are commonly reported.",
                    "Appetite and sleep were likely pushed aside for hours, and both come due now.",
                    "Piru doesn't measure any of this. It describes what sources report for the class.",
                ],
                rightNow: [
                    "Eat something, even without hunger. Protein and complex carbs are the usual suggestion.",
                    "Drink water or an electrolyte drink, in sips.",
                    "Something to chew eases a tight jaw.",
                    "Chest pain, a pounding heart that won't settle, or a severe headache needs medical help.",
                ],
                nextHours: [
                    "Lie down even if sleep doesn't come immediately.",
                    "Dark room, comfortable temperature, no screens.",
                    "A warm shower or light stretching helps tight muscles.",
                    "Low mood after a stimulant is commonly reported. If it turns into thoughts of harming yourself, use the numbers in Get Help.",
                ],
                avoid: [
                    "Taking more to put off the crash moves the crash later.",
                    "Caffeine adds to the load on the heart.",
                    "Important decisions and emotionally charged messages read differently tomorrow.",
                    "Alcohol disrupts the sleep you need.",
                ],
            )
        case .empathogen:
            CategoryGuide(
                whatsHappening: [
                    "Low mood, fatigue and emotional sensitivity in the days after are commonly reported.",
                    "How long that lasts varies between people, and the kinetics in humans aren't well measured.",
                    "Piru doesn't measure any of this. It describes what sources report for the class.",
                ],
                rightNow: [
                    "This class raises body temperature. Feeling very hot, confused or rigid is an emergency — cool down and call for help.",
                    "Sip rather than gulp, and favor electrolytes. Over-drinking water is its own danger with this class — more is not safer.",
                    "Eat light foods: fruit, toast, soup.",
                    "Gentle massage eases a sore jaw.",
                ],
                nextHours: [
                    "Rest in a comfortable, calm space. Soft music or silence both work.",
                    "Be patient with yourself over the next few days.",
                    "A walk outside helps when you're ready.",
                    "Talk to someone you trust — connection helps more than isolation.",
                ],
                avoid: [
                    "Taking more to put off the low moves the low later.",
                    "Piru doesn't establish a safe interval for adding medicines or supplements. MAOIs are the documented danger with this class.",
                    "Skip intense social situations — you may feel emotionally raw.",
                    "Don't judge your baseline mood by how you feel right now.",
                ],
            )
        case .psychedelic:
            CategoryGuide(
                whatsHappening: [
                    "Feeling emotionally open, contemplative, or just tired afterwards is commonly reported.",
                    "Lingering visual or thought patterns are reported too, and usually fade over hours.",
                    "Piru doesn't measure any of this. It describes what sources report for the class.",
                ],
                rightNow: [
                    "If the experience was intense: the acute effects of this class are time-limited, and company helps.",
                    "Eat something grounding — warm food, fruit, or anything that sounds appealing.",
                    "Drink water. Wrap up in something comfortable.",
                    "Write down anything meaningful before the details fade.",
                ],
                nextHours: [
                    "Rest when you can.",
                    "Don't try to 'figure it all out' right now. Integration takes days.",
                    "Nature, art, or quiet music can help you process gently.",
                    "Distress or perceptual changes that persist for days are worth taking to a professional.",
                ],
                avoid: [
                    "Don't make big life decisions based on acute revelations — wait a week.",
                    "Avoid screens and doom-scrolling while you're this impressionable.",
                    "Cannabis is widely reported to bring the effects back, sometimes unpleasantly.",
                    "Skip intense or crowded environments until you feel grounded.",
                ],
            )
        case .dissociative:
            CategoryGuide(
                whatsHappening: [
                    "Feeling foggy or unreal for a while afterwards is commonly reported.",
                    "Motor coordination and spatial awareness may still be impaired.",
                    "Piru doesn't measure any of this. It describes what sources report for the class.",
                ],
                rightNow: [
                    "Stay seated or lying down. Your balance may not be what you think it is.",
                    "Drink water. Eat something simple when your stomach allows.",
                    "Stay somewhere safe with someone you trust if possible.",
                    "Avoid stairs, sharp objects, and anything requiring fine motor skills.",
                ],
                nextHours: [
                    "Rest with someone nearby if you can.",
                    "The fog is reported to clear over hours. If it doesn't, get it looked at.",
                    "Gentle sensory input (music, soft textures) can help you reconnect.",
                    "Things feeling 'weird' for a while is commonly reported.",
                ],
                avoid: [
                    "Do not drive or operate machinery. Feeling normal does not establish that you can drive safely.",
                    "Alcohol, benzodiazepines and opioids on top of a dissociative raise the risk of stopped breathing.",
                    "Avoid hot baths or showers alone — you may not feel temperature accurately.",
                    "Your own read of how affected you are is unreliable while dissociated.",
                ],
            )
        case .opioid:
            CategoryGuide(
                whatsHappening: [
                    "As an opioid fades, increased pain sensitivity, restlessness and mild nausea are commonly reported.",
                    "How strong that is tracks how much and how often you've been using.",
                    "Piru doesn't measure any of this. It describes what sources report for the class.",
                ],
                rightNow: [
                    "If someone is hard to wake, breathing slowly, or has blue lips, call emergency services. Give naloxone if you have it, following its instructions.",
                    "Drink water, in sips. Eat something light.",
                    "If you feel nauseous, lie on your side.",
                    "Fresh air can help with the foggy, closed-in feeling.",
                ],
                nextHours: [
                    "Stay with someone, or let someone know to check on you. Heavy snoring or gurgling in sleep is a warning sign, not rest.",
                    "Light movement helps — even a short walk.",
                    "A warm bath can ease the achy, restless feeling — with someone in earshot.",
                    "Help is available through the numbers in Get Help.",
                ],
                avoid: [
                    "Tolerance drops quickly after a break. A dose you handled before is the documented cause of many overdoses.",
                    "Alcohol, benzodiazepines and other depressants on top of an opioid raise the risk of stopped breathing.",
                    "Don't isolate yourself. Let someone know where you are.",
                    "Do not drive. Feeling normal does not establish that you can drive safely.",
                ],
            )
        case .benzodiazepine:
            CategoryGuide(
                whatsHappening: [
                    "As a benzodiazepine wears off, rebound anxiety and restlessness are commonly reported.",
                    "Memory and coordination can stay impaired after the sedation lifts.",
                    "After regular use, stopping abruptly can be dangerous.",
                ],
                rightNow: [
                    "Stay somewhere calm and safe.",
                    "Drink water and eat something.",
                    "Breathing exercises: 4 seconds in, 7 seconds hold, 8 seconds out.",
                    "Caffeine amplifies rebound anxiety.",
                ],
                nextHours: [
                    "Sleep may be disrupted tonight.",
                    "Light activity like walking helps burn off anxious energy.",
                    "If someone is hard to wake or breathing slowly, call emergency services.",
                    "If this is frequent for you, consider talking to a professional about alternatives.",
                ],
                avoid: [
                    "Taking more in reaction to the rebound reinforces the cycle.",
                    "Alcohol acts on the same receptors, and the combination can stop breathing.",
                    "Do not drive. Feeling less sedated does not establish that memory or coordination are unimpaired.",
                    "After regular use, a seizure or severe confusion on stopping is an emergency.",
                ],
            )
        case .depressant:
            CategoryGuide(
                whatsHappening: [
                    "As a depressant wears off, feeling shaky, anxious or nauseous is commonly reported.",
                    "Headaches and fatigue are common.",
                    "Piru doesn't measure any of this. It describes what sources report for the class.",
                ],
                rightNow: [
                    "If someone is hard to wake, breathing slowly, or vomiting while drowsy, put them on their side and call emergency services.",
                    "Drink water or an electrolyte drink, in sips.",
                    "Eat something with salt, protein, and carbs.",
                    "If nauseous, small sips of water and lying on your side help.",
                ],
                nextHours: [
                    "Rest with someone nearby. A person who can't be woken needs help, not sleep.",
                    "A cool, dark room helps with headaches and overstimulation.",
                    "Light food every few hours, even if you don't feel hungry.",
                    "Fresh air and gentle movement when you're ready.",
                ],
                avoid: [
                    "More of a depressant to ease the morning moves the morning later.",
                    "If you have been drinking heavily and daily for weeks, stopping abruptly can be dangerous — seizures and delirium tremens peak 2–4 days after the last drink.",
                    "With daily phenibut or F-phenibut, dependence develops within weeks and withdrawal can be protracted.",
                    "Acetaminophen (paracetamol) after heavy alcohol use adds stress to the liver.",
                    "Do not drive. Feeling normal does not establish that you can drive safely.",
                    "Avoid greasy, heavy food — it sounds good but often makes nausea worse.",
                ],
            )
        case .cannabinoid:
            CategoryGuide(
                whatsHappening: [
                    "Feeling foggy, lethargic or mildly irritable afterwards is commonly reported.",
                    "Appetite changes and sleep disruption are common after heavy sessions.",
                    "Piru doesn't measure any of this. It describes what sources report for the class.",
                ],
                rightNow: [
                    "Drink water. A dry mouth is an effect of cannabis itself and doesn't by itself mean dehydration.",
                    "Eat something balanced.",
                    "If you feel anxious, slow your breathing. Anxiety is a listed effect of this class.",
                    "A change of scenery — even moving to a different room — can shift your headspace.",
                ],
                nextHours: [
                    "Physical activity helps with the fog.",
                    "Sleep quality may be off tonight.",
                    "If you feel spacey, grounding exercises: name 5 things you can see, 4 you can touch.",
                    "Repeated vomiting that only hot showers relieve is a recognized syndrome.",
                ],
                avoid: [
                    "Do not drive. Impairment outlasts the feeling of being high.",
                    "More cannabis to soften the comedown moves the comedown later.",
                    "Short-term memory gaps are commonly reported. Piru can't tell what caused one.",
                    "Skip intense social obligations if you're not feeling up to it.",
                ],
            )
        default:
            CategoryGuide(
                whatsHappening: [
                    "How you feel depends on what you took, how much, and your own body.",
                    "Piru doesn't measure any of this. It describes what sources report.",
                ],
                rightNow: [
                    "Drink water and eat something nutritious.",
                    "Rest in a comfortable, safe environment.",
                    "If you feel unwell, don't hesitate to call for help.",
                ],
                nextHours: [
                    "Rest with someone nearby if you can.",
                    "Light food and fluids every few hours.",
                    "Give yourself time.",
                ],
                avoid: [
                    "Taking more within the same session adds to what is still active.",
                    "Mixing adds risk.",
                    "Do not drive. Feeling normal does not establish that you can drive safely.",
                ],
            )
        }
    }
}

/// A single comedown category as a fold-open row: the category icon + name, its
/// per-category recovery tips revealed on tap. Shared by ``ComedownGuideView``'s
/// "Relevant to you" list and the session detail's Recovery section so both show
/// the identical rows. Owns its own expansion state.
struct ComedownCategoryDisclosure: View {
    let category: SubstanceCategory
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
        } label: {
            HStack(spacing: Spacing.lg) {
                Image(systemName: category.icon)
                    .foregroundStyle(category.labelColor)
                    .accessibilityHidden(true)
                    .frame(width: 24)
                Text(category.displayName)
                    .font(.body)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let guide = ComedownGuideView.guide(for: category)
        VStack(alignment: .leading, spacing: Spacing.xl) {
            tipGroup("What's happening", items: guide.whatsHappening)
            tipGroup("Right now", items: guide.rightNow)
            tipGroup("Over the next hours", items: guide.nextHours)
            tipGroup("What to avoid", items: guide.avoid)
        }
        .font(.caption)
        .padding(.vertical, Spacing.md)
    }

    private func tipGroup(_ title: LocalizedStringResource, items: [LocalizedStringResource]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Text("\u{2022}")
                        .foregroundStyle(Theme.secondaryLabel)
                    Text(item)
                        .foregroundStyle(Theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
