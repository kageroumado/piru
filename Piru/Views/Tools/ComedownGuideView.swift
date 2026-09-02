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

    /// First-seen guided category per dose, newest-first — the "what's
    /// relevant to this user right now" list this guide and Get Help share.
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
                    Section("Relevant to you") {
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
        .listStyle(.insetGrouped)
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
                Text("Practical tips for taking care of yourself as substances wear off. Every category is different — tap one below for specific guidance.")
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
                tipRow(icon: "bed.double.fill", color: .indigo, text: "Sleep when your body lets you — don't fight it")
                tipRow(icon: "sun.max.fill", color: .yellow, text: "Fresh air and gentle light help reset your system")
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
                    "Your brain burned through dopamine and norepinephrine faster than usual.",
                    "The crash is your nervous system demanding rest and replenishment.",
                    "Fatigue, irritability, and low mood are all normal parts of this process.",
                ],
                rightNow: [
                    "Eat something — even if you're not hungry. Protein and complex carbs help most.",
                    "Drink water or an electrolyte drink. You've been dehydrating without noticing.",
                    "Magnesium can help with jaw tension and muscle tightness.",
                    "Vitamin C may support your body's recovery.",
                ],
                nextHours: [
                    "Don't fight the fatigue — lie down even if sleep doesn't come immediately.",
                    "Dark room, comfortable temperature, no screens.",
                    "A warm shower or light stretching helps your muscles release.",
                    "The low mood is chemical. It lifts.",
                ],
                avoid: [
                    "Don't redose to escape the crash — it only delays and worsens recovery.",
                    "Skip the caffeine — your cardiovascular system has worked hard enough.",
                    "Don't make important decisions or send emotionally charged messages right now.",
                    "Avoid alcohol — it worsens dehydration and disrupts the sleep you need.",
                ],
            )
        case .empathogen:
            CategoryGuide(
                whatsHappening: [
                    "Your serotonin reserves are depleted — that's why everything feels flat or low.",
                    "This is temporary. Your brain will replenish over the next few days.",
                    "Some emotional sensitivity and physical fatigue is completely normal.",
                ],
                rightNow: [
                    "Stay warm — your body's temperature regulation is still off.",
                    "Sip water steadily, but don't overdo it. A glass every 30-60 minutes is fine.",
                    "Eat light foods: fruit, toast, soup. Your stomach may be sensitive.",
                    "If your jaw is sore, gentle massage and magnesium help.",
                ],
                nextHours: [
                    "Rest in a comfortable, calm space. Soft music or silence both work.",
                    "Be patient with yourself for the next 1-3 days. Low mood is the serotonin dip.",
                    "Gentle walks in nature can genuinely help when you're ready.",
                    "Talk to someone you trust — connection helps more than isolation.",
                ],
                avoid: [
                    "Don't redose — the magic is in spacing. Frequent use causes lasting harm.",
                    "Avoid 5-HTP supplements for at least 24 hours after your last dose.",
                    "Skip intense social situations — you may feel emotionally raw.",
                    "Don't judge your baseline mood by how you feel right now.",
                ],
            )
        case .psychedelic:
            CategoryGuide(
                whatsHappening: [
                    "Your serotonin receptors are returning to their normal sensitivity.",
                    "You may feel emotionally open, contemplative, or just tired.",
                    "Some residual visual or thought patterns can linger — this is normal and fades.",
                ],
                rightNow: [
                    "You're safe. If the experience was intense, remind yourself: it's temporary.",
                    "Eat something grounding — warm food, fruit, or anything that sounds appealing.",
                    "Drink water. Wrap up in something comfortable.",
                    "Write down anything meaningful before the details fade.",
                ],
                nextHours: [
                    "Rest. Sleep often comes easily once the peak is past.",
                    "Don't try to 'figure it all out' right now. Integration takes days.",
                    "Nature, art, or quiet music can help you process gently.",
                    "Be easy with yourself — profound experiences need time to settle.",
                ],
                avoid: [
                    "Don't make big life decisions based on acute revelations — wait a week.",
                    "Avoid screens and doom-scrolling. Your mind is still very impressionable.",
                    "Don't smoke cannabis unless you know how it interacts with your afterglow.",
                    "Skip intense or crowded environments until you feel grounded.",
                ],
            )
        case .dissociative:
            CategoryGuide(
                whatsHappening: [
                    "Your NMDA receptors are returning to baseline, which can feel foggy or unreal.",
                    "Motor coordination and spatial awareness may still be impaired.",
                    "Some dissociative afterglow is common — the world may feel slightly 'off' for a while.",
                ],
                rightNow: [
                    "Stay seated or lying down. Your balance may not be what you think it is.",
                    "Drink water. Eat something simple when your stomach allows.",
                    "Stay somewhere safe with someone you trust if possible.",
                    "Avoid stairs, sharp objects, and anything requiring fine motor skills.",
                ],
                nextHours: [
                    "Sleep when you can — your brain recovers fastest during rest.",
                    "The foggy feeling will clear. Give it hours.",
                    "Gentle sensory input (music, soft textures) can help you reconnect.",
                    "Don't worry if things feel 'weird' — your perception is still recalibrating.",
                ],
                avoid: [
                    "Absolutely do not drive or operate machinery.",
                    "Don't mix with depressants (alcohol, benzos, opioids) — respiratory depression risk.",
                    "Avoid hot baths/showers alone — you may not feel temperature accurately.",
                    "Don't redose while still dissociated — you can't gauge your level clearly.",
                ],
            )
        case .opioid:
            CategoryGuide(
                whatsHappening: [
                    "Your endorphin system was temporarily overridden. As the drug fades, sensitivity returns.",
                    "You may feel increased pain sensitivity, restlessness, or mild nausea.",
                    "These effects are proportional to how much and how often you've been using.",
                ],
                rightNow: [
                    "Stay hydrated — opioids are dehydrating and constipating.",
                    "Eat something light. Your appetite may be suppressed but food helps.",
                    "If you feel nauseous, lie on your side and sip ginger tea or plain water.",
                    "Fresh air can help with the foggy, closed-in feeling.",
                ],
                nextHours: [
                    "Light movement helps — even a short walk speeds recovery.",
                    "A warm bath can ease the achy, restless feeling.",
                    "Sleep if you can. Your body does its best recovery work unconscious.",
                    "If withdrawal symptoms concern you, seek medical advice. Help exists.",
                ],
                avoid: [
                    "Don't redose to chase the feeling — tolerance builds fast and that path is dangerous.",
                    "Never mix with alcohol, benzos, or other depressants.",
                    "Don't isolate yourself. Let someone know where you are.",
                    "Avoid driving — reaction time and judgment may still be affected.",
                ],
            )
        case .benzodiazepine:
            CategoryGuide(
                whatsHappening: [
                    "Your GABA receptors are readjusting — anxiety or restlessness may temporarily increase.",
                    "This is a rebound effect. It passes.",
                    "If you've been using regularly, talk to a doctor about tapering — never stop abruptly.",
                ],
                rightNow: [
                    "Stay somewhere calm and safe. The rebound anxiety is temporary.",
                    "Drink water and eat something — stable blood sugar helps mood.",
                    "Breathing exercises: 4 seconds in, 7 seconds hold, 8 seconds out.",
                    "Avoid caffeine — it amplifies the rebound anxiety.",
                ],
                nextHours: [
                    "Sleep may be disrupted tonight — melatonin or chamomile tea can help.",
                    "Light activity like walking helps burn off anxious energy.",
                    "The discomfort peaks and then fades. Give it time.",
                    "If this is frequent for you, consider talking to a professional about alternatives.",
                ],
                avoid: [
                    "Don't redose reactively — it reinforces the cycle.",
                    "Avoid alcohol completely — it acts on the same receptors.",
                    "Don't make this worse by doom-scrolling health anxiety forums.",
                    "Never abruptly stop after regular use — benzo withdrawal can be medically serious.",
                ],
            )
        case .depressant:
            CategoryGuide(
                whatsHappening: [
                    "Your central nervous system was being suppressed and is now rebounding.",
                    "You may feel shaky, anxious, or nauseous as your body recalibrates.",
                    "Headaches and fatigue are common — this is your body processing the substance.",
                ],
                rightNow: [
                    "Drink water — depressants are dehydrating, especially alcohol.",
                    "Eat something with salt, protein, and carbs. Your body needs fuel to recover.",
                    "If nauseous, small sips of water and lying on your side help.",
                    "An electrolyte drink is better than plain water if available.",
                ],
                nextHours: [
                    "Sleep it off if you can — your body needs rest to metabolize and recover.",
                    "A cool, dark room helps with headaches and overstimulation.",
                    "Light food every few hours, even if you don't feel hungry.",
                    "Fresh air and gentle movement when you're ready.",
                ],
                avoid: [
                    "Don't 'hair of the dog' — more depressant just delays recovery.",
                    "If you have been drinking heavily and daily for weeks, stopping abruptly can be medically dangerous — seizures and delirium tremens peak 2–4 days after the last drink. Seek medical advice before going cold turkey.",
                    "If you are using phenibut or F-phenibut daily, dependence develops within weeks. Protracted withdrawal can last months — taper gradually with medical guidance.",
                    "Avoid painkillers that stress the liver (acetaminophen) after heavy alcohol use.",
                    "Don't drive or make important decisions until fully sober.",
                    "Avoid greasy, heavy food — it sounds good but often makes nausea worse.",
                ],
            )
        case .cannabinoid:
            CategoryGuide(
                whatsHappening: [
                    "Your endocannabinoid system is returning to baseline.",
                    "You may feel foggy, lethargic, or mildly irritable.",
                    "Appetite changes and sleep disruption are common after heavy sessions.",
                ],
                rightNow: [
                    "Drink water — cotton mouth means you've been dehydrating.",
                    "Eat something balanced. The munchies may have had you eating junk.",
                    "If you feel anxious, focus on slow breathing. It passes.",
                    "A change of scenery — even moving to a different room — can shift your headspace.",
                ],
                nextHours: [
                    "Physical activity helps clear the fog faster than anything.",
                    "Caffeine in moderation can help with grogginess.",
                    "Sleep quality may be off tonight — melatonin can help.",
                    "If you feel spacey, grounding exercises: name 5 things you can see, 4 you can touch.",
                ],
                avoid: [
                    "Don't drive until the fog fully clears — it takes longer than you think.",
                    "Avoid more cannabis to 'take the edge off' the comedown.",
                    "Don't panic about short-term memory gaps — they resolve with sobriety.",
                    "Skip intense social obligations if you're not feeling up to it.",
                ],
            )
        default:
            CategoryGuide(
                whatsHappening: [
                    "Your body is processing and eliminating the substance.",
                    "How you feel depends on what you took, how much, and your body's chemistry.",
                ],
                rightNow: [
                    "Drink water and eat something nutritious.",
                    "Rest in a comfortable, safe environment.",
                    "If you feel unwell, don't hesitate to call for help.",
                ],
                nextHours: [
                    "Sleep is your best recovery tool.",
                    "Light food and fluids every few hours.",
                    "Give yourself time. Most effects are temporary.",
                ],
                avoid: [
                    "Don't redose without careful consideration.",
                    "Avoid mixing substances.",
                    "Don't drive or make important decisions until you feel baseline.",
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
