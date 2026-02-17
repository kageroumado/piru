import Foundation

extension SubstanceLibrary {
    static let antidepressants: [Substance] = [

        // MARK: - SSRIs

        Substance(
            name: "Sertraline",
            aliases: ["Zoloft"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 12.5, light: 25...50, common: 50...100, strong: 100...200, heavy: 200, fatal: 5000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Reduced anxiety", "Nausea", "Sexual dysfunction", "Diarrhea", "Insomnia", "Drowsiness", "Dry mouth"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Emotional Blunting", description: "A narrowing of the emotional range where both highs and lows feel muted, sometimes described as feeling 'flat' or 'numb'."),
                SubjectiveEffect(name: "Anxiolysis", description: "A gradual reduction in baseline anxiety levels that develops over weeks, making daily worries feel less consuming."),
                SubjectiveEffect(name: "Motivation Shift", description: "A subtle return of motivation and interest in activities that had felt pointless during depressive episodes."),
                SubjectiveEffect(name: "GI Disturbance", description: "Nausea, loose stools, or stomach cramping that is typically most noticeable in the first 1-2 weeks and tends to subside."),
                SubjectiveEffect(name: "Sexual Dysfunction", description: "Difficulty reaching orgasm, reduced libido, or genital numbness that often persists throughout treatment."),
                SubjectiveEffect(name: "Brain Zaps on Discontinuation", description: "Brief electric shock-like sensations in the head when doses are missed or reduced too quickly."),
                SubjectiveEffect(name: "Initial Activation", description: "A jittery, restless, or wired feeling in the first week that can temporarily increase anxiety before therapeutic effects emerge."),
                SubjectiveEffect(name: "Sleep Disruption", description: "Difficulty falling asleep or staying asleep, sometimes accompanied by vivid dreams, particularly in the early weeks."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 60, buildRate: "slow"),
            halfLifeMinutes: 1560
        ),

        Substance(
            name: "Fluoxetine",
            aliases: ["Prozac"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...80, heavy: 80, fatal: 5000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Reduced anxiety", "Nausea", "Sexual dysfunction", "Insomnia", "Appetite suppression", "Nervousness", "Headache"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Emotional Blunting", description: "A muting of emotional highs and lows that can feel like watching life from behind glass."),
                SubjectiveEffect(name: "Anxiolysis", description: "A gradual easing of persistent worry and tension that becomes noticeable after 2-4 weeks of consistent use."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A reduced interest in food and decreased hunger cues, sometimes leading to modest weight loss."),
                SubjectiveEffect(name: "Activation Energy", description: "A subtle increase in mental energy and initiative that can feel slightly stimulating compared to other SSRIs."),
                SubjectiveEffect(name: "Sexual Dysfunction", description: "Delayed orgasm, reduced genital sensitivity, or diminished sex drive that often persists throughout treatment."),
                SubjectiveEffect(name: "Initial Nervousness", description: "A jittery, agitated feeling during the first 1-2 weeks that can paradoxically worsen anxiety before improvement."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty falling or staying asleep, sometimes accompanied by vivid or unusual dreams."),
                SubjectiveEffect(name: "Cognitive Clarity", description: "An emerging sense that thoughts are less clouded by depressive rumination, noticed gradually over weeks."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 21, fullResetDays: 90, buildRate: "slow"),
            halfLifeMinutes: 5760
        ),

        Substance(
            name: "Paroxetine",
            aliases: ["Paxil"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60, fatal: 5000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Reduced anxiety", "Sexual dysfunction", "Drowsiness", "Weight gain", "Dry mouth", "Nausea", "Emotional blunting"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Emotional Blunting", description: "A pronounced flattening of emotional responses often described as feeling 'zombified' or emotionally detached."),
                SubjectiveEffect(name: "Anxiolysis", description: "A strong reduction in anxiety and panic symptoms that develops over several weeks, often considered one of the most potent SSRIs for anxiety."),
                SubjectiveEffect(name: "Sedation", description: "A persistent drowsiness and heaviness that can make it difficult to stay alert, especially in the early weeks."),
                SubjectiveEffect(name: "Sexual Dysfunction", description: "Significant difficulty with arousal, orgasm, and libido, often more pronounced than with other SSRIs."),
                SubjectiveEffect(name: "Weight Gain", description: "A gradual increase in appetite and body weight that can become noticeable within the first few months."),
                SubjectiveEffect(name: "Discontinuation Syndrome", description: "Severe withdrawal effects including brain zaps, dizziness, irritability, and flu-like symptoms if stopped abruptly, even after short tapers."),
                SubjectiveEffect(name: "Dry Mouth", description: "A persistent cottony dryness in the mouth that can make speaking and swallowing uncomfortable."),
                SubjectiveEffect(name: "Cognitive Fog", description: "A subtle difficulty with word-finding and short-term memory that some patients report during treatment."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 60, buildRate: "slow"),
            halfLifeMinutes: 1260
        ),

        Substance(
            name: "Citalopram",
            aliases: ["Celexa"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60, fatal: 3000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Reduced anxiety", "Nausea", "Sexual dysfunction", "Drowsiness", "Dry mouth", "Increased sweating", "Emotional blunting"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Emotional Blunting", description: "A flattening of emotional range where feelings of joy and sadness are both dampened, leaving a neutral baseline."),
                SubjectiveEffect(name: "Anxiolysis", description: "A calming effect on generalized worry and social anxiety that builds gradually over 2-4 weeks."),
                SubjectiveEffect(name: "Drowsiness", description: "A persistent sleepiness and lethargy that can interfere with daily functioning, particularly in the first weeks."),
                SubjectiveEffect(name: "Sexual Dysfunction", description: "Reduced libido and difficulty reaching orgasm that often develops within the first month."),
                SubjectiveEffect(name: "Increased Sweating", description: "Unexplained episodes of perspiration, including night sweats, unrelated to physical exertion or temperature."),
                SubjectiveEffect(name: "Mood Stabilization", description: "A gradual evening-out of mood swings, making emotional reactions feel more proportional to situations."),
                SubjectiveEffect(name: "Yawning", description: "Frequent, involuntary yawning throughout the day that is unrelated to tiredness."),
                SubjectiveEffect(name: "GI Disturbance", description: "Mild nausea and stomach discomfort that typically peaks in the first week and resolves within two weeks."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 60, buildRate: "slow"),
            halfLifeMinutes: 2100
        ),

        Substance(
            name: "Escitalopram",
            aliases: ["Lexapro", "Cipralex"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...20, strong: 20...30, heavy: 30, fatal: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Reduced anxiety", "Nausea", "Sexual dysfunction", "Insomnia", "Drowsiness", "Dry mouth", "Fatigue"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Emotional Blunting", description: "A subtle muting of emotional extremes that can feel like a protective buffer against overwhelming feelings."),
                SubjectiveEffect(name: "Anxiolysis", description: "A gentle but steady reduction in anxiety and rumination that is often considered the cleanest SSRI anxiolytic effect."),
                SubjectiveEffect(name: "Mood Lift", description: "A gradual brightening of outlook and reduction in depressive thoughts noticed over 2-6 weeks."),
                SubjectiveEffect(name: "Sexual Dysfunction", description: "Decreased libido or difficulty achieving orgasm that tends to persist throughout treatment."),
                SubjectiveEffect(name: "Fatigue", description: "A low-grade tiredness or lack of physical energy that may persist even after initial adjustment."),
                SubjectiveEffect(name: "Initial Nausea", description: "Stomach queasiness in the first 1-2 weeks that usually resolves as the body adjusts."),
                SubjectiveEffect(name: "Vivid Dreams", description: "Unusually detailed, memorable, or strange dreams that may occur throughout treatment."),
                SubjectiveEffect(name: "Cognitive Clarity", description: "A clearing of the depressive mental fog, allowing for more organized and less ruminative thinking."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 60, buildRate: "slow"),
            halfLifeMinutes: 1770
        ),

        Substance(
            name: "Fluvoxamine",
            aliases: ["Luvox"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 12.5, light: 25...50, common: 50...150, strong: 150...300, heavy: 300, fatal: 5000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Reduced anxiety", "Mood improvement", "Nausea", "Drowsiness", "Insomnia", "Sexual dysfunction", "Dizziness", "Dry mouth"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Anxiolysis", description: "A pronounced reduction in obsessive and anxious thought patterns, particularly effective for OCD-spectrum anxiety."),
                SubjectiveEffect(name: "Sedation", description: "A calming drowsiness that can be noticeable throughout the day, sometimes requiring dose timing adjustments."),
                SubjectiveEffect(name: "Emotional Blunting", description: "A reduction in emotional reactivity that can feel like a layer of insulation between oneself and stressful events."),
                SubjectiveEffect(name: "GI Disturbance", description: "Nausea and stomach discomfort that tend to be more pronounced than with other SSRIs, especially during initiation."),
                SubjectiveEffect(name: "Sexual Dysfunction", description: "Reduced sexual desire and delayed orgasm that may develop gradually over the first month."),
                SubjectiveEffect(name: "Dizziness", description: "Occasional lightheadedness or unsteadiness, particularly when standing up quickly."),
                SubjectiveEffect(name: "Vivid Dreams", description: "Intense, often bizarre dreams that can feel hyper-real and are frequently reported with this medication."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 60, buildRate: "slow"),
            halfLifeMinutes: 960
        ),

        // MARK: - SNRIs

        Substance(
            name: "Venlafaxine",
            aliases: ["Effexor"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 18.75, light: 37.5...75, common: 75...150, strong: 150...225, heavy: 225, fatal: 5000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Reduced anxiety", "Nausea", "Increased sweating", "Sexual dysfunction", "Dizziness", "Insomnia", "Elevated blood pressure"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mood Lift", description: "A gradual elevation of baseline mood and renewed interest in life that typically emerges after 2-4 weeks."),
                SubjectiveEffect(name: "Anxiolysis", description: "A notable reduction in generalized anxiety and panic symptoms, often felt as a lessening of chest tightness and racing thoughts."),
                SubjectiveEffect(name: "Increased Sweating", description: "Excessive perspiration, particularly night sweats, that can persist throughout treatment."),
                SubjectiveEffect(name: "Discontinuation Syndrome", description: "Severe withdrawal symptoms including brain zaps, vertigo, irritability, and nausea if doses are missed or the drug is tapered too quickly."),
                SubjectiveEffect(name: "Sexual Dysfunction", description: "Difficulty with arousal, delayed ejaculation, or reduced libido that commonly persists during treatment."),
                SubjectiveEffect(name: "Initial Nausea", description: "Significant stomach queasiness in the first 1-2 weeks that can be intense but usually subsides."),
                SubjectiveEffect(name: "Elevated Energy", description: "A noticeable increase in physical and mental energy at higher doses due to norepinephrine activity."),
                SubjectiveEffect(name: "Blood Pressure Awareness", description: "Some patients report feeling their heartbeat more intensely or noticing subtle increases in blood pressure."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 60, buildRate: "slow"),
            halfLifeMinutes: 300
        ),

        Substance(
            name: "Duloxetine",
            aliases: ["Cymbalta"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 20...30, common: 30...60, strong: 60...120, heavy: 120, fatal: 5000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Pain relief", "Reduced anxiety", "Nausea", "Dry mouth", "Drowsiness", "Sexual dysfunction", "Constipation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Pain Reduction", description: "A gradual dulling of chronic pain signals, particularly neuropathic and musculoskeletal pain, noticeable over several weeks."),
                SubjectiveEffect(name: "Mood Stabilization", description: "A steady lifting of depressive mood that develops over 2-4 weeks, with reduced crying spells and hopelessness."),
                SubjectiveEffect(name: "Anxiolysis", description: "A calming of generalized anxiety and worry that builds alongside the antidepressant effect."),
                SubjectiveEffect(name: "Dry Mouth", description: "A persistent cottony dryness that can make speaking uncomfortable and increase thirst."),
                SubjectiveEffect(name: "Initial Nausea", description: "Stomach upset and queasiness in the first 1-2 weeks that typically resolves with continued use."),
                SubjectiveEffect(name: "Drowsiness", description: "A heavy, sedated feeling that can be most prominent in the first few weeks of treatment."),
                SubjectiveEffect(name: "Sexual Dysfunction", description: "Reduced libido and difficulty with orgasm that often develops within the first month of use."),
                SubjectiveEffect(name: "Constipation", description: "Slowed bowel movements and difficulty passing stool that may require dietary adjustments."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 60, buildRate: "slow"),
            halfLifeMinutes: 720
        ),

        Substance(
            name: "Desvenlafaxine",
            aliases: ["Pristiq"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 12.5, light: 25...50, common: 50...100, strong: 100...200, heavy: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Reduced anxiety", "Nausea", "Dizziness", "Increased sweating", "Sexual dysfunction", "Insomnia", "Constipation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mood Lift", description: "A steady improvement in depressive symptoms that tends to emerge over 2-4 weeks of consistent dosing."),
                SubjectiveEffect(name: "Anxiolysis", description: "A reduction in baseline anxiety and tension, similar to venlafaxine but with potentially fewer discontinuation issues."),
                SubjectiveEffect(name: "Increased Sweating", description: "Noticeable perspiration, especially night sweats, that can persist throughout treatment."),
                SubjectiveEffect(name: "Dizziness", description: "Lightheadedness and occasional vertigo, particularly when changing positions or during dose adjustments."),
                SubjectiveEffect(name: "Sexual Dysfunction", description: "Diminished libido and difficulty achieving orgasm that commonly accompanies SNRI treatment."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty falling asleep or frequent nighttime awakenings that may require dosing in the morning."),
                SubjectiveEffect(name: "GI Disturbance", description: "Nausea and constipation that tend to be most prominent during the first few weeks."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 60, buildRate: "slow"),
            halfLifeMinutes: 660
        ),

        Substance(
            name: "Levomilnacipran",
            aliases: ["Fetzima"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 20...40, common: 40...80, strong: 80...120, heavy: 120
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Increased motivation", "Nausea", "Increased sweating", "Elevated heart rate", "Sexual dysfunction", "Constipation", "Urinary hesitancy"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Increased Motivation", description: "A noticeable boost in drive and initiative attributed to stronger norepinephrine activity compared to other SNRIs."),
                SubjectiveEffect(name: "Mood Lift", description: "A gradual improvement in mood and reduction in depressive thinking over several weeks."),
                SubjectiveEffect(name: "Physical Activation", description: "A feeling of increased physical energy and readiness to engage in activities."),
                SubjectiveEffect(name: "Elevated Heart Rate", description: "A noticeable increase in resting heart rate that some patients feel as palpitations or heart awareness."),
                SubjectiveEffect(name: "Increased Sweating", description: "Excessive perspiration during both rest and activity that can be socially uncomfortable."),
                SubjectiveEffect(name: "Urinary Hesitancy", description: "Difficulty initiating urination or a sensation of incomplete bladder emptying."),
                SubjectiveEffect(name: "GI Disturbance", description: "Nausea and constipation that are common in the first weeks and may partially persist."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 60, buildRate: "slow"),
            halfLifeMinutes: 720
        ),

        Substance(
            name: "Milnacipran",
            aliases: ["Savella"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 12.5, light: 25...50, common: 50...100, strong: 100...200, heavy: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Pain relief", "Nausea", "Increased sweating", "Elevated heart rate", "Headache", "Constipation", "Dizziness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Pain Reduction", description: "A gradual dulling of fibromyalgia and chronic pain that becomes noticeable over weeks of consistent use."),
                SubjectiveEffect(name: "Mood Stabilization", description: "A steady leveling of mood with reduced depressive episodes over 2-4 weeks."),
                SubjectiveEffect(name: "Physical Activation", description: "An increase in physical energy and reduced fatigue attributed to norepinephrine reuptake inhibition."),
                SubjectiveEffect(name: "Elevated Heart Rate", description: "An awareness of faster or stronger heartbeat, particularly during the initial dose titration."),
                SubjectiveEffect(name: "Increased Sweating", description: "Unexplained perspiration episodes that can be persistent and uncomfortable."),
                SubjectiveEffect(name: "Headache", description: "A dull, persistent headache that is common in the first weeks and usually diminishes with time."),
                SubjectiveEffect(name: "GI Disturbance", description: "Nausea and constipation that tend to peak early in treatment and gradually improve."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 60, buildRate: "slow"),
            halfLifeMinutes: 420
        ),

        // MARK: - Other Antidepressants

        Substance(
            name: "Bupropion",
            aliases: ["Wellbutrin", "Zyban"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 37.5, light: 75...150, common: 150...300, strong: 300...450, heavy: 450, fatal: 5000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 360, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1080)
                )),
            ],
            effects: ["Mood improvement", "Increased motivation", "Increased energy", "Appetite suppression", "Insomnia", "Dry mouth", "Reduced smoking cravings", "Anxiety"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Increased Energy", description: "A noticeable boost in physical and mental energy that can feel mildly stimulating, distinct from other antidepressants."),
                SubjectiveEffect(name: "Increased Motivation", description: "A renewed sense of drive and initiative that makes it easier to start and complete tasks."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A marked reduction in appetite and food cravings that often leads to weight loss."),
                SubjectiveEffect(name: "Anxiogenic Effect", description: "A paradoxical increase in anxiety or jitteriness that some patients experience, particularly at higher doses."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty falling or staying asleep, often requiring morning dosing to minimize sleep disruption."),
                SubjectiveEffect(name: "Cognitive Enhancement", description: "Improved concentration and mental clarity that patients describe as the depressive 'brain fog' lifting."),
                SubjectiveEffect(name: "Dry Mouth", description: "A persistent dryness in the mouth that develops early and may persist throughout treatment."),
                SubjectiveEffect(name: "Reduced Nicotine Cravings", description: "A diminished urge to smoke and reduced satisfaction from cigarettes, often noticeable within the first week."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 60, buildRate: "slow"),
            halfLifeMinutes: 1260
        ),

        Substance(
            name: "Mirtazapine",
            aliases: ["Remeron"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 3.75, light: 7.5...15, common: 15...30, strong: 30...45, heavy: 45, fatal: 5000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 360, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1080)
                )),
            ],
            effects: ["Mood improvement", "Drowsiness", "Increased appetite", "Weight gain", "Reduced anxiety", "Dry mouth", "Vivid dreams", "Sedation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Deep Sedation", description: "An intense drowsiness and heaviness that makes falling asleep easy, often felt within an hour of dosing."),
                SubjectiveEffect(name: "Increased Appetite", description: "A strong, sometimes insatiable craving for food, particularly carbohydrates and sweets, that develops rapidly."),
                SubjectiveEffect(name: "Weight Gain", description: "A steady increase in body weight driven by appetite stimulation and metabolic changes."),
                SubjectiveEffect(name: "Anxiolysis", description: "A significant calming of anxiety and worry that can feel warm and comforting, developing over weeks."),
                SubjectiveEffect(name: "Vivid Dreams", description: "Extremely detailed, colorful, and sometimes bizarre dreams that are commonly reported from the first night."),
                SubjectiveEffect(name: "Mood Improvement", description: "A gradual lifting of depressive mood over several weeks, with increased emotional resilience."),
                SubjectiveEffect(name: "Morning Grogginess", description: "A hangover-like drowsiness upon waking that can persist for hours, especially at higher doses."),
                SubjectiveEffect(name: "Dry Mouth", description: "A persistent oral dryness that can be particularly noticeable at night and upon waking."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 10, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 1500
        ),

        Substance(
            name: "Trazodone",
            aliases: ["Desyrel"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 12.5, light: 25...50, common: 50...150, strong: 150...300, heavy: 300, fatal: 10000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 540)
                )),
            ],
            effects: ["Drowsiness", "Sedation", "Mood improvement", "Reduced anxiety", "Dry mouth", "Dizziness", "Headache", "Blurred vision"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Sedation", description: "A heavy, sleepy feeling that comes on within 30-60 minutes, making it effective as a sleep aid even at sub-antidepressant doses."),
                SubjectiveEffect(name: "Anxiolysis", description: "A soothing reduction in anxiety and nervous tension, often noticeable even at low doses used for sleep."),
                SubjectiveEffect(name: "Sleep Induction", description: "A powerful urge to sleep that develops rapidly after dosing, frequently used specifically for insomnia."),
                SubjectiveEffect(name: "Morning Grogginess", description: "A lingering drowsiness and mental fog upon waking that can persist for hours, especially at higher doses."),
                SubjectiveEffect(name: "Dizziness", description: "Lightheadedness and unsteadiness, particularly when getting up from lying or sitting positions."),
                SubjectiveEffect(name: "Mood Improvement", description: "At antidepressant doses, a gradual lifting of depressive mood over 2-4 weeks."),
                SubjectiveEffect(name: "Dry Mouth", description: "A dry, parched feeling in the mouth that develops early in treatment."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 10, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 420
        ),

        Substance(
            name: "Nefazodone",
            aliases: [],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...300, strong: 300...600, heavy: 600
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 600)
                )),
            ],
            effects: ["Mood improvement", "Reduced anxiety", "Drowsiness", "Dry mouth", "Nausea", "Dizziness", "Blurred vision", "Lightheadedness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Anxiolysis", description: "A significant reduction in anxiety and tension without the heavy sedation associated with benzodiazepines."),
                SubjectiveEffect(name: "Mood Improvement", description: "A gradual but noticeable improvement in depressive mood over several weeks of treatment."),
                SubjectiveEffect(name: "Improved Sleep Quality", description: "Better sleep architecture with more restorative sleep, partly due to serotonin receptor modulation."),
                SubjectiveEffect(name: "Drowsiness", description: "A calming sleepiness that can be beneficial at night but may interfere with daytime functioning."),
                SubjectiveEffect(name: "Dizziness", description: "Lightheadedness and occasional unsteadiness, especially when standing up or changing positions."),
                SubjectiveEffect(name: "Blurred Vision", description: "A subtle difficulty focusing the eyes that can occur intermittently during treatment."),
                SubjectiveEffect(name: "Minimal Sexual Dysfunction", description: "Notably less sexual side effects compared to SSRIs, which patients often find a significant relief."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 60, buildRate: "slow"),
            halfLifeMinutes: 180
        ),

