import Foundation

extension SubstanceLibrary {
    static let gabaergics: [Substance] = [

        // MARK: - GHB and Prodrugs

        Substance(
            name: "GHB",
            aliases: ["Gamma-hydroxybutyrate", "G", "Liquid Ecstasy", "Fantasy"],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "g", doses: DoseRange(
                    threshold: 0.3, light: 0.5...1.0, common: 1.0...2.5, strong: 2.5...4.0, heavy: 4.0, fatal: 7
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 45, max: 90),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 90, max: 180)
                )),
            ],
            effects: ["Euphoria", "Disinhibition", "Sedation", "Anxiolysis", "Increased sociability", "Drowsiness", "Muscle relaxation", "Enhanced libido", "Dizziness", "Nausea"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Physical euphoria", description: "A warm, pleasurable wave of bodily comfort that radiates outward from the core, often compared to a full-body glow."),
                SubjectiveEffect(name: "Disinhibition", description: "A marked reduction in social hesitation and self-consciousness, making conversation and interaction feel effortless."),
                SubjectiveEffect(name: "Sociability enhancement", description: "A strong desire to connect with others and engage in conversation, accompanied by feelings of openness and friendliness."),
                SubjectiveEffect(name: "Music appreciation enhancement", description: "Music may sound richer and more emotionally resonant, with bass and rhythm feeling more physically engaging."),
                SubjectiveEffect(name: "Tactile enhancement", description: "Physical touch and textures feel amplified and more pleasurable than usual."),
                SubjectiveEffect(name: "Anxiolysis", description: "Worries and anxious thoughts dissolve, replaced by a calm confidence and sense of well-being."),
                SubjectiveEffect(name: "Motor control loss", description: "Coordination and balance become progressively impaired, with movements feeling clumsy or exaggerated."),
                SubjectiveEffect(name: "Cognitive suppression", description: "Thinking becomes slower and less precise, with difficulty maintaining complex trains of thought."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 2, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 25,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "StatPearls"]
        ),

        Substance(
            name: "GBL",
            aliases: ["Gamma-butyrolactone"],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mL", doses: DoseRange(
                    threshold: 0.3, light: 0.3...0.9, common: 0.9...1.5, strong: 1.5...3.0, heavy: 3.0, fatal: 5
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 30, max: 90),
                    total: TimeRange(min: 60, max: 120)
                )),
            ],
            effects: ["Euphoria", "Disinhibition", "Sedation", "Anxiolysis", "Increased sociability", "Drowsiness", "Muscle relaxation", "Enhanced libido", "Dizziness", "Nausea"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Physical euphoria", description: "A spreading warmth and bodily pleasure similar to GHB, as GBL is rapidly converted to GHB in the body."),
                SubjectiveEffect(name: "Rapid onset rush", description: "Effects come on faster than GHB itself, often producing a noticeable initial surge of warmth and relaxation."),
                SubjectiveEffect(name: "Disinhibition", description: "Social barriers drop away quickly, producing a carefree and outgoing demeanor."),
                SubjectiveEffect(name: "Sociability enhancement", description: "Conversations flow easily and social interactions feel rewarding and enjoyable."),
                SubjectiveEffect(name: "Anxiolysis", description: "Anxiety melts away, replaced by a calm, confident state of mind."),
                SubjectiveEffect(name: "Gastric irritation", description: "The caustic nature of GBL can cause a burning sensation in the throat and stomach, sometimes with nausea."),
                SubjectiveEffect(name: "Motor control loss", description: "Balance and coordination degrade noticeably, especially at higher doses."),
                SubjectiveEffect(name: "Sedation", description: "A heavy, drowsy feeling that can progress rapidly to irresistible sleepiness at higher doses."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 2, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 25,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA"]
        ),

        Substance(
            name: "1,4-Butanediol",
            aliases: ["1,4-BDO", "BD"],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mL", doses: DoseRange(
                    threshold: 0.5, light: 0.5...1.0, common: 1.0...2.0, strong: 2.0...3.0, heavy: 3.0, fatal: 8
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 45, max: 90),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 90, max: 180)
                )),
            ],
            effects: ["Euphoria", "Disinhibition", "Sedation", "Anxiolysis", "Drowsiness", "Muscle relaxation", "Enhanced libido", "Dizziness", "Nausea", "Slurred speech"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Delayed onset euphoria", description: "Effects take longer to manifest than GHB or GBL, with a slow build to a warm, pleasant body high."),
                SubjectiveEffect(name: "Disinhibition", description: "Social inhibitions gradually dissolve, leading to increased openness and talkativeness."),
                SubjectiveEffect(name: "Physical warmth", description: "A diffuse sense of warmth spreading through the limbs and torso, often described as cozy and comforting."),
                SubjectiveEffect(name: "Unpredictable dosing", description: "Effects can vary significantly between batches and individuals, making the experience feel inconsistent."),
                SubjectiveEffect(name: "Nausea", description: "Stomach discomfort and nausea are common, particularly during the onset as the body metabolizes the compound."),
                SubjectiveEffect(name: "Sedation", description: "A progressive heaviness and drowsiness that intensifies with dose, sometimes leading to sudden unconsciousness."),
                SubjectiveEffect(name: "Slurred speech", description: "Words become difficult to articulate clearly, similar to alcohol intoxication but often more pronounced."),
                SubjectiveEffect(name: "Motor impairment", description: "Physical coordination deteriorates, making walking and fine motor tasks challenging."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 2, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 25,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA"]
        ),

        // MARK: - Gabapentinoids

        Substance(
            name: "Gabapentin",
            aliases: ["Neurontin"],
            category: .gabapentinoid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 200...600, common: 600...1200, strong: 1200...1800, heavy: 1800, fatal: 50000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 180, max: 300),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 600)
                )),
            ],
            effects: ["Anxiolysis", "Sedation", "Muscle relaxation", "Euphoria", "Pain relief", "Dizziness", "Drowsiness", "Mood lift", "Physical warmth"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Anxiolysis", description: "Worries feel distant and manageable, with a pervasive calm that makes social situations less daunting."),
                SubjectiveEffect(name: "Physical warmth", description: "A gentle, glowing warmth in the body, particularly noticeable in the extremities and chest."),
                SubjectiveEffect(name: "Mood lift", description: "A subtle but noticeable brightening of mood, making everyday activities feel more pleasant and engaging."),
                SubjectiveEffect(name: "Muscle relaxation", description: "Tension in muscles loosens noticeably, providing relief from tightness and physical stress."),
                SubjectiveEffect(name: "Pain relief", description: "Nerve pain and discomfort become dulled, with a numbing quality that makes chronic pain more tolerable."),
                SubjectiveEffect(name: "Cognitive fog", description: "Thinking may feel slightly hazy or slowed, with difficulty concentrating on detailed tasks."),
                SubjectiveEffect(name: "Dizziness", description: "A mild spinning or unsteady sensation, especially when standing up quickly or changing positions."),
                SubjectiveEffect(name: "Staggered absorption", description: "Effects build slowly and unevenly due to dose-dependent absorption, requiring patience between doses."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 360,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Pregabalin",
            aliases: ["Lyrica"],
            category: .gabapentinoid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...150, common: 150...300, strong: 300...600, heavy: 600, fatal: 10000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 180, max: 300),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 600)
                )),
            ],
            effects: ["Euphoria", "Anxiolysis", "Sedation", "Muscle relaxation", "Pain relief", "Disinhibition", "Drowsiness", "Dizziness", "Physical warmth", "Mood lift"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Euphoria", description: "A pronounced sense of well-being and pleasure that is often described as more reliable and intense than gabapentin."),
                SubjectiveEffect(name: "Anxiolysis", description: "Anxiety dissolves comprehensively, producing a confident and socially at-ease state of mind."),
                SubjectiveEffect(name: "Sociability enhancement", description: "Social interactions feel natural and enjoyable, with reduced self-consciousness and increased warmth toward others."),
                SubjectiveEffect(name: "Physical warmth", description: "A comfortable, enveloping warmth throughout the body that contributes to overall feelings of contentment."),
                SubjectiveEffect(name: "Music appreciation enhancement", description: "Music sounds more vivid and emotionally impactful, with enhanced perception of rhythm and melody."),
                SubjectiveEffect(name: "Pain relief", description: "Neuropathic and general pain become significantly dulled, providing noticeable physical comfort."),
                SubjectiveEffect(name: "Disinhibition", description: "Behavioral restraints loosen, sometimes leading to impulsive decisions or oversharing in conversations."),
                SubjectiveEffect(name: "Drowsiness", description: "A creeping sleepiness that becomes more prominent as effects progress, especially at higher doses."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 378,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Phenibut",
            aliases: ["PhGABA"],
            category: .gabapentinoid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 250...750, common: 750...1500, strong: 1500...2500, heavy: 2500, fatal: 15000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: TimeRange(min: 240, max: 720),
                    total: TimeRange(min: 480, max: 840)
                )),
            ],
            effects: ["Anxiolysis", "Euphoria", "Increased sociability", "Sedation", "Muscle relaxation", "Mood lift", "Disinhibition", "Drowsiness", "Enhanced music appreciation", "Physical warmth"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Anxiolysis", description: "A profound reduction in anxiety that makes previously stressful situations feel completely manageable and comfortable."),
                SubjectiveEffect(name: "Sociability enhancement", description: "A strong urge to socialize and connect, with conversations feeling effortless and deeply rewarding."),
                SubjectiveEffect(name: "Euphoria", description: "A buoyant, optimistic mood elevation that colors experiences positively and enhances everyday pleasures."),
                SubjectiveEffect(name: "Music appreciation enhancement", description: "Music becomes deeply immersive, with enhanced emotional response to lyrics, melodies, and rhythms."),
                SubjectiveEffect(name: "Physical warmth", description: "A cozy, full-body warmth that promotes relaxation and a sense of physical well-being."),
                SubjectiveEffect(name: "Disinhibition", description: "Inhibitions lower significantly, which can manifest as increased openness but also impulsive behavior."),
                SubjectiveEffect(name: "Slow onset", description: "Effects take 2-4 hours to fully manifest, often leading to the temptation to redose prematurely."),
                SubjectiveEffect(name: "Rebound anxiety", description: "When effects wear off, anxiety can return more intensely than baseline, especially with frequent use."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 300,
            sources: ["PsychonautWiki", "Examine.com", "PubMed"]
        ),

        Substance(
            name: "Baclofen",
            aliases: [],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...25, common: 25...50, strong: 50...80, heavy: 80, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 540)
                )),
            ],
            effects: ["Muscle relaxation", "Sedation", "Anxiolysis", "Drowsiness", "Dizziness", "Weakness", "Pain relief", "Fatigue"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Muscle relaxation", description: "A deep, pervasive loosening of muscle tension that provides significant relief from spasticity and tightness."),
                SubjectiveEffect(name: "Sedation", description: "A calm, sleepy feeling that makes resting and lying down feel particularly comfortable and inviting."),
                SubjectiveEffect(name: "Anxiolysis", description: "A mild reduction in anxiety, more subtle than phenibut or pregabalin but still noticeable."),
                SubjectiveEffect(name: "Physical heaviness", description: "The body feels weighted and relaxed, with a strong pull toward stillness and rest."),
                SubjectiveEffect(name: "Dizziness", description: "Lightheadedness and a sense of unsteadiness, especially when transitioning between positions."),
                SubjectiveEffect(name: "Weakness", description: "Muscles may feel less responsive and weaker than usual, making physical exertion feel more effortful."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 210,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "F-Phenibut",
            aliases: ["Fluorophenibut"],
            category: .gabapentinoid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...250, common: 250...500, strong: 500...750, heavy: 750, fatal: 3000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 300, max: 540)
                )),
            ],
            effects: ["Anxiolysis", "Sedation", "Euphoria", "Muscle relaxation", "Drowsiness", "Disinhibition", "Mood lift", "Physical warmth", "Dizziness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Anxiolysis", description: "A rapid and potent reduction in anxiety, noticeably stronger and faster-acting than regular phenibut."),
                SubjectiveEffect(name: "Euphoria", description: "A warm, pleasant mood elevation that feels similar to phenibut but arrives more quickly."),
                SubjectiveEffect(name: "Sedation", description: "A pronounced drowsiness that can become overwhelming, especially at higher doses."),
                SubjectiveEffect(name: "Muscle relaxation", description: "Noticeable loosening of muscular tension throughout the body, promoting physical comfort."),
                SubjectiveEffect(name: "Shorter duration", description: "Effects are more compressed in time compared to phenibut, wearing off faster and potentially leading to more frequent dosing."),
                SubjectiveEffect(name: "Physical warmth", description: "A soothing bodily warmth that enhances the overall sense of relaxation and well-being."),
                SubjectiveEffect(name: "Disinhibition", description: "Social hesitation diminishes, leading to more open and forthcoming behavior in interactions."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 240,
            sources: ["PsychonautWiki", "PubMed", "EMCDDA"]
        ),

        // MARK: - Z-drugs

        Substance(
            name: "Zolpidem",
            aliases: ["Ambien", "Stilnox"],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...20, strong: 20...30, heavy: 30, fatal: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Sedation", "Drowsiness", "Amnesia", "Anxiolysis", "Euphoria", "Visual distortions", "Disinhibition", "Confusion", "Hallucinations", "Muscle relaxation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Hypnotic sedation", description: "An irresistible pull toward sleep that feels distinctly different from natural tiredness, with a heavy, sinking quality."),
                SubjectiveEffect(name: "Visual distortions", description: "Objects may appear to shift, melt, or breathe, and patterns can emerge from surfaces in a dreamlike fashion."),
                SubjectiveEffect(name: "Amnesia", description: "Actions performed under the influence may be completely forgotten, creating blackout periods with no recall."),
                SubjectiveEffect(name: "Disinhibition", description: "Behavior becomes impulsive and uninhibited, sometimes leading to unusual activities with no subsequent memory."),
                SubjectiveEffect(name: "Euphoria", description: "A pleasant, dreamy euphoria that occurs when the urge to sleep is resisted, often with surreal qualities."),
                SubjectiveEffect(name: "Hallucinations", description: "Vivid hallucinations may occur, including seeing people or objects that are not present, especially at higher doses."),
                SubjectiveEffect(name: "Deliriant-like confusion", description: "A dream-like state of confusion where the boundary between waking reality and hallucination blurs."),
                SubjectiveEffect(name: "Motor impairment", description: "Walking becomes uncoordinated and unstable, with a sensation of floating or disconnection from the body."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 150,
            sources: ["Drugs.com", "PsychonautWiki", "StatPearls"]
        ),

        Substance(
            name: "Zopiclone",
            aliases: ["Imovane", "Zimovane"],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1.875, light: 3.75...7.5, common: 7.5...15, strong: 15...22.5, heavy: 22.5, fatal: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 180),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: nil,
                    total: TimeRange(min: 300, max: 420)
                )),
            ],
            effects: ["Sedation", "Drowsiness", "Anxiolysis", "Amnesia", "Metallic taste", "Muscle relaxation", "Dizziness", "Confusion", "Euphoria"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Hypnotic sedation", description: "A heavy drowsiness that feels pharmacologically distinct from tiredness, pulling strongly toward sleep."),
                SubjectiveEffect(name: "Metallic taste", description: "A persistent bitter, metallic taste in the mouth that is a hallmark of zopiclone and can linger into the next day."),
                SubjectiveEffect(name: "Amnesia", description: "Memory formation is significantly impaired, and activities performed after dosing may be forgotten entirely."),
                SubjectiveEffect(name: "Anxiolysis", description: "Anxiety is suppressed effectively, contributing to a relaxed and carefree mental state."),
                SubjectiveEffect(name: "Muscle relaxation", description: "Muscles feel loose and relaxed, with physical tension dissolving throughout the body."),
                SubjectiveEffect(name: "Mild euphoria", description: "A subtle pleasant feeling when fighting off sleep, less intense than zolpidem but still noticeable."),
                SubjectiveEffect(name: "Confusion", description: "Thinking becomes muddled and disorganized, with difficulty following logical trains of thought."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 300,
            sources: ["Drugs.com", "PsychonautWiki", "StatPearls"]
        ),

        Substance(
            name: "Eszopiclone",
            aliases: ["Lunesta"],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 1...2, common: 2...3, strong: 3...6, heavy: 6, fatal: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Sedation", "Drowsiness", "Anxiolysis", "Amnesia", "Unpleasant taste", "Muscle relaxation", "Dizziness", "Confusion", "Euphoria"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Hypnotic sedation", description: "A strong, pharmacological sleepiness that promotes rapid sleep onset with a sinking, heavy quality."),
                SubjectiveEffect(name: "Unpleasant taste", description: "A bitter, metallic aftertaste similar to zopiclone that can persist for hours after ingestion."),
                SubjectiveEffect(name: "Amnesia", description: "Significant anterograde amnesia, with activities during the influence period often completely unrecalled."),
                SubjectiveEffect(name: "Anxiolysis", description: "Anxiety is effectively dampened, producing a calm and unbothered mental state."),
                SubjectiveEffect(name: "Mild euphoria", description: "A gentle sense of well-being and dreaminess, particularly when staying awake through the sedation."),
                SubjectiveEffect(name: "Confusion", description: "Mental clarity decreases, with thought processes becoming scattered and difficult to follow."),
                SubjectiveEffect(name: "Dizziness", description: "A sense of lightheadedness and spatial disorientation, particularly when standing or moving."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 360,
            sources: ["Drugs.com", "PsychonautWiki", "StatPearls"]
        ),

        Substance(
            name: "Zaleplon",
            aliases: ["Sonata"],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...20, strong: 20...40, heavy: 40, fatal: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 20),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: nil,
                    total: TimeRange(min: 60, max: 120)
                )),
            ],
            effects: ["Sedation", "Drowsiness", "Anxiolysis", "Amnesia", "Dizziness", "Euphoria", "Visual distortions", "Muscle relaxation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Ultra-short sedation", description: "Effects come on very rapidly and wear off quickly, producing a brief but intense window of sleepiness."),
                SubjectiveEffect(name: "Visual distortions", description: "Brief visual anomalies may occur, including trailing, color shifts, or subtle pattern distortions."),
                SubjectiveEffect(name: "Amnesia", description: "Memory blackouts can occur during the short active window, despite the brevity of effects."),
                SubjectiveEffect(name: "Euphoria", description: "A fleeting, pleasant dreaminess that emerges when staying awake through the sedative window."),
                SubjectiveEffect(name: "Anxiolysis", description: "A brief but effective reduction in anxiety during the short active period."),
                SubjectiveEffect(name: "Dizziness", description: "A spinning or floating sensation that accompanies the rapid onset of effects."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 60,
            sources: ["Drugs.com", "PsychonautWiki", "StatPearls"]
        ),

        // MARK: - Barbiturates

        Substance(
            name: "Phenobarbital",
            aliases: ["Luminal"],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 15, light: 30...60, common: 60...120, strong: 120...200, heavy: 200, fatal: 1500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Sedation", "Anxiolysis", "Drowsiness", "Muscle relaxation", "Cognitive suppression", "Motor impairment", "Disinhibition", "Euphoria"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Deep sedation", description: "A heavy, blanketing sedation that promotes sleep and makes staying awake feel like a significant effort."),
                SubjectiveEffect(name: "Anxiolysis", description: "A thorough suppression of anxiety, producing a calm detachment from worries and stressors."),
                SubjectiveEffect(name: "Cognitive suppression", description: "Mental processing slows considerably, with complex thinking and concentration becoming very difficult."),
                SubjectiveEffect(name: "Motor impairment", description: "Coordination degrades significantly, with ataxic gait and difficulty performing precise physical tasks."),
                SubjectiveEffect(name: "Long duration", description: "Effects persist for many hours due to the long half-life, providing extended but potentially excessive sedation."),
                SubjectiveEffect(name: "Mild euphoria", description: "A subdued sense of contentment and well-being, less pronounced than shorter-acting barbiturates."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 30, buildRate: "moderate"),
            halfLifeMinutes: 4800,
            sources: ["Drugs.com", "PsychonautWiki", "StatPearls"]
        ),

        Substance(
            name: "Secobarbital",
            aliases: ["Seconal"],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...300, heavy: 300, fatal: 3000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 240, max: 420)
                )),
            ],
            effects: ["Euphoria", "Sedation", "Anxiolysis", "Disinhibition", "Drowsiness", "Muscle relaxation", "Cognitive suppression", "Motor impairment", "Slurred speech"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Euphoria", description: "A warm, enveloping sense of pleasure and well-being that comes on relatively quickly for a barbiturate."),
                SubjectiveEffect(name: "Disinhibition", description: "Behavioral restraints lower dramatically, producing a carefree attitude similar to alcohol but more sedating."),
                SubjectiveEffect(name: "Sedation", description: "A powerful drowsiness that makes resisting sleep progressively harder as effects intensify."),
                SubjectiveEffect(name: "Slurred speech", description: "Articulation becomes difficult, with words blending together and speech becoming labored."),
                SubjectiveEffect(name: "Cognitive impairment", description: "Thinking becomes sluggish and disorganized, with impaired judgment and decision-making."),
                SubjectiveEffect(name: "Motor incoordination", description: "Balance and coordination are severely affected, with stumbling and unsteady movements."),
                SubjectiveEffect(name: "Anxiolysis", description: "Anxiety is powerfully suppressed, producing a state of calm detachment from concerns."),
                SubjectiveEffect(name: "Warmth", description: "A pleasant physical warmth that adds to the overall sense of comfort and relaxation."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 1680,
            sources: ["Drugs.com", "PsychonautWiki", "StatPearls"]
        ),

        Substance(
            name: "Pentobarbital",
            aliases: ["Nembutal"],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...300, heavy: 300, fatal: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 240, max: 420)
                )),
            ],
            effects: ["Sedation", "Euphoria", "Anxiolysis", "Drowsiness", "Disinhibition", "Muscle relaxation", "Cognitive suppression", "Motor impairment", "Slurred speech"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Rapid sedation", description: "A fast-acting wave of drowsiness and heaviness that descends quickly after ingestion."),
                SubjectiveEffect(name: "Euphoria", description: "A strong, warm euphoria that is often described as dreamy and enveloping."),
                SubjectiveEffect(name: "Disinhibition", description: "Social and behavioral inhibitions dissolve, leading to impulsive and uninhibited behavior."),
                SubjectiveEffect(name: "Anxiolysis", description: "Anxiety is profoundly suppressed, with worries feeling remote and insignificant."),
                SubjectiveEffect(name: "Slurred speech", description: "Speech becomes noticeably impaired, with words running together and pronunciation deteriorating."),
                SubjectiveEffect(name: "Motor impairment", description: "Physical coordination is severely compromised, making even simple movements feel unsteady."),
                SubjectiveEffect(name: "Cognitive suppression", description: "Clear thinking becomes impossible at higher doses, with judgment and reasoning deeply impaired."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 1200,
            sources: ["Drugs.com", "PsychonautWiki", "StatPearls"]
        ),

        Substance(
            name: "Amobarbital",
            aliases: ["Amytal"],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 15, light: 30...65, common: 65...200, strong: 200...400, heavy: 400, fatal: 3000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 600)
                )),
            ],
            effects: ["Sedation", "Euphoria", "Anxiolysis", "Drowsiness", "Disinhibition", "Muscle relaxation", "Cognitive suppression", "Motor impairment", "Slurred speech"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Sedation", description: "A deep, intermediate-duration sedation that promotes sleep and profound relaxation."),
                SubjectiveEffect(name: "Euphoria", description: "A pleasant warmth and sense of well-being similar to other intermediate-acting barbiturates."),
                SubjectiveEffect(name: "Anxiolysis", description: "Anxiety dissolves into a state of calm indifference, with stressors feeling distant and unimportant."),
                SubjectiveEffect(name: "Disinhibition", description: "Social barriers break down, leading to increased openness and sometimes reckless behavior."),
                SubjectiveEffect(name: "Muscle relaxation", description: "Deep physical relaxation with significant loosening of muscle tension throughout the body."),
                SubjectiveEffect(name: "Cognitive fog", description: "Thinking becomes cloudy and unfocused, with impaired memory formation and recall."),
                SubjectiveEffect(name: "Motor impairment", description: "Balance and coordination are noticeably impaired, with an ataxic, unsteady quality to movement."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 1320,
            sources: ["Drugs.com", "PsychonautWiki", "StatPearls"]
        ),

        Substance(
            name: "Butalbital",
            aliases: ["Fiorinal component"],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...300, heavy: 300, fatal: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 300, max: 540)
                )),
            ],
            effects: ["Sedation", "Anxiolysis", "Drowsiness", "Muscle relaxation", "Euphoria", "Pain relief", "Cognitive suppression", "Motor impairment"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Headache relief", description: "Effective relief from tension headaches, particularly when combined with analgesics as in its typical formulation."),
                SubjectiveEffect(name: "Sedation", description: "A moderate sedation that promotes drowsiness and relaxation without the extreme intensity of stronger barbiturates."),
                SubjectiveEffect(name: "Anxiolysis", description: "Anxiety is reduced to a manageable level, contributing to the headache-relieving properties."),
                SubjectiveEffect(name: "Mild euphoria", description: "A gentle sense of well-being that is less pronounced than shorter-acting barbiturates but still present."),
                SubjectiveEffect(name: "Muscle relaxation", description: "Tension in the head, neck, and shoulders loosens, complementing the pain-relieving effects."),
                SubjectiveEffect(name: "Cognitive dulling", description: "Mental sharpness decreases, with slower processing and reduced ability to concentrate."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 2100,
            sources: ["Drugs.com", "PsychonautWiki", "StatPearls"]
        ),

        // MARK: - Muscle Relaxants

        Substance(
            name: "Carisoprodol",
            aliases: ["Soma"],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 175...350, common: 350...700, strong: 700...1050, heavy: 1050, fatal: 10000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Muscle relaxation", "Euphoria", "Sedation", "Anxiolysis", "Drowsiness", "Disinhibition", "Dizziness", "Motor impairment", "Pain relief"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Physical euphoria", description: "A distinctive, warm bodily pleasure often described as a full-body relaxation that feels deeply satisfying."),
                SubjectiveEffect(name: "Muscle relaxation", description: "Profound loosening of all muscle groups, creating a sensation of the body melting into whatever surface it rests on."),
                SubjectiveEffect(name: "Sedation", description: "A heavy, pleasant drowsiness that makes resting and being still feel deeply comfortable."),
                SubjectiveEffect(name: "Disinhibition", description: "Inhibitions lower markedly, producing a carefree and socially open state of mind."),
                SubjectiveEffect(name: "Anxiolysis", description: "Anxiety and worry dissolve, replaced by a tranquil sense of calm and acceptance."),
                SubjectiveEffect(name: "Dizziness", description: "A floating, lightheaded sensation that contributes to the overall sense of detachment from physical tension."),
                SubjectiveEffect(name: "Motor impairment", description: "Coordination becomes noticeably impaired, with the body feeling loose and movements imprecise."),
                SubjectiveEffect(name: "Pain relief", description: "Muscular and general pain is significantly dulled, providing welcome relief from physical discomfort."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 120,
            sources: ["Drugs.com", "PsychonautWiki", "StatPearls"]
        ),

        Substance(
            name: "Methocarbamol",
            aliases: ["Robaxin"],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 250, light: 500...1000, common: 1000...1500, strong: 1500...2000, heavy: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Muscle relaxation", "Sedation", "Drowsiness", "Dizziness", "Pain relief", "Lightheadedness", "Nausea", "Blurred vision"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Muscle relaxation", description: "A functional loosening of tense muscles, providing relief from spasms and physical rigidity."),
                SubjectiveEffect(name: "Sedation", description: "A mild to moderate drowsiness that can make activities requiring alertness more difficult."),
                SubjectiveEffect(name: "Lightheadedness", description: "A floaty, dizzy sensation particularly when standing up or changing positions quickly."),
                SubjectiveEffect(name: "Nausea", description: "Stomach discomfort that can accompany the onset, sometimes persisting throughout the experience."),
                SubjectiveEffect(name: "Blurred vision", description: "Visual clarity decreases, with difficulty focusing on fine details or reading small text."),
                SubjectiveEffect(name: "Pain relief", description: "Muscular pain and tension are reduced, providing functional improvement in movement and comfort."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 60,
            sources: ["Drugs.com", "PsychonautWiki", "StatPearls"]
        ),

        Substance(
            name: "Cyclobenzaprine",
            aliases: ["Flexeril"],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...20, strong: 20...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 180, max: 300),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 720)
                )),
            ],
            effects: ["Muscle relaxation", "Sedation", "Drowsiness", "Dry mouth", "Dizziness", "Fatigue", "Blurred vision", "Confusion"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Muscle relaxation", description: "A thorough relaxation of skeletal muscles that provides relief from spasms, stiffness, and tension."),
                SubjectiveEffect(name: "Sedation", description: "A pronounced drowsiness with an anticholinergic quality, making mental alertness difficult to maintain."),
                SubjectiveEffect(name: "Dry mouth", description: "Noticeable reduction in saliva production, causing a persistent dry, cottony feeling in the mouth."),
                SubjectiveEffect(name: "Fatigue", description: "A pervasive tiredness that saps energy and motivation, making even light activity feel exhausting."),
                SubjectiveEffect(name: "Blurred vision", description: "Visual acuity decreases, with objects appearing hazy or out of focus, especially at close range."),
                SubjectiveEffect(name: "Mild mood lift", description: "A subtle improvement in mood, likely related to the relief of muscular pain and tension."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 1080,
            sources: ["Drugs.com", "PsychonautWiki", "StatPearls"]
        ),

        Substance(
            name: "Tizanidine",
            aliases: ["Zanaflex"],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...4, common: 4...8, strong: 8...16, heavy: 16
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Muscle relaxation", "Sedation", "Drowsiness", "Dizziness", "Dry mouth", "Hypotension", "Fatigue", "Weakness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Muscle relaxation", description: "A potent centrally-mediated muscle relaxation that effectively reduces spasticity and involuntary contractions."),
                SubjectiveEffect(name: "Sedation", description: "A strong drowsiness that can be overwhelming, particularly at higher doses or during initial use."),
                SubjectiveEffect(name: "Hypotension", description: "Blood pressure drops noticeably, causing lightheadedness and a sense of weakness when standing."),
                SubjectiveEffect(name: "Dry mouth", description: "Reduced saliva flow creating a persistent dry sensation in the mouth and throat."),
                SubjectiveEffect(name: "Physical heaviness", description: "The body feels weighted down and sluggish, with a strong desire to remain still and rest."),
                SubjectiveEffect(name: "Fatigue", description: "An encompassing tiredness that affects both physical energy and mental alertness."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 150,
            sources: ["Drugs.com", "PsychonautWiki", "StatPearls"]
        ),

        Substance(
            name: "Chlorzoxazone",
            aliases: [],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 125, light: 250...500, common: 500...750, strong: 750...1000, heavy: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Muscle relaxation", "Sedation", "Drowsiness", "Dizziness", "Lightheadedness", "Nausea", "Pain relief"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Muscle relaxation", description: "A moderate loosening of muscle tension, primarily centrally mediated, that relieves spasms and rigidity."),
                SubjectiveEffect(name: "Sedation", description: "A mild to moderate drowsiness that accompanies the muscle-relaxant effects."),
                SubjectiveEffect(name: "Lightheadedness", description: "A feeling of faintness and unsteadiness, especially during transitions from sitting to standing."),
                SubjectiveEffect(name: "Nausea", description: "Stomach upset that is common particularly during the first few doses, often diminishing with continued use."),
                SubjectiveEffect(name: "Pain relief", description: "Muscular pain and discomfort are reduced, improving physical function and comfort."),
                SubjectiveEffect(name: "Dizziness", description: "A mild vertiginous feeling that accompanies the general central nervous system depression."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 60,
            sources: ["Drugs.com", "PsychonautWiki", "StatPearls"]
        ),

        Substance(
            name: "Orphenadrine",
            aliases: ["Norflex"],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...150, strong: 150...200, heavy: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 600)
                )),
            ],
            effects: ["Muscle relaxation", "Sedation", "Dry mouth", "Euphoria", "Dizziness", "Drowsiness", "Blurred vision", "Anticholinergic effects"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Anticholinergic effects", description: "Dry mouth, blurred vision, and urinary retention from the anticholinergic action, which distinguishes it from other muscle relaxants."),
                SubjectiveEffect(name: "Euphoria", description: "A mild, pleasant mood elevation that sets orphenadrine apart from purely functional muscle relaxants."),
                SubjectiveEffect(name: "Muscle relaxation", description: "Reduction in muscle spasms and tension through both central and anticholinergic mechanisms."),
                SubjectiveEffect(name: "Dry mouth", description: "A pronounced dryness in the mouth and throat due to the suppression of saliva production."),
                SubjectiveEffect(name: "Blurred vision", description: "Difficulty focusing on nearby objects due to pupil dilation and impaired accommodation."),
                SubjectiveEffect(name: "Sedation", description: "A moderate drowsiness that can impair alertness and make concentration difficult."),
                SubjectiveEffect(name: "Dizziness", description: "A lightheaded, unsteady feeling that may worsen with positional changes."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 840,
            sources: ["Drugs.com", "PsychonautWiki", "StatPearls"]
        ),

        Substance(
            name: "Metaxalone",
            aliases: ["Skelaxin"],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 200, light: 400...800, common: 800...1200, strong: 1200...1600, heavy: 1600
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Muscle relaxation", "Sedation", "Drowsiness", "Dizziness", "Pain relief", "Nausea", "Euphoria", "Lightheadedness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Muscle relaxation", description: "Effective relief from musculoskeletal tension and pain, with a central mechanism of action."),
                SubjectiveEffect(name: "Euphoria", description: "A mild sense of well-being and mood elevation that is occasionally reported, more so than with some other muscle relaxants."),
                SubjectiveEffect(name: "Sedation", description: "A moderate drowsiness that can impair daily activities and makes resting feel more appealing."),
                SubjectiveEffect(name: "Pain relief", description: "Relief from muscle-related pain and discomfort, improving range of motion and comfort."),
                SubjectiveEffect(name: "Lightheadedness", description: "A sensation of faintness or floating, particularly when standing or exerting oneself."),
                SubjectiveEffect(name: "Nausea", description: "Stomach discomfort that occasionally accompanies the effects, particularly on an empty stomach."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 180,
            sources: ["Drugs.com", "PsychonautWiki", "StatPearls"]
        ),

        // MARK: - Alcohol

        Substance(
            name: "Ethanol",
            aliases: ["Alcohol", "Booze"],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "drinks", doses: DoseRange(
                    threshold: 0.5, light: 1...2, common: 2...4, strong: 4...6, heavy: 6, fatal: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 30, max: 90),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 480),
                    total: TimeRange(min: 120, max: 300)
                )),
            ],
            effects: ["Euphoria", "Disinhibition", "Anxiolysis", "Sedation", "Increased sociability", "Drowsiness", "Slurred speech", "Motor impairment", "Dizziness", "Nausea"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Disinhibition", description: "Social and behavioral restraints progressively dissolve, leading to increased confidence and reduced self-consciousness."),
                SubjectiveEffect(name: "Euphoria", description: "A warm, sociable mood elevation that makes social situations feel more enjoyable and rewarding."),
                SubjectiveEffect(name: "Sociability enhancement", description: "A strong drive to interact with others, with conversations feeling easier and more enjoyable."),
                SubjectiveEffect(name: "Anxiolysis", description: "Worries and social anxiety diminish, replaced by a sense of ease and comfort in one's surroundings."),
                SubjectiveEffect(name: "Cognitive impairment", description: "Thinking and judgment progressively deteriorate with dose, leading to poor decision-making and slowed processing."),
                SubjectiveEffect(name: "Motor incoordination", description: "Balance and fine motor skills degrade, with stumbling, swaying, and clumsy movements becoming apparent."),
                SubjectiveEffect(name: "Emotional amplification", description: "Emotions become more intense and volatile, with mood swings between happiness, sentimentality, and irritability."),
                SubjectiveEffect(name: "Nausea", description: "Stomach discomfort and nausea increase with dose, sometimes progressing to vomiting at higher amounts."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 90,
            sources: ["Drugs.com", "PsychonautWiki", "StatPearls"]
        ),

        // MARK: - Other GABAergics

        Substance(
            name: "Chloral Hydrate",
            aliases: [],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 125, light: 250...500, common: 500...1000, strong: 1000...1500, heavy: 1500, fatal: 10000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Sedation", "Drowsiness", "Anxiolysis", "Euphoria", "Dizziness", "Nausea", "Motor impairment", "Confusion"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Sedation", description: "A deep, heavy drowsiness that historically made this substance effective as a knockout agent."),
                SubjectiveEffect(name: "Rapid onset", description: "Effects come on quickly after ingestion, with sedation building rapidly to a peak."),
                SubjectiveEffect(name: "Confusion", description: "Mental clarity deteriorates significantly, with disorientation and difficulty understanding one's surroundings."),
                SubjectiveEffect(name: "Nausea", description: "Stomach upset is common and often precedes the sedative effects, sometimes with vomiting."),
                SubjectiveEffect(name: "Gastric irritation", description: "The compound can cause significant stomach and throat irritation during ingestion."),
                SubjectiveEffect(name: "Motor impairment", description: "Balance and coordination are substantially compromised during the active effects."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 480,
            sources: ["Drugs.com", "PsychonautWiki", "StatPearls"]
        ),

        Substance(
            name: "Kavalactones",
            aliases: ["Kava"],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 70...150, common: 150...250, strong: 250...400, heavy: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Anxiolysis", "Muscle relaxation", "Sedation", "Euphoria", "Increased sociability", "Physical warmth", "Pain relief", "Mood lift", "Drowsiness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Anxiolysis", description: "A gentle, natural-feeling reduction in anxiety that promotes calm without heavy sedation."),
                SubjectiveEffect(name: "Muscle relaxation", description: "A pleasant loosening of muscular tension, particularly in the jaw, neck, and shoulders."),
                SubjectiveEffect(name: "Sociability enhancement", description: "Social interaction feels easier and more enjoyable, with increased openness and warmth toward others."),
                SubjectiveEffect(name: "Physical warmth", description: "A spreading warmth through the body, especially in the face and extremities, that feels soothing and comforting."),
                SubjectiveEffect(name: "Mood lift", description: "A gentle elevation of mood that makes the world feel slightly brighter and more positive."),
                SubjectiveEffect(name: "Oral numbness", description: "Lips and tongue may feel numb or tingly after drinking kava, which is a characteristic and expected effect."),
                SubjectiveEffect(name: "Reverse tolerance", description: "Regular users often report that effects become more noticeable with continued use rather than less."),
                SubjectiveEffect(name: "Mild euphoria", description: "A subtle but pleasant sense of contentment and well-being that accompanies the relaxation."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 14, buildRate: "slow"),
            halfLifeMinutes: 210,
            sources: ["Drugs.com", "PsychonautWiki", "StatPearls"]
        ),

        Substance(
            name: "Meprobamate",
            aliases: ["Miltown"],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 200...400, common: 400...800, strong: 800...1200, heavy: 1200, fatal: 12000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 540)
                )),
            ],
            effects: ["Anxiolysis", "Sedation", "Euphoria", "Muscle relaxation", "Drowsiness", "Disinhibition", "Dizziness", "Motor impairment"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Anxiolysis", description: "A thorough suppression of anxiety that was historically the primary therapeutic use of this compound."),
                SubjectiveEffect(name: "Sedation", description: "A moderate, pleasant drowsiness that promotes relaxation and facilitates sleep."),
                SubjectiveEffect(name: "Euphoria", description: "A mild sense of well-being and contentment that contributes to the relaxed state."),
                SubjectiveEffect(name: "Muscle relaxation", description: "Physical tension is reduced, with muscles feeling loose and comfortable."),
                SubjectiveEffect(name: "Disinhibition", description: "Behavioral restraints are loosened, leading to more spontaneous and uninhibited behavior."),
                SubjectiveEffect(name: "Motor impairment", description: "Coordination and balance are impaired, with unsteady gait and clumsy movements."),
                SubjectiveEffect(name: "Dizziness", description: "A lightheaded, unsteady sensation that accompanies the sedative effects."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 600,
            sources: ["Drugs.com", "PsychonautWiki", "StatPearls"]
        ),

        Substance(
            name: "Methaqualone",
            aliases: ["Quaalude", "Mandrax"],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 75...150, common: 150...300, strong: 300...450, heavy: 450, fatal: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 240),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Euphoria", "Sedation", "Muscle relaxation", "Anxiolysis", "Disinhibition", "Enhanced libido", "Drowsiness", "Motor impairment", "Slurred speech", "Dizziness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Euphoria", description: "A distinctive, warm euphoria that was historically prized and made this one of the most sought-after sedatives."),
                SubjectiveEffect(name: "Muscle relaxation", description: "A profound full-body relaxation that makes the limbs feel heavy and loose, often described as boneless."),
                SubjectiveEffect(name: "Enhanced libido", description: "Sexual desire and tactile pleasure are heightened, which contributed to the substance's recreational reputation."),
                SubjectiveEffect(name: "Disinhibition", description: "Social and sexual inhibitions are markedly reduced, leading to more uninhibited behavior and expression."),
                SubjectiveEffect(name: "Sedation", description: "A heavy, pleasant drowsiness that progresses into deep sleep at higher doses."),
                SubjectiveEffect(name: "Physical warmth", description: "A warm, comfortable glow throughout the body that enhances the overall sense of well-being."),
                SubjectiveEffect(name: "Slurred speech", description: "Articulation becomes increasingly impaired as effects intensify, with words becoming indistinct."),
                SubjectiveEffect(name: "Motor impairment", description: "Movement becomes clumsy and uncoordinated, with a characteristic staggering gait."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 1200,
            sources: ["Drugs.com", "PsychonautWiki", "StatPearls"]
        ),

        Substance(
            name: "Muscimol",
            aliases: ["Amanita muscaria"],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...8, common: 8...15, strong: 15...20, heavy: 20, fatal: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 300),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 240, max: 480),
                    total: TimeRange(min: 300, max: 600)
                )),
            ],
            effects: ["Sedation", "Euphoria", "Visual distortions", "Dream-like state", "Muscle relaxation", "Dizziness", "Confusion", "Altered perception", "Nausea", "Drowsiness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Dream-like state", description: "Reality takes on a surreal, dreamlike quality where the boundary between waking consciousness and dreaming dissolves."),
                SubjectiveEffect(name: "Visual distortions", description: "Objects may appear to shift in size, colors may change, and the visual field can take on a wavy or liquid quality."),
                SubjectiveEffect(name: "Sedation", description: "A deep, unusual sedation unlike other GABAergics, with a hypnotic quality that promotes vivid internal experiences."),
                SubjectiveEffect(name: "Altered perception", description: "Sensory perception becomes distorted and unusual, with sounds, textures, and spatial awareness all affected."),
                SubjectiveEffect(name: "Euphoria", description: "A strange, otherworldly sense of bliss that feels qualitatively different from typical depressant euphoria."),
                SubjectiveEffect(name: "Confusion", description: "Disorientation is common, with difficulty distinguishing what is real from what is imagined."),
                SubjectiveEffect(name: "Nausea", description: "Stomach upset is frequently reported, particularly during the onset phase of effects."),
                SubjectiveEffect(name: "Micropsia and macropsia", description: "Objects may appear dramatically smaller or larger than they actually are, creating a disorienting Alice-in-Wonderland effect."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 10, buildRate: "moderate"),
            halfLifeMinutes: 180,
            sources: ["Drugs.com", "PsychonautWiki", "StatPearls"]
        ),

        // MARK: - Intravenous Anesthetics

        Substance(
            name: "Propofol",
            aliases: ["Diprivan", "Milk of Amnesia"],
            category: .depressant,
            defaultRoute: .intravenous,
            routes: [
                SubstanceRoute(route: .intravenous, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 20...50, common: 50...150, strong: 150...200, heavy: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.25, max: 0.5),
                    comeup: TimeRange(min: 0.5, max: 1),
                    peak: TimeRange(min: 5, max: 15),
                    offset: TimeRange(min: 5, max: 15),
                    afterglow: TimeRange(min: 15, max: 60),
                    total: TimeRange(min: 15, max: 60)
                )),
            ],
            effects: ["Rapid sedation", "Amnesia", "Euphoria on induction", "Respiratory depression", "Pain on injection"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Extremely Rapid Onset", description: "Consciousness fades within 15-30 seconds of injection, a dramatic and nearly instantaneous transition from alertness to unconsciousness."),
                SubjectiveEffect(name: "Warm Rush", description: "A brief but intense wave of warmth and tingling that spreads from the injection site through the body in the seconds before sedation takes hold."),
                SubjectiveEffect(name: "Euphoric Induction", description: "A fleeting but powerful sense of well-being and pleasure during the brief window between injection and loss of consciousness, often described as blissful."),
                SubjectiveEffect(name: "Complete Amnesia", description: "Total absence of memory formation during the period of anesthesia, with no recollection of events or passage of time."),
                SubjectiveEffect(name: "Dreamless Sleep", description: "Unlike natural sleep, propofol-induced unconsciousness is typically devoid of dreams, creating a sense of time simply vanishing."),
                SubjectiveEffect(name: "Pain at Injection Site", description: "A burning or stinging pain in the vein during injection that is common and distinctive, often the last sensation recalled before unconsciousness."),
                SubjectiveEffect(name: "Rapid Recovery", description: "Awakening occurs quickly after discontinuation with a clear-headed quality, though brief confusion and disorientation are common in the first moments."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 7, buildRate: "moderate"),
            halfLifeMinutes: 40,
            sources: ["Drugs.com", "PsychonautWiki", "StatPearls"]
        ),

        // MARK: - Other Muscle Relaxants

        Substance(
            name: "Dantrolene",
            aliases: ["Dantrium", "Ryanodex"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 12.5, light: 25...50, common: 50...100, strong: 100...200, heavy: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 360),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 720)
                )),
            ],
            effects: ["Muscle relaxation", "Drowsiness", "Fatigue", "Weakness", "Hepatotoxicity risk"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Peripheral Muscle Relaxation", description: "A direct relaxation of skeletal muscles that acts at the muscle fiber itself rather than the brain, reducing spasticity without heavy sedation."),
                SubjectiveEffect(name: "Weakness", description: "A noticeable decrease in muscle strength that can make physical activities and even routine tasks feel more effortful than usual."),
                SubjectiveEffect(name: "Drowsiness", description: "A mild to moderate sleepiness that accompanies treatment, though generally less central sedation than with other muscle relaxants."),
                SubjectiveEffect(name: "Fatigue", description: "A pervasive low-energy feeling that can affect daily functioning and motivation, especially during dose titration."),
                SubjectiveEffect(name: "Hepatotoxicity Awareness", description: "Liver damage is a serious risk with chronic use, requiring regular blood monitoring; symptoms like jaundice or abdominal pain demand immediate medical attention."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 14, buildRate: "slow"),
            halfLifeMinutes: 480,
            sources: ["Drugs.com", "PsychonautWiki", "StatPearls"]
        ),
    ]
}
