import Foundation

extension SubstanceLibrary {
    static let benzodiazepines: [Substance] = [

        // MARK: - Classical Benzodiazepines

        // MARK: Alprazolam

        Substance(
            name: "Alprazolam",
            aliases: ["Xanax", "Xans", "Bars", "Planks"],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.1, light: 0.25...0.5, common: 0.5...1.5, strong: 1.5...3, heavy: 3, fatal: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 360)
                )),
                SubstanceRoute(route: .sublingual, unit: "mg", doses: DoseRange(
                    threshold: 0.1, light: 0.125...0.5, common: 0.5...1.5, strong: 1.5...3, heavy: 3
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 45, max: 90),
                    offset: TimeRange(min: 90, max: 180),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Anxiolysis", "Sedation", "Muscle relaxation", "Disinhibition", "Euphoria", "Amnesia", "Motor impairment", "Drowsiness", "Appetite enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Rapid Anxiolysis", description: "A fast-acting wave of calm that dissolves anxiety within 20-40 minutes, often described as a weight being lifted off the chest and mind."),
                SubjectiveEffect(name: "Euphoric Disinhibition", description: "A notable mood boost and lowered inhibitions that makes social situations feel effortless and carefree, more euphoric than many other benzodiazepines."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Tension in the shoulders, jaw, and back melts away, leaving the body feeling loose and comfortable."),
                SubjectiveEffect(name: "Memory Impairment", description: "Dose-dependent amnesia where events during the peak may be partially or completely forgotten, especially at higher doses."),
                SubjectiveEffect(name: "Sedation", description: "A calming drowsiness that deepens with dose, making sleep come easily at higher amounts."),
                SubjectiveEffect(name: "Appetite Enhancement", description: "Increased hunger and food cravings, with food tasting more appealing and satisfying than usual."),
                SubjectiveEffect(name: "Motor Impairment", description: "Reduced coordination and slowed reflexes, with a stumbling, unsteady gait at higher doses."),
                SubjectiveEffect(name: "Emotional Flattening", description: "At higher doses, an indifference to emotional stimuli where nothing feels particularly upsetting or exciting."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 672,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: Diazepam

        Substance(
            name: "Diazepam",
            aliases: ["Valium"],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2.5...5, common: 5...15, strong: 15...30, heavy: 30, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
                SubstanceRoute(route: .rectal, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2.5...5, common: 5...15, strong: 15...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 30, max: 90),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 960)
                )),
                SubstanceRoute(route: .intravenous, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...10, strong: 10...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 3),
                    comeup: TimeRange(min: 2, max: 5),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 720)
                )),
            ],
            effects: ["Anxiolysis", "Sedation", "Muscle relaxation", "Anticonvulsant", "Euphoria", "Disinhibition", "Amnesia", "Motor impairment", "Drowsiness", "Appetite enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Gradual Deep Relaxation", description: "A slow-building but long-lasting sense of calm and relaxation that develops over 30-60 minutes and persists for many hours."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Profound physical relaxation with significant reduction in muscle tension and spasm, making it effective for muscle-related pain."),
                SubjectiveEffect(name: "Warm Anxiolysis", description: "A gentle dissolution of worry and anxiety with a slightly warm, contented quality that many find more pleasant than shorter-acting benzos."),
                SubjectiveEffect(name: "Anticonvulsant Effect", description: "A stabilizing effect on neural excitability that prevents seizures and reduces the feeling of brain hyperactivity."),
                SubjectiveEffect(name: "Disinhibition", description: "Lowered social barriers and reduced self-consciousness, sometimes leading to uncharacteristically bold or impulsive behavior."),
                SubjectiveEffect(name: "Drowsiness", description: "A persistent sleepiness that can last throughout the day given diazepam's very long half-life and active metabolites."),
                SubjectiveEffect(name: "Motor Impairment", description: "Decreased coordination and balance, with movements becoming clumsy and reaction times slowing noticeably."),
                SubjectiveEffect(name: "Memory Gaps", description: "Anterograde amnesia where new memories are not properly formed, leading to gaps in recall of events during peak effects."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 30, buildRate: "moderate"),
            halfLifeMinutes: 2880,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: Clonazepam

        Substance(
            name: "Clonazepam",
            aliases: ["Klonopin", "Rivotril"],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.1, light: 0.25...0.5, common: 0.5...1, strong: 1...2, heavy: 2, fatal: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
                SubstanceRoute(route: .sublingual, unit: "mg", doses: DoseRange(
                    threshold: 0.1, light: 0.125...0.5, common: 0.5...1, strong: 1...2, heavy: 2
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 30),
                    comeup: TimeRange(min: 10, max: 25),
                    peak: TimeRange(min: 90, max: 210),
                    offset: TimeRange(min: 300, max: 660),
                    afterglow: nil,
                    total: TimeRange(min: 600, max: 1320)
                )),
            ],
            effects: ["Anxiolysis", "Sedation", "Anticonvulsant", "Muscle relaxation", "Euphoria", "Disinhibition", "Amnesia", "Motor impairment", "Drowsiness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Sustained Anxiolysis", description: "A long-lasting anxiety relief that builds slowly and persists for 8-12 hours, providing steady calm without the peaks and valleys of shorter-acting benzos."),
                SubjectiveEffect(name: "Anticonvulsant Stability", description: "A stabilizing effect on neural excitability that reduces the feeling of brain hyperactivity and prevents seizure activity."),
                SubjectiveEffect(name: "Subtle Euphoria", description: "A mild but pleasant mood elevation and sense of well-being that is present but less pronounced than alprazolam."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Significant tension relief throughout the body, with particular effectiveness for anxiety-related muscle tension."),
                SubjectiveEffect(name: "Disinhibition", description: "Reduced social anxiety and lowered inhibitions that can make social interactions feel easier and more natural."),
                SubjectiveEffect(name: "Drowsiness", description: "A calm sleepiness that develops over the long duration, sometimes persisting into the next day."),
                SubjectiveEffect(name: "Motor Impairment", description: "Reduced coordination and slowed movements that become more pronounced with higher doses."),
                SubjectiveEffect(name: "Amnesia", description: "Memory formation difficulties that are dose-dependent, with higher doses causing more significant gaps in recall."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 2280,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: Lorazepam

        Substance(
            name: "Lorazepam",
            aliases: ["Ativan"],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1, common: 1...2, strong: 2...4, heavy: 4, fatal: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 540)
                )),
                SubstanceRoute(route: .sublingual, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1, common: 1...2, strong: 2...4, heavy: 4
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 300),
                    afterglow: nil,
                    total: TimeRange(min: 300, max: 480)
                )),
                SubstanceRoute(route: .intravenous, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1, common: 1...2, strong: 2...3, heavy: 3
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 3, max: 10),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 300),
                    afterglow: nil,
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Anxiolysis", "Sedation", "Amnesia", "Muscle relaxation", "Disinhibition", "Drowsiness", "Motor impairment", "Anticonvulsant", "Emotional blunting"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Clean Anxiolysis", description: "A reliable, straightforward anxiety relief without much euphoria, often described as simply feeling normal and functional rather than high."),
                SubjectiveEffect(name: "Emotional Blunting", description: "A notable dampening of emotional reactivity where both positive and negative emotions feel muted and distant."),
                SubjectiveEffect(name: "Amnesia", description: "Significant anterograde amnesia that is more pronounced than many other benzodiazepines at equivalent anxiolytic doses."),
                SubjectiveEffect(name: "Sedation", description: "Moderate drowsiness that is reliable and predictable, making it useful for anxiety-related insomnia."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Effective physical relaxation with reduced tension, though less pronounced than diazepam."),
                SubjectiveEffect(name: "Disinhibition", description: "Mild lowering of social barriers, less euphoric than alprazolam but still noticeable."),
                SubjectiveEffect(name: "Motor Impairment", description: "Decreased coordination and reaction time, particularly problematic for driving and complex tasks."),
                SubjectiveEffect(name: "Steady State", description: "Due to its intermediate half-life and lack of active metabolites, produces a predictable, stable effect profile without accumulation."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 720,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: Midazolam

        Substance(
            name: "Midazolam",
            aliases: ["Versed"],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 5...7.5, common: 7.5...15, strong: 15...25, heavy: 25, fatal: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: nil,
                    total: TimeRange(min: 90, max: 180)
                )),
                SubstanceRoute(route: .intravenous, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 1...2.5, common: 2.5...5, strong: 5...10, heavy: 10, fatal: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 3),
                    comeup: TimeRange(min: 2, max: 5),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: nil,
                    total: TimeRange(min: 60, max: 120)
                )),
                SubstanceRoute(route: .intramuscular, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2.5...5, common: 5...10, strong: 10...15, heavy: 15, fatal: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 20, max: 45),
                    offset: TimeRange(min: 45, max: 75),
                    afterglow: nil,
                    total: TimeRange(min: 75, max: 150)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...10, strong: 10...15, heavy: 15
                ), duration: DurationProfile(
                    onset: TimeRange(min: 3, max: 10),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 20, max: 45),
                    offset: TimeRange(min: 40, max: 70),
                    afterglow: nil,
                    total: TimeRange(min: 70, max: 150)
                )),
            ],
            effects: ["Amnesia", "Sedation", "Anxiolysis", "Muscle relaxation", "Drowsiness", "Motor impairment", "Disinhibition", "Respiratory depression", "Euphoria"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Profound Amnesia", description: "Extremely potent anterograde amnesia that is the defining feature of midazolam, often producing complete blackouts even at moderate doses."),
                SubjectiveEffect(name: "Rapid Onset Sedation", description: "Very fast-acting sedation, particularly via IV or IM routes, that can induce near-unconsciousness within minutes."),
                SubjectiveEffect(name: "Procedural Anxiolysis", description: "Complete elimination of anxiety and fear surrounding medical procedures, with patients often reporting no memory of the event afterward."),
                SubjectiveEffect(name: "Heavy Drowsiness", description: "An overwhelming desire to sleep that is difficult to resist, with the user often falling asleep involuntarily."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Significant physical relaxation that contributes to its use as a pre-surgical medication."),
                SubjectiveEffect(name: "Disinhibition", description: "Before sedation takes full effect, a brief window of lowered inhibitions where users may say or do things they normally would not."),
                SubjectiveEffect(name: "Motor Impairment", description: "Severe coordination loss that can render walking impossible at higher doses."),
                SubjectiveEffect(name: "Respiratory Depression", description: "Dose-dependent suppression of breathing that requires monitoring in clinical settings, particularly with IV administration."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 2, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 120,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: Temazepam

        Substance(
            name: "Temazepam",
            aliases: ["Restoril"],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...15, common: 15...30, strong: 30...45, heavy: 45, fatal: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 90, max: 120),
                    offset: TimeRange(min: 180, max: 300),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 480)
                )),
            ],
            effects: ["Sedation", "Euphoria", "Anxiolysis", "Muscle relaxation", "Drowsiness", "Amnesia", "Disinhibition", "Motor impairment", "Sleep induction"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Notable Euphoria", description: "One of the more euphoric benzodiazepines, producing a warm, pleasant buzz and sense of well-being that has made it popular recreationally."),
                SubjectiveEffect(name: "Sleep Induction", description: "Powerful hypnotic effect that makes falling asleep feel effortless, with a natural, unforced quality to the sedation."),
                SubjectiveEffect(name: "Anxiolysis", description: "Reliable anxiety relief that pairs with the euphoria to create a carefree, comfortable mental state."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Deep physical relaxation with reduced muscle tension, contributing to the overall sense of bodily comfort."),
                SubjectiveEffect(name: "Disinhibition", description: "Lowered inhibitions with increased sociability and talkativeness, sometimes leading to impulsive decisions."),
                SubjectiveEffect(name: "Amnesia", description: "Moderate anterograde amnesia, with memory gaps more likely at higher doses."),
                SubjectiveEffect(name: "Drowsiness", description: "A pleasant, warm sleepiness that builds over the duration and facilitates restful sleep."),
                SubjectiveEffect(name: "Motor Impairment", description: "Reduced coordination and balance that can make walking difficult, especially combined with the sedation."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 690,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: Triazolam

        Substance(
            name: "Triazolam",
            aliases: ["Halcion"],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.05, light: 0.0625...0.125, common: 0.125...0.25, strong: 0.25...0.5, heavy: 0.5, fatal: 10
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 120, max: 240)
                )),
                SubstanceRoute(route: .sublingual, unit: "mg", doses: DoseRange(
                    threshold: 0.05, light: 0.0625...0.125, common: 0.125...0.25, strong: 0.25...0.5, heavy: 0.5
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 45, max: 90),
                    offset: TimeRange(min: 45, max: 90),
                    afterglow: nil,
                    total: TimeRange(min: 90, max: 210)
                )),
            ],
            effects: ["Sedation", "Amnesia", "Sleep induction", "Anxiolysis", "Drowsiness", "Motor impairment", "Disinhibition", "Muscle relaxation", "Euphoria"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Rapid Sleep Onset", description: "Extremely fast-acting hypnotic effect that can induce sleep within 15-30 minutes, making it one of the quickest-acting sleep aids."),
                SubjectiveEffect(name: "Intense Amnesia", description: "Powerful anterograde amnesia that frequently causes complete blackouts, with no memory of events between dosing and sleep."),
                SubjectiveEffect(name: "Brief Euphoria Window", description: "A short window of euphoria and disinhibition before sleep takes over, which has led to its association with parasomnia behaviors."),
                SubjectiveEffect(name: "Parasomnia Risk", description: "Complex sleep behaviors such as sleepwalking, sleep-eating, or making phone calls with no memory, a well-documented phenomenon."),
                SubjectiveEffect(name: "Sedation", description: "Overwhelming drowsiness that can be nearly impossible to resist, often overtaking the user before they realize it."),
                SubjectiveEffect(name: "Anxiolysis", description: "Quick anxiety relief that helps racing thoughts settle before sleep."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Physical tension relief that contributes to the feeling of sinking comfortably into bed."),
                SubjectiveEffect(name: "Short Duration", description: "Effects wear off within 2-4 hours, which minimizes next-day grogginess but can lead to early-morning awakening."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 2, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 150,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: Oxazepam

        Substance(
            name: "Oxazepam",
            aliases: ["Serax"],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...15, common: 15...30, strong: 30...60, heavy: 60, fatal: 600
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 180),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 540)
                )),
            ],
            effects: ["Anxiolysis", "Sedation", "Muscle relaxation", "Drowsiness", "Disinhibition", "Motor impairment", "Amnesia", "Emotional blunting"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Gentle Anxiolysis", description: "A slow, mild anxiety relief that takes longer to onset than other benzodiazepines but provides steady, predictable calm."),
                SubjectiveEffect(name: "Minimal Euphoria", description: "Very little recreational appeal, with the experience described as simply feeling less anxious rather than feeling good."),
                SubjectiveEffect(name: "Emotional Blunting", description: "A dampening of emotional responses that can be helpful for anxiety but may feel flat and emotionless at higher doses."),
                SubjectiveEffect(name: "Mild Sedation", description: "Gentle drowsiness that is less overwhelming than more potent benzodiazepines, allowing functional use during the day."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Moderate physical relaxation with reduced muscle tension, though less pronounced than diazepam."),
                SubjectiveEffect(name: "Slow Onset", description: "Effects take longer to develop than most benzodiazepines due to slow absorption from the GI tract."),
                SubjectiveEffect(name: "Disinhibition", description: "Subtle lowering of social barriers without the euphoric push of more potent benzodiazepines."),
                SubjectiveEffect(name: "Motor Impairment", description: "Mild coordination decrease that is less pronounced than with faster-acting agents."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 480,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: Flurazepam

        Substance(
            name: "Flurazepam",
            aliases: ["Dalmane"],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 15...30, common: 30...45, strong: 45...60, heavy: 60, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 480, max: 960),
                    afterglow: nil,
                    total: TimeRange(min: 960, max: 2880)
                )),
            ],
            effects: ["Sedation", "Sleep induction", "Anxiolysis", "Drowsiness", "Muscle relaxation", "Amnesia", "Motor impairment", "Disinhibition", "Residual grogginess"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Powerful Sleep Induction", description: "Strong hypnotic effect that reliably initiates sleep, with a heavy, irresistible drowsiness that sets in within an hour."),
                SubjectiveEffect(name: "Next-Day Grogginess", description: "Due to extremely long-acting active metabolites, significant residual sedation and cognitive fog can persist well into the following day."),
                SubjectiveEffect(name: "Deep Anxiolysis", description: "Thorough anxiety relief that persists for many hours due to the long half-life of both the parent compound and metabolites."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Pronounced physical relaxation that helps with tension-related discomfort and facilitates comfortable sleep."),
                SubjectiveEffect(name: "Amnesia", description: "Memory impairment for events occurring during peak sedation, with gaps in recall of the hours surrounding sleep."),
                SubjectiveEffect(name: "Accumulation", description: "With repeated nightly use, the long-acting metabolites accumulate, leading to increasing daytime sedation over several days."),
                SubjectiveEffect(name: "Motor Impairment", description: "Significant coordination loss during peak effects and residual impairment the following morning."),
                SubjectiveEffect(name: "Drowsiness", description: "A deep, heavy sleepiness that makes staying awake a struggle during peak effects."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 30, buildRate: "moderate"),
            halfLifeMinutes: 2880,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: Chlordiazepoxide

        Substance(
            name: "Chlordiazepoxide",
            aliases: ["Librium"],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 5...10, common: 10...25, strong: 25...50, heavy: 50, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Anxiolysis", "Sedation", "Muscle relaxation", "Disinhibition", "Drowsiness", "Appetite enhancement", "Amnesia", "Motor impairment"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Gentle, Long-Lasting Calm", description: "A mild, slow-onset anxiolysis that builds gradually and persists for many hours, providing a baseline of calm without sharp peaks or valleys."),
                SubjectiveEffect(name: "Alcohol Withdrawal Relief", description: "Effective suppression of withdrawal symptoms including tremor, anxiety, and autonomic hyperactivity, widely used as the gold standard for this purpose."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Notable physical relaxation, particularly useful for alcohol withdrawal-related muscle tension and tremor."),
                SubjectiveEffect(name: "Appetite Enhancement", description: "Increased appetite and food intake, partly from anxiety reduction and partly from GABAergic effects on appetite centers."),
                SubjectiveEffect(name: "Minimal Euphoria", description: "Very little recreational value, with the subjective experience being one of quiet normalcy rather than a noticeable high."),
                SubjectiveEffect(name: "Disinhibition", description: "Mild lowering of social and behavioral inhibitions, less pronounced than with more potent benzodiazepines."),
                SubjectiveEffect(name: "Drowsiness", description: "Moderate sleepiness that persists for many hours due to long-acting metabolites."),
                SubjectiveEffect(name: "Amnesia", description: "Mild memory impairment at higher doses, less pronounced than with more potent amnesia-producing benzodiazepines."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 30, buildRate: "moderate"),
            halfLifeMinutes: 1500,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: Clobazam

        Substance(
            name: "Clobazam",
            aliases: ["Onfi", "Frisium"],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...20, strong: 20...40, heavy: 40, fatal: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Anxiolysis", "Anticonvulsant", "Sedation", "Muscle relaxation", "Drowsiness", "Motor impairment", "Disinhibition", "Amnesia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Functional Anxiolysis", description: "Reliable anxiety relief that allows normal functioning, with less sedation and cognitive impairment than most other benzodiazepines."),
                SubjectiveEffect(name: "Anticonvulsant Effect", description: "Effective seizure prevention through its unique 1,5-benzodiazepine structure, providing neural stability."),
                SubjectiveEffect(name: "Minimal Sedation", description: "Less drowsiness than typical benzodiazepines, making it better suited for daytime anxiety management."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Moderate physical tension relief without the heavy body sensation of more sedating benzodiazepines."),
                SubjectiveEffect(name: "Low Abuse Potential", description: "Less euphoria and recreational appeal compared to other benzodiazepines, making compulsive use less likely."),
                SubjectiveEffect(name: "Drowsiness", description: "Mild sleepiness that is manageable during daily activities at therapeutic doses."),
                SubjectiveEffect(name: "Motor Impairment", description: "Slight coordination decrease that is less problematic than with more sedating agents."),
                SubjectiveEffect(name: "Amnesia", description: "Minimal memory impairment at therapeutic doses, less amnestic than many other benzodiazepines."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 2280,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: Nitrazepam

        Substance(
            name: "Nitrazepam",
            aliases: ["Mogadon"],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2.5...5, common: 5...10, strong: 10...15, heavy: 15, fatal: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 90, max: 120),
                    offset: TimeRange(min: 180, max: 300),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 480)
                )),
            ],
            effects: ["Sedation", "Sleep induction", "Anxiolysis", "Muscle relaxation", "Amnesia", "Drowsiness", "Motor impairment", "Anticonvulsant", "Disinhibition"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Powerful Hypnotic Effect", description: "Strong sleep-inducing properties that reliably produce deep, sustained sleep lasting through the night."),
                SubjectiveEffect(name: "Deep Anxiolysis", description: "Significant anxiety relief that helps quiet racing thoughts and pre-sleep worry."),
                SubjectiveEffect(name: "Heavy Sedation", description: "Pronounced drowsiness that can make staying awake extremely difficult at moderate doses."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Thorough physical relaxation that helps the body settle into comfortable rest."),
                SubjectiveEffect(name: "Amnesia", description: "Notable anterograde amnesia, particularly for events during the onset period before sleep takes over."),
                SubjectiveEffect(name: "Anticonvulsant", description: "Effective seizure prevention, making it useful for patients with both epilepsy and sleep difficulties."),
                SubjectiveEffect(name: "Next-Day Residual Effects", description: "Due to its intermediate duration, some grogginess and cognitive slowing may persist into the morning hours."),
                SubjectiveEffect(name: "Disinhibition", description: "Lowered behavioral control during the pre-sleep window, sometimes leading to unusual behavior with no memory the next day."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 1440,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: Bromazepam

        Substance(
            name: "Bromazepam",
            aliases: ["Lexotan"],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 1.5...3, common: 3...6, strong: 6...12, heavy: 12, fatal: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 25),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 180, max: 300),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 480)
                )),
            ],
            effects: ["Anxiolysis", "Sedation", "Muscle relaxation", "Disinhibition", "Drowsiness", "Motor impairment", "Amnesia", "Emotional blunting"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Moderate Anxiolysis", description: "Reliable anxiety relief at lower doses that helps manage daily stress and worry without excessive sedation."),
                SubjectiveEffect(name: "Dose-Dependent Sedation", description: "At lower doses primarily anxiolytic, transitioning to increasingly sedating at higher doses, providing a flexible dose-response profile."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Effective physical tension relief, particularly useful for anxiety-related muscle tightness in the shoulders and back."),
                SubjectiveEffect(name: "Emotional Blunting", description: "A dampening of emotional intensity where both positive and negative stimuli provoke less reaction than usual."),
                SubjectiveEffect(name: "Mild Disinhibition", description: "Subtle lowering of social barriers that makes interactions feel easier without dramatic behavioral changes."),
                SubjectiveEffect(name: "Drowsiness", description: "Increasing sleepiness at higher doses that transitions from mild tiredness to genuine difficulty staying awake."),
                SubjectiveEffect(name: "Motor Impairment", description: "Decreased coordination and fine motor control that worsens with dose."),
                SubjectiveEffect(name: "Amnesia", description: "Moderate memory impairment at higher doses, with gaps in recall for events during peak effects."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 720,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: Flunitrazepam

        Substance(
            name: "Flunitrazepam",
            aliases: ["Rohypnol", "Roofies"],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.15, light: 0.25...0.5, common: 0.5...1, strong: 1...2, heavy: 2, fatal: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 960)
                )),
            ],
            effects: ["Amnesia", "Sedation", "Muscle relaxation", "Anxiolysis", "Disinhibition", "Euphoria", "Motor impairment", "Drowsiness", "Sleep induction"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Complete Amnesia", description: "Extremely powerful anterograde amnesia, often producing total blackouts where hours of activity are completely unremembered."),
                SubjectiveEffect(name: "Heavy Sedation", description: "Potent sedation that can render users unable to function normally, with a strong pull toward unconsciousness."),
                SubjectiveEffect(name: "Euphoria", description: "A notable euphoric component that contributes to its high abuse potential and notoriety as a date-rape drug."),
                SubjectiveEffect(name: "Disinhibition", description: "Dramatic lowering of inhibitions that can lead to highly uncharacteristic behavior with no subsequent memory."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Profound physical relaxation that can make limbs feel impossibly heavy and movement difficult."),
                SubjectiveEffect(name: "Sleep Induction", description: "Powerful hypnotic effect that can force sleep even in uncomfortable or unfamiliar environments."),
                SubjectiveEffect(name: "Motor Impairment", description: "Severe loss of coordination and balance, with slurred speech and stumbling gait at moderate doses."),
                SubjectiveEffect(name: "Vulnerability", description: "The combination of amnesia, disinhibition, and sedation creates a uniquely dangerous state of suggestibility and vulnerability."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 1200,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: Nordazepam

        Substance(
            name: "Nordazepam",
            aliases: ["Nordiazepam"],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2.5...5, common: 5...10, strong: 10...20, heavy: 20, fatal: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 4320)
                )),
            ],
            effects: ["Anxiolysis", "Sedation", "Muscle relaxation", "Drowsiness", "Disinhibition", "Amnesia", "Motor impairment", "Anticonvulsant"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Ultra-Long Duration", description: "Effects persist for an extremely long time due to very slow elimination, providing day-long anxiety relief from a single dose."),
                SubjectiveEffect(name: "Mild Steady Calm", description: "A gentle, sustained anxiolysis that feels like a subtle background calm rather than an acute drug effect."),
                SubjectiveEffect(name: "Gradual Onset", description: "Slow absorption and onset that builds over 1-2 hours, without the sudden onset that characterizes faster-acting benzodiazepines."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Moderate physical relaxation that develops gradually alongside the anxiolytic effects."),
                SubjectiveEffect(name: "Anticonvulsant", description: "Seizure prevention through long-lasting GABAergic enhancement, providing consistent neural stabilization."),
                SubjectiveEffect(name: "Drowsiness", description: "Persistent mild sleepiness that can be an issue during daytime use, especially during the first week."),
                SubjectiveEffect(name: "Accumulation", description: "Active metabolites build up over days of regular dosing, potentially intensifying all effects beyond what would be expected from a single dose."),
                SubjectiveEffect(name: "Amnesia", description: "Mild memory difficulties at higher doses, less pronounced than with more potent amnestic benzodiazepines."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 30, buildRate: "moderate"),
            halfLifeMinutes: 3600,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: Prazepam

        Substance(
            name: "Prazepam",
            aliases: ["Centrax"],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 5...10, common: 10...20, strong: 20...40, heavy: 40, fatal: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 4320)
                )),
            ],
            effects: ["Anxiolysis", "Sedation", "Muscle relaxation", "Drowsiness", "Disinhibition", "Amnesia", "Motor impairment", "Emotional blunting"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Slow Prodrug Onset", description: "Very gradual onset as prazepam must be converted to its active metabolite nordazepam in the liver, producing a smooth, slow build of effects."),
                SubjectiveEffect(name: "Mild Background Calm", description: "A subtle, barely noticeable reduction in baseline anxiety that feels more like the absence of anxiety than a drug effect."),
                SubjectiveEffect(name: "Emotional Blunting", description: "A dampening of emotional reactivity that makes stressors feel remote and unimportant."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Gentle physical relaxation that develops gradually alongside the anxiolytic effect."),
                SubjectiveEffect(name: "Low Recreational Value", description: "Minimal euphoria or rush, making it one of the least abused benzodiazepines due to its slow onset and mild effects."),
                SubjectiveEffect(name: "Drowsiness", description: "Mild, persistent sleepiness that can be an issue during initial dosing or dose increases."),
                SubjectiveEffect(name: "Long Duration", description: "Effects persist for many hours due to the very long half-life of the active metabolite nordazepam."),
                SubjectiveEffect(name: "Amnesia", description: "Mild memory effects that are less prominent than with faster-acting, more potent benzodiazepines."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 30, buildRate: "moderate"),
            halfLifeMinutes: 4320,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: Quazepam

        Substance(
            name: "Quazepam",
            aliases: ["Doral"],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 3.75, light: 7.5...15, common: 15...22.5, strong: 22.5...30, heavy: 30, fatal: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 240, max: 420),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 720)
                )),
            ],
            effects: ["Sedation", "Sleep induction", "Anxiolysis", "Muscle relaxation", "Drowsiness", "Amnesia", "Motor impairment", "Residual grogginess"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Reliable Sleep Induction", description: "Effective hypnotic action that induces sleep within 30-60 minutes, with selectivity for GABA-A receptors associated with sedation."),
                SubjectiveEffect(name: "Sustained Sleep Maintenance", description: "Long enough duration to maintain sleep through the night without early awakening, but with some next-day carryover."),
                SubjectiveEffect(name: "Pre-Sleep Anxiolysis", description: "Calming of pre-sleep worry and racing thoughts that helps the mind settle into rest."),
                SubjectiveEffect(name: "Residual Morning Grogginess", description: "Due to active metabolites with long half-lives, noticeable next-day cognitive fog and drowsiness that can impair morning functioning."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Physical relaxation that helps the body settle into a comfortable sleeping position."),
                SubjectiveEffect(name: "Amnesia", description: "Memory impairment for events during the pre-sleep period, with limited recall of activities after dosing."),
                SubjectiveEffect(name: "Motor Impairment", description: "Coordination loss that makes nighttime bathroom trips potentially hazardous, with residual morning unsteadiness."),
                SubjectiveEffect(name: "Drowsiness", description: "A heavy, persistent sleepiness that is the primary desired effect for insomnia treatment."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 30, buildRate: "moderate"),
            halfLifeMinutes: 2400,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: Estazolam

        Substance(
            name: "Estazolam",
            aliases: ["ProSom"],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1, common: 1...2, strong: 2...4, heavy: 4, fatal: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 25),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 180, max: 300),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 480)
                )),
            ],
            effects: ["Sedation", "Sleep induction", "Anxiolysis", "Muscle relaxation", "Drowsiness", "Amnesia", "Motor impairment", "Disinhibition"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Balanced Sedation", description: "A well-balanced hypnotic effect that is strong enough to induce sleep without the extreme next-day hangover of longer-acting agents."),
                SubjectiveEffect(name: "Quick Sleep Onset", description: "Relatively fast-acting sleep induction within 30 minutes, making it effective for sleep-onset insomnia."),
                SubjectiveEffect(name: "Anxiolysis", description: "Moderate anxiety relief that helps quiet the mind before sleep, useful for anxiety-driven insomnia."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Physical relaxation that aids in comfortable sleep positioning and reduces tension-related discomfort."),
                SubjectiveEffect(name: "Amnesia", description: "Anterograde memory impairment during the onset period, with poor recall of activities between dosing and falling asleep."),
                SubjectiveEffect(name: "Drowsiness", description: "A strong, inviting sleepiness that builds quickly after dosing."),
                SubjectiveEffect(name: "Motor Impairment", description: "Notable coordination loss during peak effects that makes ambulation risky."),
                SubjectiveEffect(name: "Disinhibition", description: "Brief period of lowered inhibitions before sleep overtakes, potentially leading to unusual pre-sleep behavior."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 720,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: Halazepam

        Substance(
            name: "Halazepam",
            aliases: [],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 20...40, common: 40...80, strong: 80...120, heavy: 120, fatal: 600
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 4320)
                )),
            ],
            effects: ["Anxiolysis", "Sedation", "Muscle relaxation", "Drowsiness", "Disinhibition", "Motor impairment", "Amnesia", "Emotional blunting"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mild Anxiolysis", description: "A gentle, unobtrusive anxiety relief similar to its parent compound diazepam but converted through nordazepam as an active metabolite."),
                SubjectiveEffect(name: "Emotional Blunting", description: "A flattening of emotional responses where stressful situations fail to provoke the usual anxiety or distress."),
                SubjectiveEffect(name: "Slow Onset", description: "Gradual development of effects as the prodrug is metabolized, without the sudden onset that characterizes faster benzodiazepines."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Moderate physical relaxation through GABAergic enhancement of muscle tone reduction."),
                SubjectiveEffect(name: "Minimal Euphoria", description: "Very little recreational effect, with the experience being described as simply less anxious rather than pleasurable."),
                SubjectiveEffect(name: "Drowsiness", description: "Mild to moderate sleepiness that persists throughout the long duration of action."),
                SubjectiveEffect(name: "Motor Impairment", description: "Subtle coordination decrease that can accumulate with repeated daily dosing."),
                SubjectiveEffect(name: "Amnesia", description: "Mild anterograde memory effects that are less pronounced than with more potent agents."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 30, buildRate: "moderate"),
            halfLifeMinutes: 840,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: Lormetazepam

        Substance(
            name: "Lormetazepam",
            aliases: ["Noctamid"],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1, common: 1...2, strong: 2...4, heavy: 4, fatal: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 15, max: 25),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 180, max: 300),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 480)
                )),
            ],
            effects: ["Sedation", "Sleep induction", "Anxiolysis", "Muscle relaxation", "Amnesia", "Drowsiness", "Motor impairment", "Disinhibition"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Clean Hypnotic Effect", description: "Effective sleep induction without excessive next-day hangover, thanks to its intermediate half-life and lack of long-acting metabolites."),
                SubjectiveEffect(name: "Rapid Sleep Onset", description: "Fast-acting sedation that reliably induces sleep within 20-30 minutes of dosing."),
                SubjectiveEffect(name: "Pre-Sleep Calm", description: "Quick dissolving of bedtime anxiety and racing thoughts, allowing the mind to quiet before sleep."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Physical relaxation that contributes to comfortable sleep onset and maintenance."),
                SubjectiveEffect(name: "Amnesia", description: "Anterograde memory impairment during the pre-sleep window, with events between dosing and sleep often unremembered."),
                SubjectiveEffect(name: "Minimal Next-Day Effects", description: "Relatively clean offset with less morning grogginess than longer-acting hypnotic benzodiazepines."),
                SubjectiveEffect(name: "Motor Impairment", description: "Significant coordination loss during peak effects that makes nighttime movement hazardous."),
                SubjectiveEffect(name: "Disinhibition", description: "Brief lowering of inhibitions before sleep onset, potentially leading to unusual behavior."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 600,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: Medazepam

        Substance(
            name: "Medazepam",
            aliases: [],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...20, strong: 20...30, heavy: 30, fatal: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Anxiolysis", "Sedation", "Muscle relaxation", "Drowsiness", "Disinhibition", "Motor impairment", "Amnesia", "Emotional blunting"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Daytime Anxiolysis", description: "A mild anxiolytic effect with less sedation than most benzodiazepines, making it suitable for use during waking hours."),
                SubjectiveEffect(name: "Gentle Calm", description: "A subtle background calm that reduces baseline anxiety without producing noticeable intoxication or impairment."),
                SubjectiveEffect(name: "Emotional Blunting", description: "Mild dampening of emotional reactivity, useful for managing emotional volatility but potentially causing a sense of flatness."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Moderate physical tension relief that develops gradually over the course of action."),
                SubjectiveEffect(name: "Low Sedation", description: "Less drowsiness than most benzodiazepines at equivalent anxiolytic doses, allowing better daytime functioning."),
                SubjectiveEffect(name: "Prodrug Activation", description: "Converted to active metabolites including diazepam, producing a gradual onset that avoids the sharp peaks of direct-acting agents."),
                SubjectiveEffect(name: "Disinhibition", description: "Mild lowering of social barriers that is less pronounced than with more euphoric benzodiazepines."),
                SubjectiveEffect(name: "Amnesia", description: "Minimal memory impairment at therapeutic doses, contributing to its favorable side-effect profile for daytime use."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 30, buildRate: "moderate"),
            halfLifeMinutes: 2160,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: Clorazepate

        Substance(
            name: "Clorazepate",
            aliases: ["Tranxene"],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 3.75, light: 7.5...15, common: 15...30, strong: 30...60, heavy: 60, fatal: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Anxiolysis", "Sedation", "Muscle relaxation", "Anticonvulsant", "Drowsiness", "Disinhibition", "Amnesia", "Motor impairment"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Prodrug Anxiolysis", description: "Rapid conversion to nordazepam in the stomach provides a smooth onset of anxiety relief without the sharp peaks of direct-acting agents."),
                SubjectiveEffect(name: "Long-Acting Calm", description: "Extended duration through the active metabolite nordazepam, providing sustained baseline anxiety control throughout the day."),
                SubjectiveEffect(name: "Anticonvulsant Effect", description: "Effective seizure prevention through both the parent compound and its long-acting metabolites."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Moderate physical relaxation that builds gradually and persists for many hours."),
                SubjectiveEffect(name: "Drowsiness", description: "Persistent sleepiness that can be problematic during daytime use, especially in the early days of treatment."),
                SubjectiveEffect(name: "Disinhibition", description: "Mild lowering of social and behavioral inhibitions that becomes more apparent at higher doses."),
                SubjectiveEffect(name: "Motor Impairment", description: "Gradual coordination decrease that may accumulate with daily dosing due to long-acting metabolites."),
                SubjectiveEffect(name: "Amnesia", description: "Moderate anterograde memory impairment that is dose-dependent and more noticeable at higher doses."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 30, buildRate: "moderate"),
            halfLifeMinutes: 2880,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: Cinolazepam

        Substance(
            name: "Cinolazepam",
            aliases: [],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 20...40, common: 40...80, strong: 80...120, heavy: 120, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 90, max: 120),
                    offset: TimeRange(min: 180, max: 300),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 480)
                )),
            ],
            effects: ["Sedation", "Sleep induction", "Anxiolysis", "Muscle relaxation", "Drowsiness", "Amnesia", "Motor impairment", "Disinhibition"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Effective Sleep Induction", description: "Reliable hypnotic action that induces sleep within 30-60 minutes, primarily used in European countries for insomnia."),
                SubjectiveEffect(name: "Anxiolysis", description: "Moderate pre-sleep anxiety relief that helps quiet mental chatter and worry."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Physical relaxation that contributes to comfortable sleep and reduces restlessness."),
                SubjectiveEffect(name: "Heavy Drowsiness", description: "Strong sedation that makes resisting sleep difficult at therapeutic doses."),
                SubjectiveEffect(name: "Amnesia", description: "Anterograde memory impairment typical of hypnotic benzodiazepines, affecting recall of pre-sleep activities."),
                SubjectiveEffect(name: "Motor Impairment", description: "Significant coordination loss during peak effects, making ambulation risky."),
                SubjectiveEffect(name: "Disinhibition", description: "Lowered behavioral control that may manifest as unusual behavior during the onset window before sleep."),
                SubjectiveEffect(name: "Moderate Duration", description: "Intermediate duration that generally maintains sleep through the night without excessive morning carryover."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 540,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: Nimetazepam

        Substance(
            name: "Nimetazepam",
            aliases: ["Erimin"],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2.5...5, common: 5...10, strong: 10...15, heavy: 15, fatal: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 720)
                )),
            ],
            effects: ["Sedation", "Sleep induction", "Euphoria", "Anxiolysis", "Muscle relaxation", "Amnesia", "Disinhibition", "Drowsiness", "Motor impairment"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Euphoric Sedation", description: "A notably pleasurable sedation with a warm, euphoric quality that has made it popular recreationally, particularly in Southeast Asia."),
                SubjectiveEffect(name: "Strong Sleep Induction", description: "Potent hypnotic effect that reliably produces deep sleep, making it effective for severe insomnia."),
                SubjectiveEffect(name: "Anxiolysis", description: "Effective anxiety relief that combines with the euphoria to produce a carefree, relaxed mental state."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Pronounced physical relaxation with limbs feeling heavy and loose."),
                SubjectiveEffect(name: "Disinhibition", description: "Significant lowering of behavioral inhibitions that can lead to impulsive or reckless actions, especially recreationally."),
                SubjectiveEffect(name: "Amnesia", description: "Notable anterograde amnesia, with blackout episodes common at recreational doses."),
                SubjectiveEffect(name: "Drowsiness", description: "Deep, pervasive sleepiness that can last well beyond the initial dose period."),
                SubjectiveEffect(name: "Motor Impairment", description: "Severe coordination loss with slurred speech and unsteady gait at moderate to high doses."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 900,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: - Novel / Designer Benzodiazepines

        // MARK: Etizolam

        Substance(
            name: "Etizolam",
            aliases: ["Etilaam", "Etizest"],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.2, light: 0.5...1, common: 1...2, strong: 2...4, heavy: 4, fatal: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 360)
                )),
                SubstanceRoute(route: .sublingual, unit: "mg", doses: DoseRange(
                    threshold: 0.2, light: 0.5...1, common: 1...2, strong: 2...4, heavy: 4
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 45, max: 90),
                    offset: TimeRange(min: 90, max: 180),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Anxiolysis", "Euphoria", "Sedation", "Muscle relaxation", "Disinhibition", "Drowsiness", "Amnesia", "Motor impairment", "Appetite enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Clean Anxiolysis", description: "A highly effective, focused anxiety relief that many users describe as the most functionally useful benzodiazepine, providing calm without excessive sedation."),
                SubjectiveEffect(name: "Mood-Brightening Euphoria", description: "A pleasant, warm euphoria with a positive mood quality, often described as feeling like everything is right with the world."),
                SubjectiveEffect(name: "Rapid Onset", description: "Fast-acting effects that begin within 15-30 minutes, providing quick relief from acute anxiety episodes."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Noticeable physical relaxation and tension relief, making it useful for anxiety-related muscle tightness."),
                SubjectiveEffect(name: "Appetite Enhancement", description: "Increased hunger and desire to eat, with food tasting more appealing and snacking becoming common."),
                SubjectiveEffect(name: "Disinhibition", description: "Lowered social inhibitions that make interactions feel easier and more natural, with less overthinking."),
                SubjectiveEffect(name: "Amnesia", description: "Dose-dependent memory impairment that becomes significant at higher doses, potentially causing gaps in recall."),
                SubjectiveEffect(name: "Drowsiness", description: "Moderate sedation that increases with dose, transitioning from mild relaxation to genuine sleepiness."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 204,
            sources: ["PsychonautWiki", "DrugBank", "EMCDDA", "PubMed"]
        ),

        // MARK: Flualprazolam

        Substance(
            name: "Flualprazolam",
            aliases: [],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.05, light: 0.1...0.25, common: 0.25...0.5, strong: 0.5...1, heavy: 1, fatal: 10
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 180, max: 300),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 540)
                )),
            ],
            effects: ["Sedation", "Anxiolysis", "Amnesia", "Muscle relaxation", "Euphoria", "Disinhibition", "Drowsiness", "Motor impairment", "Respiratory depression"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Potent Sedation", description: "Significantly stronger sedation than alprazolam at equivalent anxiolytic doses, with a heavy, enveloping drowsiness."),
                SubjectiveEffect(name: "Strong Amnesia", description: "Pronounced anterograde amnesia that frequently causes complete blackouts, with users losing hours or days of memory."),
                SubjectiveEffect(name: "Deceptive Onset", description: "Effects may feel milder than expected initially, tempting redosing that leads to rapid escalation into dangerous territory."),
                SubjectiveEffect(name: "Euphoria", description: "A notable euphoric quality similar to alprazolam but more sedating, contributing to high abuse potential."),
                SubjectiveEffect(name: "Anxiolysis", description: "Powerful anxiety elimination that is effective but accompanied by disproportionate sedation and amnesia."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "Deep physical relaxation with significant reduction in muscle tone."),
                SubjectiveEffect(name: "Motor Impairment", description: "Severe coordination loss that can render walking impossible, with slurred speech and drooping eyelids."),
                SubjectiveEffect(name: "Respiratory Depression", description: "Notable breathing suppression that is more significant than with most classical benzodiazepines, increasing overdose risk."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 600,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: Clonazolam

        Substance(
            name: "Clonazolam",
            aliases: ["Clon"],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mcg", doses: DoseRange(
                    threshold: 50, light: 75...150, common: 150...300, strong: 300...500, heavy: 500, fatal: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 600, max: 900)
                )),
            ],
            effects: ["Amnesia", "Sedation", "Euphoria", "Anxiolysis", "Muscle relaxation", "Disinhibition", "Motor impairment", "Drowsiness", "Respiratory depression", "Blackouts"],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 360,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: Flubromazolam

        Substance(
            name: "Flubromazolam",
            aliases: [],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mcg", doses: DoseRange(
                    threshold: 50, light: 75...125, common: 125...250, strong: 250...500, heavy: 500, fatal: 1500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Amnesia", "Sedation", "Muscle relaxation", "Anxiolysis", "Euphoria", "Disinhibition", "Motor impairment", "Drowsiness", "Respiratory depression", "Blackouts"],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 1080,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: Pyrazolam

        Substance(
            name: "Pyrazolam",
            aliases: [],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1, common: 1...2, strong: 2...3, heavy: 3, fatal: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 90, max: 180),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Anxiolysis", "Muscle relaxation", "Disinhibition", "Motor impairment", "Amnesia", "Drowsiness", "Sedation", "Emotional blunting"],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 1020,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: Nifoxipam

        Substance(
            name: "Nifoxipam",
            aliases: [],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1, common: 1...2, strong: 2...3, heavy: 3, fatal: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Sedation", "Anxiolysis", "Muscle relaxation", "Drowsiness", "Amnesia", "Motor impairment", "Disinhibition", "Anticonvulsant"],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 1440,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: Diclazepam

        Substance(
            name: "Diclazepam",
            aliases: [],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1, common: 1...2, strong: 2...4, heavy: 4, fatal: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 4320)
                )),
            ],
            effects: ["Anxiolysis", "Sedation", "Muscle relaxation", "Amnesia", "Disinhibition", "Drowsiness", "Motor impairment", "Anticonvulsant", "Euphoria"],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 30, buildRate: "moderate"),
            halfLifeMinutes: 2520,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: Meclonazepam

        Substance(
            name: "Meclonazepam",
            aliases: [],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 1...2, common: 2...4, strong: 4...6, heavy: 6, fatal: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Anxiolysis", "Sedation", "Muscle relaxation", "Drowsiness", "Amnesia", "Disinhibition", "Motor impairment", "Anticonvulsant"],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 1080,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: Flubromazepam

        Substance(
            name: "Flubromazepam",
            aliases: [],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...4, common: 4...8, strong: 8...14, heavy: 14, fatal: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: ["Sedation", "Anxiolysis", "Muscle relaxation", "Amnesia", "Drowsiness", "Disinhibition", "Motor impairment", "Anticonvulsant", "Residual grogginess"],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 30, buildRate: "moderate"),
            halfLifeMinutes: 6360,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: Deschloroetizolam

        Substance(
            name: "Deschloroetizolam",
            aliases: [],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...4, common: 4...6, strong: 6...10, heavy: 10, fatal: 80
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 25),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 210),
                    afterglow: nil,
                    total: TimeRange(min: 300, max: 420)
                )),
            ],
            effects: ["Anxiolysis", "Sedation", "Muscle relaxation", "Euphoria", "Disinhibition", "Drowsiness", "Amnesia", "Motor impairment"],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 240,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: Metizolam

        Substance(
            name: "Metizolam",
            aliases: [],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 1...2, common: 2...3, strong: 3...5, heavy: 5, fatal: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 90, max: 180),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Anxiolysis", "Sedation", "Muscle relaxation", "Disinhibition", "Euphoria", "Drowsiness", "Amnesia", "Motor impairment"],
            toleranceInfo: ToleranceInfo(halfLife: 2, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 200,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: Norflurazepam

        Substance(
            name: "Norflurazepam",
            aliases: [],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...15, strong: 15...25, heavy: 25, fatal: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 4320)
                )),
            ],
            effects: ["Sedation", "Anxiolysis", "Muscle relaxation", "Drowsiness", "Amnesia", "Motor impairment", "Disinhibition", "Residual grogginess"],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 30, buildRate: "moderate"),
            halfLifeMinutes: 4320,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: Bromazolam

        Substance(
            name: "Bromazolam",
            aliases: [],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1, common: 1...2, strong: 2...4, heavy: 4, fatal: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 25),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 180, max: 300),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 540)
                )),
            ],
            effects: ["Sedation", "Anxiolysis", "Euphoria", "Muscle relaxation", "Amnesia", "Disinhibition", "Motor impairment", "Drowsiness", "Blackouts"],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 600,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: Flunitrazolam

        Substance(
            name: "Flunitrazolam",
            aliases: [],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mcg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...350, heavy: 350, fatal: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 20),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 30, max: 90),
                    offset: TimeRange(min: 60, max: 150),
                    afterglow: nil,
                    total: TimeRange(min: 120, max: 300)
                )),
            ],
            effects: ["Amnesia", "Sedation", "Anxiolysis", "Muscle relaxation", "Euphoria", "Disinhibition", "Motor impairment", "Drowsiness", "Sleep induction", "Blackouts"],
            toleranceInfo: ToleranceInfo(halfLife: 2, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 150,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: Nitrazolam

        Substance(
            name: "Nitrazolam",
            aliases: [],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1, common: 1...2, strong: 2...3, heavy: 3, fatal: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 25),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 180, max: 300),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 540)
                )),
            ],
            effects: ["Sedation", "Anxiolysis", "Sleep induction", "Muscle relaxation", "Amnesia", "Drowsiness", "Motor impairment", "Disinhibition"],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 600,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: Phenazepam

        Substance(
            name: "Phenazepam",
            aliases: [],
            category: .benzodiazepine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1, common: 1...2, strong: 2...4, heavy: 4, fatal: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 720, max: 2160),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 4320)
                )),
            ],
            effects: ["Sedation", "Amnesia", "Anxiolysis", "Muscle relaxation", "Disinhibition", "Motor impairment", "Drowsiness", "Blackouts", "Anticonvulsant", "Respiratory depression"],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 30, buildRate: "moderate"),
            halfLifeMinutes: 3600,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),
    ]
}