        Substance(
            name: "Vilazodone",
            aliases: ["Viibryd"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Reduced anxiety", "Nausea", "Diarrhea", "Dizziness", "Insomnia", "Dry mouth", "Sexual dysfunction"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Anxiolysis", description: "A reduction in anxiety that builds over weeks, combining SSRI and 5-HT1A partial agonist mechanisms."),
                SubjectiveEffect(name: "Mood Lift", description: "A gradual improvement in mood with less emotional blunting than traditional SSRIs."),
                SubjectiveEffect(name: "GI Disturbance", description: "Diarrhea and nausea that can be significant in the first weeks, more prominent than with many SSRIs."),
                SubjectiveEffect(name: "Reduced Sexual Dysfunction", description: "Less sexual side effects than typical SSRIs, which patients often find notable and welcome."),
                SubjectiveEffect(name: "Initial Insomnia", description: "Difficulty sleeping in the first weeks that usually resolves as the body adjusts to the medication."),
                SubjectiveEffect(name: "Dizziness", description: "Occasional lightheadedness, particularly during dose changes and in the early days of treatment."),
                SubjectiveEffect(name: "Emotional Reconnection", description: "A sense of re-engaging with emotions and life rather than feeling numbed or detached."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 60, buildRate: "slow"),
            halfLifeMinutes: 1500
        ),

