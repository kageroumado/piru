import Foundation

extension SubstanceLibrary {
    // swiftlint:disable function_body_length
    static let nootropics: [Substance] = [

        // MARK: - 1. Piracetam

        Substance(
            name: "Piracetam",
            aliases: ["Nootropil"],
            category: .nootropic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 400, light: 800...1200, common: 1200...2400, strong: 2400...4800, heavy: 4800
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 540)
                )),
            ],
            effects: ["Improved focus", "Enhanced memory", "Mental clarity", "Increased verbal fluency", "Reduced brain fog", "Subtle mood lift", "Headache"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mental Sharpening", description: "A gradual clearing of mental haze, with thoughts feeling slightly more organized and easier to access."),
                SubjectiveEffect(name: "Verbal Fluency", description: "Words come a bit more readily during conversation, with less searching for the right term."),
                SubjectiveEffect(name: "Subtle Mood Brightening", description: "A mild but noticeable improvement in baseline mood that develops over days of consistent use."),
                SubjectiveEffect(name: "Reading Comprehension Boost", description: "Text feels easier to process, with improved ability to retain what was just read."),
                SubjectiveEffect(name: "Reduced Mental Fatigue", description: "Cognitive tasks feel slightly less draining, allowing for longer periods of sustained mental effort."),
                SubjectiveEffect(name: "Headache", description: "A dull tension headache that can occur when choline intake is insufficient, typically behind the forehead."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 90, fullResetDays: 60, buildRate: "negligible"),
            halfLifeMinutes: 300,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 2. Aniracetam

        Substance(
            name: "Aniracetam",
            aliases: ["Draganon", "Ampamet", "Memodrin"],
            category: .nootropic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 200...400, common: 400...750, strong: 750...1500, heavy: 1500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 120, max: 240)
                )),
            ],
            effects: ["Reduced anxiety", "Enhanced creativity", "Improved memory", "Increased verbal fluency", "Mental clarity", "Mood enhancement", "Holistic thinking", "Headache"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Anxiolytic Calm", description: "A gentle reduction in background anxiety without sedation, making social situations feel more comfortable."),
                SubjectiveEffect(name: "Creative Flow", description: "An enhanced ability to make novel connections between ideas, with thinking feeling more fluid and lateral."),
                SubjectiveEffect(name: "Holistic Thinking", description: "A shift toward seeing the bigger picture rather than fixating on details, with improved pattern recognition."),
                SubjectiveEffect(name: "Verbal Expressiveness", description: "An increased ease in articulating thoughts, with words flowing more naturally in conversation and writing."),
                SubjectiveEffect(name: "Mood Warmth", description: "A subtle emotional warmth and improved sense of well-being that develops within an hour of dosing."),
                SubjectiveEffect(name: "Sensory Enrichment", description: "Music and visual experiences may feel slightly more vivid and engaging than baseline."),
                SubjectiveEffect(name: "Headache", description: "A choline-depletion headache that can emerge after extended use without adequate choline supplementation."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 90, fullResetDays: 45, buildRate: "negligible"),
            halfLifeMinutes: 105,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 3. Oxiracetam

        Substance(
            name: "Oxiracetam",
            aliases: ["Neuromet", "ISF-2522"],
            category: .nootropic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 200, light: 400...800, common: 800...1200, strong: 1200...2400, heavy: 2400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Improved logical thinking", "Enhanced memory", "Increased focus", "Mental stimulation", "Improved attention span", "Headache", "Nausea"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Analytical Sharpness", description: "A noticeable improvement in logical reasoning and the ability to work through multi-step problems."),
                SubjectiveEffect(name: "Mild Stimulation", description: "A clean, caffeine-like mental energy without jitteriness, making it easier to stay engaged with tasks."),
                SubjectiveEffect(name: "Memory Consolidation", description: "Information studied while taking oxiracetam feels easier to recall later, particularly factual and technical material."),
                SubjectiveEffect(name: "Sustained Attention", description: "An improved ability to maintain focus on a single task for extended periods without drifting."),
                SubjectiveEffect(name: "Phonetic Clarity", description: "Spoken words and sounds may seem slightly crisper and easier to distinguish and process."),
                SubjectiveEffect(name: "Headache", description: "A tension-type headache from acetylcholine depletion, avoidable with concurrent choline supplementation."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 90, fullResetDays: 60, buildRate: "negligible"),
            halfLifeMinutes: 480,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 4. Pramiracetam

        Substance(
            name: "Pramiracetam",
            aliases: ["Pramistar", "CI-879"],
            category: .nootropic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...400, strong: 400...600, heavy: 600
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 240, max: 360),
                    offset: TimeRange(min: 180, max: 300),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 540)
                )),
            ],
            effects: ["Enhanced long-term memory", "Improved focus", "Increased mental endurance", "Heightened concentration", "Emotional blunting", "Mental clarity", "Headache"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Laser Focus", description: "A pronounced narrowing of attention onto the task at hand, making distractions easier to ignore."),
                SubjectiveEffect(name: "Long-Term Memory Enhancement", description: "Improved encoding and recall of information over days and weeks, particularly for studied material."),
                SubjectiveEffect(name: "Mental Endurance", description: "The ability to sustain demanding cognitive work for longer periods before feeling mentally fatigued."),
                SubjectiveEffect(name: "Emotional Flatness", description: "A reduction in emotional reactivity that some find helpful for productivity but others experience as blunting."),
                SubjectiveEffect(name: "Cognitive Stamina", description: "Complex tasks that normally cause mental fatigue feel more manageable across longer work sessions."),
                SubjectiveEffect(name: "Headache", description: "A racetam-class headache typically caused by insufficient choline intake during supplementation."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 30, fullResetDays: 60, buildRate: "slow"),
            halfLifeMinutes: 330,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 5. Phenylpiracetam

        Substance(
            name: "Phenylpiracetam",
            aliases: ["Phenotropil", "Carphedon", "Fonturacetam"],
            category: .nootropic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...400, heavy: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 420)
                )),
            ],
            effects: ["Psychostimulation", "Improved focus", "Enhanced physical stamina", "Cold resistance", "Reduced fatigue", "Increased motivation", "Wakefulness", "Tolerance builds rapidly"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Clean Stimulation", description: "A clear-headed, energizing effect stronger than other racetams, noticeably improving drive and wakefulness."),
                SubjectiveEffect(name: "Physical Energy Boost", description: "A tangible increase in physical stamina and exercise tolerance, with workouts feeling less effortful."),
                SubjectiveEffect(name: "Cold Tolerance", description: "A reported ability to withstand cold temperatures more comfortably, likely related to increased catecholamine activity."),
                SubjectiveEffect(name: "Motivational Drive", description: "A notable increase in the desire to start and complete tasks, reducing procrastination."),
                SubjectiveEffect(name: "Mood Elevation", description: "A mild but noticeable uplift in mood and sense of confidence that accompanies the stimulant effect."),
                SubjectiveEffect(name: "Rapid Tolerance", description: "The stimulating effects diminish quickly with consecutive daily use, often requiring cycling."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A mild reduction in hunger that can last several hours after dosing."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 7, buildRate: "rapid"),
            halfLifeMinutes: 240,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 6. Coluracetam

        Substance(
            name: "Coluracetam",
            aliases: ["MKC-231", "BCI-540"],
            category: .nootropic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 3...5, common: 5...15, strong: 15...35, heavy: 35
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 120, max: 240)
                )),
                SubstanceRoute(route: .sublingual, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...10, strong: 10...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 20),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 45, max: 90),
                    offset: TimeRange(min: 45, max: 90),
                    afterglow: nil,
                    total: TimeRange(min: 90, max: 180)
                )),
            ],
            effects: ["Enhanced color vision", "Improved memory", "Reduced anxiety", "Mood enhancement", "Mental clarity", "Increased choline uptake", "Headache"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Enhanced Color Perception", description: "Colors may appear more saturated and vivid, particularly noticeable outdoors or when viewing artwork."),
                SubjectiveEffect(name: "Visual Clarity", description: "A subtle sharpening of visual perception, with edges and details appearing slightly more defined."),
                SubjectiveEffect(name: "Anxiolytic Effect", description: "A mild calming of background anxiety without cognitive impairment or drowsiness."),
                SubjectiveEffect(name: "Mood Brightening", description: "A gentle improvement in overall emotional tone, with things feeling slightly more pleasant."),
                SubjectiveEffect(name: "Memory Support", description: "Improved recall and faster information retrieval, particularly noticeable with recently learned material."),
                SubjectiveEffect(name: "Headache", description: "Possible tension headache from increased choline demand, usually preventable with choline co-supplementation."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 30, buildRate: "slow"),
            halfLifeMinutes: 180,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 7. Fasoracetam

        Substance(
            name: "Fasoracetam",
            aliases: ["NFC-1", "NS-105", "LAM-105"],
            category: .nootropic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...50, strong: 50...100, heavy: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 120, max: 240)
                )),
                SubstanceRoute(route: .sublingual, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...10, common: 10...30, strong: 30...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 20),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 45, max: 90),
                    offset: TimeRange(min: 45, max: 90),
                    afterglow: nil,
                    total: TimeRange(min: 90, max: 180)
                )),
            ],
            effects: ["Reduced anxiety", "Improved focus", "GABA-B upregulation", "Enhanced memory", "Mental clarity", "Mood stabilization", "Mild stimulation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Calm Focus", description: "A unique combination of reduced anxiety and improved concentration, feeling both relaxed and mentally sharp."),
                SubjectiveEffect(name: "GABAergic Stabilization", description: "A smoothing out of mood fluctuations over time, with fewer emotional highs and lows throughout the day."),
                SubjectiveEffect(name: "Subtle Motivation", description: "A mild increase in the drive to engage with tasks, without the restlessness of typical stimulants."),
                SubjectiveEffect(name: "Anxiety Reduction", description: "A noticeable easing of social and generalized anxiety that builds over several days of use."),
                SubjectiveEffect(name: "Memory Improvement", description: "Gradually improved ability to form and retrieve memories, particularly noticeable after consistent use."),
                SubjectiveEffect(name: "Mental Clarity", description: "A reduction in mental noise and improved ability to think through problems sequentially."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 30, buildRate: "slow"),
            halfLifeMinutes: 105,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 8. Noopept

        Substance(
            name: "Noopept",
            aliases: ["GVS-111", "Omberacetam"],
            category: .nootropic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...15, common: 15...30, strong: 30...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 20),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 120, max: 240)
                )),
                SubstanceRoute(route: .sublingual, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...10, common: 10...20, strong: 20...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 10),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: nil,
                    total: TimeRange(min: 90, max: 180)
                )),
            ],
            effects: ["Enhanced memory", "Improved focus", "Mental clarity", "Neuroprotection", "Increased BDNF", "Mild psychostimulation", "Irritability", "Headache"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Rapid Onset Clarity", description: "A quick-acting mental sharpness, often felt within minutes especially with sublingual dosing."),
                SubjectiveEffect(name: "Memory Enhancement", description: "Noticeably improved ability to encode new information and retrieve recent memories."),
                SubjectiveEffect(name: "Mild Psychostimulation", description: "A gentle increase in alertness and mental energy, subtler than caffeine but with a clean quality."),
                SubjectiveEffect(name: "Emotional Sensitivity", description: "Some users report increased emotional reactivity or irritability, particularly at higher doses."),
                SubjectiveEffect(name: "Sensory Sharpening", description: "Sounds and visual details may seem slightly more vivid and easier to process."),
                SubjectiveEffect(name: "Cognitive Fluidity", description: "Thoughts connect more easily, with improved ability to shift between tasks and concepts."),
                SubjectiveEffect(name: "Headache", description: "A dull headache that may emerge with regular use, often mitigated by adding a choline source."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 30, buildRate: "slow"),
            halfLifeMinutes: 20,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 9. Semax

        Substance(
            name: "Semax",
            aliases: ["MEHFPGP", "Semax heptapeptide"],
            category: .nootropic,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .insufflation, unit: "mcg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...600, strong: 600...1000, heavy: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 10),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 120, max: 240)
                )),
            ],
            effects: ["Improved focus", "Enhanced memory", "Increased BDNF", "Reduced anxiety", "Neuroprotection", "Mental clarity", "Mild mood lift"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Cognitive Sharpening", description: "A noticeable improvement in mental acuity and the speed of information processing within hours of dosing."),
                SubjectiveEffect(name: "Focused Attention", description: "Enhanced ability to maintain concentration on demanding tasks with fewer attention lapses."),
                SubjectiveEffect(name: "Anxiety Relief", description: "A subtle calming of nervous tension without any sedation or cognitive dulling."),
                SubjectiveEffect(name: "Mood Elevation", description: "A mild but consistent improvement in overall sense of well-being and emotional resilience."),
                SubjectiveEffect(name: "Mental Stamina", description: "Improved endurance for prolonged intellectual work, with less of the usual cognitive fatigue."),
                SubjectiveEffect(name: "Nasal Clarity", description: "When used intranasally, a brief tingling sensation followed by rapidly improving mental clarity."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 14, buildRate: "slow"),
            halfLifeMinutes: 3,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 10. Selank

        Substance(
            name: "Selank",
            aliases: ["TP-7"],
            category: .nootropic,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .insufflation, unit: "mcg", doses: DoseRange(
                    threshold: 50, light: 100...250, common: 250...500, strong: 500...1000, heavy: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 10),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 120, max: 240)
                )),
            ],
            effects: ["Reduced anxiety", "Improved mood", "Enhanced cognitive function", "Emotional stability", "Stress relief", "Mild sedation", "Improved sleep quality"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Anxiolytic Calm", description: "A pronounced yet gentle reduction in anxiety, with worries feeling less pressing and intrusive."),
                SubjectiveEffect(name: "Emotional Equilibrium", description: "A stabilization of emotional responses, making it easier to stay composed under stress."),
                SubjectiveEffect(name: "Relaxed Wakefulness", description: "A calming effect that does not impair alertness, feeling mentally at ease while remaining productive."),
                SubjectiveEffect(name: "Stress Resilience", description: "Stressful situations feel more manageable, with a buffer between stimulus and emotional reaction."),
                SubjectiveEffect(name: "Improved Sleep Onset", description: "Easier transition into sleep when dosed in the evening, with a quieting of racing thoughts."),
                SubjectiveEffect(name: "Mood Stabilization", description: "A general evening-out of mood swings, with less reactivity to minor annoyances and setbacks."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 14, buildRate: "slow"),
            halfLifeMinutes: 3,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 11. Alpha-GPC

        Substance(
            name: "Alpha-GPC",
            aliases: ["L-Alpha-Glycerylphosphorylcholine", "Choline Alfoscerate"],
            category: .nootropic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 150...300, common: 300...600, strong: 600...1200, heavy: 1200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 480)
                )),
            ],
            effects: ["Enhanced memory", "Improved focus", "Increased acetylcholine", "Mental clarity", "Headache relief when stacked", "Improved power output", "Nausea"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mental Clarity", description: "A clearing of brain fog within an hour of dosing, with thoughts feeling more accessible and organized."),
                SubjectiveEffect(name: "Memory Support", description: "Improved ability to recall names, facts, and recent events, especially noticeable when stacked with racetams."),
                SubjectiveEffect(name: "Headache Prevention", description: "Effective at eliminating the headaches commonly caused by racetam use through cholinergic support."),
                SubjectiveEffect(name: "Focused Energy", description: "A subtle boost in mental energy and attentional control without the jittery quality of stimulants."),
                SubjectiveEffect(name: "Physical Power", description: "A mild improvement in explosive strength and power output during resistance training."),
                SubjectiveEffect(name: "Nausea", description: "Mild stomach discomfort that can occur at higher doses, especially when taken on an empty stomach."),
            ],
            halfLifeMinutes: 270,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 12. CDP-Choline (Citicoline)

        Substance(
            name: "CDP-Choline",
            aliases: ["Citicoline", "Cytidine diphosphocholine"],
            category: .nootropic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...250, common: 250...500, strong: 500...1000, heavy: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 720)
                )),
            ],
            effects: ["Enhanced memory", "Improved focus", "Increased attention", "Mental clarity", "Neuroprotection", "Improved verbal memory", "Mild headache"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Steady Focus", description: "A reliable improvement in sustained attention, feeling more locked-in during reading and studying."),
                SubjectiveEffect(name: "Verbal Memory Boost", description: "Improved recall of words, names, and verbal information, noticeable during conversation and study."),
                SubjectiveEffect(name: "Mental Clarity", description: "A subtle lifting of cognitive haze, with information processing feeling smoother and more efficient."),
                SubjectiveEffect(name: "Cholinergic Support", description: "A sense of the brain being properly fueled, particularly when used alongside racetams."),
                SubjectiveEffect(name: "Mild Wakefulness", description: "A gentle alerting effect from the cytidine component, less pronounced than typical stimulants."),
                SubjectiveEffect(name: "Headache", description: "An occasional mild headache, less common than with Alpha-GPC due to the lower choline load per dose."),
            ],
            halfLifeMinutes: 4200,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 13. L-Theanine

        Substance(
            name: "L-Theanine",
            aliases: ["Theanine", "Suntheanine"],
            category: .nootropic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...400, heavy: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Reduced anxiety", "Calm focus", "Relaxation without sedation", "Improved sleep quality", "Synergy with caffeine", "Reduced stress", "Alpha brain wave increase"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Calm Alertness", description: "A distinctive state of being relaxed yet mentally sharp, without the drowsiness that comes with most calming agents."),
                SubjectiveEffect(name: "Caffeine Smoothing", description: "When combined with caffeine, the jittery edge is removed while preserving the focus and energy benefits."),
                SubjectiveEffect(name: "Anxiety Softening", description: "A gentle reduction in nervous tension and racing thoughts, making stressful tasks feel more approachable."),
                SubjectiveEffect(name: "Background Relaxation", description: "A physical and mental loosening of tension that persists throughout the day without impairing function."),
                SubjectiveEffect(name: "Improved Sleep Transition", description: "When taken in the evening, a smoother and faster transition from wakefulness to sleep."),
                SubjectiveEffect(name: "Attentional Flow", description: "An enhanced ability to enter flow states during focused work, with fewer intrusive thoughts."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 30, buildRate: "slow"),
            halfLifeMinutes: 75,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 14. Lion's Mane

        Substance(
            name: "Lion's Mane",
            aliases: ["Hericium erinaceus", "Yamabushitake"],
            category: .nootropic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 250...500, common: 500...1000, strong: 1000...3000, heavy: 3000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 960)
                )),
            ],
            effects: ["Improved nerve growth factor", "Enhanced memory", "Reduced brain fog", "Neuroprotection", "Improved mood", "Reduced anxiety", "Digestive support"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Gradual Brain Fog Clearing", description: "A progressive lifting of mental cloudiness over weeks of use, with thinking becoming noticeably clearer."),
                SubjectiveEffect(name: "Improved Recall", description: "A slow but steady improvement in the ability to retrieve memories and learned information."),
                SubjectiveEffect(name: "Mood Improvement", description: "A gentle elevation of baseline mood that accumulates over weeks, with reduced irritability and more patience."),
                SubjectiveEffect(name: "Reduced Anxiety", description: "A subtle easing of anxious feelings that develops gradually with consistent supplementation."),
                SubjectiveEffect(name: "Dream Vividness", description: "Some users report more vivid and memorable dreams after several weeks of regular use."),
                SubjectiveEffect(name: "Digestive Comfort", description: "A mild improvement in gut comfort and digestion, reflecting the mushroom's prebiotic properties."),
            ],
            halfLifeMinutes: 360,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 15. Bacopa Monnieri

        Substance(
            name: "Bacopa Monnieri",
            aliases: ["Brahmi", "Water Hyssop", "Bacopa"],
            category: .nootropic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...450, strong: 450...600, heavy: 600
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 960)
                )),
            ],
            effects: ["Enhanced memory formation", "Reduced anxiety", "Improved attention", "Neuroprotection", "Mild sedation", "Gastrointestinal discomfort", "Improved learning rate"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Memory Consolidation", description: "A gradual improvement in the ability to form and retain new memories, typically noticed after 4-6 weeks."),
                SubjectiveEffect(name: "Calm Focus", description: "A mild calming effect that aids concentration, though some find it slightly sedating at first."),
                SubjectiveEffect(name: "Reduced Test Anxiety", description: "Information feels more accessible during high-pressure recall situations after extended supplementation."),
                SubjectiveEffect(name: "Learning Enhancement", description: "New material feels slightly easier to absorb and understand, particularly with consistent daily use."),
                SubjectiveEffect(name: "Mild Sedation", description: "A gentle sleepiness that can occur initially, often diminishing as the body adjusts over the first week."),
                SubjectiveEffect(name: "Stomach Discomfort", description: "Mild gastrointestinal upset that some users experience, typically manageable by taking it with food."),
            ],
            halfLifeMinutes: 180,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 16. Sulbutiamine

        Substance(
            name: "Sulbutiamine",
            aliases: ["Arcalion", "Bisibuthiamine"],
            category: .nootropic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...400, strong: 400...600, heavy: 600
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 420)
                )),
            ],
            effects: ["Reduced fatigue", "Improved motivation", "Enhanced memory", "Mood enhancement", "Increased mental energy", "Reduced social anxiety", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Anti-Fatigue Effect", description: "A noticeable reduction in mental and physical fatigue, with a renewed sense of energy during the day."),
                SubjectiveEffect(name: "Motivational Boost", description: "An increased desire to engage with tasks and goals, with procrastination feeling less appealing."),
                SubjectiveEffect(name: "Social Confidence", description: "A reduction in social anxiety with increased ease in conversations and group settings."),
                SubjectiveEffect(name: "Mood Enhancement", description: "A mild but distinct uplift in mood that can make the day feel generally more enjoyable."),
                SubjectiveEffect(name: "Mental Energy", description: "A sense of having more cognitive resources available, making demanding mental work feel less draining."),
                SubjectiveEffect(name: "Sleep Disruption", description: "Difficulty falling asleep if taken too late in the day due to the stimulating thiamine-derived effects."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 300,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 17. NSI-189

        Substance(
            name: "NSI-189",
            aliases: ["NSI-189 phosphate"],
            category: .nootropic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 20...40, common: 40...80, strong: 80...120, heavy: 120
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 960)
                )),
            ],
            effects: ["Improved mood", "Enhanced cognitive function", "Hippocampal neurogenesis", "Reduced depression", "Improved spatial memory", "Increased emotional depth", "Headache", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mood Restoration", description: "A progressive lifting of low mood and anhedonia, with everyday activities starting to feel engaging again."),
                SubjectiveEffect(name: "Emotional Richness", description: "Colors, music, and social interactions may feel more emotionally resonant and meaningful."),
                SubjectiveEffect(name: "Cognitive Brightening", description: "A sense of mental fog lifting, with improved ability to think clearly and plan ahead."),
                SubjectiveEffect(name: "Spatial Awareness", description: "An improved sense of spatial navigation and environmental awareness over weeks of use."),
                SubjectiveEffect(name: "Renewed Interest", description: "A gradual return of curiosity and interest in hobbies and activities that had felt flat."),
                SubjectiveEffect(name: "Headache", description: "A persistent headache that some users report, particularly during the first days of use."),
                SubjectiveEffect(name: "Sleep Difficulty", description: "Trouble falling or staying asleep, more common at higher doses or when taken later in the day."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 30, buildRate: "slow"),
            halfLifeMinutes: 1140,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 18. Dihexa

        Substance(
            name: "Dihexa",
            aliases: ["N-Hexanoic-Tyr-Ile-(6)-aminohexanoic amide"],
            category: .nootropic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 480)
                )),
            ],
            effects: ["Enhanced memory formation", "Improved cognitive function", "Increased synaptogenesis", "Neuroprotection", "Enhanced learning", "Mental clarity"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Memory Formation", description: "A noticeable improvement in the ability to encode and recall new information within days of use."),
                SubjectiveEffect(name: "Learning Acceleration", description: "New concepts and skills feel easier to grasp, with a sense of faster mental processing."),
                SubjectiveEffect(name: "Cognitive Clarity", description: "A sharpening of mental function with thoughts feeling more precise and well-organized."),
                SubjectiveEffect(name: "Focus Enhancement", description: "Improved ability to sustain attention on complex material without losing the thread."),
                SubjectiveEffect(name: "Mental Resilience", description: "A sense of cognitive reserves being deeper, with less mental fatigue during extended intellectual work."),
                SubjectiveEffect(name: "Subtle Neuroprotection", description: "A background sense of cognitive health being supported, though this is more inferred than directly felt."),
            ],
            halfLifeMinutes: 360,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 19. Sunifiram

        Substance(
            name: "Sunifiram",
            aliases: ["DM-235"],
            category: .nootropic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 4...7, common: 7...10, strong: 10...15, heavy: 15
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 20),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 120, max: 240)
                )),
                SubstanceRoute(route: .sublingual, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 3...5, common: 5...8, strong: 8...12, heavy: 12
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 10),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: nil,
                    total: TimeRange(min: 90, max: 180)
                )),
            ],
            effects: ["Enhanced memory", "Improved focus", "Increased mental energy", "Heightened perception", "Mood enhancement", "Mild stimulation", "Nausea"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Pronounced Mental Energy", description: "A strong boost in cognitive energy that is noticeable within 30 minutes, more potent than most racetams."),
                SubjectiveEffect(name: "Perceptual Enhancement", description: "Sensory input feels heightened, with sounds, colors, and textures seeming more detailed and vivid."),
                SubjectiveEffect(name: "Sharp Focus", description: "An intense narrowing of attention onto the current task, making deep work feel effortless."),
                SubjectiveEffect(name: "Memory Boost", description: "Improved ability to form and recall memories, with studied material feeling more firmly encoded."),
                SubjectiveEffect(name: "Mood Uplift", description: "A noticeable elevation in mood and sense of well-being, sometimes described as mildly euphoric."),
                SubjectiveEffect(name: "Nausea", description: "Stomach discomfort that can occur especially at higher doses, typically manageable with food."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 60,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 20. Unifiram

        Substance(
            name: "Unifiram",
            aliases: ["DM-232"],
            category: .nootropic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...10, strong: 10...15, heavy: 15
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 20),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 120, max: 240)
                )),
                SubstanceRoute(route: .sublingual, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...4, common: 4...8, strong: 8...12, heavy: 12
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 10),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: nil,
                    total: TimeRange(min: 90, max: 180)
                )),
            ],
            effects: ["Enhanced memory", "Improved focus", "Increased alertness", "Mental clarity", "Mood enhancement", "Mild stimulation", "Nausea"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Heightened Alertness", description: "A sharp increase in mental wakefulness and readiness, noticeable within minutes of sublingual dosing."),
                SubjectiveEffect(name: "Intense Focus", description: "A strong and immediate improvement in concentration, with distractions becoming easier to tune out."),
                SubjectiveEffect(name: "Memory Enhancement", description: "Improved formation and retrieval of memories, with information feeling more solidly encoded."),
                SubjectiveEffect(name: "Mental Clarity", description: "A pronounced clearing of cognitive fog with thoughts feeling crisp, precise, and well-ordered."),
                SubjectiveEffect(name: "Mood Improvement", description: "A mild but clear uplift in mood and motivation that complements the cognitive effects."),
                SubjectiveEffect(name: "Nausea", description: "Gastrointestinal discomfort that may occur at higher doses, similar in character to sunifiram."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 60,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 21. IDRA-21

        Substance(
            name: "IDRA-21",
            aliases: ["7-Chloro-3-methyl-3,4-dihydro-2H-1,2,4-benzothiadiazine 1,1-dioxide"],
            category: .nootropic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 5...10, common: 10...25, strong: 25...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 360, max: 720),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Enhanced memory", "Improved learning", "Increased AMPA activity", "Mental clarity", "Heightened focus", "Anxiety", "Overstimulation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Enhanced Learning Speed", description: "New information feels significantly easier to absorb and understand, with faster comprehension of complex material."),
                SubjectiveEffect(name: "Intense Focus", description: "A powerful narrowing of attention that can make deep cognitive work feel highly engaging."),
                SubjectiveEffect(name: "Memory Imprinting", description: "Studied material feels deeply encoded, with improved long-term retention of information."),
                SubjectiveEffect(name: "Mental Overstimulation", description: "At higher doses, a sense of cognitive overdrive that can feel uncomfortable or anxiety-inducing."),
                SubjectiveEffect(name: "Heightened Anxiety", description: "An increase in nervous energy and anxious feelings, particularly at stronger doses or in anxiety-prone individuals."),
                SubjectiveEffect(name: "Cognitive Intensity", description: "A strong sense of mental activation that some find productive and others find overwhelming."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 10, fullResetDays: 21, buildRate: "slow"),
            halfLifeMinutes: 480,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 22. PRL-8-53

        Substance(
            name: "PRL-8-53",
            aliases: ["Methyl 3-(2-(benzhydryloxy)ethyl)aminobenzoate"],
            category: .nootropic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 3...5, common: 5...10, strong: 10...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 120, max: 240)
                )),
            ],
            effects: ["Enhanced short-term memory", "Improved word recall", "Increased learning speed", "Mental clarity", "Improved retention", "Headache"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Word Recall Boost", description: "A notable improvement in the ability to recall words and verbal information, particularly useful for studying."),
                SubjectiveEffect(name: "Short-Term Memory Lift", description: "Recently encountered information stays more accessible, with less of the usual rapid forgetting."),
                SubjectiveEffect(name: "Learning Acceleration", description: "Material feels easier to learn the first time through, requiring fewer repetitions for retention."),
                SubjectiveEffect(name: "Mental Freshness", description: "A sense of cognitive clarity and readiness, as though the mind has been reset and refreshed."),
                SubjectiveEffect(name: "Retention Improvement", description: "Information studied under the influence tends to stick better over subsequent days."),
                SubjectiveEffect(name: "Headache", description: "A mild headache that some users report, possibly related to cholinergic activity changes."),
            ],
            halfLifeMinutes: 60,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 23. Bromantane

        Substance(
            name: "Bromantane",
            aliases: ["Ladasten", "ADK-709"],
            category: .nootropic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 25...50, common: 50...100, strong: 100...200, heavy: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 960)
                )),
            ],
            effects: ["Increased motivation", "Reduced fatigue", "Mild stimulation", "Improved physical performance", "Upregulated dopamine synthesis", "Reduced anxiety", "Enhanced resilience to stress"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Smooth Motivation", description: "A steady, non-jittery increase in motivation and drive that feels natural rather than forced."),
                SubjectiveEffect(name: "Anti-Fatigue", description: "A clear reduction in both mental and physical fatigue, with more energy available throughout the day."),
                SubjectiveEffect(name: "Anxiolytic Stimulation", description: "The unusual combination of mild stimulation with anxiety reduction, feeling energized yet calm."),
                SubjectiveEffect(name: "Physical Performance", description: "Improved exercise capacity and endurance, with workouts feeling more sustainable and less exhausting."),
                SubjectiveEffect(name: "Stress Resilience", description: "An improved ability to cope with stressful situations without feeling overwhelmed or depleted."),
                SubjectiveEffect(name: "Dopaminergic Tone", description: "A gentle baseline improvement in mood and reward sensitivity that builds over days of use."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 30, buildRate: "slow"),
            halfLifeMinutes: 690,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 24. RGPU-95

        Substance(
            name: "RGPU-95",
            aliases: ["Mesocarb analog"],
            category: .nootropic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...25, common: 25...50, strong: 50...100, heavy: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 720)
                )),
            ],
            effects: ["Increased wakefulness", "Improved focus", "Mild stimulation", "Reduced fatigue", "Enhanced motivation", "Insomnia", "Appetite suppression"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Wakefulness", description: "A strong promotion of alertness and wakefulness, making it difficult to feel sleepy during its duration."),
                SubjectiveEffect(name: "Focused Stimulation", description: "A clean stimulant effect that improves concentration and task engagement without excessive physical arousal."),
                SubjectiveEffect(name: "Motivation Enhancement", description: "An increased drive to initiate and complete tasks, with reduced tendency to procrastinate."),
                SubjectiveEffect(name: "Appetite Reduction", description: "A noticeable decrease in hunger signals that persists for several hours after dosing."),
                SubjectiveEffect(name: "Fatigue Resistance", description: "The normal feeling of tiring over the day is significantly blunted, allowing sustained activity."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty falling asleep if dosed too late, as the wakefulness-promoting effects can last many hours."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 360,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 25. Cerebrolysin

        Substance(
            name: "Cerebrolysin",
            aliases: ["FPF-1070"],
            category: .nootropic,
            defaultRoute: .intramuscular,
            routes: [
                SubstanceRoute(route: .intramuscular, unit: "mL", doses: DoseRange(
                    threshold: 1, light: 1...2, common: 2...5, strong: 5...10, heavy: 10
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 960)
                )),
            ],
            effects: ["Enhanced memory", "Neuroprotection", "Improved cognitive recovery", "Increased neurotrophic factors", "Mental clarity", "Injection site pain", "Dizziness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Cognitive Brightening", description: "A gradual but noticeable improvement in mental clarity and processing speed over the course of treatment."),
                SubjectiveEffect(name: "Memory Recovery", description: "Improved ability to form and recall memories, particularly noted by those recovering from cognitive decline."),
                SubjectiveEffect(name: "Mental Energy", description: "A sense of renewed cognitive vitality, with thinking feeling less effortful and more fluid."),
                SubjectiveEffect(name: "Emotional Stability", description: "A calming of mood fluctuations and improved emotional regulation throughout the treatment course."),
                SubjectiveEffect(name: "Injection Site Discomfort", description: "Pain, redness, or swelling at the injection site that typically resolves within hours."),
                SubjectiveEffect(name: "Dizziness", description: "A mild lightheadedness that can occur shortly after injection, usually transient."),
            ],
            halfLifeMinutes: 30,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 26. Cortexin

        Substance(
            name: "Cortexin",
            aliases: ["Cortex polypeptides"],
            category: .nootropic,
            defaultRoute: .intramuscular,
            routes: [
                SubstanceRoute(route: .intramuscular, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 5...10, common: 10...20, strong: 20...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 960)
                )),
            ],
            effects: ["Improved cognitive function", "Neuroprotection", "Enhanced memory", "Reduced brain fog", "Improved attention", "Injection site pain", "Mild headache"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Cognitive Restoration", description: "A gradual improvement in overall mental function, with thinking becoming clearer over the treatment cycle."),
                SubjectiveEffect(name: "Brain Fog Reduction", description: "A progressive clearing of mental haziness, with improved ability to concentrate and process information."),
                SubjectiveEffect(name: "Attentional Improvement", description: "Better sustained attention and reduced distractibility during demanding cognitive tasks."),
                SubjectiveEffect(name: "Memory Support", description: "Improved recall of recent events and information, with memories feeling more accessible."),
                SubjectiveEffect(name: "Injection Site Pain", description: "Localized soreness at the injection site that can last a day, typically mild and manageable."),
                SubjectiveEffect(name: "Mild Headache", description: "An occasional light headache during the first few days of treatment that usually resolves."),
            ],
            halfLifeMinutes: 30,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 27. 9-Me-BC

        Substance(
            name: "9-Me-BC",
            aliases: ["9-Methyl-\u{03B2}-carboline", "9-Methyl-beta-carboline"],
            category: .nootropic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 5...10, common: 10...15, strong: 15...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 360, max: 720),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Increased dopamine synthesis", "Enhanced motivation", "Improved focus", "Neuroprotection", "Increased neurogenesis", "Photosensitivity", "Wakefulness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Dopaminergic Drive", description: "A progressive increase in baseline motivation and reward sensitivity as dopamine synthesis upregulates over days."),
                SubjectiveEffect(name: "Sustained Focus", description: "An improved ability to maintain concentration on tasks, with less mental wandering throughout the day."),
                SubjectiveEffect(name: "Wakefulness Promotion", description: "A clear alerting effect that makes daytime sleepiness less likely, without a stimulant crash."),
                SubjectiveEffect(name: "Motivational Enhancement", description: "Tasks feel more worthwhile and engaging, with an increased willingness to tackle difficult projects."),
                SubjectiveEffect(name: "Photosensitivity", description: "Increased sensitivity to sunlight and UV exposure, requiring sun protection measures during use."),
                SubjectiveEffect(name: "Mood Stabilization", description: "A gradual normalization of mood with improved emotional resilience over the supplementation period."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 30, buildRate: "slow"),
            halfLifeMinutes: 1440,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

        // MARK: - 28. Nefiracetam

        Substance(
            name: "Nefiracetam",
            aliases: ["DM-9384", "Translon"],
            category: .nootropic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...600, strong: 600...900, heavy: 900
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 420)
                )),
            ],
            effects: ["Enhanced memory", "Improved focus", "Reduced apathy", "Mood stabilization", "Increased GABAergic activity", "Mental clarity", "Nausea"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Anti-Apathy Effect", description: "A reduction in emotional flatness and indifference, with renewed interest in activities and engagement."),
                SubjectiveEffect(name: "Memory Enhancement", description: "Improved ability to form and retrieve memories, particularly noticeable after several days of use."),
                SubjectiveEffect(name: "Mood Stabilization", description: "A smoothing of emotional fluctuations, with less reactivity to daily stressors and annoyances."),
                SubjectiveEffect(name: "Focused Attention", description: "Improved concentration with a balanced quality, neither overly stimulating nor sedating."),
                SubjectiveEffect(name: "Mental Clarity", description: "A clearer headspace with reduced cognitive noise, making it easier to think sequentially."),
                SubjectiveEffect(name: "Nausea", description: "Mild stomach discomfort that some users experience, especially at higher doses or without food."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 30, buildRate: "slow"),
            halfLifeMinutes: 210,
            sources: ["Examine.com", "PubMed", "DrugBank"]
        ),

    ]
    // swiftlint:enable function_body_length
}
