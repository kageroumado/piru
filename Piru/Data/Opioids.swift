import Foundation

extension SubstanceLibrary {
    static let opioids: [Substance] = [

        // MARK: - Morphine

        Substance(
            name: "Morphine",
            aliases: ["MS Contin", "Kadian", "Avinza"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 7.5...15, common: 15...30, strong: 30...60, heavy: 60, fatal: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 240, max: 360)
                )),
                SubstanceRoute(route: .intravenous, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 2.5...5, common: 5...10, strong: 10...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.5, max: 2),
                    comeup: TimeRange(min: 2, max: 10),
                    peak: TimeRange(min: 15, max: 60),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 120, max: 240)
                )),
                SubstanceRoute(route: .intramuscular, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...15, strong: 15...25, heavy: 25
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 20),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 30, max: 90),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 180, max: 300)
                )),
                SubstanceRoute(route: .subcutaneous, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...15, strong: 15...25, heavy: 25
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 30, max: 90),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 180, max: 300)
                )),
                SubstanceRoute(route: .rectal, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 7.5...15, common: 15...30, strong: 30...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Euphoria", "Pain relief", "Sedation", "Warmth", "Respiratory depression", "Nausea", "Constipation", "Itching", "Nodding", "Anxiolysis"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Warm Euphoria", description: "A deep, radiating warmth and profound sense of well-being that spreads from the core outward, often described as being enveloped in a warm blanket of contentment."),
                SubjectiveEffect(name: "Pain Dissolution", description: "Complete or near-complete suppression of physical pain, replaced by a pervasive sense of bodily comfort and ease."),
                SubjectiveEffect(name: "Emotional Blunting", description: "Worries, anxieties, and emotional distress feel muted and distant, as if separated by a thick pane of glass."),
                SubjectiveEffect(name: "Heavy Sedation", description: "A profound drowsiness and desire to close the eyes, with the body feeling pleasantly heavy and difficult to move."),
                SubjectiveEffect(name: "Nodding", description: "A semi-conscious state of drifting in and out of a dreamlike drowsiness, with the head drooping forward involuntarily."),
                SubjectiveEffect(name: "Itching", description: "A diffuse, oddly pleasant tingling and itchiness across the skin, particularly on the face and nose, caused by histamine release."),
                SubjectiveEffect(name: "Nausea", description: "A wave-like queasiness in the stomach that can range from mild discomfort to active vomiting, especially in opioid-naive users."),
                SubjectiveEffect(name: "Respiratory Slowing", description: "A noticeable reduction in the urge to breathe, with breaths becoming shallow and infrequent, which can be dangerous at high doses."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "rapid"),
            halfLifeMinutes: 180,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: - Codeine

        Substance(
            name: "Codeine",
            aliases: ["Lean", "Purple Drank", "Sizzurp"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 15, light: 30...60, common: 60...120, strong: 120...200, heavy: 200, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Mild euphoria", "Pain relief", "Sedation", "Relaxation", "Nausea", "Constipation", "Itching", "Drowsiness", "Respiratory depression"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Gentle Warmth", description: "A mild, pleasant warmth that settles over the body, less intense than stronger opioids but still distinctly comforting."),
                SubjectiveEffect(name: "Subtle Mood Lift", description: "A gentle elevation of mood and mild contentment, often described as feeling cozy and at ease rather than overtly euphoric."),
                SubjectiveEffect(name: "Pain Relief", description: "Moderate reduction in pain perception, providing noticeable comfort for mild to moderate pain."),
                SubjectiveEffect(name: "Drowsiness", description: "A soft, sleepy feeling that makes rest feel inviting, with eyelids growing heavy and thoughts slowing down."),
                SubjectiveEffect(name: "Relaxation", description: "A general loosening of physical and mental tension, with the body feeling calm and unbothered."),
                SubjectiveEffect(name: "Nausea", description: "Stomach unease that is common especially on first use, sometimes accompanied by a spinning sensation."),
                SubjectiveEffect(name: "Itching", description: "Mild skin itchiness, particularly on the face and arms, caused by histamine release from opioid receptor activation."),
                SubjectiveEffect(name: "Mental Fog", description: "A hazy, slightly clouded quality to thinking where concentration becomes difficult and thoughts drift easily."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 4, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: - Hydrocodone

        Substance(
            name: "Hydrocodone",
            aliases: ["Vicodin", "Norco", "Lortab", "Hycodan"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...20, strong: 20...35, heavy: 35, fatal: 90
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Euphoria", "Pain relief", "Sedation", "Warmth", "Anxiolysis", "Nausea", "Constipation", "Itching", "Respiratory depression", "Drowsiness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Warm Euphoria", description: "A smooth, enveloping sense of well-being and warmth that builds gradually, often described as a cozy, carefree feeling."),
                SubjectiveEffect(name: "Pain Relief", description: "Effective suppression of moderate to severe pain, with a noticeable sense of physical comfort replacing discomfort."),
                SubjectiveEffect(name: "Anxiolysis", description: "Worries and stress dissolve into the background, replaced by a calm indifference to problems that normally cause anxiety."),
                SubjectiveEffect(name: "Sedation", description: "A heavy, sleepy quality that makes lying down feel irresistible, with the body sinking into whatever surface it rests on."),
                SubjectiveEffect(name: "Itching", description: "A prickly, diffuse itchiness especially around the nose and face that users often scratch at without fully noticing."),
                SubjectiveEffect(name: "Nausea", description: "Stomach queasiness that can be triggered or worsened by movement, particularly common in those without opioid tolerance."),
                SubjectiveEffect(name: "Constipation", description: "A marked slowing of gastrointestinal motility resulting in difficult, infrequent bowel movements that persist with regular use."),
                SubjectiveEffect(name: "Respiratory Depression", description: "Breathing becomes noticeably slower and shallower, with reduced awareness of the need to breathe, posing overdose risk at high doses."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 4, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 228,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: - Oxycodone

        Substance(
            name: "Oxycodone",
            aliases: ["OxyContin", "Percocet", "Oxy", "Oxys", "Roxicodone"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...20, strong: 20...40, heavy: 40, fatal: 80
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 240, max: 360)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 3...7, common: 7...15, strong: 15...25, heavy: 25
                ), duration: DurationProfile(
                    onset: TimeRange(min: 3, max: 10),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 120, max: 240)
                )),
            ],
            effects: ["Euphoria", "Pain relief", "Sedation", "Warmth", "Stimulation", "Anxiolysis", "Nausea", "Constipation", "Itching", "Respiratory depression"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Energetic Euphoria", description: "A bright, uplifting euphoria with a stimulating edge that distinguishes it from more sedating opioids, often making users feel social and motivated."),
                SubjectiveEffect(name: "Warm Body High", description: "A pervasive warmth that radiates through the body, creating a deeply comfortable and pleasurable physical sensation."),
                SubjectiveEffect(name: "Pain Elimination", description: "Powerful analgesic effect that effectively silences moderate to severe pain, leaving a sensation of profound physical comfort."),
                SubjectiveEffect(name: "Anxiolysis", description: "A confident, worry-free mental state where social anxiety and general stress feel completely absent."),
                SubjectiveEffect(name: "Mild Stimulation", description: "Unlike purely sedating opioids, oxycodone can produce a notable energy boost and desire to be active or talkative at lower doses."),
                SubjectiveEffect(name: "Itching", description: "Histamine-mediated skin itchiness that is particularly noticeable on the nose, face, and chest."),
                SubjectiveEffect(name: "Nausea", description: "Waves of stomach unease that may be provoked by standing up or moving around, sometimes leading to vomiting."),
                SubjectiveEffect(name: "Nodding", description: "At higher doses, a dreamlike state of semi-consciousness where the user drifts in and out of a pleasant drowsiness."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 240,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: - Hydromorphone

        Substance(
            name: "Hydromorphone",
            aliases: ["Dilaudid", "Hydromorph Contin", "Exalgo"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 1...2, common: 2...4, strong: 4...8, heavy: 8, fatal: 24
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 240, max: 360)
                )),
                SubstanceRoute(route: .intravenous, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1, common: 1...2, strong: 2...4, heavy: 4, fatal: 10
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.5, max: 1),
                    comeup: TimeRange(min: 1, max: 5),
                    peak: TimeRange(min: 15, max: 45),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 120, max: 240)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 1...2, common: 2...4, strong: 4...6, heavy: 6
                ), duration: DurationProfile(
                    onset: TimeRange(min: 3, max: 10),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 120, max: 240)
                )),
            ],
            effects: ["Intense euphoria", "Pain relief", "Sedation", "Warmth", "Rush", "Nodding", "Nausea", "Constipation", "Itching", "Respiratory depression"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Intense Rush", description: "An immediate, overwhelming wave of euphoria and warmth upon IV administration, often described as one of the most intense opioid rushes available."),
                SubjectiveEffect(name: "Deep Euphoria", description: "A profound, all-encompassing sense of bliss and contentment that is notably more intense than most other opioids milligram-for-milligram."),
                SubjectiveEffect(name: "Heavy Sedation", description: "An extremely powerful drowsiness that makes staying awake difficult, with the body feeling impossibly heavy and immovable."),
                SubjectiveEffect(name: "Pain Obliteration", description: "Near-total suppression of even severe pain, with a potency significantly exceeding morphine at equivalent doses."),
                SubjectiveEffect(name: "Nodding", description: "Pronounced drifting between wakefulness and a dreamy, semiconscious state with vivid hypnagogic imagery."),
                SubjectiveEffect(name: "Warmth", description: "An intense internal warmth that feels like it radiates from the chest and spreads to the extremities."),
                SubjectiveEffect(name: "Nausea", description: "Strong nausea and potential vomiting, particularly in opioid-naive users or with rapid dose escalation."),
                SubjectiveEffect(name: "Respiratory Depression", description: "Significantly depressed breathing rate and depth, posing serious overdose risk due to the substance's high potency."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 4, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 150,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: - Oxymorphone

        Substance(
            name: "Oxymorphone",
            aliases: ["Opana", "Numorphan"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...15, strong: 15...25, heavy: 25, fatal: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 240, max: 360)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 1.5...3, common: 3...6, strong: 6...10, heavy: 10
                ), duration: DurationProfile(
                    onset: TimeRange(min: 3, max: 10),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 120, max: 240)
                )),
            ],
            effects: ["Intense euphoria", "Pain relief", "Sedation", "Warmth", "Nodding", "Nausea", "Constipation", "Itching", "Respiratory depression", "Anxiolysis"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Powerful Euphoria", description: "An intense, long-lasting euphoria that many describe as even more potent than hydromorphone, with a deeply satisfying quality."),
                SubjectiveEffect(name: "Complete Pain Relief", description: "Exceptional analgesic potency that eliminates even severe pain, providing a sensation of total physical comfort."),
                SubjectiveEffect(name: "Deep Sedation", description: "An overwhelming drowsiness that pulls the user into a deeply relaxed, near-sleep state with heavy limbs and slow movements."),
                SubjectiveEffect(name: "Nodding", description: "Extended periods of drifting in and out of consciousness in a pleasant, dreamlike state."),
                SubjectiveEffect(name: "Warmth", description: "A penetrating warmth that begins in the core and spreads outward, creating a cocoon-like sensation of comfort."),
                SubjectiveEffect(name: "Anxiolysis", description: "Total dissolution of anxiety and worry, with an unshakeable calm and emotional insulation from stressors."),
                SubjectiveEffect(name: "Nausea", description: "Significant nausea that may persist for hours, especially at higher doses or in those without tolerance."),
                SubjectiveEffect(name: "Itching", description: "Pronounced histamine-driven itchiness across the body, especially the face and extremities, that can be both bothersome and oddly satisfying to scratch."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 4, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 480,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: - Heroin

        Substance(
            name: "Heroin",
            aliases: ["Diacetylmorphine", "H", "Smack", "Dope", "Diamorphine"],
            category: .opioid,
            defaultRoute: .intravenous,
            routes: [
                SubstanceRoute(route: .intravenous, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 5...10, common: 10...25, strong: 25...50, heavy: 50, fatal: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 0.5),
                    comeup: TimeRange(min: 1, max: 5),
                    peak: TimeRange(min: 15, max: 60),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 120, max: 300)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...35, strong: 35...50, heavy: 50, fatal: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 3, max: 10),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 120, max: 240)
                )),
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...35, strong: 35...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 1),
                    comeup: TimeRange(min: 1, max: 5),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 120, max: 240)
                )),
            ],
            effects: ["Intense euphoria", "Rush", "Pain relief", "Warmth", "Sedation", "Nodding", "Nausea", "Constipation", "Itching", "Respiratory depression"],
            subjectiveEffects: [
                SubjectiveEffect(name: "The Rush", description: "An immediate, explosive wave of euphoria upon IV injection that is widely described as one of the most intensely pleasurable sensations possible, hitting within seconds."),
                SubjectiveEffect(name: "Overwhelming Euphoria", description: "A total-body bliss that obliterates all negative sensation and emotion, often described as the prototypical opioid high against which all others are compared."),
                SubjectiveEffect(name: "Deep Warmth", description: "An intense, radiating warmth that spreads from the injection site or stomach throughout the entire body within minutes."),
                SubjectiveEffect(name: "Heavy Nodding", description: "Pronounced semiconsciousness where the user cycles between dreamlike states and brief moments of awareness, often with vivid mental imagery."),
                SubjectiveEffect(name: "Complete Pain Relief", description: "Total suppression of physical pain at moderate doses, with a powerful analgesic effect that lasts several hours."),
                SubjectiveEffect(name: "Profound Sedation", description: "An irresistible heaviness that makes movement feel impossible, with consciousness narrowing to a small, comfortable point."),
                SubjectiveEffect(name: "Nausea and Vomiting", description: "Severe nausea common in opioid-naive users, which may paradoxically be followed by euphoria after vomiting."),
                SubjectiveEffect(name: "Respiratory Depression", description: "Dangerously slowed breathing that is the primary cause of fatal overdose, often occurring without the user being aware of it."),
                SubjectiveEffect(name: "Itching", description: "Intense, widespread histamine-mediated itching across the body, particularly the nose and face."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 4, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: - Fentanyl

        Substance(
            name: "Fentanyl",
            aliases: ["Fent", "Duragesic", "Sublimaze", "Actiq"],
            category: .opioid,
            defaultRoute: .transdermal,
            routes: [
                SubstanceRoute(route: .transdermal, unit: "\u{00B5}g/hr", doses: DoseRange(
                    threshold: 6, light: 12...25, common: 25...50, strong: 50...100, heavy: 100, fatal: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 360, max: 720),
                    comeup: TimeRange(min: 120, max: 240),
                    peak: TimeRange(min: 720, max: 1440),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 4320, max: 4320)
                )),
                SubstanceRoute(route: .sublingual, unit: "\u{00B5}g", doses: DoseRange(
                    threshold: 12, light: 12...25, common: 25...50, strong: 50...100, heavy: 100, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 60, max: 120)
                )),
                SubstanceRoute(route: .intravenous, unit: "\u{00B5}g", doses: DoseRange(
                    threshold: 6, light: 12...25, common: 25...50, strong: 50...75, heavy: 75, fatal: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 0.5),
                    comeup: TimeRange(min: 0.5, max: 2),
                    peak: TimeRange(min: 5, max: 15),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 60, max: 120)
                )),
            ],
            effects: ["Intense euphoria", "Pain relief", "Sedation", "Respiratory depression", "Nausea", "Constipation", "Muscle rigidity", "Warmth", "Nodding", "Itching"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Rapid Onset Euphoria", description: "An extremely fast-acting euphoria that peaks within seconds of IV administration but fades quickly, creating an intense but brief high."),
                SubjectiveEffect(name: "Chest Tightness", description: "A characteristic wooden-chest sensation caused by skeletal muscle rigidity, which can feel like difficulty expanding the lungs to breathe."),
                SubjectiveEffect(name: "Extreme Sedation", description: "Overwhelming drowsiness that sets in rapidly, with users sometimes losing consciousness before fully registering the high."),
                SubjectiveEffect(name: "Pain Obliteration", description: "Extremely potent analgesia active at microgram doses, capable of suppressing the most severe surgical pain."),
                SubjectiveEffect(name: "Short Duration", description: "The subjective effects wear off notably quickly compared to other opioids, often within 1-2 hours, leading to frequent redosing."),
                SubjectiveEffect(name: "Warmth", description: "A brief but intense flush of warmth concentrated in the chest and abdomen."),
                SubjectiveEffect(name: "Nausea", description: "Intense nausea and vomiting, especially in those without tolerance, that can onset very rapidly."),
                SubjectiveEffect(name: "Respiratory Depression", description: "Severe and rapid-onset respiratory depression that is the leading cause of fentanyl-related fatalities, often occurring before the user can react."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 4, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 240,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: - Methadone

        Substance(
            name: "Methadone",
            aliases: ["Done", "Dolophine", "Methadose"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...20, strong: 20...40, heavy: 40, fatal: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 540, max: 1200)
                )),
            ],
            effects: ["Pain relief", "Euphoria", "Sedation", "Warmth", "Anxiolysis", "Nausea", "Constipation", "Sweating", "Respiratory depression", "Drowsiness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Slow-Building Warmth", description: "A gradual, long-lasting warmth that takes 1-3 hours to fully develop but then persists for many hours, creating sustained comfort."),
                SubjectiveEffect(name: "Stable Euphoria", description: "A moderate but unusually long-lasting sense of well-being that plateaus and remains steady rather than peaking and crashing."),
                SubjectiveEffect(name: "Sustained Pain Relief", description: "Extended-duration analgesia lasting 24-36 hours, providing a consistent baseline of pain control."),
                SubjectiveEffect(name: "Anxiolysis", description: "A reliable reduction in anxiety that develops slowly and persists throughout the long duration of action."),
                SubjectiveEffect(name: "Excessive Sweating", description: "Profuse perspiration, particularly at night, that is a hallmark side effect and often persists even with long-term use."),
                SubjectiveEffect(name: "Drowsiness", description: "A persistent sleepiness that can last throughout the day due to the extremely long half-life."),
                SubjectiveEffect(name: "QT Prolongation Risk", description: "At higher doses, a potentially dangerous effect on heart rhythm that users may experience as palpitations or lightheadedness."),
                SubjectiveEffect(name: "Accumulation Effects", description: "Due to the long half-life, effects can build over several days of regular dosing, making the first few days deceptively mild before full effects manifest."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 1500,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: - Buprenorphine

        Substance(
            name: "Buprenorphine",
            aliases: ["Subutex", "Suboxone", "Bupe", "Zubsolv"],
            category: .opioid,
            defaultRoute: .sublingual,
            routes: [
                SubstanceRoute(route: .sublingual, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...2, common: 2...4, strong: 4...8, heavy: 8, fatal: 64
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Mild euphoria", "Pain relief", "Anxiolysis", "Nausea", "Constipation", "Sedation", "Headache", "Sweating", "Respiratory depression", "Warmth"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Ceiling Effect Euphoria", description: "A mild, capped euphoria that reaches a plateau and does not increase with higher doses due to buprenorphine's partial agonist nature."),
                SubjectiveEffect(name: "Withdrawal Prevention", description: "A sense of normalcy and relief from opioid withdrawal symptoms, often described as feeling stable rather than high."),
                SubjectiveEffect(name: "Mild Warmth", description: "A subtle, gentle warmth less intense than full agonist opioids, providing comfort without the overwhelming body high."),
                SubjectiveEffect(name: "Anxiolysis", description: "Notable anxiety reduction that makes daily stressors feel manageable without the heavy sedation of full agonists."),
                SubjectiveEffect(name: "Headache", description: "A dull, persistent headache that is a common side effect, particularly when starting treatment or adjusting doses."),
                SubjectiveEffect(name: "Nausea", description: "Stomach discomfort and queasiness, especially during the first few days of use, that usually improves with continued dosing."),
                SubjectiveEffect(name: "Precipitated Withdrawal", description: "If taken too soon after a full agonist opioid, buprenorphine can trigger sudden, intense withdrawal symptoms due to its high receptor affinity displacing other opioids."),
                SubjectiveEffect(name: "Sweating", description: "Increased perspiration that is particularly noticeable at night and can persist as a chronic side effect."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 30, buildRate: "moderate"),
            halfLifeMinutes: 2160,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: - Tramadol

        Substance(
            name: "Tramadol",
            aliases: ["Ultram", "Tramal", "Zydol"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...300, heavy: 300, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Mild euphoria", "Pain relief", "Mood lift", "Anxiolysis", "Stimulation", "Nausea", "Dizziness", "Constipation", "Seizure risk", "Sweating"],
            subjectiveEffects: [
                SubjectiveEffect(name: "SNRI-Like Mood Lift", description: "A distinctive mood elevation with an antidepressant quality due to serotonin and norepinephrine reuptake inhibition, feeling more like an energizing uplift than a typical opioid high."),
                SubjectiveEffect(name: "Mild Stimulation", description: "A noticeable energizing effect at lower doses, with increased motivation and talkativeness that differentiates it from sedating opioids."),
                SubjectiveEffect(name: "Subtle Warmth", description: "A gentle body warmth less pronounced than classical opioids, providing comfort without heavy sedation."),
                SubjectiveEffect(name: "Pain Relief", description: "Moderate analgesic effect through dual mechanisms of opioid receptor activation and monoamine reuptake inhibition."),
                SubjectiveEffect(name: "Anxiolysis", description: "Reduction in anxiety through both opioid and serotonergic mechanisms, creating a calm but alert mental state."),
                SubjectiveEffect(name: "Dizziness", description: "A spinning or lightheaded sensation that is common especially at higher doses or when standing up quickly."),
                SubjectiveEffect(name: "Seizure Risk", description: "At high doses, tramadol lowers the seizure threshold significantly, and users may experience pre-seizure symptoms like muscle twitching or confusion."),
                SubjectiveEffect(name: "Nausea", description: "Frequent stomach upset and queasiness, partly from opioid effects and partly from serotonergic activity."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 4, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 390,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: - Tapentadol

        Substance(
            name: "Tapentadol",
            aliases: ["Nucynta", "Palexia"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...75, common: 75...150, strong: 150...250, heavy: 250, fatal: 600
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Euphoria", "Pain relief", "Sedation", "Warmth", "Anxiolysis", "Nausea", "Dizziness", "Constipation", "Respiratory depression", "Drowsiness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Dual-Mechanism Euphoria", description: "A warm euphoria with both opioid and noradrenergic qualities, feeling cleaner and more focused than pure mu-opioid agonists."),
                SubjectiveEffect(name: "Strong Pain Relief", description: "Potent analgesic effect comparable to oxycodone, with effective suppression of moderate to severe pain through dual action."),
                SubjectiveEffect(name: "Warm Sedation", description: "A comfortable drowsiness paired with body warmth, making relaxation and sleep feel effortless."),
                SubjectiveEffect(name: "Anxiolysis", description: "Noticeable anxiety reduction with a calm, settled mental state that does not feel as foggy as some other opioids."),
                SubjectiveEffect(name: "Dizziness", description: "Lightheadedness and occasional vertigo, particularly when changing positions or at higher doses."),
                SubjectiveEffect(name: "Nausea", description: "Stomach discomfort that is a frequent side effect, sometimes accompanied by vomiting during the first hours after dosing."),
                SubjectiveEffect(name: "Constipation", description: "Slowed gut motility leading to difficult bowel movements, consistent with its opioid mechanism of action."),
                SubjectiveEffect(name: "Respiratory Depression", description: "Dose-dependent reduction in breathing rate and depth that poses overdose risk, particularly when combined with other depressants."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 4, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 240,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: - Kratom

        Substance(
            name: "Kratom",
            aliases: ["Mitragyna speciosa", "Biak", "Ketum", "Thom"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "g", doses: DoseRange(
                    threshold: 1, light: 1...2, common: 2...4, strong: 4...6, heavy: 6, fatal: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Euphoria", "Pain relief", "Stimulation", "Sedation", "Mood lift", "Anxiolysis", "Nausea", "Constipation", "Wobbles", "Warmth"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Dose-Dependent Duality", description: "At low doses, a stimulating coffee-like energy and sociability; at higher doses, a warm, sedating opioid-like relaxation and euphoria."),
                SubjectiveEffect(name: "Mood Enhancement", description: "A notable brightening of mood and increased optimism, with enhanced sociability and desire to engage with others."),
                SubjectiveEffect(name: "Gentle Warmth", description: "A mild, pleasant body warmth that develops at moderate doses, less intense than pharmaceutical opioids but distinctly comforting."),
                SubjectiveEffect(name: "Pain Relief", description: "Moderate analgesic effects through partial opioid receptor activation, helpful for mild to moderate chronic pain."),
                SubjectiveEffect(name: "Stimulation", description: "At lower doses, increased physical energy, mental alertness, and motivation similar to a strong cup of coffee."),
                SubjectiveEffect(name: "Wobbles", description: "A distinctive side effect at higher doses involving eye jitteriness, nausea, and dizziness that signals overuse."),
                SubjectiveEffect(name: "Nausea", description: "Stomach upset that is common especially at higher doses, sometimes accompanied by the characteristic wobbles."),
                SubjectiveEffect(name: "Anxiolysis", description: "A calming effect on anxiety that makes social situations and stressful tasks feel more manageable."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 1380,
            sources: ["PsychonautWiki", "Erowid", "PubMed", "WHO"]
        ),

        // MARK: - O-DSMT

        Substance(
            name: "O-DSMT",
            aliases: ["O-Desmethyltramadol"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 15, light: 25...50, common: 50...100, strong: 100...150, heavy: 150, fatal: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Euphoria", "Pain relief", "Sedation", "Warmth", "Anxiolysis", "Nausea", "Constipation", "Itching", "Respiratory depression", "Dizziness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Classical Opioid Euphoria", description: "A warm, satisfying euphoria closely resembling tramadol's active metabolite effects but with greater intensity and more typical opioid character."),
                SubjectiveEffect(name: "Warm Body High", description: "A spreading warmth through the body that creates a comfortable, relaxed physical sensation."),
                SubjectiveEffect(name: "Pain Relief", description: "Effective analgesia through direct mu-opioid receptor agonism, stronger than tramadol for equivalent subjective effects."),
                SubjectiveEffect(name: "Sedation", description: "A pleasant drowsiness that increases with dose, making rest and sleep feel deeply appealing."),
                SubjectiveEffect(name: "Anxiolysis", description: "Notable reduction in anxiety and worry, with a calm mental state that persists through the duration."),
                SubjectiveEffect(name: "Itching", description: "Histamine-related skin itchiness typical of opioid receptor activation, indicating genuine opioid activity."),
                SubjectiveEffect(name: "Nausea", description: "Stomach upset common at higher doses or in those without tolerance to opioids."),
                SubjectiveEffect(name: "Dizziness", description: "Lightheadedness and occasional unsteadiness, particularly noticeable when first standing up."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 4, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 540,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: - Tianeptine

        Substance(
            name: "Tianeptine",
            aliases: ["Stablon", "Coaxil", "Tatinol"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 12.5, light: 25...50, common: 50...100, strong: 100...200, heavy: 200, fatal: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 120, max: 240)
                )),
            ],
            effects: ["Euphoria", "Mood lift", "Anxiolysis", "Pain relief", "Warmth", "Nausea", "Constipation", "Sweating", "Respiratory depression", "Irritability on withdrawal"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Antidepressant Euphoria", description: "A mood-brightening euphoria with an antidepressant quality at supratherapeutic doses, distinct from typical opioid warmth and more emotionally uplifting."),
                SubjectiveEffect(name: "Mood Stabilization", description: "At therapeutic doses, a leveling of mood swings and emotional reactivity, with increased emotional resilience."),
                SubjectiveEffect(name: "Anxiolysis", description: "Significant anxiety reduction through combined opioid and glutamatergic mechanisms, creating a calm, centered mental state."),
                SubjectiveEffect(name: "Subtle Warmth", description: "A mild body warmth at higher doses that indicates opioid receptor engagement, less intense than classical opioids."),
                SubjectiveEffect(name: "Pain Relief", description: "Moderate analgesic effects at supratherapeutic doses through mu-opioid receptor agonism."),
                SubjectiveEffect(name: "Withdrawal Irritability", description: "Abrupt cessation after regular use produces pronounced irritability, agitation, and emotional volatility that can be severe."),
                SubjectiveEffect(name: "Sweating", description: "Increased perspiration, particularly during dose escalation or when combining with physical activity."),
                SubjectiveEffect(name: "Rapid Tolerance", description: "Effects diminish quickly with repeated use, driving dose escalation and creating a cycle of increasing consumption."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 4, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 150,
            sources: ["PsychonautWiki", "PubMed", "DrugBank", "EMCDDA"]
        ),

        // MARK: - Meperidine

        Substance(
            name: "Meperidine",
            aliases: ["Demerol", "Pethidine"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...300, heavy: 300, fatal: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 120, max: 240)
                )),
            ],
            effects: ["Euphoria", "Pain relief", "Sedation", "Warmth", "Nausea", "Dizziness", "Constipation", "Respiratory depression", "Seizure risk", "Dry mouth"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Quick-Onset Euphoria", description: "A fast-acting euphoria with a stimulating edge, notably different from morphine in its energetic and almost giddy quality."),
                SubjectiveEffect(name: "Anticholinergic Effects", description: "Pronounced dry mouth, blurred vision, and urinary retention due to meperidine's unique anticholinergic properties."),
                SubjectiveEffect(name: "Pain Relief", description: "Moderate analgesia with a relatively short duration, requiring more frequent dosing than other opioids."),
                SubjectiveEffect(name: "Stimulating Warmth", description: "A warm body sensation paired with mild mental stimulation, creating a unique combination among opioids."),
                SubjectiveEffect(name: "Dizziness", description: "Notable lightheadedness and vertigo, especially when standing or changing positions rapidly."),
                SubjectiveEffect(name: "Nausea", description: "Significant nausea that is more common with meperidine than many other opioids, often accompanied by sweating."),
                SubjectiveEffect(name: "Seizure Risk", description: "Accumulation of the neurotoxic metabolite normeperidine can cause tremors, myoclonus, and seizures with repeated dosing."),
                SubjectiveEffect(name: "Short Duration", description: "Effects fade within 2-3 hours, notably shorter than most other opioids, necessitating frequent redosing."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 4, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 210,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: - Dihydrocodeine

        Substance(
            name: "Dihydrocodeine",
            aliases: ["DHC", "DF-118", "Paracodin"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 15, light: 30...60, common: 60...90, strong: 90...150, heavy: 150, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Euphoria", "Pain relief", "Sedation", "Warmth", "Relaxation", "Nausea", "Constipation", "Itching", "Respiratory depression", "Drowsiness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Moderate Euphoria", description: "A pleasant warmth and mood elevation slightly stronger than codeine, with a smooth, comfortable quality to the high."),
                SubjectiveEffect(name: "Pain Relief", description: "Effective moderate analgesia that sits between codeine and morphine in potency, providing reliable pain control."),
                SubjectiveEffect(name: "Gentle Sedation", description: "A calm drowsiness that is less overwhelming than stronger opioids, making it suitable for relaxation without total incapacitation."),
                SubjectiveEffect(name: "Body Warmth", description: "A pleasant warmth spreading through the torso and extremities, creating a comfortable, cozy sensation."),
                SubjectiveEffect(name: "Relaxation", description: "Both physical and mental relaxation, with muscle tension easing and a general sense of calm settling in."),
                SubjectiveEffect(name: "Itching", description: "Mild to moderate skin itchiness, particularly on the face and nose, from histamine release."),
                SubjectiveEffect(name: "Nausea", description: "Stomach upset that is common at higher doses, sometimes accompanied by dizziness."),
                SubjectiveEffect(name: "Drowsiness", description: "A sleepy, heavy-eyed feeling that builds over the duration and makes napping feel inviting."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 4, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 240,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: - Poppy Seed Tea

        Substance(
            name: "Poppy Seed Tea",
            aliases: ["PST", "Poppy Tea"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "g", doses: DoseRange(
                    threshold: 20, light: 40...100, common: 100...200, strong: 200...400, heavy: 400, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 180, max: 480),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 480, max: 960)
                )),
            ],
            effects: ["Euphoria", "Pain relief", "Sedation", "Warmth", "Nodding", "Nausea", "Constipation", "Itching", "Respiratory depression", "Unpredictable potency"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Morphine-Like Euphoria", description: "A full-spectrum opioid euphoria resembling morphine's profile due to the tea containing a mixture of natural opium alkaloids."),
                SubjectiveEffect(name: "Unpredictable Intensity", description: "Potency varies dramatically between batches, making each preparation a gamble that can range from barely active to dangerously strong."),
                SubjectiveEffect(name: "Long Duration", description: "Effects can persist for 8-12 hours or longer due to the mix of alkaloids with varying half-lives, including codeine, morphine, and thebaine."),
                SubjectiveEffect(name: "Warm Sedation", description: "A deep, enveloping warmth paired with heavy sedation, characteristic of the full opium alkaloid profile."),
                SubjectiveEffect(name: "Nodding", description: "Drifting in and out of a dreamlike drowsy state, often more prolonged than with pure morphine due to multiple alkaloids."),
                SubjectiveEffect(name: "Pain Relief", description: "Broad-spectrum analgesia from the combined action of multiple opioid alkaloids present in the tea."),
                SubjectiveEffect(name: "Nausea", description: "Significant nausea common with opium preparations, sometimes severe enough to cause vomiting."),
                SubjectiveEffect(name: "Itching", description: "Diffuse skin itchiness from histamine release triggered by the morphine and codeine content."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 4, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - Loperamide

        Substance(
            name: "Loperamide",
            aliases: ["Imodium", "Loperamide HCl"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 2...4, common: 4...8, strong: 8...16, heavy: 16, fatal: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 960)
                )),
            ],
            effects: ["Anti-diarrheal effect", "Constipation", "Abdominal cramps", "Nausea", "Bloating", "Dizziness", "Cardiac arrhythmia risk at high doses"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Peripheral Opioid Action", description: "At normal doses, effects are confined to the gut with no CNS euphoria, as loperamide does not cross the blood-brain barrier in significant amounts."),
                SubjectiveEffect(name: "Anti-Diarrheal Effect", description: "Effective slowing of intestinal motility, reducing stool frequency and urgency within 1-2 hours of dosing."),
                SubjectiveEffect(name: "Constipation", description: "At therapeutic doses, can cause excessive slowing of bowel function leading to uncomfortable constipation."),
                SubjectiveEffect(name: "Abdominal Discomfort", description: "Cramping, bloating, and a feeling of fullness in the abdomen from reduced gut motility."),
                SubjectiveEffect(name: "Cardiac Risk at High Doses", description: "At massively supratherapeutic doses taken to overcome the blood-brain barrier, serious cardiac arrhythmias and QT prolongation can occur, potentially fatal."),
                SubjectiveEffect(name: "Minimal Withdrawal Relief", description: "At very high doses, some users report mild relief from opioid withdrawal symptoms, though this comes with extreme cardiac danger."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 4, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 660,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: - U-47700

        Substance(
            name: "U-47700",
            aliases: ["Pink", "U4", "U-4"],
            category: .opioid,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 7.5...15, common: 15...25, strong: 25...40, heavy: 40, fatal: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 120, max: 240)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 3...7.5, common: 7.5...15, strong: 15...25, heavy: 25, fatal: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 120, max: 240)
                )),
            ],
            effects: ["Intense euphoria", "Pain relief", "Sedation", "Warmth", "Rush", "Nausea", "Respiratory depression", "Itching", "Caustic to nasal tissue", "Short duration"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Intense Rush", description: "A powerful, fast-onset wave of euphoria when insufflated that hits hard but fades relatively quickly."),
                SubjectiveEffect(name: "Potent Euphoria", description: "A strong opioid euphoria comparable to hydromorphone, with a warm, enveloping quality that is highly reinforcing."),
                SubjectiveEffect(name: "Nasal Tissue Damage", description: "Severe caustic burning in the nasal passages when insufflated, often causing lasting damage, bleeding, and scabbing with repeated use."),
                SubjectiveEffect(name: "Short Duration", description: "Effects last only 1-2 hours, driving compulsive redosing and increasing the risk of dose escalation."),
                SubjectiveEffect(name: "Sedation", description: "Heavy drowsiness that sets in during the tail end of the experience as the initial rush subsides."),
                SubjectiveEffect(name: "Warmth", description: "A brief but intense body warmth concentrated in the chest and abdomen during the peak."),
                SubjectiveEffect(name: "Respiratory Depression", description: "Significant respiratory depression that can onset rapidly, particularly dangerous given the short duration encouraging redosing."),
                SubjectiveEffect(name: "Nausea", description: "Pronounced nausea common at higher doses, sometimes severe enough to cause vomiting."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 4, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 210,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: - Mitragynine

        Substance(
            name: "Mitragynine",
            aliases: ["Mitragynine extract", "Kratom alkaloid"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...50, strong: 50...100, heavy: 100, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Euphoria", "Pain relief", "Stimulation", "Sedation", "Mood lift", "Anxiolysis", "Nausea", "Constipation", "Wobbles", "Warmth"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Dose-Dependent Stimulation/Sedation", description: "As the primary active alkaloid in kratom, produces stimulation at low doses and sedation at high doses, mirroring the whole-plant experience."),
                SubjectiveEffect(name: "Mood Enhancement", description: "A bright, optimistic mood elevation with increased sociability and emotional warmth toward others."),
                SubjectiveEffect(name: "Mild Opioid Warmth", description: "A gentle, pleasant warmth at moderate to high doses from partial mu-opioid receptor agonism."),
                SubjectiveEffect(name: "Pain Relief", description: "Moderate analgesic effects through opioid receptor activation, useful for chronic pain management at higher doses."),
                SubjectiveEffect(name: "Anxiolysis", description: "A calming reduction in anxiety that makes social interactions and daily tasks feel less stressful."),
                SubjectiveEffect(name: "Wobbles", description: "A disorienting combination of eye jitteriness, nausea, and dizziness at excessive doses, signaling that the dose was too high."),
                SubjectiveEffect(name: "Nausea", description: "Stomach upset that is common at higher doses, serving as a natural ceiling that discourages dose escalation."),
                SubjectiveEffect(name: "Physical Energy", description: "At low doses, noticeable increase in physical stamina and motivation, traditionally used by laborers for sustained work."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 1380,
            sources: ["PsychonautWiki", "Erowid", "PubMed", "WHO"]
        ),

        // MARK: - 2-Methyl-AP-237

        Substance(
            name: "2-Methyl-AP-237",
            aliases: ["2-MAP-237", "2MAP"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60, fatal: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 30, max: 90),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 120, max: 240)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...15, common: 15...25, strong: 25...40, heavy: 40, fatal: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 2, max: 5),
                    comeup: TimeRange(min: 3, max: 10),
                    peak: TimeRange(min: 15, max: 45),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 90, max: 180)
                )),
            ],
            effects: ["Euphoria", "Pain relief", "Sedation", "Warmth", "Rush", "Nausea", "Respiratory depression", "Caustic to nasal tissue", "Short duration", "Constipation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Fast-Onset Rush", description: "A rapid wave of euphoria when insufflated, hitting within minutes with a warm, pleasurable peak."),
                SubjectiveEffect(name: "Caustic Nasal Burn", description: "Severe burning and irritation of nasal tissues when insufflated, often causing lasting damage with repeated use and described as one of the most caustic opioids available."),
                SubjectiveEffect(name: "Short Duration", description: "Effects last only 1-3 hours, leading to compulsive redosing and increased risk of adverse effects."),
                SubjectiveEffect(name: "Warm Euphoria", description: "A classic opioid warmth and euphoria during the brief peak, satisfying but fleeting."),
                SubjectiveEffect(name: "Sedation", description: "Drowsiness that intensifies as the short-lived euphoria wears off, leaving heavy-limbed fatigue."),
                SubjectiveEffect(name: "Respiratory Depression", description: "Significant breathing suppression that is dangerous given the temptation to redose frequently."),
                SubjectiveEffect(name: "Nausea", description: "Stomach upset that can be severe, especially with the rapid onset of insufflated doses."),
                SubjectiveEffect(name: "Constipation", description: "Typical opioid-induced gut slowing that occurs with repeated use."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 4, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 90,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: - Brorphine

        Substance(
            name: "Brorphine",
            aliases: ["Brorphine HCl"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...10, strong: 10...20, heavy: 20, fatal: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 20),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 120, max: 180)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 1...3, common: 3...7, strong: 7...12, heavy: 12, fatal: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 3, max: 10),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 120, max: 180)
                )),
            ],
            effects: ["Euphoria", "Pain relief", "Sedation", "Warmth", "Respiratory depression", "Nausea", "Constipation", "Itching", "Nodding", "Short duration"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Potent Euphoria", description: "A strong, classical opioid euphoria with notable warmth and contentment, punching above its weight relative to dose."),
                SubjectiveEffect(name: "Rapid Onset", description: "Quick onset of effects, particularly via insufflation, with the peak arriving faster than many other opioids."),
                SubjectiveEffect(name: "Heavy Sedation", description: "Pronounced drowsiness and physical heaviness that makes staying active difficult during the peak."),
                SubjectiveEffect(name: "Nodding", description: "Semiconscious drifting between wakefulness and dreamlike states, characteristic of strong opioid intoxication."),
                SubjectiveEffect(name: "Short Duration", description: "Effects fade within 2-3 hours, creating a pattern of frequent redosing that increases overdose risk."),
                SubjectiveEffect(name: "Warmth", description: "A spreading body warmth that accompanies the euphoric peak, concentrated in the core."),
                SubjectiveEffect(name: "Respiratory Depression", description: "Significant suppression of breathing rate that is a primary overdose concern with this potent compound."),
                SubjectiveEffect(name: "Itching", description: "Histamine-mediated skin itchiness common with opioid receptor activation."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 4, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: - Etazene

        Substance(
            name: "Etazene",
            aliases: ["Etodesnitazene", "Etazene HCl"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...10, strong: 10...15, heavy: 15, fatal: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 20),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 180, max: 360)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 1...3, common: 3...5, strong: 5...10, heavy: 10, fatal: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Intense euphoria", "Pain relief", "Sedation", "Warmth", "Nodding", "Respiratory depression", "Nausea", "Constipation", "Itching", "High potency"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Powerful Euphoria", description: "An intense opioid euphoria from the benzimidazole class, with strong warmth and contentment at very low doses."),
                SubjectiveEffect(name: "High Potency", description: "Active in single-digit milligram doses, requiring precise measurement and carrying extreme overdose risk from small dosing errors."),
                SubjectiveEffect(name: "Deep Sedation", description: "Overwhelming drowsiness that can incapacitate at moderate doses, with difficulty maintaining consciousness."),
                SubjectiveEffect(name: "Nodding", description: "Pronounced semiconscious drifting characteristic of potent opioid intoxication."),
                SubjectiveEffect(name: "Pain Obliteration", description: "Powerful analgesic effects that suppress even severe pain at milligram doses."),
                SubjectiveEffect(name: "Warmth", description: "Intense radiating body warmth concentrated in the chest and spreading outward."),
                SubjectiveEffect(name: "Respiratory Depression", description: "Severe respiratory depression that onset rapidly, making this one of the more dangerous novel opioids."),
                SubjectiveEffect(name: "Nausea", description: "Strong nausea and vomiting risk, particularly in those without significant opioid tolerance."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 4, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 300,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: - Isotonitazene

        Substance(
            name: "Isotonitazene",
            aliases: ["Iso", "ISO"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "\u{00B5}g", doses: DoseRange(
                    threshold: 2, light: 5...10, common: 10...25, strong: 25...50, heavy: 50, fatal: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 20),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 180, max: 360)
                )),
                SubstanceRoute(route: .insufflation, unit: "\u{00B5}g", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...15, strong: 15...30, heavy: 30, fatal: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Intense euphoria", "Pain relief", "Sedation", "Warmth", "Nodding", "Respiratory depression", "Nausea", "Constipation", "Itching", "Extremely high potency"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Extreme Potency", description: "Active in microgram quantities, making it one of the most potent opioids known, with an enormous overdose risk from even tiny measurement errors."),
                SubjectiveEffect(name: "Overwhelming Euphoria", description: "An extraordinarily intense opioid euphoria that can be incapacitating, with total body warmth and bliss."),
                SubjectiveEffect(name: "Rapid Incapacitation", description: "The high potency means even slight overdoses can render a person unconscious within minutes, often before help can be sought."),
                SubjectiveEffect(name: "Profound Sedation", description: "Extreme drowsiness that rapidly transitions to unconsciousness at doses only slightly above the therapeutic range."),
                SubjectiveEffect(name: "Nodding", description: "Deep, prolonged semiconscious states with minimal awareness of surroundings."),
                SubjectiveEffect(name: "Warmth", description: "An intense flush of body warmth that accompanies the onset of effects."),
                SubjectiveEffect(name: "Severe Respiratory Depression", description: "Life-threatening respiratory depression that onsets rapidly and is the leading cause of fatalities, often requiring multiple doses of naloxone to reverse."),
                SubjectiveEffect(name: "Naloxone Resistance", description: "May require higher or repeated doses of naloxone to reverse compared to other opioids due to extreme receptor binding affinity."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 4, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 360,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: - AP-237

        Substance(
            name: "AP-237",
            aliases: ["Bucinnazine", "AP237"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 15...30, common: 30...50, strong: 50...80, heavy: 80, fatal: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 30, max: 90),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 120, max: 240)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...35, strong: 35...50, heavy: 50, fatal: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 2, max: 5),
                    comeup: TimeRange(min: 3, max: 10),
                    peak: TimeRange(min: 15, max: 45),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 90, max: 180)
                )),
            ],
            effects: ["Euphoria", "Pain relief", "Sedation", "Warmth", "Rush", "Nausea", "Respiratory depression", "Caustic to nasal tissue", "Short duration", "Constipation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Moderate Euphoria", description: "A classical opioid euphoria that is warm and pleasant but generally considered less intense than the related 2-MAP-237."),
                SubjectiveEffect(name: "Caustic Nasal Irritation", description: "Significant burning and irritation of nasal passages when insufflated, though reported as somewhat less caustic than 2-MAP-237."),
                SubjectiveEffect(name: "Short to Moderate Duration", description: "Effects last approximately 2-4 hours, shorter than many pharmaceutical opioids but slightly longer than some research chemicals."),
                SubjectiveEffect(name: "Rush", description: "A noticeable onset rush when insufflated, with a wave of warmth and euphoria building over several minutes."),
                SubjectiveEffect(name: "Warm Sedation", description: "A comfortable drowsiness paired with body warmth, becoming more pronounced as the experience progresses."),
                SubjectiveEffect(name: "Pain Relief", description: "Moderate analgesic effects through mu-opioid receptor agonism."),
                SubjectiveEffect(name: "Respiratory Depression", description: "Dose-dependent breathing suppression that carries overdose risk, particularly with redosing."),
                SubjectiveEffect(name: "Nausea", description: "Stomach discomfort common at higher doses, consistent with opioid receptor activation in the brainstem."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 4, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 90,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: - Nalbuphine

        Substance(
            name: "Nalbuphine",
            aliases: ["Nubain"],
            category: .opioid,
            defaultRoute: .intramuscular,
            routes: [
                SubstanceRoute(route: .intramuscular, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...15, strong: 15...20, heavy: 20, fatal: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 180, max: 360)
                )),
                SubstanceRoute(route: .intravenous, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 3...5, common: 5...10, strong: 10...20, heavy: 20, fatal: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 2, max: 5),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Pain relief", "Sedation", "Mild euphoria", "Dizziness", "Nausea", "Sweating", "Respiratory depression", "Dysphoria at high doses", "Warmth"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mixed Agonist-Antagonist Effects", description: "A unique subjective profile as a kappa agonist and mu antagonist, producing pain relief with limited euphoria and a ceiling on respiratory depression."),
                SubjectiveEffect(name: "Mild Warmth", description: "A subtle body warmth less intense than full mu-agonists, providing comfort without the overwhelming body high."),
                SubjectiveEffect(name: "Limited Euphoria", description: "Mild mood elevation that is significantly less reinforcing than full agonist opioids, making abuse potential lower."),
                SubjectiveEffect(name: "Dysphoria at High Doses", description: "Increasing kappa receptor activation at higher doses produces unpleasant feelings of unease, anxiety, and emotional discomfort."),
                SubjectiveEffect(name: "Sedation", description: "Moderate drowsiness that helps with pain-related sleep disturbance."),
                SubjectiveEffect(name: "Dizziness", description: "Noticeable lightheadedness and vertigo, more pronounced than with many pure mu-agonists."),
                SubjectiveEffect(name: "Sweating", description: "Increased perspiration that can be uncomfortable, related to kappa opioid receptor activation."),
                SubjectiveEffect(name: "Nausea", description: "Stomach upset that is a common side effect, sometimes persistent throughout the duration."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 300,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: - Pentazocine

        Substance(
            name: "Pentazocine",
            aliases: ["Talwin", "Fortral"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 12.5, light: 25...50, common: 50...100, strong: 100...150, heavy: 150, fatal: 600
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 90),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 180, max: 240)
                )),
            ],
            effects: ["Pain relief", "Sedation", "Mild euphoria", "Dysphoria at high doses", "Dizziness", "Nausea", "Sweating", "Respiratory depression", "Psychotomimetic effects"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mixed Agonist Profile", description: "As a kappa agonist and weak mu agonist, produces a distinctive subjective experience that differs markedly from pure mu-opioids."),
                SubjectiveEffect(name: "Psychotomimetic Effects", description: "At higher doses, kappa activation can produce disturbing perceptual distortions, depersonalization, and feelings of unreality."),
                SubjectiveEffect(name: "Mild Pain Relief", description: "Moderate analgesia that is effective for mild to moderate pain but with a ceiling effect on maximum relief."),
                SubjectiveEffect(name: "Dysphoria", description: "Unpleasant emotional states including anxiety, restlessness, and a sense of wrongness that can emerge at higher doses due to kappa activation."),
                SubjectiveEffect(name: "Sedation", description: "Drowsiness and fatigue that is common at therapeutic doses, making it useful for pain-related insomnia."),
                SubjectiveEffect(name: "Dizziness", description: "Pronounced lightheadedness and vertigo, more common with pentazocine than with full mu-agonists."),
                SubjectiveEffect(name: "Sweating", description: "Uncomfortable perspiration related to the kappa opioid component of its pharmacology."),
                SubjectiveEffect(name: "Nausea", description: "Frequent stomach upset that can be persistent and bothersome throughout the duration."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 150,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: - Butorphanol

        Substance(
            name: "Butorphanol",
            aliases: ["Stadol", "Stadol NS"],
            category: .opioid,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1, common: 1...2, strong: 2...3, heavy: 3, fatal: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 120, max: 240)
                )),
            ],
            effects: ["Pain relief", "Sedation", "Mild euphoria", "Dizziness", "Nausea", "Drowsiness", "Respiratory depression", "Dysphoria at high doses", "Sweating"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Rapid Nasal Onset", description: "Fast-acting effects when administered via nasal spray, with onset within minutes and peak effects occurring quickly."),
                SubjectiveEffect(name: "Dissociative-Like Quality", description: "A unique dreamy, somewhat detached quality to the high due to kappa opioid receptor agonism, distinct from typical opioid warmth."),
                SubjectiveEffect(name: "Moderate Pain Relief", description: "Effective analgesia with a ceiling effect, particularly useful for migraine and acute pain via the nasal spray formulation."),
                SubjectiveEffect(name: "Sedation", description: "Notable drowsiness that makes driving and operating machinery dangerous, with a strong desire to lie down and rest."),
                SubjectiveEffect(name: "Dizziness", description: "Pronounced lightheadedness and vertigo that is one of the most commonly reported side effects."),
                SubjectiveEffect(name: "Dysphoria at High Doses", description: "Increasing doses activate kappa receptors more strongly, producing unpleasant feelings of anxiety, unease, and emotional distress."),
                SubjectiveEffect(name: "Nausea", description: "Stomach queasiness that is common, especially with the initial dose or dose increases."),
                SubjectiveEffect(name: "Sweating", description: "Increased perspiration related to kappa opioid receptor stimulation."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 200,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),
    ]
}