        Substance(
            name: "Vortioxetine",
            aliases: ["Trintellix"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...20, strong: 20...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Improved cognition", "Reduced anxiety", "Nausea", "Dizziness", "Sexual dysfunction", "Constipation", "Headache"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Cognitive Enhancement", description: "An improvement in concentration, memory, and mental processing speed that distinguishes this medication from other antidepressants."),
                SubjectiveEffect(name: "Mood Lift", description: "A gradual brightening of mood with a sense of emotional re-engagement that develops over weeks."),
                SubjectiveEffect(name: "Anxiolysis", description: "A reduction in generalized anxiety and worry that builds alongside the antidepressant effect."),
                SubjectiveEffect(name: "Initial Nausea", description: "Dose-dependent nausea that is often the most troublesome side effect, typically worst at higher doses."),
                SubjectiveEffect(name: "Reduced Emotional Blunting", description: "A notable preservation of emotional range compared to SSRIs, with patients reporting they still feel like themselves."),
                SubjectiveEffect(name: "Sexual Function Preservation", description: "Less impairment of sexual function than typical SSRIs, though some dysfunction may still occur."),
                SubjectiveEffect(name: "Headache", description: "A mild to moderate headache that is common in the first weeks and usually subsides."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 60, buildRate: "slow"),
            halfLifeMinutes: 3960
        ),

