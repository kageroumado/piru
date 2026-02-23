import Foundation

extension SubstanceLibrary {

    // MARK: - Hormones, Endocrine Modulators, and Anabolic Steroids

    static let hormones: [Substance] = [

        // MARK: - Estrogens

        Substance(
            name: "Estradiol",
            aliases: ["Estrace", "E2"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1, common: 1...4, strong: 4...8, heavy: 8
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
                SubstanceRoute(route: .sublingual, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1, common: 1...4, strong: 4...8, heavy: 8
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 720)
                )),
                SubstanceRoute(route: .transdermal, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1, common: 1...4, strong: 4...8, heavy: 8
                ), duration: DurationProfile(
                    onset: TimeRange(min: 120, max: 360),
                    comeup: TimeRange(min: 240, max: 480),
                    peak: TimeRange(min: 1440, max: 2880),
                    offset: TimeRange(min: 1440, max: 2880),
                    afterglow: nil,
                    total: TimeRange(min: 2880, max: 5760)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mood Stabilization", description: "A gradual evening-out of emotional volatility, with fewer sudden dips in mood and a growing sense of emotional groundedness over weeks."),
                SubjectiveEffect(name: "Skin Softening", description: "A noticeable change in skin texture over weeks to months, with skin feeling smoother, thinner, and more easily prone to dryness."),
                SubjectiveEffect(name: "Breast Tenderness", description: "A persistent soreness or sensitivity in the chest area, often described as an aching or tingling sensation that fluctuates in intensity."),
                SubjectiveEffect(name: "Reduced Libido", description: "A gradual decrease in spontaneous sexual thoughts and physical arousal, often developing over the first few months."),
                SubjectiveEffect(name: "Emotional Depth", description: "An increased capacity to feel emotions more vividly, with crying becoming easier and emotional responses feeling richer and more textured."),
                SubjectiveEffect(name: "Temperature Sensitivity", description: "A shift in temperature perception, often feeling colder more easily with increased sensitivity to ambient temperature changes."),
                SubjectiveEffect(name: "Fatigue", description: "A subtle but persistent tiredness, especially in the first weeks, often described as feeling drained or needing more sleep than usual."),
            ],
            halfLifeMinutes: 990,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Estradiol Valerate",
            aliases: ["EV", "Progynova", "Delestrogen"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...4, common: 4...8, strong: 8...12, heavy: 12
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
                SubstanceRoute(route: .intramuscular, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 5...10, common: 10...20, strong: 20...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 720, max: 1440),
                    comeup: TimeRange(min: 1440, max: 2880),
                    peak: TimeRange(min: 4320, max: 10080),
                    offset: TimeRange(min: 7200, max: 14400),
                    afterglow: nil,
                    total: TimeRange(min: 10080, max: 20160)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mood Stabilization", description: "A gradual smoothing of emotional highs and lows, often noticed as a growing sense of calm and emotional resilience over weeks."),
                SubjectiveEffect(name: "Injection Site Soreness", description: "A dull ache or tenderness at the injection site that may persist for a day or two, sometimes accompanied by minor swelling."),
                SubjectiveEffect(name: "Breast Tenderness", description: "A persistent aching or sensitivity in breast tissue, often fluctuating with the injection cycle and intensifying over the first months."),
                SubjectiveEffect(name: "Emotional Depth", description: "A noticeable increase in emotional sensitivity, with feelings seeming more vivid and tears coming more readily than before."),
                SubjectiveEffect(name: "Skin Softening", description: "A gradual change in skin quality over months, with skin feeling softer and less oily."),
                SubjectiveEffect(name: "Energy Fluctuation", description: "A pattern of feeling more energetic shortly after injection followed by gradual fatigue as levels taper before the next dose."),
                SubjectiveEffect(name: "Reduced Libido", description: "A decrease in spontaneous sexual desire that develops gradually over the first weeks to months of use."),
            ],
            halfLifeMinutes: 6480,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Estradiol Cypionate",
            aliases: ["Depo-Estradiol", "EC"],
            category: .other,
            defaultRoute: .intramuscular,
            routes: [
                SubstanceRoute(route: .intramuscular, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...3, common: 3...5, strong: 5...10, heavy: 10
                ), duration: DurationProfile(
                    onset: TimeRange(min: 720, max: 1440),
                    comeup: TimeRange(min: 1440, max: 2880),
                    peak: TimeRange(min: 4320, max: 10080),
                    offset: TimeRange(min: 7200, max: 14400),
                    afterglow: nil,
                    total: TimeRange(min: 10080, max: 20160)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mood Improvement", description: "A steady lift in baseline mood developing over days to weeks, often described as feeling more emotionally present and less flat."),
                SubjectiveEffect(name: "Breast Tenderness", description: "A growing soreness and sensitivity in the chest that tends to peak mid-cycle and may feel like a deep ache or tingling."),
                SubjectiveEffect(name: "Skin Softening", description: "A progressive softening and thinning of the skin texture, becoming noticeably different from baseline over months."),
                SubjectiveEffect(name: "Reduced Body Odor", description: "A subtle shift in body scent, with sweat becoming less pungent and body odor changing character over weeks."),
                SubjectiveEffect(name: "Emotional Sensitivity", description: "A heightened responsiveness to emotional stimuli, where music, stories, or interpersonal moments can provoke stronger feelings than expected."),
                SubjectiveEffect(name: "Fatigue", description: "A gentle tiredness that can accompany the first weeks of use, often requiring more sleep or rest than usual."),
            ],
            halfLifeMinutes: 12960,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Estradiol Enanthate",
            aliases: [],
            category: .other,
            defaultRoute: .intramuscular,
            routes: [
                SubstanceRoute(route: .intramuscular, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 5...10, common: 10...20, strong: 20...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 720, max: 1440),
                    comeup: TimeRange(min: 1440, max: 2880),
                    peak: TimeRange(min: 4320, max: 10080),
                    offset: TimeRange(min: 7200, max: 14400),
                    afterglow: nil,
                    total: TimeRange(min: 10080, max: 20160)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mood Stabilization", description: "A long-acting emotional leveling effect, with mood feeling more consistent throughout the extended injection interval."),
                SubjectiveEffect(name: "Breast Tenderness", description: "A persistent soreness in breast tissue that may wax and wane over the long injection cycle."),
                SubjectiveEffect(name: "Skin Changes", description: "A gradual softening of skin texture and reduction in oil production developing over months."),
                SubjectiveEffect(name: "Emotional Depth", description: "An expanded emotional range, with feelings seeming richer and more nuanced than before starting treatment."),
                SubjectiveEffect(name: "Reduced Libido", description: "A gradual tapering of spontaneous sexual interest, often settling into a new baseline over the first months."),
                SubjectiveEffect(name: "Temperature Sensitivity", description: "A tendency to feel colder more easily, with hands and feet often feeling chilly in environments that previously felt comfortable."),
            ],
            halfLifeMinutes: 8640,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Ethinylestradiol",
            aliases: ["EE", "birth control component"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 10, light: 20...30, common: 30...50, strong: 50...100, heavy: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Nausea", description: "A queasy, unsettled stomach feeling that is most common in the first few weeks and often subsides with continued use."),
                SubjectiveEffect(name: "Breast Tenderness", description: "A swelling and soreness in the breasts that can range from mild sensitivity to noticeable aching."),
                SubjectiveEffect(name: "Mood Changes", description: "Shifts in emotional baseline that may include increased irritability, tearfulness, or a general sense of emotional flatness."),
                SubjectiveEffect(name: "Headache", description: "A dull, persistent headache that may develop in the first weeks and can be triggered or worsened by hormonal fluctuations."),
                SubjectiveEffect(name: "Water Retention", description: "A bloated, puffy feeling particularly noticeable in the hands, feet, and face, caused by fluid retention."),
                SubjectiveEffect(name: "Reduced Libido", description: "A dampening of sexual desire that can feel like a lack of interest or reduced responsiveness to arousal."),
            ],
            halfLifeMinutes: 2160,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Conjugated Estrogens",
            aliases: ["Premarin"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.15, light: 0.3...0.625, common: 0.625...1.25, strong: 1.25...2.5, heavy: 2.5
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Hot Flash Relief", description: "A noticeable reduction in the frequency and intensity of hot flashes, often feeling like a wave of warmth that no longer fully materializes."),
                SubjectiveEffect(name: "Mood Improvement", description: "A gradual lifting of irritability and emotional lability, with mood feeling more stable and less reactive over weeks."),
                SubjectiveEffect(name: "Nausea", description: "A mild stomach queasiness that is most pronounced in the first weeks of starting and usually fades with continued use."),
                SubjectiveEffect(name: "Breast Tenderness", description: "A fullness and aching sensitivity in the breasts that fluctuates in intensity over the first months."),
                SubjectiveEffect(name: "Water Retention", description: "A subtle bloating and puffiness, particularly in the extremities, that may cause a feeling of heaviness."),
                SubjectiveEffect(name: "Improved Sleep", description: "A gradual improvement in sleep quality, with fewer nighttime awakenings and a more restful feeling upon waking."),
            ],
            halfLifeMinutes: 1020,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - Anti-Androgens

        Substance(
            name: "Spironolactone",
            aliases: ["Aldactone", "Spiro"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 12.5, light: 25...50, common: 50...200, strong: 200...400, heavy: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Frequent Urination", description: "A markedly increased need to urinate, often every one to two hours, especially noticeable in the first weeks of use."),
                SubjectiveEffect(name: "Dizziness", description: "A lightheaded or woozy sensation, particularly when standing up quickly, caused by lowered blood pressure."),
                SubjectiveEffect(name: "Thirst", description: "A persistent feeling of being thirsty that accompanies the diuretic effect, requiring increased fluid intake."),
                SubjectiveEffect(name: "Fatigue", description: "A noticeable drop in energy levels that can feel like a heavy tiredness, especially in the first weeks."),
                SubjectiveEffect(name: "Brain Fog", description: "A subtle haziness in thinking and difficulty concentrating, sometimes described as feeling mentally sluggish."),
                SubjectiveEffect(name: "Salt Cravings", description: "An increased desire for salty foods as the body adjusts to electrolyte changes from the potassium-sparing diuretic effect."),
                SubjectiveEffect(name: "Reduced Libido", description: "A gradual decrease in sexual drive that develops over weeks to months as androgen levels are suppressed."),
            ],
            halfLifeMinutes: 1350,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Cyproterone Acetate",
            aliases: ["CPA", "Androcur"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...12.5, common: 12.5...50, strong: 50...100, heavy: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 120, max: 240),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Fatigue", description: "A pronounced tiredness and low energy that can feel like a constant weight, often described as needing more sleep and feeling drained throughout the day."),
                SubjectiveEffect(name: "Reduced Libido", description: "A significant and often rapid decrease in sexual desire, sometimes reaching a near-complete absence of spontaneous sexual thoughts."),
                SubjectiveEffect(name: "Depression", description: "A gradual onset of low mood, reduced motivation, and emotional flatness that may worsen over time at higher doses."),
                SubjectiveEffect(name: "Brain Fog", description: "A dulling of mental sharpness with difficulty concentrating and slower cognitive processing."),
                SubjectiveEffect(name: "Weight Gain", description: "A gradual increase in body weight, often felt as increased appetite and a tendency to store more fat."),
                SubjectiveEffect(name: "Emotional Blunting", description: "A muted emotional range where both positive and negative feelings feel dampened or distant."),
            ],
            halfLifeMinutes: 2400,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Bicalutamide",
            aliases: ["Casodex"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 12.5, light: 25...50, common: 50...150, strong: 150...300, heavy: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 120, max: 240),
                    peak: TimeRange(min: 480, max: 1440),
                    offset: TimeRange(min: 1440, max: 4320),
                    afterglow: nil,
                    total: TimeRange(min: 2880, max: 8640)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Breast Tenderness", description: "A developing soreness and sensitivity in breast tissue, often one of the first noticeable effects within the first weeks."),
                SubjectiveEffect(name: "Hot Flashes", description: "Sudden waves of warmth spreading across the face and upper body, sometimes accompanied by sweating and flushing."),
                SubjectiveEffect(name: "Fatigue", description: "A mild but persistent tiredness that settles in gradually, often described as a lower baseline energy level."),
                SubjectiveEffect(name: "Reduced Libido", description: "A gradual decrease in sexual drive as androgen signaling is blocked, developing over weeks."),
                SubjectiveEffect(name: "Mood Changes", description: "Subtle shifts in emotional baseline, with some reporting increased emotional sensitivity or mild mood instability."),
                SubjectiveEffect(name: "GI Discomfort", description: "Occasional nausea or stomach upset, usually mild and often occurring shortly after taking the dose."),
            ],
            halfLifeMinutes: 8640,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - 5-Alpha Reductase Inhibitors

        Substance(
            name: "Finasteride",
            aliases: ["Propecia", "Proscar"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1, common: 1...5, strong: 5...10, heavy: 10
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Reduced Hair Shedding", description: "A gradual decrease in the amount of hair falling out during washing or brushing, typically noticeable after several months."),
                SubjectiveEffect(name: "Reduced Libido", description: "A subtle to moderate dampening of sexual desire that some experience within the first weeks to months."),
                SubjectiveEffect(name: "Erectile Changes", description: "A reduction in the firmness or frequency of erections, sometimes accompanied by decreased sensitivity."),
                SubjectiveEffect(name: "Brain Fog", description: "A mild cognitive haziness or difficulty with word recall that some report developing gradually over time."),
                SubjectiveEffect(name: "Mood Changes", description: "Subtle shifts in emotional tone, occasionally including mild depressive symptoms or emotional flatness."),
                SubjectiveEffect(name: "Watery Ejaculate", description: "A noticeable change in semen consistency, becoming thinner and more watery in texture."),
            ],
            halfLifeMinutes: 390,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Dutasteride",
            aliases: ["Avodart"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.1, light: 0.25...0.5, common: 0.5...2.5, strong: 2.5...5, heavy: 5
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 120, max: 240),
                    peak: TimeRange(min: 480, max: 1440),
                    offset: TimeRange(min: 1440, max: 4320),
                    afterglow: nil,
                    total: TimeRange(min: 2880, max: 8640)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Reduced Hair Shedding", description: "A marked decrease in hair loss that develops over months, often more pronounced than with finasteride due to broader DHT suppression."),
                SubjectiveEffect(name: "Reduced Libido", description: "A dampening of sexual desire that may be more noticeable than with other 5-alpha reductase inhibitors due to the dual-type blockade."),
                SubjectiveEffect(name: "Erectile Changes", description: "Potential changes in erectile function ranging from slightly softer erections to more noticeable difficulty maintaining arousal."),
                SubjectiveEffect(name: "Breast Tenderness", description: "A mild soreness or sensitivity in breast tissue that some develop over the first months of use."),
                SubjectiveEffect(name: "Mood Changes", description: "Subtle emotional shifts that may include mild low mood or a sense of emotional dampening."),
                SubjectiveEffect(name: "Brain Fog", description: "A diffuse mental cloudiness with difficulty focusing that some report developing gradually."),
            ],
            halfLifeMinutes: 28800,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - Testosterone and Esters

        Substance(
            name: "Testosterone",
            aliases: ["T", "Test"],
            category: .other,
            defaultRoute: .intramuscular,
            routes: [
                SubstanceRoute(route: .intramuscular, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...500, heavy: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 720, max: 1440),
                    comeup: TimeRange(min: 1440, max: 2880),
                    peak: TimeRange(min: 4320, max: 10080),
                    offset: TimeRange(min: 7200, max: 14400),
                    afterglow: nil,
                    total: TimeRange(min: 10080, max: 20160)
                )),
                SubstanceRoute(route: .transdermal, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...25, common: 25...50, strong: 50...100, heavy: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 240),
                    comeup: TimeRange(min: 120, max: 360),
                    peak: TimeRange(min: 720, max: 1440),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Increased Energy", description: "A noticeable boost in physical and mental energy, often described as feeling more driven and less fatigued throughout the day."),
                SubjectiveEffect(name: "Mood Elevation", description: "A gradual improvement in baseline mood with increased confidence and a more assertive, positive outlook."),
                SubjectiveEffect(name: "Increased Libido", description: "A significant increase in sexual desire and spontaneous arousal that is often one of the first effects noticed."),
                SubjectiveEffect(name: "Increased Aggression", description: "A heightened irritability or shorter fuse, sometimes experienced as impatience or a stronger competitive drive."),
                SubjectiveEffect(name: "Oily Skin", description: "A noticeable increase in skin oiliness and acne susceptibility, particularly on the face, back, and shoulders."),
                SubjectiveEffect(name: "Voice Deepening", description: "A gradual lowering of vocal pitch over months, often accompanied by periods of voice cracking during the transition."),
                SubjectiveEffect(name: "Body Composition Changes", description: "A shift toward increased muscle mass and reduced subcutaneous fat, with the body feeling harder and more angular over months."),
                SubjectiveEffect(name: "Increased Appetite", description: "A heightened hunger drive with increased caloric needs, especially noticeable during the first months as metabolism shifts."),
            ],
            halfLifeMinutes: 60,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Testosterone Cypionate",
            aliases: ["Test C", "Depo-Testosterone"],
            category: .other,
            defaultRoute: .intramuscular,
            routes: [
                SubstanceRoute(route: .intramuscular, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...500, heavy: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 720, max: 1440),
                    comeup: TimeRange(min: 1440, max: 2880),
                    peak: TimeRange(min: 4320, max: 10080),
                    offset: TimeRange(min: 7200, max: 14400),
                    afterglow: nil,
                    total: TimeRange(min: 10080, max: 20160)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Increased Energy", description: "A sustained boost in daily energy and motivation that peaks a few days after injection and gradually tapers."),
                SubjectiveEffect(name: "Mood Elevation", description: "An improved sense of well-being and confidence that follows the injection cycle, sometimes dipping before the next dose."),
                SubjectiveEffect(name: "Increased Libido", description: "A marked increase in sexual desire that often peaks shortly after injection and may fluctuate with the cycle."),
                SubjectiveEffect(name: "Injection Site Soreness", description: "A dull ache or tenderness at the injection site that can last for a day or two, especially with larger volumes."),
                SubjectiveEffect(name: "Oily Skin", description: "An increase in sebum production leading to oilier skin and potential acne breakouts, particularly on the face and back."),
                SubjectiveEffect(name: "Mood Swings", description: "Emotional fluctuations that track with the injection cycle, with irritability or low mood often appearing as levels trough."),
                SubjectiveEffect(name: "Increased Strength", description: "A progressive increase in physical strength and exercise capacity that builds noticeably over the first months."),
            ],
            halfLifeMinutes: 11520,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Testosterone Enanthate",
            aliases: ["Test E"],
            category: .other,
            defaultRoute: .intramuscular,
            routes: [
                SubstanceRoute(route: .intramuscular, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...500, heavy: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 720, max: 1440),
                    comeup: TimeRange(min: 1440, max: 2880),
                    peak: TimeRange(min: 4320, max: 10080),
                    offset: TimeRange(min: 7200, max: 14400),
                    afterglow: nil,
                    total: TimeRange(min: 10080, max: 20160)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Increased Energy", description: "A reliable boost in physical stamina and mental drive that peaks mid-cycle and slowly tapers before the next injection."),
                SubjectiveEffect(name: "Mood Improvement", description: "A lifted mood and increased sense of assertiveness that develops within days of injection."),
                SubjectiveEffect(name: "Increased Libido", description: "A strong increase in sexual desire that follows the pharmacokinetic curve, peaking a few days post-injection."),
                SubjectiveEffect(name: "Water Retention", description: "A subtle bloating and puffiness, particularly in the face and extremities, from increased fluid retention."),
                SubjectiveEffect(name: "Acne", description: "An increase in skin breakouts, particularly on the back and shoulders, that correlates with rising androgen levels."),
                SubjectiveEffect(name: "Increased Aggression", description: "A shortened temper or heightened irritability that can manifest as impatience or a lower threshold for frustration."),
                SubjectiveEffect(name: "Night Sweats", description: "Episodes of heavy sweating during sleep, sometimes requiring a change of bedding, especially at higher doses."),
            ],
            halfLifeMinutes: 7200,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Testosterone Propionate",
            aliases: ["Test P"],
            category: .other,
            defaultRoute: .intramuscular,
            routes: [
                SubstanceRoute(route: .intramuscular, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 25...50, common: 50...100, strong: 100...200, heavy: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 120, max: 360),
                    comeup: TimeRange(min: 360, max: 720),
                    peak: TimeRange(min: 1440, max: 2880),
                    offset: TimeRange(min: 2880, max: 4320),
                    afterglow: nil,
                    total: TimeRange(min: 4320, max: 7200)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Rapid Onset Energy", description: "A quick surge in energy and alertness felt within hours of injection due to the fast-acting ester."),
                SubjectiveEffect(name: "Injection Pain", description: "A notable stinging or burning sensation at the injection site that can persist as soreness for one to two days."),
                SubjectiveEffect(name: "Increased Libido", description: "A rapid spike in sexual desire that peaks quickly and necessitates frequent injections to maintain stable levels."),
                SubjectiveEffect(name: "Mood Fluctuation", description: "More pronounced mood swings due to the short half-life, with noticeable peaks and troughs in emotional state."),
                SubjectiveEffect(name: "Oily Skin", description: "A fast-developing increase in skin oiliness that tracks closely with the rapid rise in testosterone levels post-injection."),
                SubjectiveEffect(name: "Increased Aggression", description: "Sharper spikes in irritability compared to longer esters, coinciding with the rapid peak in blood levels."),
            ],
            halfLifeMinutes: 1200,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Testosterone Undecanoate",
            aliases: ["Nebido", "Aveed"],
            category: .other,
            defaultRoute: .intramuscular,
            routes: [
                SubstanceRoute(route: .intramuscular, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 250...500, common: 500...1000, strong: 1000...1500, heavy: 1500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1440, max: 2880),
                    comeup: TimeRange(min: 2880, max: 7200),
                    peak: TimeRange(min: 10080, max: 20160),
                    offset: TimeRange(min: 14400, max: 28800),
                    afterglow: nil,
                    total: TimeRange(min: 20160, max: 40320)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Stable Energy", description: "A more consistent energy level compared to shorter esters, with less noticeable peaks and troughs between injections."),
                SubjectiveEffect(name: "Mood Stability", description: "A steadier emotional baseline due to the very long-acting ester, with fewer mood swings across the injection interval."),
                SubjectiveEffect(name: "Increased Libido", description: "A sustained increase in sexual desire that remains relatively stable throughout the long injection cycle."),
                SubjectiveEffect(name: "Injection Site Reaction", description: "A significant injection site reaction due to the large volume, often including prolonged soreness, swelling, or a lump."),
                SubjectiveEffect(name: "Gradual Onset", description: "Effects build slowly over days to weeks rather than peaking sharply, creating a more gradual transition in how one feels."),
                SubjectiveEffect(name: "Oily Skin", description: "A sustained increase in skin oiliness that remains relatively constant rather than spiking and falling."),
            ],
            halfLifeMinutes: 60480,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - Progestogens

