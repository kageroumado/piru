import Foundation

extension SubstanceLibrary {
    // swiftlint:disable function_body_length
    static let cannabinoids: [Substance] = [

        // MARK: - 1. THC (Delta-9-THC)

        Substance(
            name: "THC",
            aliases: ["Delta-9-THC", "Cannabis", "Weed", "Marijuana", "Pot", "Dope", "Ganja", "Herb"],
            category: .cannabinoid,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...15, strong: 15...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 2),
                    comeup: TimeRange(min: 2, max: 5),
                    peak: TimeRange(min: 15, max: 45),
                    offset: TimeRange(min: 45, max: 90),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 60, max: 180)
                )),
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 2.5...5, common: 5...15, strong: 15...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 90),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 240, max: 720),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: [
                "Euphoria", "Relaxation", "Appetite increase", "Time distortion",
                "Giggles", "Dry mouth", "Red eyes", "Anxiety", "Paranoia", "Music enhancement",
            ],
            subjectiveEffects: [
                SubjectiveEffect(name: "Altered time perception", description: "Time feels dramatically slowed down, with minutes seeming to stretch into much longer periods."),
                SubjectiveEffect(name: "Creative enhancement", description: "Thoughts become more associative and divergent, with novel ideas and connections arising more easily."),
                SubjectiveEffect(name: "Appetite stimulation", description: "An intense increase in hunger commonly known as the munchies, with food tasting and smelling more appealing."),
                SubjectiveEffect(name: "Music appreciation enhancement", description: "Music sounds richer, more layered, and emotionally resonant, with heightened perception of individual instruments and rhythms."),
                SubjectiveEffect(name: "Giggles", description: "An irrepressible tendency to find things humorous, with laughter coming easily and frequently at even mildly funny stimuli."),
                SubjectiveEffect(name: "Physical relaxation", description: "Muscles loosen and physical tension dissolves, often accompanied by a warm, heavy sensation throughout the body."),
                SubjectiveEffect(name: "Anxiety and paranoia", description: "Racing thoughts, social self-consciousness, and unfounded fears can emerge, particularly at higher doses or in unfamiliar settings."),
                SubjectiveEffect(name: "Short-term memory impairment", description: "Difficulty retaining new information and following trains of thought, often forgetting what was just said or done."),
                SubjectiveEffect(name: "Sensory enhancement", description: "Colors may appear more vivid, textures more detailed, and flavors more complex and enjoyable."),
                SubjectiveEffect(name: "Introspective thinking", description: "Thoughts may turn inward toward self-examination, sometimes revealing new perspectives on personal matters."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 28, buildRate: "moderate"),
            halfLifeMinutes: 120
        ),

        // MARK: - 2. Delta-8-THC

        Substance(
            name: "Delta-8-THC",
            aliases: ["D8", "Delta-8"],
            category: .cannabinoid,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 3...8, common: 8...20, strong: 20...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.5, max: 3),
                    comeup: TimeRange(min: 3, max: 8),
                    peak: TimeRange(min: 15, max: 45),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 60, max: 150)
                )),
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 5...10, common: 10...25, strong: 25...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 90),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 90, max: 180),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 240, max: 420)
                )),
            ],
            effects: [
                "Mild euphoria", "Relaxation", "Appetite increase", "Dry mouth",
                "Red eyes", "Clear-headedness", "Reduced anxiety", "Pain relief",
                "Drowsiness", "Time distortion",
            ],
            subjectiveEffects: [
                SubjectiveEffect(name: "Clear-headed high", description: "A milder, more lucid intoxication than Delta-9-THC, with less mental fog and reduced likelihood of anxiety."),
                SubjectiveEffect(name: "Gentle relaxation", description: "A smooth, calming body relaxation that feels less intense and more manageable than traditional THC."),
                SubjectiveEffect(name: "Reduced anxiety", description: "Less prone to causing paranoia or anxiety compared to Delta-9-THC, often described as a more comfortable high."),
                SubjectiveEffect(name: "Mild euphoria", description: "A subtle but pleasant mood elevation that feels lighter and less overwhelming than Delta-9-THC."),
                SubjectiveEffect(name: "Pain relief", description: "Moderate analgesic effects that reduce discomfort without the intense psychoactive effects of stronger cannabinoids."),
                SubjectiveEffect(name: "Appetite stimulation", description: "Increased hunger similar to Delta-9-THC but often reported as less intense."),
                SubjectiveEffect(name: "Drowsiness", description: "A gentle sleepiness that can develop, especially at higher doses, promoting relaxation and rest."),
                SubjectiveEffect(name: "Mild time distortion", description: "A slight alteration in time perception, less pronounced than with Delta-9-THC."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 28, buildRate: "moderate"),
            halfLifeMinutes: 120
        ),

        // MARK: - 3. CBD (Cannabidiol)

        Substance(
            name: "CBD",
            aliases: ["Cannabidiol"],
            category: .cannabinoid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...25, common: 25...75, strong: 75...150, heavy: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 480)
                )),
                SubstanceRoute(route: .sublingual, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 5...20, common: 20...50, strong: 50...100, heavy: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: [
                "Anxiety relief", "Relaxation", "Pain relief", "Anti-inflammation",
                "Improved sleep", "Muscle relaxation", "Reduced stress", "Clarity",
            ],
            subjectiveEffects: [
                SubjectiveEffect(name: "Subtle calm", description: "A gentle sense of relaxation and well-being without any intoxication or impairment of cognition."),
                SubjectiveEffect(name: "Anxiety relief", description: "Anxious thoughts and tension gradually diminish, replaced by a quiet sense of ease and stability."),
                SubjectiveEffect(name: "Physical relaxation", description: "Muscle tension eases and the body feels more comfortable, without the heavy sedation of THC."),
                SubjectiveEffect(name: "Mental clarity", description: "Unlike THC, CBD promotes clear thinking and focus, sometimes described as removing a background hum of stress."),
                SubjectiveEffect(name: "Pain modulation", description: "Chronic pain and inflammation become more manageable, with a gradual reduction in discomfort over time."),
                SubjectiveEffect(name: "Improved sleep quality", description: "Sleep onset and maintenance may improve, with a calmer transition into rest without next-day grogginess."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 14, buildRate: "slow"),
            halfLifeMinutes: 1500
        ),

        // MARK: - 4. CBN (Cannabinol)

        Substance(
            name: "CBN",
            aliases: ["Cannabinol"],
            category: .cannabinoid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 2.5...5, common: 5...10, strong: 10...25, heavy: 25
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 180),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 420)
                )),
            ],
            effects: [
                "Sedation", "Drowsiness", "Relaxation", "Pain relief",
                "Appetite increase", "Muscle relaxation", "Improved sleep",
                "Mild euphoria",
            ],
            subjectiveEffects: [
                SubjectiveEffect(name: "Sedation", description: "A pronounced drowsiness and heaviness that strongly promotes sleep, making it primarily useful as a nighttime supplement."),
                SubjectiveEffect(name: "Physical relaxation", description: "Deep muscular relaxation that helps the body feel loose and comfortable, ideal for winding down."),
                SubjectiveEffect(name: "Sleep promotion", description: "A strong pull toward sleep that helps with both sleep onset and staying asleep throughout the night."),
                SubjectiveEffect(name: "Mild euphoria", description: "A very subtle, warm sense of well-being that accompanies the sedative effects without significant intoxication."),
                SubjectiveEffect(name: "Pain relief", description: "Moderate analgesic effects that complement the sedation, making it easier to rest comfortably despite discomfort."),
                SubjectiveEffect(name: "Appetite increase", description: "A mild stimulation of hunger, particularly noticeable in the evening hours."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "slow"),
            halfLifeMinutes: 180
        ),

        // MARK: - 5. CBG (Cannabigerol)

        Substance(
            name: "CBG",
            aliases: ["Cannabigerol"],
            category: .cannabinoid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...25, common: 25...50, strong: 50...100, heavy: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 480)
                )),
            ],
            effects: [
                "Focus enhancement", "Anti-inflammation", "Pain relief",
                "Appetite increase", "Relaxation", "Reduced anxiety",
                "Neuroprotection", "Antibacterial",
            ],
            subjectiveEffects: [
                SubjectiveEffect(name: "Gentle focus", description: "A mild improvement in concentration and mental clarity without any intoxicating effects."),
                SubjectiveEffect(name: "Reduced anxiety", description: "A subtle calming effect that eases nervous tension without sedation or cognitive impairment."),
                SubjectiveEffect(name: "Anti-inflammatory comfort", description: "Gradual reduction in inflammatory discomfort, particularly noticeable with consistent use over time."),
                SubjectiveEffect(name: "Mild relaxation", description: "A gentle easing of tension in body and mind, promoting a sense of baseline well-being."),
                SubjectiveEffect(name: "Appetite modulation", description: "A mild increase in appetite, though less pronounced than with THC or CBN."),
                SubjectiveEffect(name: "Pain relief", description: "Subtle analgesic effects that help take the edge off chronic pain and discomfort."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 14, buildRate: "slow"),
            halfLifeMinutes: 150
        ),

        // MARK: - 6. THCV (Tetrahydrocannabivarin)

        Substance(
            name: "THCV",
            aliases: ["Tetrahydrocannabivarin"],
            category: .cannabinoid,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...10, strong: 10...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.5, max: 3),
                    comeup: TimeRange(min: 3, max: 8),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 20, max: 40),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 45, max: 90)
                )),
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 5...10, common: 10...25, strong: 25...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 120, max: 240)
                )),
            ],
            effects: [
                "Stimulation", "Euphoria", "Appetite suppression", "Focus enhancement",
                "Energetic high", "Clear-headedness", "Time distortion",
                "Dry mouth", "Anxiety",
            ],
            subjectiveEffects: [
                SubjectiveEffect(name: "Energetic high", description: "A stimulating, uplifting experience that feels more activating than traditional THC, promoting activity and engagement."),
                SubjectiveEffect(name: "Appetite suppression", description: "Unlike most cannabinoids, THCV tends to reduce hunger rather than stimulate it, at least at lower doses."),
                SubjectiveEffect(name: "Clear-headed stimulation", description: "Mental clarity is maintained or enhanced, with a focused, sharp quality to the high."),
                SubjectiveEffect(name: "Short duration", description: "Effects wear off faster than traditional THC, typically lasting about half as long."),
                SubjectiveEffect(name: "Euphoria", description: "A bright, uplifting mood elevation that feels energetic rather than sedating or dreamy."),
                SubjectiveEffect(name: "Focus enhancement", description: "Concentration and task engagement may improve, making this more functional than typical THC."),
                SubjectiveEffect(name: "Anxiety potential", description: "The stimulating nature can occasionally produce anxiety or restlessness in sensitive individuals."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 90
        ),

        // MARK: - 7. HHC (Hexahydrocannabinol)

        Substance(
            name: "HHC",
            aliases: ["Hexahydrocannabinol"],
            category: .cannabinoid,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 3...8, common: 8...20, strong: 20...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.5, max: 3),
                    comeup: TimeRange(min: 3, max: 8),
                    peak: TimeRange(min: 15, max: 45),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 60, max: 150)
                )),
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 5...15, common: 15...30, strong: 30...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 90),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 90, max: 180),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 240, max: 420)
                )),
            ],
            effects: [
                "Euphoria", "Relaxation", "Pain relief", "Appetite increase",
                "Dry mouth", "Red eyes", "Giggles", "Time distortion",
                "Drowsiness", "Anxiety",
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 28, buildRate: "moderate"),
            halfLifeMinutes: 120
        ),

        // MARK: - 8. THCO (THC-O-Acetate)

        Substance(
            name: "THCO",
            aliases: ["THC-O-Acetate", "THC-O"],
            category: .cannabinoid,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 1...3, common: 3...10, strong: 10...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 120, max: 240)
                )),
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...15, strong: 15...25, heavy: 25
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 300, max: 540)
                )),
            ],
            effects: [
                "Intense euphoria", "Psychedelic-like visuals", "Deep relaxation",
                "Spiritual experiences", "Time distortion", "Dry mouth",
                "Paranoia", "Anxiety", "Sedation", "Appetite increase",
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 28, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: - 9. THCP (Tetrahydrocannabiphorol)

        Substance(
            name: "THCP",
            aliases: ["Tetrahydrocannabiphorol"],
            category: .cannabinoid,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "mcg", doses: DoseRange(
                    threshold: 50, light: 100...250, common: 250...500, strong: 500...1000, heavy: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.5, max: 3),
                    comeup: TimeRange(min: 3, max: 10),
                    peak: TimeRange(min: 30, max: 90),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 120, max: 300)
                )),
                SubstanceRoute(route: .oral, unit: "mcg", doses: DoseRange(
                    threshold: 100, light: 150...300, common: 300...750, strong: 750...1500, heavy: 1500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 90),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 300),
                    offset: TimeRange(min: 120, max: 300),
                    afterglow: TimeRange(min: 240, max: 720),
                    total: TimeRange(min: 360, max: 660)
                )),
            ],
            effects: [
                "Intense euphoria", "Heavy sedation", "Strong pain relief",
                "Appetite increase", "Dry mouth", "Red eyes", "Paranoia",
                "Time distortion", "Couch lock", "Anxiety",
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 28, buildRate: "rapid"),
            halfLifeMinutes: 240
        ),

        // MARK: - 10. THCa (Tetrahydrocannabinolic acid)

        Substance(
            name: "THCa",
            aliases: ["Tetrahydrocannabinolic acid", "THCA"],
            category: .cannabinoid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 25...50, common: 50...200, strong: 200...500, heavy: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 480)
                )),
            ],
            effects: [
                "Anti-inflammation", "Nausea relief", "Pain relief",
                "Neuroprotection", "Appetite modulation", "Reduced muscle spasms",
                "Mild relaxation", "No intoxication",
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 14, buildRate: "slow"),
            halfLifeMinutes: 180
        ),

        // MARK: - 11. HHCO (HHC-O-Acetate)

        Substance(
            name: "HHCO",
            aliases: ["HHC-O-Acetate", "HHC-O"],
            category: .cannabinoid,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...15, strong: 15...25, heavy: 25
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 120, max: 240)
                )),
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 3...8, common: 8...20, strong: 20...35, heavy: 35
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 300, max: 540)
                )),
            ],
            effects: [
                "Intense euphoria", "Deep relaxation", "Sedation",
                "Pain relief", "Dry mouth", "Red eyes", "Time distortion",
                "Appetite increase", "Paranoia", "Couch lock",
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 28, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: - 12. THCB

        Substance(
            name: "THCB",
            aliases: ["Tetrahydrocannabutol"],
            category: .cannabinoid,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 1...3, common: 3...8, strong: 8...15, heavy: 15
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.5, max: 3),
                    comeup: TimeRange(min: 3, max: 8),
                    peak: TimeRange(min: 15, max: 45),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 60, max: 150)
                )),
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...12, strong: 12...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 90),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 90, max: 180),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 240, max: 420)
                )),
            ],
            effects: [
                "Euphoria", "Pain relief", "Relaxation", "Anti-inflammation",
                "Dry mouth", "Red eyes", "Drowsiness", "Appetite increase",
                "Time distortion",
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 28, buildRate: "moderate"),
            halfLifeMinutes: 120
        ),

        // MARK: - 13. JWH-018

        Substance(
            name: "JWH-018",
            aliases: ["1-Pentyl-3-(1-naphthoyl)indole", "AM-678"],
            category: .cannabinoid,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 1...3, common: 3...5, strong: 5...10, heavy: 10, fatal: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 2),
                    comeup: TimeRange(min: 2, max: 5),
                    peak: TimeRange(min: 15, max: 60),
                    offset: TimeRange(min: 30, max: 90),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 60, max: 180)
                )),
            ],
            effects: [
                "Intense euphoria", "Anxiety", "Paranoia", "Tachycardia",
                "Dry mouth", "Red eyes", "Nausea", "Time distortion",
                "Dissociation", "Panic",
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 90
        ),

        // MARK: - 14. JWH-073

        Substance(
            name: "JWH-073",
            aliases: ["1-Butyl-3-(1-naphthoyl)indole"],
            category: .cannabinoid,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 3...5, common: 5...10, strong: 10...15, heavy: 15, fatal: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 2),
                    comeup: TimeRange(min: 2, max: 5),
                    peak: TimeRange(min: 15, max: 60),
                    offset: TimeRange(min: 30, max: 90),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 60, max: 180)
                )),
            ],
            effects: [
                "Euphoria", "Relaxation", "Anxiety", "Paranoia",
                "Tachycardia", "Dry mouth", "Nausea", "Time distortion",
                "Dizziness", "Sedation",
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 90
        ),

        // MARK: - 15. JWH-210

        Substance(
            name: "JWH-210",
            aliases: ["4-Ethylnaphthalen-1-yl-(1-pentylindol-3-yl)methanone"],
            category: .cannabinoid,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 1...2, common: 2...4, strong: 4...8, heavy: 8, fatal: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 2),
                    comeup: TimeRange(min: 2, max: 5),
                    peak: TimeRange(min: 15, max: 60),
                    offset: TimeRange(min: 30, max: 90),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 60, max: 180)
                )),
            ],
            effects: [
                "Intense euphoria", "Strong relaxation", "Anxiety", "Paranoia",
                "Tachycardia", "Dry mouth", "Red eyes", "Nausea",
                "Dissociation", "Time distortion",
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 90
        ),

        // MARK: - 16. AM-2201

        Substance(
            name: "AM-2201",
            aliases: ["1-(5-Fluoropentyl)-3-(1-naphthoyl)indole"],
            category: .cannabinoid,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1, common: 1...3, strong: 3...5, heavy: 5, fatal: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 2),
                    comeup: TimeRange(min: 2, max: 5),
                    peak: TimeRange(min: 15, max: 60),
                    offset: TimeRange(min: 30, max: 90),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 60, max: 180)
                )),
            ],
            effects: [
                "Intense euphoria", "Anxiety", "Paranoia", "Tachycardia",
                "Seizure risk", "Nausea", "Dry mouth", "Dissociation",
                "Panic", "Time distortion",
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 90
        ),

        // MARK: - 17. 5F-AKB48

        Substance(
            name: "5F-AKB48",
            aliases: ["5F-APINACA"],
            category: .cannabinoid,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1.5, common: 1.5...3, strong: 3...5, heavy: 5, fatal: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 2),
                    comeup: TimeRange(min: 2, max: 5),
                    peak: TimeRange(min: 15, max: 60),
                    offset: TimeRange(min: 30, max: 90),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 60, max: 180)
                )),
            ],
            effects: [
                "Intense euphoria", "Sedation", "Anxiety", "Paranoia",
                "Tachycardia", "Nausea", "Dry mouth", "Dissociation",
                "Seizure risk", "Confusion",
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 90
        ),

        // MARK: - 18. AB-FUBINACA

        Substance(
            name: "AB-FUBINACA",
            aliases: ["AB-FUB"],
            category: .cannabinoid,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "mcg", doses: DoseRange(
                    threshold: 50, light: 100...250, common: 250...500, strong: 500...1000, heavy: 1000, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 2),
                    comeup: TimeRange(min: 2, max: 5),
                    peak: TimeRange(min: 15, max: 60),
                    offset: TimeRange(min: 30, max: 90),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 60, max: 180)
                )),
            ],
            effects: [
                "Intense euphoria", "Heavy sedation", "Anxiety", "Paranoia",
                "Tachycardia", "Seizure risk", "Nausea", "Vomiting",
                "Loss of consciousness", "Psychosis",
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 60
        ),

        // MARK: - 19. AB-CHMINACA

        Substance(
            name: "AB-CHMINACA",
            aliases: ["AB-CHM"],
            category: .cannabinoid,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "mcg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...500, strong: 500...750, heavy: 750, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 2),
                    comeup: TimeRange(min: 2, max: 5),
                    peak: TimeRange(min: 15, max: 60),
                    offset: TimeRange(min: 30, max: 90),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 60, max: 180)
                )),
            ],
            effects: [
                "Intense euphoria", "Heavy sedation", "Anxiety", "Paranoia",
                "Tachycardia", "Seizure risk", "Nausea", "Confusion",
                "Loss of consciousness", "Psychosis",
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 60
        ),

        // MARK: - 20. MDMB-4en-PINACA

        Substance(
            name: "MDMB-4en-PINACA",
            aliases: ["MDMB-4en"],
            category: .cannabinoid,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "mcg", doses: DoseRange(
                    threshold: 10, light: 25...75, common: 75...150, strong: 150...300, heavy: 300, fatal: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 2),
                    comeup: TimeRange(min: 2, max: 5),
                    peak: TimeRange(min: 15, max: 60),
                    offset: TimeRange(min: 30, max: 90),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 60, max: 180)
                )),
            ],
            effects: [
                "Intense euphoria", "Extreme sedation", "Anxiety", "Paranoia",
                "Tachycardia", "Seizure risk", "Nausea", "Vomiting",
                "Loss of consciousness", "Psychosis",
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 60
        ),

        // MARK: - 21. Nabilone

        Substance(
            name: "Nabilone",
            aliases: ["Cesamet"],
            category: .cannabinoid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1, common: 1...2, strong: 2...4, heavy: 4
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 90),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: [
                "Nausea relief", "Euphoria", "Drowsiness", "Dry mouth",
                "Dizziness", "Pain relief", "Relaxation", "Appetite increase",
                "Disorientation",
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 28, buildRate: "moderate"),
            halfLifeMinutes: 120
        ),

        // MARK: - 22. Dronabinol

        Substance(
            name: "Dronabinol",
            aliases: ["Marinol"],
            category: .cannabinoid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2.5...5, common: 5...10, strong: 10...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 90),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 240, max: 720),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: [
                "Euphoria", "Nausea relief", "Appetite increase", "Drowsiness",
                "Dry mouth", "Dizziness", "Relaxation", "Paranoia",
                "Time distortion", "Anxiety",
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 28, buildRate: "moderate"),
            halfLifeMinutes: 120
        ),

        // MARK: - 23. CUMYL-PINACA

        Substance(
            name: "CUMYL-PINACA",
            aliases: ["SGT-24"],
            category: .cannabinoid,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 0.1, light: 0.25...0.5, common: 0.5...1, strong: 1...2, heavy: 2
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 2),
                    comeup: TimeRange(min: 2, max: 5),
                    peak: TimeRange(min: 15, max: 60),
                    offset: TimeRange(min: 30, max: 90),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 60, max: 180)
                )),
            ],
            effects: [
                "Intense cannabinoid effects", "Anxiety", "Paranoia", "Tachycardia",
                "Risk of seizures", "Nausea", "Confusion", "Sedation",
            ],
            subjectiveEffects: [
                SubjectiveEffect(name: "Intense intoxication", description: "An extremely powerful cannabinoid high that far exceeds natural cannabis, with rapid onset and overwhelming psychoactive intensity even at sub-milligram doses."),
                SubjectiveEffect(name: "Severe anxiety and paranoia", description: "Intense, often uncontrollable anxiety and paranoid ideation that can escalate rapidly into full panic attacks, especially in inexperienced users."),
                SubjectiveEffect(name: "Tachycardia", description: "A dangerous acceleration of heart rate that can reach alarming levels, posing serious cardiovascular risk particularly in those with pre-existing conditions."),
                SubjectiveEffect(name: "Seizure risk", description: "A significant risk of seizures that distinguishes this compound from natural cannabis, representing a potentially life-threatening medical emergency."),
                SubjectiveEffect(name: "Heavy sedation", description: "An overwhelming drowsiness and physical heaviness that can progress to loss of consciousness at higher doses."),
                SubjectiveEffect(name: "Nausea and vomiting", description: "Intense gastrointestinal distress including severe nausea and projectile vomiting, sometimes persisting for hours after use."),
                SubjectiveEffect(name: "Cognitive impairment", description: "Profound confusion and disorientation that far exceeds typical cannabis intoxication, with complete inability to think clearly or communicate coherently."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 60
        ),

        // MARK: - 24. ADB-BUTINACA

        Substance(
            name: "ADB-BUTINACA",
            aliases: ["ADB-BINACA"],
            category: .cannabinoid,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 0.05, light: 0.1...0.25, common: 0.25...0.5, strong: 0.5...1, heavy: 1
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 2),
                    comeup: TimeRange(min: 2, max: 5),
                    peak: TimeRange(min: 15, max: 60),
                    offset: TimeRange(min: 30, max: 90),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 60, max: 180)
                )),
            ],
            effects: [
                "Extreme potency", "Sedation", "Confusion", "Risk of overdose",
                "Nausea", "Respiratory depression", "Loss of consciousness",
                "Seizure risk",
            ],
            subjectiveEffects: [
                SubjectiveEffect(name: "Extreme potency", description: "One of the most potent synthetic cannabinoids ever identified, active at microgram-level doses with an extremely narrow margin between desired effects and life-threatening overdose."),
                SubjectiveEffect(name: "Overwhelming sedation", description: "A rapid, crushing sedation that can render the user completely unresponsive within minutes, frequently progressing to unconsciousness."),
                SubjectiveEffect(name: "Profound confusion", description: "Total cognitive disorganization where the user loses all sense of identity, location, and situation, far beyond any natural cannabis experience."),
                SubjectiveEffect(name: "Respiratory depression", description: "A dangerous suppression of breathing that has been directly linked to numerous fatalities worldwide, making this compound exceptionally lethal."),
                SubjectiveEffect(name: "Nausea and vomiting", description: "Severe gastrointestinal distress that poses an aspiration risk in unconscious users, compounding the danger of overdose."),
                SubjectiveEffect(name: "Seizure activity", description: "A high risk of tonic-clonic seizures that can occur without warning, representing a medical emergency requiring immediate intervention."),
                SubjectiveEffect(name: "Cardiovascular crisis", description: "Extreme tachycardia and blood pressure fluctuations that can progress to cardiac arrest, contributing to the compound's high fatality rate."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 60
        ),

        // MARK: - 25. MDMB-FUBINACA

        Substance(
            name: "MDMB-FUBINACA",
            aliases: ["MDMB-FUB"],
            category: .cannabinoid,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 0.05, light: 0.1...0.25, common: 0.25...0.5, strong: 0.5...0.75, heavy: 0.75
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 2),
                    comeup: TimeRange(min: 2, max: 5),
                    peak: TimeRange(min: 15, max: 60),
                    offset: TimeRange(min: 30, max: 90),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 60, max: 180)
                )),
            ],
            effects: [
                "Extreme potency", "Complete incapacitation", "Seizure risk",
                "Fatality risk", "Respiratory depression", "Loss of consciousness",
                "Cardiovascular collapse", "Psychosis",
            ],
            subjectiveEffects: [
                SubjectiveEffect(name: "Extreme potency with fatal risk", description: "Considered one of the most dangerous synthetic cannabinoids ever created, responsible for mass casualty events worldwide with an almost nonexistent margin of safety."),
                SubjectiveEffect(name: "Complete incapacitation", description: "Rapid and total loss of physical and cognitive function, with users becoming completely unresponsive and unable to move, speak, or protect their airway."),
                SubjectiveEffect(name: "Seizures", description: "Frequent and severe seizure activity that can occur at any dose, often the first sign of a life-threatening overdose requiring emergency medical care."),
                SubjectiveEffect(name: "Respiratory failure", description: "Profound suppression of the breathing reflex that has directly caused numerous deaths, often within minutes of exposure to even small amounts."),
                SubjectiveEffect(name: "Loss of consciousness", description: "A sudden and complete loss of awareness that can occur with startling rapidity, leaving the user vulnerable to aspiration, injury, and death."),
                SubjectiveEffect(name: "Cardiovascular collapse", description: "Severe disruption of heart rhythm and blood pressure that can progress to cardiac arrest, contributing to this compound's extraordinarily high mortality rate."),
                SubjectiveEffect(name: "Psychotic episodes", description: "Acute psychotic reactions including terrifying hallucinations, extreme agitation, and violent behavior that may persist long after the primary intoxication subsides."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 60
        ),

        // MARK: - 26. 5F-MDMB-PICA

        Substance(
            name: "5F-MDMB-PICA",
            aliases: ["5F-MDMB-2201"],
            category: .cannabinoid,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 0.05, light: 0.1...0.2, common: 0.2...0.5, strong: 0.5...1, heavy: 1
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 2),
                    comeup: TimeRange(min: 2, max: 5),
                    peak: TimeRange(min: 15, max: 60),
                    offset: TimeRange(min: 30, max: 90),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 60, max: 180)
                )),
            ],
            effects: [
                "Intense cannabinoid effects", "Paranoia", "Confusion",
                "Sedation", "Overdose risk", "Nausea", "Tachycardia",
            ],
            subjectiveEffects: [
                SubjectiveEffect(name: "Intense cannabinoid intoxication", description: "A rapidly overwhelming high that bears little resemblance to natural cannabis, with potent psychoactive effects at sub-milligram doses."),
                SubjectiveEffect(name: "Severe paranoia", description: "An intense and often terrifying paranoid state that can escalate to full psychotic episodes, far exceeding anything experienced with natural cannabis."),
                SubjectiveEffect(name: "Profound confusion", description: "Complete cognitive disorganization with inability to process basic information, maintain awareness of surroundings, or communicate coherently."),
                SubjectiveEffect(name: "Heavy sedation", description: "An overwhelming physical heaviness that can rapidly progress from drowsiness to complete loss of consciousness at moderate doses."),
                SubjectiveEffect(name: "Overdose potential", description: "A dangerously narrow therapeutic window where the difference between desired effects and life-threatening overdose can be measured in fractions of a milligram."),
                SubjectiveEffect(name: "Nausea and vomiting", description: "Severe gastrointestinal distress that frequently accompanies use, creating additional aspiration risks in heavily sedated users."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 60
        ),

        // MARK: - 27. SGT-151

        Substance(
            name: "SGT-151",
            aliases: ["CUMYL-PEGACLONE"],
            category: .cannabinoid,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 0.1, light: 0.25...0.5, common: 0.5...1, strong: 1...2, heavy: 2
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 2),
                    comeup: TimeRange(min: 2, max: 5),
                    peak: TimeRange(min: 15, max: 60),
                    offset: TimeRange(min: 30, max: 90),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 60, max: 180)
                )),
            ],
            effects: [
                "Cannabinoid effects", "Anxiety", "Sedation", "Dysphoria",
                "Nausea", "Tachycardia", "Confusion",
            ],
            subjectiveEffects: [
                SubjectiveEffect(name: "Synthetic cannabinoid intoxication", description: "A potent cannabimimetic high with a notably dysphoric and uncomfortable character that many users report as less pleasant than other synthetic cannabinoids."),
                SubjectiveEffect(name: "Anxiety and dysphoria", description: "A pronounced negative emotional tone including unease, dread, and persistent discomfort that distinguishes this compound from more euphoric cannabinoids."),
                SubjectiveEffect(name: "Sedation", description: "A heavy, dulling sedation that promotes physical inactivity and mental sluggishness without the pleasant relaxation of natural cannabis."),
                SubjectiveEffect(name: "Tachycardia", description: "A noticeable and often uncomfortable acceleration of heart rate that can provoke anxiety and cardiovascular concern."),
                SubjectiveEffect(name: "Nausea", description: "A persistent queasiness that frequently accompanies use, sometimes progressing to vomiting at higher doses."),
                SubjectiveEffect(name: "Cognitive impairment", description: "A significant dulling of mental function including impaired memory, slowed thinking, and difficulty concentrating that can persist beyond the acute effects."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 60
        ),
    ]
    // swiftlint:enable function_body_length
}