        Substance(
            name: "Agomelatine",
            aliases: ["Valdoxan"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 6.25, light: 12.5...25, common: 25...50, strong: 50...75, heavy: 75
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 420)
                )),
            ],
            effects: ["Mood improvement", "Improved sleep quality", "Reduced anxiety", "Nausea", "Dizziness", "Headache", "Drowsiness", "Fatigue"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Improved Sleep Quality", description: "A normalization of circadian rhythm and sleep architecture, with easier sleep onset and more restorative rest."),
                SubjectiveEffect(name: "Mood Lift", description: "A gradual improvement in depressive mood that develops alongside improved sleep patterns."),
                SubjectiveEffect(name: "Anxiolysis", description: "A calming of anxiety symptoms that emerges over several weeks of treatment."),
                SubjectiveEffect(name: "Minimal Sexual Side Effects", description: "Very low incidence of sexual dysfunction compared to SSRIs, often a key reason for prescribing."),
                SubjectiveEffect(name: "Minimal Emotional Blunting", description: "Preservation of emotional range and feeling that is often noted as a significant advantage over SSRIs."),
                SubjectiveEffect(name: "Drowsiness", description: "A mild sleepiness that can be leveraged by taking the medication at bedtime."),
                SubjectiveEffect(name: "Headache", description: "A dull headache that can occur in the early days of treatment and usually resolves."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 60, buildRate: "slow"),
            halfLifeMinutes: 90
        ),

        // MARK: - TCAs

        Substance(
            name: "Amitriptyline",
            aliases: ["Elavil"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 25...50, common: 50...150, strong: 150...300, heavy: 300, fatal: 750
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Sedation", "Drowsiness", "Dry mouth", "Weight gain", "Constipation", "Blurred vision", "Urinary retention"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Heavy Sedation", description: "A deep, enveloping drowsiness that can make staying awake difficult, especially in the first weeks of treatment."),
                SubjectiveEffect(name: "Mood Lift", description: "A gradual lifting of depressive mood over 2-4 weeks, often accompanied by improved sleep quality."),
                SubjectiveEffect(name: "Pain Reduction", description: "A dulling of chronic pain, particularly nerve pain and migraine frequency, that develops over weeks."),
                SubjectiveEffect(name: "Dry Mouth", description: "A pronounced, persistent oral dryness that is one of the most consistently reported anticholinergic side effects."),
                SubjectiveEffect(name: "Weight Gain", description: "A noticeable increase in appetite and body weight that can be substantial over months of treatment."),
                SubjectiveEffect(name: "Cognitive Slowing", description: "A feeling of mental sluggishness and difficulty concentrating, often described as thinking through fog."),
                SubjectiveEffect(name: "Constipation", description: "Significant slowing of bowel movements due to anticholinergic effects, often requiring management."),
                SubjectiveEffect(name: "Blurred Vision", description: "Difficulty focusing the eyes, particularly on close objects, due to anticholinergic effects on the pupils."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 60, buildRate: "slow"),
            halfLifeMinutes: 1500
        ),

        Substance(
            name: "Nortriptyline",
            aliases: ["Pamelor"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 25...50, common: 50...100, strong: 100...150, heavy: 150, fatal: 750
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Drowsiness", "Dry mouth", "Constipation", "Weight gain", "Blurred vision", "Dizziness", "Urinary retention"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mood Stabilization", description: "A steady improvement in depressive mood with less sedation than other TCAs, making it better tolerated during the day."),
                SubjectiveEffect(name: "Pain Reduction", description: "Effective dulling of neuropathic pain and headaches that develops over weeks."),
                SubjectiveEffect(name: "Dry Mouth", description: "A persistent dryness in the mouth that is common but often less severe than with amitriptyline."),
                SubjectiveEffect(name: "Constipation", description: "Slowed bowel function due to anticholinergic effects that may require dietary adjustments."),
                SubjectiveEffect(name: "Drowsiness", description: "Mild to moderate sleepiness that tends to be less intense than with more sedating TCAs."),
                SubjectiveEffect(name: "Weight Gain", description: "A gradual increase in body weight, though typically less than with amitriptyline."),
                SubjectiveEffect(name: "Dizziness", description: "Lightheadedness, particularly when standing up quickly, due to orthostatic blood pressure changes."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 60, buildRate: "slow"),
            halfLifeMinutes: 1860
        ),

        Substance(
            name: "Imipramine",
            aliases: ["Tofranil"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 25...75, common: 75...150, strong: 150...300, heavy: 300, fatal: 750
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Sedation", "Dry mouth", "Constipation", "Blurred vision", "Weight gain", "Urinary retention", "Dizziness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mood Lift", description: "A gradual lifting of depressive mood over several weeks, considered one of the classic antidepressant responses."),
                SubjectiveEffect(name: "Sedation", description: "A heavy drowsiness and desire to sleep that can be helpful for depressive insomnia but impairing during the day."),
                SubjectiveEffect(name: "Anxiolysis", description: "A reduction in panic symptoms and anxiety that has historically made this a key treatment for panic disorder."),
                SubjectiveEffect(name: "Dry Mouth", description: "A very prominent oral dryness that is one of the most commonly reported side effects."),
                SubjectiveEffect(name: "Constipation", description: "Significant slowing of bowel movements that often requires proactive management."),
                SubjectiveEffect(name: "Blurred Vision", description: "Difficulty with near-focus vision due to anticholinergic effects on the pupil."),
                SubjectiveEffect(name: "Urinary Retention", description: "A sensation of difficulty initiating urination or feeling that the bladder does not fully empty."),
                SubjectiveEffect(name: "Weight Gain", description: "An increase in appetite and body weight that can become significant over months."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 60, buildRate: "slow"),
            halfLifeMinutes: 900
        ),

        Substance(
            name: "Desipramine",
            aliases: ["Norpramin"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 25...75, common: 75...150, strong: 150...300, heavy: 300, fatal: 750
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Increased energy", "Dry mouth", "Constipation", "Insomnia", "Dizziness", "Blurred vision", "Increased sweating"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Increased Energy", description: "A notably activating effect compared to other TCAs, with less sedation and more mental alertness."),
                SubjectiveEffect(name: "Mood Lift", description: "An improvement in depressive mood with a quality of increased drive and engagement."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty sleeping due to the stimulating noradrenergic effects, often requiring morning dosing."),
                SubjectiveEffect(name: "Dry Mouth", description: "A persistent oral dryness that is common with all TCAs but may be more tolerable with this one."),
                SubjectiveEffect(name: "Increased Sweating", description: "Excessive perspiration that can be embarrassing and persist throughout treatment."),
                SubjectiveEffect(name: "Constipation", description: "Slowed bowel function that develops early in treatment and requires management."),
                SubjectiveEffect(name: "Cognitive Activation", description: "A mild sharpening of focus and mental energy that distinguishes it from more sedating TCAs."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 60, buildRate: "slow"),
            halfLifeMinutes: 1260
        ),

        Substance(
            name: "Clomipramine",
            aliases: ["Anafranil"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 25...75, common: 75...150, strong: 150...250, heavy: 250, fatal: 750
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Reduced obsessive thoughts", "Sedation", "Dry mouth", "Sexual dysfunction", "Constipation", "Weight gain", "Drowsiness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Reduced Obsessive Thoughts", description: "A significant quieting of intrusive, repetitive thoughts and compulsive urges that develops over several weeks."),
                SubjectiveEffect(name: "Mood Improvement", description: "A gradual lifting of depressive mood alongside the anti-obsessional effects."),
                SubjectiveEffect(name: "Sedation", description: "A pronounced drowsiness and heaviness, particularly during the initial weeks of treatment."),
                SubjectiveEffect(name: "Sexual Dysfunction", description: "Significant difficulty with arousal and orgasm, often more pronounced than with other TCAs due to strong serotonergic effects."),
                SubjectiveEffect(name: "Dry Mouth", description: "Persistent oral dryness that is among the most common anticholinergic side effects."),
                SubjectiveEffect(name: "Weight Gain", description: "A gradual increase in body weight driven by increased appetite and metabolic changes."),
                SubjectiveEffect(name: "Constipation", description: "Significant slowing of bowel function due to anticholinergic effects."),
                SubjectiveEffect(name: "Emotional Relief", description: "A sense of release from the constant pressure of obsessive-compulsive symptoms that can feel profoundly liberating."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 60, buildRate: "slow"),
            halfLifeMinutes: 1920
        ),

        Substance(
            name: "Doxepin",
            aliases: ["Sinequan"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 25...75, common: 75...150, strong: 150...300, heavy: 300, fatal: 750
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Sedation", "Drowsiness", "Dry mouth", "Weight gain", "Blurred vision", "Constipation", "Dizziness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Deep Sedation", description: "An intense drowsiness that makes this medication highly effective for sleep but challenging for daytime alertness."),
                SubjectiveEffect(name: "Anxiolysis", description: "A strong calming effect on anxiety and agitation that develops alongside sedation."),
                SubjectiveEffect(name: "Mood Improvement", description: "A gradual lifting of depressive symptoms over several weeks of consistent use."),
                SubjectiveEffect(name: "Antihistaminic Sedation", description: "A heavy, sleepy feeling driven by potent antihistamine effects that are pronounced even at low doses."),
                SubjectiveEffect(name: "Dry Mouth", description: "Significant oral dryness that is among the most common side effects."),
                SubjectiveEffect(name: "Weight Gain", description: "Increased appetite and body weight, often significant due to strong antihistamine activity."),
                SubjectiveEffect(name: "Blurred Vision", description: "Difficulty focusing, especially on close objects, due to anticholinergic effects."),
                SubjectiveEffect(name: "Itch Relief", description: "A notable anti-itch effect due to potent antihistamine properties, sometimes prescribed specifically for pruritus."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 60, buildRate: "slow"),
            halfLifeMinutes: 1020
        ),

        Substance(
            name: "Trimipramine",
            aliases: ["Surmontil"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 12.5, light: 25...75, common: 75...150, strong: 150...300, heavy: 300, fatal: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Sedation", "Drowsiness", "Dry mouth", "Weight gain", "Constipation", "Blurred vision", "Dizziness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Sedation", description: "A deep, calming drowsiness that develops quickly after dosing and can persist throughout the day."),
                SubjectiveEffect(name: "Mood Improvement", description: "A gradual lifting of depressive mood over several weeks, with improved emotional stability."),
                SubjectiveEffect(name: "Improved Sleep", description: "An enhancement of sleep quality and duration due to strong sedating properties."),
                SubjectiveEffect(name: "Dry Mouth", description: "Persistent oral dryness driven by anticholinergic activity."),
                SubjectiveEffect(name: "Weight Gain", description: "A notable increase in appetite and body weight over the course of treatment."),
                SubjectiveEffect(name: "Cognitive Dulling", description: "A slowing of mental processing and difficulty with concentration that can accompany the sedating effects."),
                SubjectiveEffect(name: "Constipation", description: "Reduced bowel motility from anticholinergic effects, often requiring proactive management."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 60, buildRate: "slow"),
            halfLifeMinutes: 900
        ),

        Substance(
            name: "Protriptyline",
            aliases: ["Vivactil"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Increased energy", "Dry mouth", "Constipation", "Insomnia", "Blurred vision", "Increased sweating", "Anxiety"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Increased Energy", description: "A stimulating, activating quality that sets it apart from other TCAs, with less sedation and more daytime alertness."),
                SubjectiveEffect(name: "Mood Lift", description: "A gradual improvement in depressive mood with a focus on energy and motivation."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty sleeping due to the activating nature of this medication, often requiring morning dosing."),
                SubjectiveEffect(name: "Increased Sweating", description: "Excessive perspiration that can be persistent and uncomfortable."),
                SubjectiveEffect(name: "Dry Mouth", description: "A persistent dryness in the mouth from anticholinergic activity."),
                SubjectiveEffect(name: "Anxiogenic Effect", description: "A paradoxical increase in anxiety or nervousness in some patients due to the activating profile."),
                SubjectiveEffect(name: "Constipation", description: "Slowed bowel function from anticholinergic effects."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 60, buildRate: "slow"),
            halfLifeMinutes: 4740
        ),

        Substance(
            name: "Maprotiline",
            aliases: ["Ludiomil"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 12.5, light: 25...75, common: 75...150, strong: 150...225, heavy: 225, fatal: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Sedation", "Drowsiness", "Dry mouth", "Constipation", "Blurred vision", "Dizziness", "Weight gain"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Sedation", description: "A pronounced drowsiness and heaviness similar to other TCAs, often helpful for sleep-disrupted depression."),
                SubjectiveEffect(name: "Mood Lift", description: "A gradual improvement in depressive mood over several weeks of consistent use."),
                SubjectiveEffect(name: "Anxiolysis", description: "A calming of anxiety symptoms that accompanies the sedating and mood-stabilizing effects."),
                SubjectiveEffect(name: "Dry Mouth", description: "Persistent oral dryness from anticholinergic effects."),
                SubjectiveEffect(name: "Weight Gain", description: "A significant increase in appetite and body weight driven by antihistamine and anticholinergic activity."),
                SubjectiveEffect(name: "Constipation", description: "Reduced bowel motility requiring proactive dietary and hydration management."),
                SubjectiveEffect(name: "Dizziness", description: "Lightheadedness and unsteadiness, particularly upon standing, due to orthostatic blood pressure changes."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 60, buildRate: "slow"),
            halfLifeMinutes: 3060
        ),

        // MARK: - MAOIs

        Substance(
            name: "Phenelzine",
            aliases: ["Nardil"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 7.5, light: 15...30, common: 30...60, strong: 60...90, heavy: 90, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 960),
                    afterglow: nil,
                    total: TimeRange(min: 960, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Reduced anxiety", "Insomnia", "Dizziness", "Weight gain", "Sexual dysfunction", "Dry mouth", "Drowsiness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mood Lift", description: "A robust improvement in depressive mood that can be dramatic in treatment-resistant cases, often described as a return of emotional vitality."),
                SubjectiveEffect(name: "Anxiolysis", description: "A profound reduction in anxiety, particularly social anxiety and panic, that is often considered superior to SSRIs."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty sleeping that can be persistent and may require sleep hygiene adjustments or adjunctive treatment."),
                SubjectiveEffect(name: "Weight Gain", description: "A significant increase in appetite and body weight that is common with long-term use."),
                SubjectiveEffect(name: "Orthostatic Dizziness", description: "Lightheadedness when standing up quickly due to drops in blood pressure, a hallmark side effect."),
                SubjectiveEffect(name: "Dietary Vigilance", description: "A constant awareness of tyramine-containing foods that must be avoided to prevent dangerous blood pressure spikes."),
                SubjectiveEffect(name: "Sexual Dysfunction", description: "Difficulty with arousal and orgasm that can persist throughout treatment."),
                SubjectiveEffect(name: "Emotional Reconnection", description: "A sense of regaining emotional depth and the ability to feel pleasure, often after years of failed treatments."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 42, buildRate: "slow"),
            halfLifeMinutes: 690
        ),

        Substance(
            name: "Tranylcypromine",
            aliases: ["Parnate"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60, fatal: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 960),
                    afterglow: nil,
                    total: TimeRange(min: 960, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Increased energy", "Reduced anxiety", "Insomnia", "Dizziness", "Dry mouth", "Sexual dysfunction", "Lightheadedness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Increased Energy", description: "A stimulating, amphetamine-like quality that provides increased alertness and drive, unique among antidepressants."),
                SubjectiveEffect(name: "Mood Lift", description: "A potent antidepressant effect that can feel like a fog has been lifted, often effective where others have failed."),
                SubjectiveEffect(name: "Anxiolysis", description: "A significant reduction in social anxiety and panic symptoms that develops over several weeks."),
                SubjectiveEffect(name: "Insomnia", description: "Marked difficulty sleeping due to the stimulating nature, often requiring afternoon dosing cutoffs."),
                SubjectiveEffect(name: "Orthostatic Dizziness", description: "Pronounced lightheadedness upon standing that is among the most common side effects."),
                SubjectiveEffect(name: "Dietary Vigilance", description: "Necessary avoidance of tyramine-rich foods to prevent potentially dangerous hypertensive reactions."),
                SubjectiveEffect(name: "Sexual Dysfunction", description: "Difficulty with arousal and orgasm that may develop during treatment."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 42, buildRate: "slow"),
            halfLifeMinutes: 150
        ),

        Substance(
            name: "Isocarboxazid",
            aliases: ["Marplan"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60, fatal: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 960),
                    afterglow: nil,
                    total: TimeRange(min: 960, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Reduced anxiety", "Dizziness", "Insomnia", "Dry mouth", "Weight gain", "Drowsiness", "Nausea"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mood Improvement", description: "A gradual lifting of depressive symptoms similar to other MAOIs, often effective in atypical depression."),
                SubjectiveEffect(name: "Anxiolysis", description: "A reduction in anxiety and panic symptoms that develops over several weeks."),
                SubjectiveEffect(name: "Orthostatic Dizziness", description: "Lightheadedness upon standing that is common with irreversible MAOIs."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty with sleep that can be persistent and require adjunctive management."),
                SubjectiveEffect(name: "Weight Gain", description: "An increase in appetite and body weight over the course of treatment."),
                SubjectiveEffect(name: "Dietary Restrictions", description: "The necessity of avoiding tyramine-containing foods, creating ongoing vigilance around meals."),
                SubjectiveEffect(name: "Nausea", description: "Mild stomach upset that may occur during initiation and usually settles."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 42, buildRate: "slow"),
            halfLifeMinutes: 2160
        ),

        Substance(
            name: "Selegiline",
            aliases: ["Emsam"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1.25, light: 2.5...5, common: 5...10, strong: 10...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 960),
                    afterglow: nil,
                    total: TimeRange(min: 960, max: 1440)
                )),
                SubstanceRoute(route: .transdermal, unit: "mg/24hr", doses: DoseRange(
                    threshold: 3, light: 6...9, common: 9...12, strong: 12...18, heavy: 18
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 480, max: 960),
                    offset: TimeRange(min: 480, max: 960),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Increased energy", "Insomnia", "Dizziness", "Nausea", "Dry mouth", "Application site reaction", "Headache"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Increased Energy", description: "A mild stimulating effect with improved alertness and reduced fatigue, particularly at lower doses."),
                SubjectiveEffect(name: "Mood Lift", description: "A gradual improvement in depressive mood that builds over several weeks."),
                SubjectiveEffect(name: "Cognitive Enhancement", description: "Improved focus and mental clarity attributed to dopaminergic and noradrenergic effects at low doses."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty sleeping that can develop due to the activating properties of the medication."),
                SubjectiveEffect(name: "Reduced Dietary Restrictions", description: "At lower transdermal doses, less need for tyramine avoidance compared to traditional MAOIs."),
                SubjectiveEffect(name: "Application Site Irritation", description: "Redness, itching, or discomfort at the patch site when using the transdermal formulation."),
                SubjectiveEffect(name: "Dizziness", description: "Occasional lightheadedness, particularly during dose adjustments."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 42, buildRate: "slow"),
            halfLifeMinutes: 600
        ),

        Substance(
            name: "Moclobemide",
            aliases: ["Manerix"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...150, common: 150...300, strong: 300...600, heavy: 600
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 960),
                    afterglow: nil,
                    total: TimeRange(min: 960, max: 1440)
                )),
            ],
            effects: ["Mood improvement", "Reduced anxiety", "Insomnia", "Nausea", "Dizziness", "Dry mouth", "Headache", "Restlessness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mood Improvement", description: "A gentle lifting of depressive mood with fewer side effects than irreversible MAOIs due to reversible enzyme inhibition."),
                SubjectiveEffect(name: "Anxiolysis", description: "A reduction in anxiety symptoms, particularly social anxiety, that develops over weeks."),
                SubjectiveEffect(name: "Increased Energy", description: "A mild boost in energy and alertness without the heavy stimulation of tranylcypromine."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty sleeping that some patients experience, particularly with evening dosing."),
                SubjectiveEffect(name: "Reduced Dietary Restrictions", description: "Significantly fewer dietary restrictions than irreversible MAOIs, though some caution with tyramine is still advised."),
                SubjectiveEffect(name: "Headache", description: "A mild headache that may occur during the first weeks of treatment."),
                SubjectiveEffect(name: "Restlessness", description: "A subtle inner agitation or inability to sit still that some patients notice."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 42, buildRate: "slow"),
            halfLifeMinutes: 90
        ),

        Substance(
            name: "Syrian Rue",
            aliases: ["Harmine", "Harmaline", "Peganum harmala"],
            category: .antidepressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "g", doses: DoseRange(
                    threshold: 0.5, light: 1...2, common: 2...3.5, strong: 3.5...5, heavy: 5
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 180),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Mood improvement", "Nausea", "Dizziness", "Sedation", "Vivid dreams", "Tremor", "Purging", "Visual distortions"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Sedation", description: "A deep, dreamy drowsiness that can feel heavy and trance-like at higher doses."),
                SubjectiveEffect(name: "Nausea and Purging", description: "Significant stomach discomfort and possible vomiting, traditionally considered part of a cleansing process."),
                SubjectiveEffect(name: "Vivid Dreams", description: "Intensely detailed, colorful, and often meaningful dreams that can feel prophetic or deeply symbolic."),
                SubjectiveEffect(name: "Visual Distortions", description: "Subtle changes in visual perception including enhanced colors and mild patterning at higher doses."),
                SubjectiveEffect(name: "Mood Improvement", description: "A lifting of mood and reduction in depressive thinking attributed to MAO inhibition and harmala alkaloids."),
                SubjectiveEffect(name: "Tremor", description: "A fine shaking or vibrating sensation in the hands and body, particularly at higher doses."),
                SubjectiveEffect(name: "Introspective State", description: "A contemplative, inward-facing mental state that can facilitate self-reflection and emotional processing."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 210
        ),
    ]
}