        Substance(
            name: "Progesterone",
            aliases: ["Prometrium", "P4"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...400, heavy: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 720)
                )),
                SubstanceRoute(route: .rectal, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...400, heavy: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 360, max: 720),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2160)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Drowsiness", description: "A strong sedative pull that can feel like a heavy, warm sleepiness, especially pronounced when taken orally at bedtime."),
                SubjectiveEffect(name: "Improved Sleep", description: "A deeper, more restful sleep quality with easier onset of sleep and fewer nighttime awakenings."),
                SubjectiveEffect(name: "Mood Calming", description: "A noticeable anxiolytic effect that feels like a gentle emotional smoothing, reducing anxiety and nervous tension."),
                SubjectiveEffect(name: "Breast Fullness", description: "A sensation of increased breast fullness and rounding, sometimes accompanied by tenderness or tingling."),
                SubjectiveEffect(name: "Bloating", description: "A puffy, water-retentive feeling particularly in the abdomen, similar to premenstrual bloating."),
                SubjectiveEffect(name: "Increased Appetite", description: "A heightened desire to eat, sometimes with specific cravings for carbohydrate-rich or comfort foods."),
                SubjectiveEffect(name: "Dizziness", description: "A mild lightheadedness or spacey feeling, particularly noticeable within the first hour of oral dosing."),
            ],
            halfLifeMinutes: 300,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Medroxyprogesterone",
            aliases: ["Provera", "MPA", "Depo-Provera"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1.25, light: 2.5...5, common: 5...10, strong: 10...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 960),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
                SubstanceRoute(route: .intramuscular, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...150, strong: 150...300, heavy: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1440, max: 2880),
                    comeup: TimeRange(min: 2880, max: 7200),
                    peak: TimeRange(min: 10080, max: 20160),
                    offset: TimeRange(min: 20160, max: 40320),
                    afterglow: nil,
                    total: TimeRange(min: 40320, max: 60480)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mood Changes", description: "Shifts in emotional baseline that can include increased irritability, depressive feelings, or emotional reactivity developing over weeks."),
                SubjectiveEffect(name: "Weight Gain", description: "A gradual increase in body weight, often accompanied by increased appetite and a tendency toward fat accumulation."),
                SubjectiveEffect(name: "Fatigue", description: "A persistent low-grade tiredness that can feel like a lack of motivation or a heavier-than-usual body throughout the day."),
                SubjectiveEffect(name: "Reduced Libido", description: "A noticeable decrease in sexual interest and arousal that may develop gradually over the first months."),
                SubjectiveEffect(name: "Bloating", description: "A full, swollen feeling in the abdomen from water retention, often uncomfortable and persistent."),
                SubjectiveEffect(name: "Headache", description: "A dull, tension-type headache that can recur regularly, especially in the first weeks of use."),
            ],
            halfLifeMinutes: 1800,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Norethindrone",
            aliases: ["Norethisterone"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.175, light: 0.35...0.5, common: 0.5...5, strong: 5...10, heavy: 10
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 720)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Breakthrough Bleeding", description: "Irregular spotting or light bleeding between expected periods, particularly common in the first months of use."),
                SubjectiveEffect(name: "Headache", description: "A recurring dull headache that can develop in the first weeks and may fluctuate with the hormonal cycle."),
                SubjectiveEffect(name: "Mood Changes", description: "Emotional shifts that may include increased moodiness, irritability, or a lower emotional resilience than baseline."),
                SubjectiveEffect(name: "Nausea", description: "A mild queasiness, usually most noticeable shortly after taking the dose, that often diminishes over time."),
                SubjectiveEffect(name: "Breast Tenderness", description: "A soreness and sensitivity in breast tissue that can range from mild to moderately uncomfortable."),
                SubjectiveEffect(name: "Fatigue", description: "A gentle but noticeable decrease in energy levels, sometimes accompanied by a desire to sleep more."),
            ],
            halfLifeMinutes: 540,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Levonorgestrel",
            aliases: ["Plan B", "Mirena"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.05, light: 0.1...0.15, common: 0.15...1.5, strong: 1.5...3, heavy: 3
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 480, max: 960),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Nausea", description: "A strong wave of queasiness that can occur within hours of taking a high dose, sometimes accompanied by vomiting."),
                SubjectiveEffect(name: "Fatigue", description: "A heavy tiredness that can feel like exhaustion, particularly after taking emergency contraceptive doses."),
                SubjectiveEffect(name: "Headache", description: "A throbbing or dull headache that can develop within hours and persist for a day or more."),
                SubjectiveEffect(name: "Abdominal Cramping", description: "Painful cramping in the lower abdomen, similar to menstrual cramps, that can last for several days."),
                SubjectiveEffect(name: "Breast Tenderness", description: "A swelling and soreness in the breasts that can develop shortly after dosing and persist for days."),
                SubjectiveEffect(name: "Mood Changes", description: "Emotional volatility including tearfulness, irritability, or anxiety that may develop within days of use."),
            ],
            halfLifeMinutes: 1440,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - GnRH Agonists

        Substance(
            name: "GnRH Agonists / Leuprolide",
            aliases: ["Lupron"],
            category: .other,
            defaultRoute: .intramuscular,
            routes: [
                SubstanceRoute(route: .intramuscular, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 3.75...7.5, common: 7.5...22.5, strong: 22.5...45, heavy: 45
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1440, max: 2880),
                    comeup: TimeRange(min: 2880, max: 7200),
                    peak: TimeRange(min: 10080, max: 20160),
                    offset: TimeRange(min: 20160, max: 40320),
                    afterglow: nil,
                    total: TimeRange(min: 40320, max: 60480)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Hot Flashes", description: "Intense waves of heat spreading across the body, often accompanied by profuse sweating and facial flushing."),
                SubjectiveEffect(name: "Mood Changes", description: "Significant emotional shifts including depression, irritability, and mood swings as sex hormone levels drop to castrate range."),
                SubjectiveEffect(name: "Fatigue", description: "A deep, pervasive tiredness that can feel like a complete loss of physical drive and vitality."),
                SubjectiveEffect(name: "Reduced Libido", description: "A dramatic reduction in sexual desire, often reaching near-complete absence as gonadal hormone production ceases."),
                SubjectiveEffect(name: "Joint Pain", description: "A diffuse aching in joints that develops gradually and can feel like stiffness and soreness, especially in the morning."),
                SubjectiveEffect(name: "Brain Fog", description: "A marked cognitive dulling with difficulty concentrating, poor memory recall, and a sense of mental sluggishness."),
                SubjectiveEffect(name: "Initial Flare", description: "A temporary worsening of symptoms in the first one to two weeks as hormone levels spike before suppression takes effect."),
            ],
            halfLifeMinutes: 180,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - Aromatase Inhibitors

        Substance(
            name: "Anastrozole",
            aliases: ["Arimidex"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1, common: 1...2, strong: 2...5, heavy: 5
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Joint Pain", description: "A diffuse aching and stiffness in joints, particularly in the hands, wrists, and knees, that is one of the most commonly reported effects."),
                SubjectiveEffect(name: "Hot Flashes", description: "Sudden episodes of intense warmth spreading through the upper body, often accompanied by sweating and skin flushing."),
                SubjectiveEffect(name: "Fatigue", description: "A persistent low-energy state that can feel like a deep tiredness unrelieved by rest."),
                SubjectiveEffect(name: "Mood Changes", description: "Emotional shifts that may include increased irritability, depressive feelings, or emotional fragility from estrogen depletion."),
                SubjectiveEffect(name: "Dry Skin", description: "A noticeable dryness and thinning of the skin as estrogen levels drop, sometimes accompanied by itching."),
                SubjectiveEffect(name: "Headache", description: "Recurring headaches that may range from mild tension-type to more severe, often developing in the first weeks."),
            ],
            halfLifeMinutes: 2880,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Letrozole",
            aliases: ["Femara"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 1...2.5, common: 2.5...5, strong: 5...10, heavy: 10
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Joint Pain", description: "A prominent musculoskeletal aching, often felt as morning stiffness and deep joint soreness that can limit mobility."),
                SubjectiveEffect(name: "Hot Flashes", description: "Frequent surges of heat and sweating, particularly noticeable at night and during periods of stress."),
                SubjectiveEffect(name: "Fatigue", description: "A heavy, draining tiredness that persists throughout the day and is often unresponsive to increased rest."),
                SubjectiveEffect(name: "Mood Changes", description: "A tendency toward low mood, irritability, or emotional flatness related to the profound estrogen suppression."),
                SubjectiveEffect(name: "Headache", description: "A persistent dull headache that may become a recurring feature, often worse in the first weeks of treatment."),
                SubjectiveEffect(name: "Dizziness", description: "A lightheaded or unsteady sensation that can occur intermittently, especially when changing positions."),
            ],
            halfLifeMinutes: 2880,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Exemestane",
            aliases: ["Aromasin"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 6.25, light: 12.5...25, common: 25...50, strong: 50...75, heavy: 75
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Joint Pain", description: "A stiff, aching sensation in joints that is common with all aromatase inhibitors and can significantly impact daily activities."),
                SubjectiveEffect(name: "Hot Flashes", description: "Waves of intense body heat and sweating that can occur multiple times daily, disrupting comfort and sleep."),
                SubjectiveEffect(name: "Fatigue", description: "A deep exhaustion that settles in as estrogen is irreversibly suppressed, often worsening over the first months."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty falling or staying asleep, often exacerbated by nighttime hot flashes and general discomfort."),
                SubjectiveEffect(name: "Mood Changes", description: "Emotional instability that may manifest as depression, anxiety, or a pervasive sense of being emotionally drained."),
                SubjectiveEffect(name: "Nausea", description: "A mild but recurring stomach upset that some experience, particularly when taking the medication without food."),
            ],
            halfLifeMinutes: 1440,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - SERMs and Fertility

        Substance(
            name: "Tamoxifen",
            aliases: ["Nolvadex"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Hot Flashes", description: "Sudden waves of heat flushing through the body, often concentrated in the face and chest, accompanied by sweating."),
                SubjectiveEffect(name: "Nausea", description: "A persistent queasiness that is most noticeable in the first weeks and can be worsened by taking the medication on an empty stomach."),
                SubjectiveEffect(name: "Fatigue", description: "A dragging tiredness that can make daily activities feel more effortful than usual."),
                SubjectiveEffect(name: "Mood Changes", description: "Emotional shifts including depression, irritability, or mood swings that may fluctuate unpredictably."),
                SubjectiveEffect(name: "Brain Fog", description: "Cognitive difficulties often described as 'chemo brain,' including poor memory, difficulty finding words, and reduced mental clarity."),
                SubjectiveEffect(name: "Joint Stiffness", description: "A mild to moderate aching and stiffness in the joints, particularly noticeable in the morning upon waking."),
            ],
            halfLifeMinutes: 7200,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Raloxifene",
            aliases: ["Evista"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 15, light: 30...60, common: 60...120, strong: 120...180, heavy: 180
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Hot Flashes", description: "A worsening of hot flashes, particularly in the first months, with waves of heat that can be intense and disruptive."),
                SubjectiveEffect(name: "Leg Cramps", description: "Painful muscle cramping in the calves and legs, sometimes occurring at night and disrupting sleep."),
                SubjectiveEffect(name: "Joint Pain", description: "A mild aching in joints that can feel like a general stiffness, especially in the morning."),
                SubjectiveEffect(name: "Fatigue", description: "A subtle but persistent tiredness that may make physical activity feel more demanding than usual."),
                SubjectiveEffect(name: "Sweating", description: "Increased perspiration that goes beyond hot flashes, with a general tendency to sweat more easily."),
            ],
            halfLifeMinutes: 1920,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Clomiphene",
            aliases: ["Clomid"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 12.5, light: 25...50, common: 50...100, strong: 100...150, heavy: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Visual Disturbances", description: "Blurring, spots, or trailing lights in the visual field that can develop during use and usually resolve after discontinuation."),
                SubjectiveEffect(name: "Hot Flashes", description: "Sudden surges of warmth and flushing, similar to menopausal hot flashes, occurring multiple times daily."),
                SubjectiveEffect(name: "Mood Swings", description: "Pronounced emotional volatility with rapid shifts between irritability, tearfulness, and anxiety."),
                SubjectiveEffect(name: "Bloating", description: "Abdominal distension and discomfort from ovarian stimulation and fluid retention."),
                SubjectiveEffect(name: "Headache", description: "A persistent dull headache that is common during the treatment cycle and may worsen with continued use."),
                SubjectiveEffect(name: "Ovarian Discomfort", description: "A dull aching or pressure in the pelvic area as the ovaries respond to stimulation, ranging from mild to significant."),
            ],
            halfLifeMinutes: 7200,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - Neurosteroids and Precursors

        Substance(
            name: "Dehydroepiandrosterone",
            aliases: ["DHEA"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...25, common: 25...50, strong: 50...100, heavy: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Increased Energy", description: "A mild but noticeable boost in vitality and physical energy that develops gradually over the first weeks."),
                SubjectiveEffect(name: "Mood Improvement", description: "A subtle lifting of mood and increased sense of well-being, sometimes described as feeling more vibrant or youthful."),
                SubjectiveEffect(name: "Oily Skin", description: "An increase in sebum production that can lead to oilier skin and occasional acne breakouts."),
                SubjectiveEffect(name: "Increased Libido", description: "A noticeable uptick in sexual desire, particularly in those with previously low DHEA levels."),
                SubjectiveEffect(name: "Body Odor Changes", description: "A shift in body scent toward a more pungent or musky odor, reflecting increased androgen metabolite production."),
                SubjectiveEffect(name: "Hair Changes", description: "Potential changes in hair growth patterns, including increased body hair or scalp oiliness."),
            ],
            halfLifeMinutes: 1200,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Pregnenolone",
            aliases: [],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...25, common: 25...50, strong: 50...100, heavy: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 720)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Improved Memory", description: "A subtle enhancement in recall and cognitive clarity, often described as thinking feeling slightly sharper or more fluid."),
                SubjectiveEffect(name: "Mood Enhancement", description: "A gentle lift in overall mood with a mild anxiolytic quality, creating a greater sense of calm and well-being."),
                SubjectiveEffect(name: "Vivid Dreams", description: "An increase in dream vividness and recall, with dreams often becoming more detailed and memorable."),
                SubjectiveEffect(name: "Increased Energy", description: "A mild boost in mental and physical energy that feels more like restored baseline than stimulation."),
                SubjectiveEffect(name: "Drowsiness", description: "A relaxing, mildly sedating quality at higher doses that can promote sleepiness, especially in the evening."),
            ],
            halfLifeMinutes: 120,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - Corticosteroids

        Substance(
            name: "Hydrocortisone",
            aliases: ["Cortef"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...80, heavy: 80
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 720)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Increased Energy", description: "A noticeable boost in energy and ability to function, particularly in those replacing deficient cortisol levels."),
                SubjectiveEffect(name: "Mood Elevation", description: "An improved sense of well-being and reduced fatigue that can feel like emerging from a fog, especially in adrenal insufficiency."),
                SubjectiveEffect(name: "Increased Appetite", description: "A significant increase in hunger, often with cravings for calorie-dense foods, that can lead to weight gain over time."),
                SubjectiveEffect(name: "Water Retention", description: "A puffy, bloated feeling from fluid retention, particularly in the face, giving a rounded appearance at higher doses."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty falling asleep or staying asleep, especially when doses are taken later in the day."),
                SubjectiveEffect(name: "Anxiety", description: "A jittery, wound-up feeling that can accompany the energy boost, sometimes manifesting as restlessness or racing thoughts."),
            ],
            halfLifeMinutes: 90,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Prednisolone",
            aliases: [],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...40, strong: 40...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Increased Energy", description: "A stimulating burst of energy that can feel almost manic at higher doses, with difficulty sitting still or relaxing."),
                SubjectiveEffect(name: "Insomnia", description: "A pronounced inability to fall asleep, with the mind feeling wired and alert well into the night."),
                SubjectiveEffect(name: "Increased Appetite", description: "A ravenous hunger that feels insatiable, often leading to significant overeating and weight gain with prolonged use."),
                SubjectiveEffect(name: "Mood Changes", description: "Emotional volatility ranging from euphoria and grandiosity to irritability and depression, sometimes shifting rapidly."),
                SubjectiveEffect(name: "Facial Puffiness", description: "A rounding and swelling of the face from fluid retention and fat redistribution, often called 'moon face.'"),
                SubjectiveEffect(name: "GI Discomfort", description: "Stomach irritation, heartburn, or a gnawing sensation in the upper abdomen, worsened by taking without food."),
            ],
            halfLifeMinutes: 180,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Fludrocortisone",
            aliases: ["Florinef"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.025, light: 0.05...0.1, common: 0.1...0.2, strong: 0.2...0.5, heavy: 0.5
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1080, max: 2160)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Reduced Dizziness", description: "A noticeable improvement in orthostatic symptoms, with less lightheadedness when standing up, especially in those with adrenal insufficiency."),
                SubjectiveEffect(name: "Water Retention", description: "A puffy, swollen feeling from increased fluid retention as the mineralocorticoid effect promotes sodium and water reabsorption."),
                SubjectiveEffect(name: "Increased Blood Pressure", description: "A sense of improved circulation and reduced faintness as blood pressure normalizes, but headaches if it rises too high."),
                SubjectiveEffect(name: "Headache", description: "A pressure-like headache that can develop if fluid retention or blood pressure increases beyond the intended range."),
                SubjectiveEffect(name: "Ankle Swelling", description: "Noticeable puffiness in the ankles and lower legs from edema, particularly after prolonged standing."),
            ],
            halfLifeMinutes: 210,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - Anabolic Steroids

        Substance(
            name: "Nandrolone Decanoate",
            aliases: ["Deca-Durabolin", "Deca"],
            category: .other,
            defaultRoute: .intramuscular,
            routes: [
                SubstanceRoute(route: .intramuscular, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...300, strong: 300...600, heavy: 600
                ), duration: DurationProfile(
                    onset: TimeRange(min: 720, max: 1440),
                    comeup: TimeRange(min: 1440, max: 2880),
                    peak: TimeRange(min: 4320, max: 10080),
                    offset: TimeRange(min: 7200, max: 14400),
                    afterglow: nil,
                    total: TimeRange(min: 10080, max: 20160)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Joint Relief", description: "A noticeable reduction in joint pain and improved joint comfort, often described as joints feeling lubricated and cushioned."),
                SubjectiveEffect(name: "Increased Strength", description: "A steady, progressive increase in strength that builds gradually over weeks without the rapid spikes of faster compounds."),
                SubjectiveEffect(name: "Mood Changes", description: "Emotional shifts that may include depression, anxiety, or a flat affect, sometimes referred to as 'deca depression.'"),
                SubjectiveEffect(name: "Reduced Libido", description: "A significant drop in sexual desire and erectile function, commonly known as 'deca dick,' from progesteronic and prolactin effects."),
                SubjectiveEffect(name: "Water Retention", description: "A smooth, watery appearance to the physique from subcutaneous fluid retention, with the body feeling puffy and bloated."),
                SubjectiveEffect(name: "Increased Appetite", description: "A heightened drive to eat more, supporting the muscle-building process but requiring dietary discipline."),
                SubjectiveEffect(name: "Improved Recovery", description: "A noticeable reduction in post-workout soreness and faster recovery between training sessions."),
            ],
            halfLifeMinutes: 8640,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Boldenone Undecylenate",
            aliases: ["Equipoise", "EQ"],
            category: .other,
            defaultRoute: .intramuscular,
            routes: [
                SubstanceRoute(route: .intramuscular, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...400, strong: 400...800, heavy: 800
                ), duration: DurationProfile(
                    onset: TimeRange(min: 720, max: 1440),
                    comeup: TimeRange(min: 1440, max: 2880),
                    peak: TimeRange(min: 4320, max: 10080),
                    offset: TimeRange(min: 7200, max: 14400),
                    afterglow: nil,
                    total: TimeRange(min: 10080, max: 20160)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Increased Appetite", description: "A very pronounced increase in hunger that is one of the most commonly reported effects, making caloric surplus much easier to achieve."),
                SubjectiveEffect(name: "Increased Vascularity", description: "A noticeable prominence of veins, particularly in the arms and shoulders, creating a more vascular appearance."),
                SubjectiveEffect(name: "Anxiety", description: "An increase in anxious feelings or restlessness that some experience, sometimes described as a heightened state of unease."),
                SubjectiveEffect(name: "Increased Endurance", description: "A notable boost in cardiovascular endurance and stamina, making it easier to sustain longer and more intense workouts."),
                SubjectiveEffect(name: "Slow Steady Gains", description: "A gradual but consistent increase in lean muscle mass that develops over many weeks due to the long-acting ester."),
                SubjectiveEffect(name: "Elevated Hematocrit", description: "A sensation of improved oxygen delivery and endurance as red blood cell production increases, but with a feeling of thicker blood."),
            ],
            halfLifeMinutes: 20160,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Trenbolone Acetate",
            aliases: ["Tren A"],
            category: .other,
            defaultRoute: .intramuscular,
            routes: [
                SubstanceRoute(route: .intramuscular, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...400, heavy: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 120, max: 360),
                    comeup: TimeRange(min: 360, max: 720),
                    peak: TimeRange(min: 1440, max: 2880),
                    offset: TimeRange(min: 2880, max: 4320),
                    afterglow: nil,
                    total: TimeRange(min: 4320, max: 7200)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Night Sweats", description: "Profuse sweating during sleep that can soak through sheets, often requiring a towel or change of bedding."),
                SubjectiveEffect(name: "Insomnia", description: "A significant disruption of sleep quality with difficulty falling asleep, frequent awakenings, and restless nights."),
                SubjectiveEffect(name: "Increased Aggression", description: "A markedly heightened irritability and aggressive drive that can affect interpersonal relationships and decision-making."),
                SubjectiveEffect(name: "Cardiovascular Strain", description: "A feeling of elevated heart rate and breathlessness during even mild exertion, often described as 'tren cardio.'"),
                SubjectiveEffect(name: "Rapid Strength Gains", description: "A dramatic and fast increase in strength that can feel almost unnatural in its speed and magnitude."),
                SubjectiveEffect(name: "Body Recomposition", description: "Simultaneous fat loss and muscle gain that creates a visibly harder, more defined physique within weeks."),
                SubjectiveEffect(name: "Paranoia", description: "An intrusive, suspicious mindset that can include jealousy, distrust, and obsessive thought patterns."),
                SubjectiveEffect(name: "Tren Cough", description: "A sudden, violent coughing episode immediately after injection caused by oil entering a blood vessel, lasting one to two minutes."),
            ],
            halfLifeMinutes: 2160,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Trenbolone Enanthate",
            aliases: ["Tren E"],
            category: .other,
            defaultRoute: .intramuscular,
            routes: [
                SubstanceRoute(route: .intramuscular, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...400, strong: 400...700, heavy: 700
                ), duration: DurationProfile(
                    onset: TimeRange(min: 720, max: 1440),
                    comeup: TimeRange(min: 1440, max: 2880),
                    peak: TimeRange(min: 4320, max: 10080),
                    offset: TimeRange(min: 7200, max: 14400),
                    afterglow: nil,
                    total: TimeRange(min: 10080, max: 20160)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Night Sweats", description: "Severe nocturnal sweating that can persist throughout the night, worsening with dose and duration."),
                SubjectiveEffect(name: "Insomnia", description: "A chronic difficulty sleeping that builds over the course of the cycle, leaving a persistent sense of sleep deprivation."),
                SubjectiveEffect(name: "Increased Aggression", description: "A heightened aggressive drive and shortened temper that can be harder to manage than with the acetate ester due to sustained levels."),
                SubjectiveEffect(name: "Cardiovascular Strain", description: "Noticeable shortness of breath and reduced cardiovascular capacity, even during routine physical activities."),
                SubjectiveEffect(name: "Rapid Physique Changes", description: "Dramatic improvements in muscle hardness, definition, and vascularity that become apparent within weeks."),
                SubjectiveEffect(name: "Paranoia", description: "Intrusive suspicious thoughts and jealousy that can intensify over the course of the cycle."),
                SubjectiveEffect(name: "Mood Instability", description: "Unpredictable emotional swings between confidence and irritability, with potential for anxiety and depressive episodes."),
            ],
            halfLifeMinutes: 10080,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Oxandrolone",
            aliases: ["Anavar", "Var"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...40, strong: 40...80, heavy: 80
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Increased Strength", description: "A disproportionately large increase in strength relative to body weight gain, noticeable within the first two weeks."),
                SubjectiveEffect(name: "Muscle Hardening", description: "A drier, harder appearance to muscles with reduced water retention, creating a more defined look."),
                SubjectiveEffect(name: "Improved Vascularity", description: "Increased vein visibility, particularly during exercise, creating a more vascular and lean appearance."),
                SubjectiveEffect(name: "Mild Mood Boost", description: "A subtle but consistent improvement in mood and sense of well-being without the intense emotional swings of stronger androgens."),
                SubjectiveEffect(name: "Muscle Pumps", description: "An intense, sometimes painful pumping sensation in muscles during exercise, particularly in the lower back and shins."),
                SubjectiveEffect(name: "Reduced Appetite", description: "A slight suppression of hunger that some notice, making it easier to maintain a caloric deficit."),
            ],
            halfLifeMinutes: 600,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Stanozolol",
            aliases: ["Winstrol", "Winny"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...25, common: 25...50, strong: 50...100, heavy: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Joint Dryness", description: "A noticeable aching and cracking in joints from reduced synovial fluid, making movements feel stiff and uncomfortable."),
                SubjectiveEffect(name: "Increased Strength", description: "A rapid boost in strength and power output without significant increases in body weight."),
                SubjectiveEffect(name: "Muscle Hardening", description: "A dry, grainy look to muscles with enhanced definition and vascularity, giving a chiseled appearance."),
                SubjectiveEffect(name: "Hair Thinning", description: "Accelerated hair shedding and thinning, particularly in those predisposed to male pattern baldness."),
                SubjectiveEffect(name: "Increased Aggression", description: "A shortened temper and heightened competitive drive that can affect mood and interpersonal interactions."),
                SubjectiveEffect(name: "Muscle Cramps", description: "Sudden, painful cramping in muscles during or after exercise, often in the calves and hamstrings."),
            ],
            halfLifeMinutes: 540,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Methandienone",
            aliases: ["Dianabol", "Dbol"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...80, heavy: 80
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 720)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Rapid Weight Gain", description: "A fast and dramatic increase in body weight within the first weeks, largely from water retention and glycogen loading."),
                SubjectiveEffect(name: "Euphoria", description: "A strong sense of well-being and confidence, often described as feeling powerful and invincible during the cycle."),
                SubjectiveEffect(name: "Increased Strength", description: "A rapid and dramatic surge in strength that can feel almost overnight, with significant jumps in training weights."),
                SubjectiveEffect(name: "Water Retention", description: "Pronounced bloating and puffiness throughout the body, giving a smooth, puffy appearance to the physique."),
                SubjectiveEffect(name: "Muscle Pumps", description: "Intense, sometimes debilitating pumps during exercise, particularly in the back and calves."),
                SubjectiveEffect(name: "Increased Appetite", description: "A powerful hunger drive that makes consuming large amounts of food feel easy and natural."),
                SubjectiveEffect(name: "Acne", description: "An increase in skin breakouts, particularly on the face, back, and shoulders, due to strong androgenic activity."),
            ],
            halfLifeMinutes: 360,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Oxymetholone",
            aliases: ["Anadrol"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 12.5, light: 25...50, common: 50...100, strong: 100...150, heavy: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Massive Strength Gains", description: "An extreme increase in strength within the first week, with weight on major lifts jumping dramatically."),
                SubjectiveEffect(name: "Rapid Weight Gain", description: "A very fast increase in body weight from water retention and muscle fullness, often 5-10 pounds in the first week."),
                SubjectiveEffect(name: "Headaches", description: "Throbbing headaches that can be severe, often related to increased blood pressure and water retention."),
                SubjectiveEffect(name: "Nausea", description: "A persistent queasiness and reduced desire to eat despite the body's increased caloric needs."),
                SubjectiveEffect(name: "Lethargy", description: "A heavy, sluggish feeling that can counteract the physical strength gains, making daily activities feel exhausting."),
                SubjectiveEffect(name: "Bloating", description: "Extreme water retention creating a puffy, swollen appearance, particularly in the face and midsection."),
                SubjectiveEffect(name: "Muscle Pumps", description: "Painful, debilitating pumps during training, particularly in the lower back, that can limit workout duration."),
            ],
            halfLifeMinutes: 540,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Mesterolone",
            aliases: ["Proviron"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 12.5, light: 25...50, common: 50...100, strong: 100...150, heavy: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mood Enhancement", description: "A subtle but noticeable improvement in overall mood and sense of well-being, often described as feeling more positive and driven."),
                SubjectiveEffect(name: "Increased Libido", description: "A boost in sexual desire and function, often used specifically for this purpose as an androgenic enhancer."),
                SubjectiveEffect(name: "Muscle Hardening", description: "A mild hardening and drying effect on muscle appearance, reducing water retention and improving definition."),
                SubjectiveEffect(name: "Improved Vascularity", description: "Enhanced vein visibility and a more defined, dry look to the physique."),
                SubjectiveEffect(name: "Reduced Estrogen Effects", description: "A reduction in estrogen-related side effects when combined with aromatizing compounds, through SHBG binding competition."),
            ],
            halfLifeMinutes: 720,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Turinabol",
            aliases: ["Tbol", "4-Chlorodehydromethyltestosterone"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 960),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Lean Muscle Gains", description: "Slow, steady gains in lean muscle without significant water retention, resulting in a cleaner look than many oral steroids."),
                SubjectiveEffect(name: "Increased Strength", description: "A gradual but reliable increase in strength that builds consistently over the course of the cycle."),
                SubjectiveEffect(name: "Improved Endurance", description: "A boost in stamina and work capacity, making it possible to sustain longer training sessions."),
                SubjectiveEffect(name: "Muscle Pumps", description: "Noticeable muscle pumps during exercise, though generally less painful than those from other orals."),
                SubjectiveEffect(name: "Reduced Recovery Time", description: "A shortened recovery period between workouts, with less delayed-onset muscle soreness."),
                SubjectiveEffect(name: "Mild Mood Boost", description: "A gentle improvement in drive and motivation without the intense emotional effects of stronger androgens."),
            ],
            halfLifeMinutes: 960,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - Peptide Hormones and Growth Factors

        Substance(
            name: "Insulin",
            aliases: ["Humalog", "Novolog"],
            category: .other,
            defaultRoute: .subcutaneous,
            routes: [
                SubstanceRoute(route: .subcutaneous, unit: "IU", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...15, strong: 15...30, heavy: 30, fatal: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 300),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 480)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Hypoglycemia", description: "A dangerous drop in blood sugar causing shakiness, sweating, confusion, dizziness, and intense hunger that requires immediate carbohydrate intake."),
                SubjectiveEffect(name: "Increased Hunger", description: "A powerful, sometimes overwhelming urge to eat as blood sugar is driven into cells and the body signals for more fuel."),
                SubjectiveEffect(name: "Drowsiness", description: "A heavy, sleepy feeling that can accompany blood sugar fluctuations, sometimes progressing to difficulty staying awake."),
                SubjectiveEffect(name: "Sweating", description: "Cold, clammy sweating that often signals dropping blood sugar levels and serves as a warning sign."),
                SubjectiveEffect(name: "Muscle Fullness", description: "A noticeable increase in muscle volume and fullness as glucose and nutrients are driven into muscle cells."),
                SubjectiveEffect(name: "Injection Site Reactions", description: "Localized redness, swelling, or lipodystrophy at injection sites with repeated use in the same area."),
            ],
            halfLifeMinutes: 6,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Human Growth Hormone",
            aliases: ["HGH", "Somatropin"],
            category: .other,
            defaultRoute: .subcutaneous,
            routes: [
                SubstanceRoute(route: .subcutaneous, unit: "IU", doses: DoseRange(
                    threshold: 0.5, light: 1...2, common: 2...4, strong: 4...8, heavy: 8
                ), duration: DurationProfile(
                    onset: TimeRange(min: 120, max: 240),
                    comeup: TimeRange(min: 240, max: 480),
                    peak: TimeRange(min: 480, max: 1440),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Water Retention", description: "A noticeable bloating and puffiness, particularly in the hands and face, that is most pronounced in the first weeks."),
                SubjectiveEffect(name: "Joint Pain", description: "An aching and stiffness in joints, especially the wrists and fingers, from fluid retention and tissue growth."),
                SubjectiveEffect(name: "Carpal Tunnel Symptoms", description: "Numbness, tingling, and pain in the hands and wrists that can disrupt sleep and grip strength."),
                SubjectiveEffect(name: "Improved Sleep", description: "A deeper, more restorative sleep quality with more vivid dreams, often one of the first benefits noticed."),
                SubjectiveEffect(name: "Improved Skin Quality", description: "A gradual improvement in skin texture and elasticity, with skin feeling thicker, smoother, and more youthful."),
                SubjectiveEffect(name: "Increased Energy", description: "A gradual improvement in overall vitality and recovery, with increased energy and reduced fatigue over weeks."),
                SubjectiveEffect(name: "Fat Redistribution", description: "A slow reduction in abdominal fat and an overall leaner body composition that develops over months of consistent use."),
            ],
            halfLifeMinutes: 240,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "IGF-1",
            aliases: ["Mecasermin", "Increlex"],
            category: .other,
            defaultRoute: .subcutaneous,
            routes: [
                SubstanceRoute(route: .subcutaneous, unit: "µg", doses: DoseRange(
                    threshold: 10, light: 20...40, common: 40...80, strong: 80...120, heavy: 120
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 1200)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Hypoglycemia", description: "A drop in blood sugar causing shakiness, sweating, and hunger, requiring careful timing with meals."),
                SubjectiveEffect(name: "Muscle Pumps", description: "An intense fullness and pumping in muscles during exercise from enhanced nutrient uptake."),
                SubjectiveEffect(name: "Joint Discomfort", description: "An aching sensation in joints from growth factor activity, particularly in the hands and wrists."),
                SubjectiveEffect(name: "Fatigue", description: "A tiredness that can follow the hypoglycemic dips, sometimes requiring rest or napping."),
                SubjectiveEffect(name: "Improved Recovery", description: "A noticeable reduction in post-exercise soreness and faster healing of minor injuries."),
            ],
            halfLifeMinutes: 600,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - Thyroid Hormones

        Substance(
            name: "Thyroid T3",
            aliases: ["Liothyronine", "Cytomel"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 5, light: 12.5...25, common: 25...50, strong: 50...100, heavy: 100, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Increased Energy", description: "A noticeable boost in metabolic energy and alertness, often felt as a wired, active sensation throughout the day."),
                SubjectiveEffect(name: "Increased Heart Rate", description: "A faster resting heart rate and palpitations that can feel like the heart is pounding or racing."),
                SubjectiveEffect(name: "Heat Intolerance", description: "A tendency to feel uncomfortably warm in situations that would normally be tolerable, with increased sweating."),
                SubjectiveEffect(name: "Weight Loss", description: "An accelerated rate of fat and weight loss from increased metabolic rate, but with potential muscle loss at higher doses."),
                SubjectiveEffect(name: "Anxiety", description: "A jittery, nervous energy that can manifest as restlessness, racing thoughts, and difficulty relaxing."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty falling asleep due to the stimulatory metabolic effect, particularly with doses taken later in the day."),
                SubjectiveEffect(name: "Increased Appetite", description: "A paradoxical increase in hunger as metabolism speeds up, requiring discipline to maintain a caloric deficit."),
            ],
            halfLifeMinutes: 1440,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - Dopamine Agonists

        Substance(
            name: "Cabergoline",
            aliases: ["Dostinex"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.125, light: 0.25...0.5, common: 0.5...1, strong: 1...2, heavy: 2
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 180),
                    comeup: TimeRange(min: 120, max: 240),
                    peak: TimeRange(min: 480, max: 1440),
                    offset: TimeRange(min: 1440, max: 2880),
                    afterglow: nil,
                    total: TimeRange(min: 2880, max: 10080)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Nausea", description: "A queasy stomach feeling that is most common when starting and can be reduced by taking the medication with food or at bedtime."),
                SubjectiveEffect(name: "Dizziness", description: "A lightheaded, woozy sensation especially when standing up, from the blood pressure-lowering dopaminergic effect."),
                SubjectiveEffect(name: "Fatigue", description: "A tiredness that can accompany the first doses as the body adjusts to prolactin suppression."),
                SubjectiveEffect(name: "Mood Enhancement", description: "A subtle lift in mood and motivation from the dopamine agonist activity, sometimes described as feeling more clear-headed."),
                SubjectiveEffect(name: "Reduced Refractory Period", description: "A shortened recovery time between sexual activity, one of the most commonly discussed effects of prolactin reduction."),
                SubjectiveEffect(name: "Improved Libido", description: "An increase in sexual desire as prolactin levels normalize, often noticed within the first weeks."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 30, buildRate: "slow"),
            halfLifeMinutes: 4320,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

    ]

    // MARK: - Additional Medications

    static let additionalMedications: [Substance] = [

        // MARK: - Dermatological

        Substance(
            name: "Minoxidil",
            aliases: ["Rogaine"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 1...2.5, common: 2.5...5, strong: 5...10, heavy: 10
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Increased Hair Growth", description: "A gradual increase in hair density and regrowth that becomes noticeable after several months of consistent use."),
                SubjectiveEffect(name: "Initial Shedding", description: "A temporary increase in hair loss in the first weeks as dormant follicles are stimulated, which can be alarming but is a normal response."),
                SubjectiveEffect(name: "Dizziness", description: "A lightheaded feeling from blood pressure reduction, particularly when standing up quickly, more common with oral use."),
                SubjectiveEffect(name: "Unwanted Hair Growth", description: "Growth of fine hair in unwanted areas such as the forehead, cheeks, or arms, especially with oral administration."),
                SubjectiveEffect(name: "Water Retention", description: "A puffy, bloated feeling from fluid retention, particularly noticeable in the face and extremities with oral use."),
                SubjectiveEffect(name: "Heart Palpitations", description: "An awareness of the heartbeat that may include occasional racing or skipped beats, more common at higher oral doses."),
            ],
            halfLifeMinutes: 270,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Isotretinoin",
            aliases: ["Accutane", "Roaccutane"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...80, heavy: 80
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 120, max: 240),
                    peak: TimeRange(min: 480, max: 1440),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1200, max: 2880)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Dry Skin", description: "An extreme dryness of the skin that can lead to peeling, flaking, and cracking, especially on the lips and face."),
                SubjectiveEffect(name: "Dry Lips", description: "Severely chapped and cracked lips that require constant application of lip balm and can split painfully."),
                SubjectiveEffect(name: "Joint Pain", description: "An aching stiffness in joints and muscles, particularly in the lower back and knees, that worsens with physical activity."),
                SubjectiveEffect(name: "Mood Changes", description: "Potential shifts in emotional state including irritability, low mood, or feelings of depression that require monitoring."),
                SubjectiveEffect(name: "Fatigue", description: "A general tiredness and reduced physical stamina, especially during the first months of treatment."),
                SubjectiveEffect(name: "Initial Breakout", description: "A temporary worsening of acne in the first weeks before improvement begins, sometimes called a 'purge.'"),
                SubjectiveEffect(name: "Dry Eyes", description: "A gritty, uncomfortable dryness in the eyes that may make contact lens wear difficult or impossible."),
            ],
            halfLifeMinutes: 1260,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - Anti-Inflammatory and Immunomodulatory

        Substance(
            name: "Colchicine",
            aliases: [],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.3, light: 0.6...1.2, common: 1.2...2.4, strong: 2.4...4.8, heavy: 4.8, fatal: 10
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 120),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 1440)
                )),
            ],
            effects: [],
            subjectiveEffects: [
                SubjectiveEffect(name: "Nausea", description: "A dose-limiting queasiness that often signals the maximum tolerable dose has been reached."),
                SubjectiveEffect(name: "Diarrhea", description: "Loose, watery stools that are one of the most common effects and often the first sign of approaching toxicity."),
                SubjectiveEffect(name: "Abdominal Cramping", description: "Painful cramping in the stomach and intestines that accompanies the gastrointestinal effects."),
                SubjectiveEffect(name: "Gout Relief", description: "A significant reduction in the acute pain, swelling, and inflammation of a gout flare within hours to days."),
                SubjectiveEffect(name: "Fatigue", description: "A general tiredness and weakness that can accompany use, especially at higher doses."),
                SubjectiveEffect(name: "Muscle Weakness", description: "A subtle weakening of muscle strength that can develop with prolonged use, manifesting as difficulty with physical tasks."),
            ],
            halfLifeMinutes: 1740,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Methotrexate",
            aliases: [],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...25, strong: 25...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 180),
                    comeup: TimeRange(min: 120, max: 240),
                    peak: TimeRange(min: 360, max: 720),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: [],
            halfLifeMinutes: 420,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Hydroxychloroquine",
            aliases: ["Plaquenil"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 200...300, common: 300...400, strong: 400...600, heavy: 600, fatal: 4000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 180),
                    comeup: TimeRange(min: 120, max: 240),
                    peak: TimeRange(min: 480, max: 1440),
                    offset: TimeRange(min: 1440, max: 2880),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: [],
            halfLifeMinutes: 57600,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - Antibiotics

        Substance(
            name: "Azithromycin",
            aliases: ["Zithromax", "Z-Pack"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 125, light: 250...500, common: 500...1000, strong: 1000...2000, heavy: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 180),
                    comeup: TimeRange(min: 120, max: 240),
                    peak: TimeRange(min: 240, max: 720),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 4320)
                )),
            ],
            effects: [],
            halfLifeMinutes: 4320,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Amoxicillin",
            aliases: [],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 125, light: 250...500, common: 500...1000, strong: 1000...2000, heavy: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 720)
                )),
            ],
            effects: [],
            halfLifeMinutes: 60,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Doxycycline",
            aliases: [],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...400, heavy: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: [],
            halfLifeMinutes: 1080,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Ciprofloxacin",
            aliases: ["Cipro"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 125, light: 250...500, common: 500...1000, strong: 1000...1500, heavy: 1500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 600, max: 1080)
                )),
            ],
            effects: [],
            halfLifeMinutes: 240,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - Antifungals and Antivirals

        Substance(
            name: "Fluconazole",
            aliases: ["Diflucan"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...150, common: 150...400, strong: 400...800, heavy: 800
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2160)
                )),
            ],
            effects: [],
            halfLifeMinutes: 1800,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Acyclovir",
            aliases: ["Zovirax", "Valtrex prodrug"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 200...400, common: 400...800, strong: 800...1600, heavy: 1600
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 90),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 480)
                )),
            ],
            effects: [],
            halfLifeMinutes: 180,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - Anticoagulants and Antiplatelets

        Substance(
            name: "Warfarin",
            aliases: ["Coumadin"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 1...2, common: 2...5, strong: 5...10, heavy: 10, fatal: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 180),
                    comeup: TimeRange(min: 360, max: 720),
                    peak: TimeRange(min: 1440, max: 5760),
                    offset: TimeRange(min: 2880, max: 7200),
                    afterglow: nil,
                    total: TimeRange(min: 2880, max: 8640)
                )),
            ],
            effects: [],
            halfLifeMinutes: 2400,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Rivaroxaban",
            aliases: ["Xarelto"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...15, common: 15...20, strong: 20...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 600, max: 1080)
                )),
            ],
            effects: [],
            halfLifeMinutes: 540,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Apixaban",
            aliases: ["Eliquis"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1.25, light: 2.5...5, common: 5...10, strong: 10...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 60, max: 180),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 600, max: 1080)
                )),
            ],
            effects: [],
            halfLifeMinutes: 720,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Clopidogrel",
            aliases: ["Plavix"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...75, common: 75...150, strong: 150...300, heavy: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 120, max: 240),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: [],
            halfLifeMinutes: 360,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - Statins

        Substance(
            name: "Rosuvastatin",
            aliases: ["Crestor"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...20, strong: 20...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 120, max: 240),
                    peak: TimeRange(min: 180, max: 300),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 1140, max: 1440)
                )),
            ],
            effects: [],
            halfLifeMinutes: 1140,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Atorvastatin",
            aliases: ["Lipitor"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...80, heavy: 80
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 120, max: 240),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 840, max: 1440)
                )),
            ],
            effects: [],
            halfLifeMinutes: 840,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Simvastatin",
            aliases: ["Zocor"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...80, heavy: 80
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: [],
            halfLifeMinutes: 180,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - GI Medications

        Substance(
            name: "Metoclopramide",
            aliases: ["Reglan"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...20, strong: 20...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 480)
                )),
            ],
            effects: [],
            halfLifeMinutes: 360,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Misoprostol",
            aliases: ["Cytotec"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...400, strong: 400...800, heavy: 800
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 30, max: 90),
                    offset: TimeRange(min: 60, max: 180),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: [],
            halfLifeMinutes: 30,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Mifepristone",
            aliases: ["RU-486", "Mifeprex"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...400, strong: 400...600, heavy: 600
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 120, max: 240),
                    peak: TimeRange(min: 480, max: 1440),
                    offset: TimeRange(min: 1440, max: 2880),
                    afterglow: nil,
                    total: TimeRange(min: 2880, max: 5760)
                )),
            ],
            effects: [],
            halfLifeMinutes: 1620,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - Opioid Antagonists and Addiction Medicine

        Substance(
            name: "Naloxone",
            aliases: ["Narcan"],
            category: .other,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 1...2, common: 2...4, strong: 4...8, heavy: 8
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 3),
                    comeup: TimeRange(min: 2, max: 5),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 15, max: 30),
                    afterglow: nil,
                    total: TimeRange(min: 30, max: 90)
                )),
                SubstanceRoute(route: .intramuscular, unit: "mg", doses: DoseRange(
                    threshold: 0.1, light: 0.2...0.4, common: 0.4...2, strong: 2...4, heavy: 4
                ), duration: DurationProfile(
                    onset: TimeRange(min: 2, max: 5),
                    comeup: TimeRange(min: 3, max: 5),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 15, max: 30),
                    afterglow: nil,
                    total: TimeRange(min: 30, max: 90)
                )),
            ],
            effects: [],
            halfLifeMinutes: 60,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Naltrexone",
            aliases: ["Vivitrol", "ReVia"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 6.25, light: 12.5...25, common: 25...50, strong: 50...100, heavy: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 4320)
                )),
            ],
            effects: [],
            halfLifeMinutes: 240,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Disulfiram",
            aliases: ["Antabuse"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 62.5, light: 125...250, common: 250...500, strong: 500...750, heavy: 750
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 120, max: 360),
                    peak: TimeRange(min: 720, max: 1440),
                    offset: TimeRange(min: 1440, max: 2880),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: [],
            halfLifeMinutes: 7200,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Acamprosate",
            aliases: ["Campral"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 166, light: 333...666, common: 666...1332, strong: 1332...1998, heavy: 1998
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 120, max: 240),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 780)
                )),
            ],
            effects: [],
            halfLifeMinutes: 1200,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Varenicline",
            aliases: ["Chantix", "Champix"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1, common: 1...2, strong: 2...3, heavy: 3
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 120, max: 240),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 1440)
                )),
            ],
            effects: [],
            halfLifeMinutes: 1440,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - Respiratory

        Substance(
            name: "Budesonide",
            aliases: ["Pulmicort", "Entocort"],
            category: .other,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "µg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...400, strong: 400...800, heavy: 800
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: [],
            halfLifeMinutes: 180,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Fluticasone",
            aliases: ["Flonase", "Flovent"],
            category: .other,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "µg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...250, strong: 250...500, heavy: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: [],
            halfLifeMinutes: 600,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Albuterol",
            aliases: ["Salbutamol", "Ventolin", "ProAir"],
            category: .other,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "µg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...400, strong: 400...800, heavy: 800
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 30, max: 120),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: [],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 7, buildRate: "rapid"),
            halfLifeMinutes: 330,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Ipratropium",
            aliases: ["Atrovent"],
            category: .other,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "µg", doses: DoseRange(
                    threshold: 10, light: 20...40, common: 40...80, strong: 80...160, heavy: 160
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 480)
                )),
            ],
            effects: [],
            halfLifeMinutes: 120,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Theophylline",
            aliases: [],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...400, strong: 400...600, heavy: 600, fatal: 5000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: [],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 14, buildRate: "slow"),
            halfLifeMinutes: 480,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - Immunosuppressants

        Substance(
            name: "Tacrolimus",
            aliases: ["Prograf"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 1...2, common: 2...5, strong: 5...10, heavy: 10
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 60, max: 240),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: [],
            halfLifeMinutes: 720,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Cyclosporine",
            aliases: ["Sandimmune", "Neoral"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...400, heavy: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 90, max: 240),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: [],
            halfLifeMinutes: 1140,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Mycophenolate",
            aliases: ["CellCept"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 125, light: 250...500, common: 500...1000, strong: 1000...2000, heavy: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1080)
                )),
            ],
            effects: [],
            halfLifeMinutes: 1020,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - Diabetes and Metabolic

        Substance(
            name: "Pioglitazone",
            aliases: ["Actos"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 7.5, light: 15...30, common: 30...45, strong: 45...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 120, max: 240),
                    peak: TimeRange(min: 480, max: 1440),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: [],
            halfLifeMinutes: 420,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Glipizide",
            aliases: ["Glucotrol"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1.25, light: 2.5...5, common: 5...10, strong: 10...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 720)
                )),
            ],
            effects: [],
            halfLifeMinutes: 240,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Empagliflozin",
            aliases: ["Jardiance"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...15, common: 15...25, strong: 25...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 90, max: 240),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: [],
            halfLifeMinutes: 780,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - GLP-1 and Weight Management

        Substance(
            name: "Liraglutide",
            aliases: ["Victoza", "Saxenda"],
            category: .other,
            defaultRoute: .subcutaneous,
            routes: [
                SubstanceRoute(route: .subcutaneous, unit: "mg", doses: DoseRange(
                    threshold: 0.3, light: 0.6...1.2, common: 1.2...1.8, strong: 1.8...3, heavy: 3
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 120, max: 360),
                    peak: TimeRange(min: 480, max: 720),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: [],
            halfLifeMinutes: 780,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Semaglutide",
            aliases: ["Ozempic", "Wegovy", "Rybelsus"],
            category: .other,
            defaultRoute: .subcutaneous,
            routes: [
                SubstanceRoute(route: .subcutaneous, unit: "mg", doses: DoseRange(
                    threshold: 0.125, light: 0.25...0.5, common: 0.5...1, strong: 1...2, heavy: 2
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 240),
                    comeup: TimeRange(min: 240, max: 720),
                    peak: TimeRange(min: 1440, max: 2880),
                    offset: TimeRange(min: 2880, max: 5760),
                    afterglow: nil,
                    total: TimeRange(min: 7200, max: 10080)
                )),
            ],
            effects: [],
            halfLifeMinutes: 10080,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Tirzepatide",
            aliases: ["Mounjaro", "Zepbound"],
            category: .other,
            defaultRoute: .subcutaneous,
            routes: [
                SubstanceRoute(route: .subcutaneous, unit: "mg", doses: DoseRange(
                    threshold: 1.25, light: 2.5...5, common: 5...10, strong: 10...15, heavy: 15
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 240),
                    comeup: TimeRange(min: 240, max: 720),
                    peak: TimeRange(min: 1440, max: 2880),
                    offset: TimeRange(min: 2880, max: 5760),
                    afterglow: nil,
                    total: TimeRange(min: 7200, max: 10080)
                )),
            ],
            effects: [],
            halfLifeMinutes: 7200,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Orlistat",
            aliases: ["Xenical", "Alli"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 30, light: 60...120, common: 120...360, strong: 360...540, heavy: 540
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 60, max: 240),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 480)
                )),
            ],
            effects: [],
            halfLifeMinutes: 120,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - Miscellaneous

        Substance(
            name: "Naloxegol",
            aliases: ["Movantik"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 6.25, light: 12.5...25, common: 25...50, strong: 50...75, heavy: 75
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 120),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 120, max: 300),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: [],
            halfLifeMinutes: 660,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Methylprednisolone",
            aliases: ["Medrol", "Solu-Medrol"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 4...8, common: 8...32, strong: 32...64, heavy: 64
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 480, max: 960),
                    afterglow: nil,
                    total: TimeRange(min: 1080, max: 2160)
                )),
            ],
            effects: [],
            halfLifeMinutes: 210,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Esomeprazole",
            aliases: ["Nexium"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 20...40, common: 40...80, strong: 80...120, heavy: 120
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 960, max: 1440)
                )),
            ],
            effects: [],
            halfLifeMinutes: 90,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        Substance(
            name: "Lansoprazole",
            aliases: ["Prevacid"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 7.5, light: 15...30, common: 30...60, strong: 60...90, heavy: 90
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: [],
            halfLifeMinutes: 105,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

    ]
}
