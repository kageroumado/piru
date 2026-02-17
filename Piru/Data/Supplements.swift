import Foundation

extension SubstanceLibrary {
    // swiftlint:disable function_body_length
    static let supplements: [Substance] = [

        // MARK: - Vitamins

        // MARK: 1. Vitamin D3

        Substance(
            name: "Vitamin D3",
            aliases: ["Cholecalciferol", "Vitamin D", "D3"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "IU", doses: DoseRange(
                    threshold: 400, light: 1000...2000, common: 2000...5000, strong: 5000...10000, heavy: 10000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 360, max: 720),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: ["Improved mood", "Stronger bones", "Enhanced immune function", "Better calcium absorption", "Reduced fatigue", "Improved sleep quality"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mood Brightening", description: "A gradual improvement in baseline mood over weeks, particularly noticeable during winter months or periods of low sun exposure."),
                SubjectiveEffect(name: "Energy Restoration", description: "A slow but steady reduction in daytime fatigue and sluggishness as levels normalize."),
                SubjectiveEffect(name: "Improved Well-Being", description: "A general sense of feeling healthier and more resilient that develops over consistent supplementation."),
                SubjectiveEffect(name: "Better Sleep", description: "Improved sleep quality and more consistent sleep-wake cycles after several weeks of adequate levels."),
                SubjectiveEffect(name: "Immune Resilience", description: "Fewer and shorter colds or infections noticed over months of maintaining optimal levels."),
                SubjectiveEffect(name: "Reduced Seasonal Blues", description: "A lessening of the low mood and lethargy commonly experienced during shorter winter days."),
            ],
            halfLifeMinutes: 21600
        ),

        // MARK: 2. Vitamin C

        Substance(
            name: "Vitamin C",
            aliases: ["Ascorbic Acid", "L-Ascorbic Acid"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 60, light: 250...500, common: 500...1000, strong: 1000...2000, heavy: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 720)
                )),
            ],
            effects: ["Enhanced immune function", "Antioxidant protection", "Improved skin health", "Faster wound healing", "Reduced cold duration", "Gastrointestinal discomfort"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Immune Support", description: "A perception of getting sick less frequently or recovering faster from colds with consistent daily use."),
                SubjectiveEffect(name: "Skin Clarity", description: "A gradual improvement in skin tone and brightness noticed over weeks of supplementation."),
                SubjectiveEffect(name: "Mild Energy Boost", description: "A subtle increase in daily energy, particularly in those who were previously deficient."),
                SubjectiveEffect(name: "Faster Recovery", description: "Minor cuts and bruises seem to heal somewhat more quickly with consistent intake."),
                SubjectiveEffect(name: "Stomach Sensitivity", description: "Gastrointestinal discomfort or loose stools at higher doses, especially on an empty stomach."),
            ],
            halfLifeMinutes: 90
        ),

        // MARK: 3. Vitamin B12

        Substance(
            name: "Vitamin B12",
            aliases: ["Cobalamin", "Methylcobalamin", "Cyanocobalamin", "B12"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 2.4, light: 100...500, common: 500...1000, strong: 1000...5000, heavy: 5000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 720)
                )),
                SubstanceRoute(route: .sublingual, unit: "µg", doses: DoseRange(
                    threshold: 2.4, light: 100...500, common: 500...1000, strong: 1000...5000, heavy: 5000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 300, max: 660)
                )),
            ],
            effects: ["Improved energy", "Reduced fatigue", "Enhanced mental clarity", "Better nerve function", "Improved mood", "Red blood cell support"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Energy Restoration", description: "A significant improvement in daily energy levels for those who were deficient, often noticed within weeks."),
                SubjectiveEffect(name: "Mental Clarity", description: "A clearing of brain fog and improved cognitive function, especially pronounced in those with low baseline levels."),
                SubjectiveEffect(name: "Mood Improvement", description: "A gradual lifting of low mood and improved emotional resilience with corrected B12 status."),
                SubjectiveEffect(name: "Reduced Tingling", description: "A reduction in numbness or tingling in extremities for those experiencing deficiency-related neuropathy."),
                SubjectiveEffect(name: "Better Stamina", description: "Improved endurance during physical activity as oxygen-carrying capacity normalizes."),
            ],
            halfLifeMinutes: 8640
        ),

        // MARK: 4. Vitamin B6

        Substance(
            name: "Vitamin B6",
            aliases: ["Pyridoxine", "Pyridoxal-5-Phosphate", "P5P", "B6"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1.3, light: 10...25, common: 25...50, strong: 50...100, heavy: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 720)
                )),
            ],
            effects: ["Improved mood", "Enhanced neurotransmitter synthesis", "Reduced PMS symptoms", "Better sleep", "Vivid dreams", "Reduced homocysteine levels"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Vivid Dreams", description: "Noticeably more vivid and memorable dreams, often reported within the first few nights of supplementation."),
                SubjectiveEffect(name: "Mood Support", description: "A subtle improvement in emotional stability and reduced irritability with consistent use."),
                SubjectiveEffect(name: "PMS Relief", description: "A reduction in premenstrual mood changes, bloating, and discomfort for some users."),
                SubjectiveEffect(name: "Better Sleep Quality", description: "Improved sleep depth and feeling more rested upon waking, likely related to neurotransmitter support."),
                SubjectiveEffect(name: "Dream Recall", description: "A marked increase in the ability to remember dreams in detail upon waking."),
            ],
            halfLifeMinutes: 25920
        ),

        // MARK: 5. Vitamin B1

        Substance(
            name: "Vitamin B1",
            aliases: ["Thiamine", "Thiamin", "B1"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1.2, light: 10...25, common: 25...100, strong: 100...300, heavy: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 720)
                )),
            ],
            effects: ["Improved energy metabolism", "Enhanced nervous system function", "Reduced fatigue", "Better carbohydrate processing", "Improved appetite"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Energy Improvement", description: "A gradual reduction in fatigue and improved ability to sustain energy throughout the day."),
                SubjectiveEffect(name: "Mental Steadiness", description: "A subtle stabilization of cognitive function and reduced mental fatigue during demanding tasks."),
                SubjectiveEffect(name: "Appetite Normalization", description: "An improvement in appetite regulation, particularly for those who were deficient."),
                SubjectiveEffect(name: "Nerve Comfort", description: "Reduced nerve-related discomfort and tingling sensations in those with prior deficiency."),
                SubjectiveEffect(name: "Metabolic Support", description: "A general sense of the body processing food and energy more efficiently over time."),
            ],
            halfLifeMinutes: 90
        ),

        // MARK: 6. Vitamin B2

        Substance(
            name: "Vitamin B2",
            aliases: ["Riboflavin", "B2"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1.3, light: 5...10, common: 10...25, strong: 25...100, heavy: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 720)
                )),
            ],
            effects: ["Reduced migraine frequency", "Improved energy production", "Better skin health", "Enhanced iron absorption", "Antioxidant support", "Bright yellow urine"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Migraine Reduction", description: "A gradual decrease in migraine frequency and severity over weeks to months of consistent supplementation."),
                SubjectiveEffect(name: "Bright Yellow Urine", description: "A harmless but very noticeable fluorescent yellow coloring of urine, often the most immediately obvious effect."),
                SubjectiveEffect(name: "Skin Improvement", description: "A subtle improvement in skin clarity and reduction in cracking at the corners of the mouth."),
                SubjectiveEffect(name: "Energy Support", description: "A mild improvement in daily energy levels as cellular energy production is supported."),
                SubjectiveEffect(name: "Eye Comfort", description: "Reduced eye fatigue and sensitivity to light for those who were previously deficient."),
            ],
            halfLifeMinutes: 75
        ),

        // MARK: 7. Vitamin B3

        Substance(
            name: "Vitamin B3",
            aliases: ["Niacin", "Nicotinic Acid", "Niacinamide", "B3"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 16, light: 50...100, common: 100...500, strong: 500...1000, heavy: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 720)
                )),
            ],
            effects: ["Skin flushing", "Improved cholesterol profile", "Enhanced circulation", "Reduced joint stiffness", "Improved skin health", "Nausea at high doses"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Niacin Flush", description: "A warm, tingling, reddening sensation across the skin that can feel intense but is harmless and temporary."),
                SubjectiveEffect(name: "Improved Circulation", description: "A noticeable warmth in extremities and a sense of improved blood flow, particularly after flushing."),
                SubjectiveEffect(name: "Joint Comfort", description: "A gradual reduction in joint stiffness and improved flexibility over consistent use."),
                SubjectiveEffect(name: "Skin Warmth", description: "A flushing warmth that spreads across the face and upper body within 20 minutes of dosing."),
                SubjectiveEffect(name: "Nausea", description: "Stomach discomfort and nausea at higher doses, particularly when taken on an empty stomach."),
                SubjectiveEffect(name: "Energy Boost", description: "A subtle improvement in cellular energy production that may contribute to feeling slightly more energetic."),
            ],
            halfLifeMinutes: 45
        ),

        // MARK: 8. Vitamin B5

        Substance(
            name: "Vitamin B5",
            aliases: ["Pantothenic Acid", "Pantothenate", "B5"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...50, common: 50...250, strong: 250...500, heavy: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 720)
                )),
            ],
            effects: ["Improved energy metabolism", "Enhanced adrenal function", "Better wound healing", "Reduced acne", "Improved stress resilience"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Stress Tolerance", description: "A gradual improvement in the ability to handle daily stressors without feeling as depleted."),
                SubjectiveEffect(name: "Skin Clearing", description: "A reduction in acne breakouts over weeks, particularly at higher supplemental doses."),
                SubjectiveEffect(name: "Energy Steadiness", description: "More consistent energy throughout the day with fewer afternoon crashes."),
                SubjectiveEffect(name: "Wound Healing", description: "Minor cuts and skin irritations seem to resolve somewhat faster with consistent use."),
                SubjectiveEffect(name: "Adrenal Support", description: "A sense of better recovery from stressful periods, with less prolonged fatigue afterward."),
            ],
            halfLifeMinutes: 150
        ),

        // MARK: 9. Vitamin B9

        Substance(
            name: "Vitamin B9",
            aliases: ["Folate", "Folic Acid", "Methylfolate", "B9"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 100, light: 200...400, common: 400...800, strong: 800...1000, heavy: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 720)
                )),
            ],
            effects: ["Improved mood", "Enhanced cell division", "Reduced homocysteine levels", "Better prenatal health", "Improved cognitive function"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mood Improvement", description: "A subtle but steady improvement in emotional well-being, particularly in those with MTHFR variants or prior deficiency."),
                SubjectiveEffect(name: "Mental Clarity", description: "A gradual clearing of cognitive fog as methylation pathways are better supported."),
                SubjectiveEffect(name: "Energy Support", description: "Reduced fatigue and improved daily energy as folate-dependent processes function more efficiently."),
                SubjectiveEffect(name: "Emotional Stability", description: "More even moods with less frequent dips into low mood or irritability."),
                SubjectiveEffect(name: "General Vitality", description: "An overall sense of improved health and vitality that develops over weeks of adequate intake."),
            ],
            halfLifeMinutes: 180
        ),

        // MARK: 10. Vitamin A

        Substance(
            name: "Vitamin A",
            aliases: ["Retinol", "Retinyl Palmitate", "Beta-Carotene"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "IU", doses: DoseRange(
                    threshold: 1000, light: 2500...5000, common: 5000...8000, strong: 8000...10000, heavy: 10000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 360, max: 720),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: ["Improved vision", "Enhanced immune function", "Better skin health", "Antioxidant protection", "Improved cell growth", "Nausea at high doses"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Night Vision Support", description: "A gradual improvement in the ability to see in low-light conditions with consistent supplementation."),
                SubjectiveEffect(name: "Skin Health", description: "Improved skin texture and clarity over weeks, with reduced dryness and better overall complexion."),
                SubjectiveEffect(name: "Immune Resilience", description: "A sense of getting sick less often or recovering more quickly from minor illnesses."),
                SubjectiveEffect(name: "Eye Comfort", description: "Reduced eye dryness and improved comfort during extended screen time."),
                SubjectiveEffect(name: "Nausea", description: "Stomach upset and nausea at high doses, a sign of potential toxicity requiring dose reduction."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: 11. Vitamin E

        Substance(
            name: "Vitamin E",
            aliases: ["Tocopherol", "Alpha-Tocopherol", "d-Alpha-Tocopherol"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "IU", doses: DoseRange(
                    threshold: 15, light: 100...200, common: 200...400, strong: 400...800, heavy: 800
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 360, max: 720),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: ["Antioxidant protection", "Improved skin health", "Enhanced immune function", "Reduced oxidative stress", "Better cardiovascular support"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Skin Improvement", description: "A gradual improvement in skin smoothness and moisture retention noticed over months of use."),
                SubjectiveEffect(name: "Reduced Dryness", description: "Less dry and cracked skin, particularly during winter months, with improved overall skin barrier function."),
                SubjectiveEffect(name: "General Well-Being", description: "A subtle sense of improved health and vitality from enhanced antioxidant protection."),
                SubjectiveEffect(name: "Immune Support", description: "A perception of improved resistance to common illnesses over long-term supplementation."),
                SubjectiveEffect(name: "Cardiovascular Comfort", description: "A background sense of improved cardiovascular health, more inferred from biomarkers than directly felt."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: 12. Vitamin K2

        Substance(
            name: "Vitamin K2",
            aliases: ["Menaquinone", "MK-7", "MK-4", "K2"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 45, light: 90...100, common: 100...200, strong: 200...500, heavy: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 360, max: 720),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: ["Improved calcium metabolism", "Better bone density", "Enhanced cardiovascular health", "Reduced arterial calcification", "Improved dental health"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Bone Strength", description: "A long-term sense of improved skeletal strength, though effects are more measurable than felt day-to-day."),
                SubjectiveEffect(name: "Dental Improvement", description: "Reduced tooth sensitivity and improved dental health noticed over months of consistent use."),
                SubjectiveEffect(name: "Cardiovascular Support", description: "A background sense of improved heart health when combined with vitamin D3 supplementation."),
                SubjectiveEffect(name: "Calcium Utilization", description: "A sense that calcium supplementation is working more effectively, with fewer issues like stiffness."),
                SubjectiveEffect(name: "General Health Assurance", description: "Peace of mind from supporting proper calcium distribution away from arteries and into bones."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: - Minerals

        // MARK: 13. Magnesium

        Substance(
            name: "Magnesium",
            aliases: ["Magnesium Glycinate", "Magnesium L-Threonate", "Magnesium Citrate", "Mag"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...400, strong: 400...600, heavy: 600
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 240, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 600)
                )),
            ],
            effects: ["Improved sleep quality", "Reduced muscle cramps", "Enhanced relaxation", "Better stress resilience", "Reduced anxiety", "Improved bowel regularity", "Headache relief"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Deep Sleep", description: "Noticeably deeper and more restorative sleep, often one of the first effects people report after starting."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "A reduction in muscle tension and nighttime cramps, with limbs feeling less tight and more at ease."),
                SubjectiveEffect(name: "Calming Effect", description: "A gentle whole-body relaxation when taken in the evening, easing the transition from day to night."),
                SubjectiveEffect(name: "Anxiety Reduction", description: "A subtle lowering of background anxiety and nervous tension, particularly noticeable under stress."),
                SubjectiveEffect(name: "Bowel Regularity", description: "Improved regularity and easier bowel movements, especially with citrate forms at higher doses."),
                SubjectiveEffect(name: "Headache Relief", description: "A reduction in tension headache frequency for those whose headaches are related to magnesium insufficiency."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: 14. Zinc

        Substance(
            name: "Zinc",
            aliases: ["Zinc Picolinate", "Zinc Citrate", "Zinc Gluconate"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...15, common: 15...30, strong: 30...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 1080)
                )),
            ],
            effects: ["Enhanced immune function", "Improved skin health", "Better wound healing", "Nausea on empty stomach", "Metallic taste", "Improved testosterone support"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Immune Strength", description: "A noticeable reduction in the frequency of colds and minor infections over months of use."),
                SubjectiveEffect(name: "Skin Clearing", description: "Improved skin clarity and faster healing of blemishes, often noticed within weeks."),
                SubjectiveEffect(name: "Metallic Taste", description: "A distinct metallic or mineral taste in the mouth, especially when taken on an empty stomach."),
                SubjectiveEffect(name: "Nausea", description: "Stomach upset that can be quite pronounced when taken without food, particularly with higher doses."),
                SubjectiveEffect(name: "Hormonal Support", description: "A subtle improvement in energy and libido that some male users attribute to testosterone support."),
            ],
            halfLifeMinutes: 180
        ),

        // MARK: 15. Iron

        Substance(
            name: "Iron",
            aliases: ["Ferrous Sulfate", "Iron Bisglycinate", "Ferrous Gluconate"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...18, common: 18...27, strong: 27...45, heavy: 45
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 1080)
                )),
            ],
            effects: ["Improved energy", "Reduced fatigue", "Better oxygen transport", "Constipation", "Nausea", "Dark stools", "Improved exercise tolerance"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Energy Restoration", description: "A dramatic improvement in energy levels for those who were iron-deficient, often felt within weeks of supplementation."),
                SubjectiveEffect(name: "Exercise Tolerance", description: "Significantly improved ability to sustain physical exertion without becoming breathless or exhausted."),
                SubjectiveEffect(name: "Reduced Fatigue", description: "A marked reduction in chronic tiredness and the ability to get through the day without crashing."),
                SubjectiveEffect(name: "Dark Stools", description: "A harmless darkening of stool color that is a common and expected side effect."),
                SubjectiveEffect(name: "Constipation", description: "Reduced bowel regularity and harder stools, a frequent side effect particularly with ferrous sulfate forms."),
                SubjectiveEffect(name: "Stomach Upset", description: "Nausea and stomach discomfort, especially when taken on an empty stomach or at higher doses."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: 16. Potassium

        Substance(
            name: "Potassium",
            aliases: ["Potassium Citrate", "Potassium Gluconate", "Potassium Chloride"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 99...200, common: 200...500, strong: 500...1000, heavy: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 1080)
                )),
            ],
            effects: ["Improved muscle function", "Better electrolyte balance", "Reduced cramping", "Improved blood pressure", "Enhanced nerve signaling"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Cramp Relief", description: "A noticeable reduction in muscle cramps, especially during and after exercise or at night."),
                SubjectiveEffect(name: "Muscle Function", description: "Improved muscle responsiveness and reduced feelings of weakness during physical activity."),
                SubjectiveEffect(name: "Hydration Balance", description: "A sense of better fluid balance in the body, with less water retention and puffiness."),
                SubjectiveEffect(name: "Blood Pressure Support", description: "A subtle improvement in cardiovascular comfort for those with borderline elevated blood pressure."),
                SubjectiveEffect(name: "Reduced Fatigue", description: "Less physical fatigue during the day, particularly for those with previously low potassium intake."),
            ],
            halfLifeMinutes: 720
        ),

        // MARK: 17. Selenium

        Substance(
            name: "Selenium",
            aliases: ["Sodium Selenite", "Selenomethionine"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 20, light: 50...100, common: 100...200, strong: 200...400, heavy: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 1080)
                )),
            ],
            effects: ["Antioxidant protection", "Enhanced thyroid function", "Improved immune response", "Better reproductive health", "Reduced oxidative stress"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Thyroid Support", description: "Improved energy and metabolic rate for those whose thyroid function was impaired by selenium deficiency."),
                SubjectiveEffect(name: "Immune Resilience", description: "A subtle improvement in resistance to infections noticed over months of consistent supplementation."),
                SubjectiveEffect(name: "Mood Stabilization", description: "A mild improvement in mood stability, likely related to thyroid hormone optimization."),
                SubjectiveEffect(name: "General Vitality", description: "A background sense of improved cellular health and reduced oxidative burden."),
                SubjectiveEffect(name: "Hair and Nail Quality", description: "Improved hair thickness and nail strength noticed over weeks to months of adequate selenium intake."),
            ],
            halfLifeMinutes: 1440
        ),

        // MARK: 18. Calcium

        Substance(
            name: "Calcium",
            aliases: ["Calcium Carbonate", "Calcium Citrate"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 200...500, common: 500...1000, strong: 1000...1300, heavy: 1300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 1080)
                )),
            ],
            effects: ["Stronger bones", "Improved dental health", "Better muscle contraction", "Enhanced nerve function", "Constipation", "Reduced risk of osteoporosis"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Bone Confidence", description: "A long-term sense of improved skeletal health, though benefits are more measurable than immediately felt."),
                SubjectiveEffect(name: "Dental Strength", description: "Improved tooth and jaw health noticed over months, with fewer dental sensitivities."),
                SubjectiveEffect(name: "Muscle Function", description: "Smoother muscle contractions and fewer cramps, particularly when combined with magnesium."),
                SubjectiveEffect(name: "Constipation", description: "A common side effect of reduced bowel motility, especially with calcium carbonate forms."),
                SubjectiveEffect(name: "Nail Strength", description: "Stronger, less brittle nails noticed over weeks of consistent supplementation."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: 19. Chromium

        Substance(
            name: "Chromium",
            aliases: ["Chromium Picolinate", "Chromium Polynicotinate"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...500, heavy: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 1080)
                )),
            ],
            effects: ["Improved blood sugar regulation", "Reduced carbohydrate cravings", "Enhanced insulin sensitivity", "Better appetite control", "Improved lipid profile"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Craving Reduction", description: "A noticeable decrease in cravings for sweets and refined carbohydrates within days of starting."),
                SubjectiveEffect(name: "Blood Sugar Stability", description: "Fewer energy crashes and less post-meal drowsiness as blood sugar swings become more moderate."),
                SubjectiveEffect(name: "Appetite Control", description: "Improved ability to manage portion sizes and resist snacking between meals."),
                SubjectiveEffect(name: "Steady Energy", description: "More consistent energy levels throughout the day without the typical highs and lows."),
                SubjectiveEffect(name: "Reduced Sweet Tooth", description: "A gradual diminishing of the desire for sugary foods and drinks over weeks of use."),
            ],
            halfLifeMinutes: 2400
        ),

        // MARK: 20. Iodine

        Substance(
            name: "Iodine",
            aliases: ["Potassium Iodide", "Kelp Iodine", "Lugol's"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 50, light: 100...150, common: 150...300, strong: 300...1000, heavy: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 1080)
                )),
            ],
            effects: ["Improved thyroid function", "Enhanced metabolism", "Better cognitive development", "Improved hormonal balance", "Increased energy"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Metabolic Improvement", description: "A gradual increase in metabolic rate and energy for those who were iodine-deficient."),
                SubjectiveEffect(name: "Mental Sharpness", description: "Improved cognitive function and reduced brain fog as thyroid hormones normalize."),
                SubjectiveEffect(name: "Energy Boost", description: "A noticeable increase in daily energy and reduced sluggishness with corrected iodine status."),
                SubjectiveEffect(name: "Body Temperature Regulation", description: "Feeling less cold and better able to maintain body warmth, related to improved thyroid function."),
                SubjectiveEffect(name: "Hormonal Balance", description: "A sense of improved overall hormonal function, with better mood and energy stability."),
            ],
            halfLifeMinutes: 4320
        ),

        // MARK: - Amino Acids

        // MARK: 21. L-Tryptophan

        Substance(
            name: "L-Tryptophan",
            aliases: ["Tryptophan"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 250...500, common: 500...1000, strong: 1000...2000, heavy: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Improved sleep quality", "Enhanced mood", "Increased serotonin production", "Reduced anxiety", "Drowsiness", "Better stress management"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Sleepiness", description: "A gentle wave of drowsiness that makes falling asleep feel natural and effortless when taken before bed."),
                SubjectiveEffect(name: "Mood Elevation", description: "A subtle improvement in mood and emotional well-being that develops over days of regular use."),
                SubjectiveEffect(name: "Anxiety Softening", description: "A reduction in anxious feelings and worry, with the mind feeling calmer and less agitated."),
                SubjectiveEffect(name: "Relaxation", description: "A whole-body sense of calm that settles in within an hour of dosing."),
                SubjectiveEffect(name: "Stress Buffering", description: "An improved ability to cope with daily stressors without becoming overwhelmed or reactive."),
                SubjectiveEffect(name: "Dream Vividness", description: "Increased dream recall and vividness due to enhanced serotonin signaling during sleep."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: 22. 5-HTP

        Substance(
            name: "5-HTP",
            aliases: ["5-Hydroxytryptophan", "Oxitriptan"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...300, heavy: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Improved mood", "Better sleep quality", "Reduced appetite", "Increased serotonin levels", "Nausea", "Reduced anxiety", "Vivid dreams"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mood Lift", description: "A noticeable improvement in mood within hours of dosing, with a gentle sense of contentment."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A clear reduction in hunger and cravings, particularly for carbohydrate-rich comfort foods."),
                SubjectiveEffect(name: "Sleep Improvement", description: "Easier sleep onset and deeper sleep quality, with a more refreshed feeling upon waking."),
                SubjectiveEffect(name: "Vivid Dreams", description: "Notably more vivid, colorful, and memorable dreams, sometimes bordering on overwhelming."),
                SubjectiveEffect(name: "Nausea", description: "A common side effect of stomach discomfort, especially when starting or at higher doses."),
                SubjectiveEffect(name: "Anxiolytic Calm", description: "A serotonin-mediated reduction in anxiety that can be felt within the first dose."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 240
        ),

        // MARK: 23. L-Tyrosine

        Substance(
            name: "L-Tyrosine",
            aliases: ["Tyrosine", "N-Acetyl L-Tyrosine", "NALT"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 250...500, common: 500...1000, strong: 1000...2000, heavy: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Improved focus", "Enhanced mental performance under stress", "Better dopamine production", "Increased alertness", "Improved motivation", "Reduced brain fog"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Stress-Proof Focus", description: "An improved ability to maintain cognitive performance under pressure, with less mental deterioration during stressful tasks."),
                SubjectiveEffect(name: "Alertness Boost", description: "A mild increase in wakefulness and mental readiness, noticeable within an hour of dosing on an empty stomach."),
                SubjectiveEffect(name: "Motivational Drive", description: "An increased sense of purpose and willingness to engage with challenging tasks."),
                SubjectiveEffect(name: "Brain Fog Clearing", description: "A reduction in mental haziness, with thoughts feeling more accessible and organized."),
                SubjectiveEffect(name: "Cognitive Endurance", description: "Better sustained mental performance during long work sessions or sleep-deprived states."),
                SubjectiveEffect(name: "Mood Stability Under Stress", description: "Maintained emotional composure in situations that would normally cause frustration or overwhelm."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: 24. GABA

        Substance(
            name: "GABA",
            aliases: ["Gamma-aminobutyric acid", "Gamma-Aminobutyric Acid"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 250...500, common: 500...750, strong: 750...1000, heavy: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Enhanced relaxation", "Reduced anxiety", "Improved sleep onset", "Calming effect", "Skin tingling at high doses", "Reduced mental chatter"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Calming Wave", description: "A noticeable wave of calm and relaxation that sets in within 30-60 minutes of dosing."),
                SubjectiveEffect(name: "Mental Quieting", description: "A reduction in racing thoughts and mental chatter, making it easier to relax and unwind."),
                SubjectiveEffect(name: "Sleep Onset Aid", description: "An easier transition to sleep when taken before bed, with less tossing and turning."),
                SubjectiveEffect(name: "Skin Tingling", description: "A pins-and-needles tingling sensation across the face and body at higher doses, harmless but noticeable."),
                SubjectiveEffect(name: "Anxiety Relief", description: "A perceptible reduction in anxious tension, though the oral bioavailability debate means effects vary widely."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: 25. L-Glutamine

        Substance(
            name: "L-Glutamine",
            aliases: ["Glutamine"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "g", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...10, strong: 10...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Improved gut lining integrity", "Enhanced muscle recovery", "Reduced sugar cravings", "Better immune function", "Improved digestive health"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Digestive Comfort", description: "A gradual improvement in gut comfort and reduction in bloating and digestive irritation."),
                SubjectiveEffect(name: "Sugar Craving Reduction", description: "A noticeable decrease in cravings for sweet foods, often felt within the first week of use."),
                SubjectiveEffect(name: "Muscle Recovery", description: "Reduced post-exercise soreness and faster recovery between intense training sessions."),
                SubjectiveEffect(name: "Gut Healing", description: "A progressive improvement in digestive symptoms for those with gut permeability issues."),
                SubjectiveEffect(name: "Immune Support", description: "A subtle improvement in overall immune resilience with consistent daily supplementation."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: 26. NAC

        Substance(
            name: "NAC",
            aliases: ["N-Acetyl Cysteine", "N-Acetylcysteine"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 200, light: 400...600, common: 600...1200, strong: 1200...1800, heavy: 1800
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Antioxidant support", "Enhanced liver detoxification", "Improved respiratory health", "Reduced mucus buildup", "Better glutathione production", "Nausea"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Respiratory Clearing", description: "A noticeable thinning of mucus and improved breathing clarity, often felt within hours of dosing."),
                SubjectiveEffect(name: "Mental Clarity", description: "A subtle cognitive clearing that some users attribute to reduced oxidative stress and inflammation."),
                SubjectiveEffect(name: "Hangover Recovery", description: "Accelerated recovery from alcohol consumption when taken prophylactically, with reduced morning-after symptoms."),
                SubjectiveEffect(name: "Liver Support", description: "A background sense of improved detoxification capacity, particularly valued by those on medications."),
                SubjectiveEffect(name: "Compulsive Behavior Reduction", description: "A reported reduction in ruminating thoughts and compulsive behaviors with consistent use."),
                SubjectiveEffect(name: "Nausea", description: "Mild stomach discomfort that can occur due to the sulfurous nature of the compound."),
            ],
            halfLifeMinutes: 330
        ),

        // MARK: 27. Creatine

        Substance(
            name: "Creatine",
            aliases: ["Creatine Monohydrate", "Creatine HCl"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "g", doses: DoseRange(
                    threshold: 1, light: 2...3, common: 3...5, strong: 5...10, heavy: 10
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Improved strength", "Enhanced exercise performance", "Better muscle recovery", "Increased water retention", "Improved cognitive function", "Weight gain from water"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Strength Increase", description: "A noticeable improvement in maximum strength and power output during resistance training after loading."),
                SubjectiveEffect(name: "Muscle Fullness", description: "Muscles feel and appear fuller and more volumized due to increased intracellular water retention."),
                SubjectiveEffect(name: "Improved Recovery", description: "Faster recovery between sets and between training sessions, with less lingering soreness."),
                SubjectiveEffect(name: "Cognitive Boost", description: "A subtle improvement in mental energy and working memory, particularly during sleep deprivation or stress."),
                SubjectiveEffect(name: "Weight Gain", description: "A rapid increase of a few pounds on the scale from water retention, typically within the first week."),
                SubjectiveEffect(name: "Exercise Endurance", description: "Improved ability to sustain high-intensity efforts for slightly longer before fatigue sets in."),
            ],
            halfLifeMinutes: 180
        ),

        // MARK: 28. Beta-Alanine

        Substance(
            name: "Beta-Alanine",
            aliases: ["β-Alanine"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "g", doses: DoseRange(
                    threshold: 0.5, light: 1...2, common: 2...3.2, strong: 3.2...5, heavy: 5
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Improved muscular endurance", "Skin tingling (paresthesia)", "Enhanced exercise capacity", "Reduced muscle fatigue", "Better high-intensity performance"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Paresthesia Tingling", description: "A distinctive prickling or itching sensation across the face, ears, and hands within 15-20 minutes of dosing."),
                SubjectiveEffect(name: "Endurance Boost", description: "An improved ability to push through high-rep sets and sustained efforts before muscle burn forces a stop."),
                SubjectiveEffect(name: "Reduced Muscle Burn", description: "The burning sensation during intense exercise feels more manageable due to increased muscle carnosine levels."),
                SubjectiveEffect(name: "Pre-Workout Activation", description: "A sense of physical readiness and activation that many associate with the onset of the tingling effect."),
                SubjectiveEffect(name: "Sustained Performance", description: "Better maintenance of exercise intensity across longer workout sessions over weeks of loading."),
            ],
            halfLifeMinutes: 150
        ),

        // MARK: 29. Taurine

        Substance(
            name: "Taurine",
            aliases: ["L-Taurine", "2-Aminoethanesulfonic Acid"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 250, light: 500...1000, common: 1000...2000, strong: 2000...3000, heavy: 3000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Enhanced cardiovascular function", "Improved exercise performance", "Better electrolyte balance", "Calming effect", "Reduced muscle cramps", "Antioxidant support"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Calming Effect", description: "A mild but noticeable calming influence, sometimes described as taking the edge off without causing drowsiness."),
                SubjectiveEffect(name: "Exercise Support", description: "Improved endurance and reduced post-exercise soreness when taken consistently around workouts."),
                SubjectiveEffect(name: "Reduced Cramping", description: "A decrease in muscle cramps and spasms, particularly during and after physical activity."),
                SubjectiveEffect(name: "Cardiovascular Steadiness", description: "A subtle sense of cardiovascular stability, with less awareness of heart rate during exertion."),
                SubjectiveEffect(name: "Hydration Balance", description: "Better fluid balance and less swelling in extremities, related to improved electrolyte management."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: 30. L-Citrulline

        Substance(
            name: "L-Citrulline",
            aliases: ["Citrulline", "Citrulline Malate"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "g", doses: DoseRange(
                    threshold: 1, light: 2...3, common: 3...6, strong: 6...10, heavy: 10
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Improved blood flow", "Enhanced muscle pumps", "Better exercise endurance", "Reduced muscle soreness", "Improved nitric oxide production", "Lower blood pressure"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Muscle Pumps", description: "A pronounced fullness and tightness in working muscles during resistance training, noticeably more than baseline."),
                SubjectiveEffect(name: "Improved Blood Flow", description: "A sense of warmth and increased circulation, particularly in the extremities during exercise."),
                SubjectiveEffect(name: "Exercise Endurance", description: "An improved ability to sustain moderate-intensity exercise for longer before fatigue sets in."),
                SubjectiveEffect(name: "Reduced Soreness", description: "Less delayed-onset muscle soreness in the days following intense training sessions."),
                SubjectiveEffect(name: "Blood Pressure Reduction", description: "A subtle lowering of blood pressure that some users notice as reduced head pressure or improved comfort."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: 31. Glycine

        Substance(
            name: "Glycine",
            aliases: ["L-Glycine", "Aminoacetic Acid"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "g", doses: DoseRange(
                    threshold: 1, light: 1...3, common: 3...5, strong: 5...10, heavy: 10
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Improved sleep quality", "Enhanced collagen production", "Calming effect", "Better joint health", "Sweet taste", "Reduced inflammation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Sleep Quality Improvement", description: "Noticeably deeper and more restful sleep with reduced time to fall asleep when taken before bed."),
                SubjectiveEffect(name: "Calming Sweetness", description: "A pleasant sweet taste that makes it easy to take, with a relaxing effect that follows shortly after."),
                SubjectiveEffect(name: "Morning Freshness", description: "Waking up feeling more rested and alert, with less residual grogginess compared to other sleep aids."),
                SubjectiveEffect(name: "Joint Comfort", description: "A gradual improvement in joint comfort and flexibility over weeks of consistent supplementation."),
                SubjectiveEffect(name: "Relaxation", description: "A gentle calming effect that promotes rest without heavy sedation or cognitive impairment."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: 32. L-Arginine

        Substance(
            name: "L-Arginine",
            aliases: ["Arginine", "AAKG"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "g", doses: DoseRange(
                    threshold: 1, light: 2...3, common: 3...6, strong: 6...10, heavy: 10
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Improved blood flow", "Enhanced nitric oxide production", "Better exercise performance", "Improved wound healing", "Gastrointestinal discomfort at high doses"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Muscle Pumps", description: "Enhanced blood flow to working muscles resulting in a noticeable pump effect during exercise."),
                SubjectiveEffect(name: "Warmth in Extremities", description: "A feeling of increased warmth in hands and feet due to improved peripheral blood flow."),
                SubjectiveEffect(name: "Exercise Performance", description: "Improved endurance and recovery between sets during resistance training."),
                SubjectiveEffect(name: "Gastrointestinal Discomfort", description: "Stomach upset, bloating, or diarrhea at higher doses, especially when taken on an empty stomach."),
                SubjectiveEffect(name: "Improved Circulation", description: "A general sense of better blood flow, sometimes noticed as improved skin color and warmth."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: - Herbal

        // MARK: 33. Ashwagandha

        Substance(
            name: "Ashwagandha",
            aliases: ["Withania somnifera", "KSM-66", "Sensoril", "Indian Ginseng"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 150...300, common: 300...600, strong: 600...1000, heavy: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Reduced stress", "Lower cortisol levels", "Improved sleep quality", "Enhanced physical endurance", "Better anxiety management", "Improved thyroid function", "Increased libido"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Stress Resilience", description: "A noticeable ability to handle stressful situations with more composure and less emotional reactivity."),
                SubjectiveEffect(name: "Sleep Deepening", description: "Improved sleep depth and quality, with a more relaxed feeling at bedtime and better rest."),
                SubjectiveEffect(name: "Anxiety Reduction", description: "A tangible reduction in anxious thoughts and physical tension that develops over the first week."),
                SubjectiveEffect(name: "Physical Endurance", description: "Improved stamina during exercise and daily activities, with less perceived exertion."),
                SubjectiveEffect(name: "Libido Enhancement", description: "A gradual increase in sexual desire and function, more commonly reported with KSM-66 extracts."),
                SubjectiveEffect(name: "Emotional Groundedness", description: "A sense of being more emotionally centered and less reactive to minor daily frustrations."),
                SubjectiveEffect(name: "Thyroid Warmth", description: "For those with sluggish thyroid, a sense of improved metabolic warmth and energy."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: 34. Rhodiola Rosea

        Substance(
            name: "Rhodiola Rosea",
            aliases: ["Rhodiola", "Golden Root", "Arctic Root"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...400, strong: 400...700, heavy: 700
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Reduced fatigue", "Enhanced mental performance", "Improved stress resilience", "Better physical endurance", "Elevated mood", "Mild stimulation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Anti-Fatigue", description: "A clear reduction in mental and physical fatigue, feeling as though energy reserves are deeper and more accessible."),
                SubjectiveEffect(name: "Mild Stimulation", description: "A gentle energizing effect that feels more natural than caffeine, without jitteriness or a crash."),
                SubjectiveEffect(name: "Mood Elevation", description: "A subtle but noticeable improvement in mood and optimism, particularly during stressful periods."),
                SubjectiveEffect(name: "Stress Buffering", description: "An improved ability to maintain composure and performance under demanding conditions."),
                SubjectiveEffect(name: "Mental Performance", description: "Clearer thinking and improved task performance, especially when fatigued or under time pressure."),
                SubjectiveEffect(name: "Physical Endurance", description: "Improved stamina during exercise and reduced perception of effort during physical activity."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 240
        ),

        // MARK: 35. Valerian Root

        Substance(
            name: "Valerian Root",
            aliases: ["Valeriana officinalis", "Valerian"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 200...300, common: 300...600, strong: 600...900, heavy: 900
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Improved sleep onset", "Enhanced relaxation", "Reduced anxiety", "Sedation", "Vivid dreams", "Morning grogginess", "Distinctive odor"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Sedation", description: "A noticeable drowsiness and heaviness that promotes falling asleep, usually felt within 30-60 minutes."),
                SubjectiveEffect(name: "Sleep Onset", description: "A faster transition from wakefulness to sleep, with less time lying awake with racing thoughts."),
                SubjectiveEffect(name: "Vivid Dreams", description: "Markedly more vivid and sometimes unusual dreams, a commonly reported and distinctive effect."),
                SubjectiveEffect(name: "Morning Grogginess", description: "A residual sleepiness upon waking that can last into the morning, especially at higher doses."),
                SubjectiveEffect(name: "Distinctive Smell", description: "A strong, earthy, somewhat unpleasant odor from the capsules or tea that some find off-putting."),
                SubjectiveEffect(name: "Relaxation", description: "A deep muscle relaxation and mental unwinding that helps transition away from the stresses of the day."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 60
        ),

        // MARK: 36. St. John's Wort

        Substance(
            name: "St. John's Wort",
            aliases: ["Hypericum perforatum", "Saint John's Wort", "SJW"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 150...300, common: 300...600, strong: 600...900, heavy: 900
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Improved mood", "Reduced mild depression", "Better emotional balance", "Increased photosensitivity", "Drug interactions", "Enhanced well-being"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mood Brightening", description: "A gradual lifting of low mood over 2-4 weeks, with things feeling slightly more positive and manageable."),
                SubjectiveEffect(name: "Emotional Stabilization", description: "A smoothing of emotional ups and downs, with a more even and predictable baseline mood."),
                SubjectiveEffect(name: "Enhanced Well-Being", description: "A general sense of improved well-being and life satisfaction that develops with consistent use."),
                SubjectiveEffect(name: "Sun Sensitivity", description: "Increased sensitivity to sunlight, with skin burning more easily and eyes feeling more sensitive to glare."),
                SubjectiveEffect(name: "Reduced Rumination", description: "A decrease in repetitive negative thinking patterns, with the mind feeling less stuck on worries."),
                SubjectiveEffect(name: "Motivation Return", description: "A gradual return of interest and motivation for daily activities that had previously felt burdensome."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 30, buildRate: "slow"),
            halfLifeMinutes: 1560
        ),

        // MARK: 37. Ginkgo Biloba

        Substance(
            name: "Ginkgo Biloba",
            aliases: ["Ginkgo", "Maidenhair Tree"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 40, light: 60...120, common: 120...240, strong: 240...360, heavy: 360
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Improved memory", "Enhanced blood circulation", "Better cognitive function", "Reduced brain fog", "Improved focus", "Headache at high doses"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Memory Support", description: "A gradual improvement in recall and memory formation noticed over weeks of consistent supplementation."),
                SubjectiveEffect(name: "Brain Fog Reduction", description: "A slow but perceptible clearing of mental haziness, with thoughts feeling more accessible."),
                SubjectiveEffect(name: "Cerebral Blood Flow", description: "A subtle sense of improved mental clarity potentially related to enhanced blood flow to the brain."),
                SubjectiveEffect(name: "Focus Improvement", description: "Better sustained attention during reading and cognitive tasks, developing gradually over weeks."),
                SubjectiveEffect(name: "Headache", description: "Occasional headaches at higher doses, possibly related to changes in cerebral blood flow."),
                SubjectiveEffect(name: "Peripheral Warmth", description: "Improved circulation in hands and feet, with less coldness in the extremities."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: 38. Turmeric/Curcumin

        Substance(
            name: "Turmeric",
            aliases: ["Curcumin", "Curcuma longa", "Turmeric Extract"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 250...500, common: 500...1000, strong: 1000...2000, heavy: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Reduced inflammation", "Improved joint comfort", "Antioxidant protection", "Better digestive function", "Enhanced recovery", "Reduced muscle soreness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Joint Relief", description: "A gradual reduction in joint stiffness and discomfort, particularly noticeable in the morning or after exercise."),
                SubjectiveEffect(name: "Reduced Soreness", description: "Less muscle soreness after intense workouts, with faster recovery between training sessions."),
                SubjectiveEffect(name: "Digestive Comfort", description: "Improved digestive function with less bloating and stomach discomfort after meals."),
                SubjectiveEffect(name: "Anti-Inflammatory Feel", description: "A general sense of reduced bodily inflammation, with less puffiness and physical discomfort."),
                SubjectiveEffect(name: "Recovery Enhancement", description: "Improved physical recovery from exercise and daily wear, feeling less beaten up over time."),
            ],
            halfLifeMinutes: 120
        ),

        // MARK: 39. Milk Thistle

        Substance(
            name: "Milk Thistle",
            aliases: ["Silymarin", "Silybum marianum"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...150, common: 150...300, strong: 300...600, heavy: 600
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Improved liver function", "Enhanced detoxification", "Antioxidant protection", "Better digestion", "Reduced liver enzyme levels", "Mild laxative effect"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Liver Support", description: "A sense of improved tolerance to dietary indiscretions and alcohol, with faster recovery."),
                SubjectiveEffect(name: "Digestive Improvement", description: "Better digestion and less discomfort after rich or fatty meals."),
                SubjectiveEffect(name: "Detox Feeling", description: "A general sense of cleanliness and improved detoxification capacity over weeks of use."),
                SubjectiveEffect(name: "Reduced Bloating", description: "Less abdominal bloating and discomfort, particularly after eating."),
                SubjectiveEffect(name: "Mild Laxative Effect", description: "Slightly increased bowel frequency and softer stools, usually mild and not bothersome."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: 40. Tongkat Ali

        Substance(
            name: "Tongkat Ali",
            aliases: ["Eurycoma longifolia", "Longjack", "Malaysian Ginseng"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...400, strong: 400...600, heavy: 600
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Increased testosterone levels", "Improved libido", "Enhanced physical performance", "Better stress management", "Improved body composition", "Increased energy"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Libido Increase", description: "A noticeable improvement in sexual desire and function, often one of the first effects reported."),
                SubjectiveEffect(name: "Energy Boost", description: "Increased daily energy and reduced fatigue, with a more vibrant sense of vitality."),
                SubjectiveEffect(name: "Confidence Improvement", description: "A subtle increase in assertiveness and self-confidence that builds over weeks of use."),
                SubjectiveEffect(name: "Stress Tolerance", description: "Better ability to handle stressful situations without feeling overwhelmed or depleted."),
                SubjectiveEffect(name: "Physical Performance", description: "Improved exercise capacity and body composition over weeks, with better strength and recovery."),
                SubjectiveEffect(name: "Mood Elevation", description: "A mild but consistent improvement in overall mood and sense of well-being."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: 41. Black Seed Oil

        Substance(
            name: "Black Seed Oil",
            aliases: ["Nigella sativa", "Black Cumin Seed Oil", "Kalonji Oil"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mL", doses: DoseRange(
                    threshold: 0.5, light: 1...2, common: 2...3, strong: 3...5, heavy: 5
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Reduced inflammation", "Enhanced immune function", "Improved blood sugar regulation", "Antioxidant protection", "Better respiratory health", "Strong peppery taste"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Anti-Inflammatory Relief", description: "A reduction in general aches and inflammatory discomfort noticed over weeks of regular use."),
                SubjectiveEffect(name: "Immune Boost", description: "A sense of improved immune resilience, with fewer and milder seasonal illnesses."),
                SubjectiveEffect(name: "Blood Sugar Stability", description: "More stable energy levels and fewer post-meal energy crashes with consistent use."),
                SubjectiveEffect(name: "Respiratory Comfort", description: "Improved breathing ease and reduced congestion, particularly during allergy season."),
                SubjectiveEffect(name: "Peppery Taste", description: "A strong, spicy, peppery flavor that can be off-putting when taken straight, but manageable in capsules."),
                SubjectiveEffect(name: "Digestive Warmth", description: "A warming sensation in the stomach after ingestion, along with generally improved digestive comfort."),
            ],
            halfLifeMinutes: 480
        ),

        // MARK: 42. Ginseng

        Substance(
            name: "Ginseng",
            aliases: ["Panax ginseng", "Korean Ginseng", "Asian Ginseng", "Red Ginseng"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...400, strong: 400...600, heavy: 600
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Improved energy", "Enhanced mental clarity", "Better physical endurance", "Reduced fatigue", "Improved immune function", "Mild stimulation", "Increased libido"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Energy Vitality", description: "A noticeable increase in overall energy and vitality, often felt within hours of dosing."),
                SubjectiveEffect(name: "Mental Sharpness", description: "Improved cognitive clarity and alertness, with a sense of the mind being more engaged."),
                SubjectiveEffect(name: "Physical Endurance", description: "Better stamina during physical activity, with reduced perception of effort and fatigue."),
                SubjectiveEffect(name: "Mild Stimulation", description: "A gentle energizing effect that feels warming and invigorating without causing anxiety."),
                SubjectiveEffect(name: "Immune Strengthening", description: "A sense of improved resistance to illness over long-term supplementation."),
                SubjectiveEffect(name: "Libido Enhancement", description: "A subtle increase in sexual desire and function reported by some users."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: 43. Echinacea

        Substance(
            name: "Echinacea",
            aliases: ["Echinacea purpurea", "Coneflower"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 200...300, common: 300...500, strong: 500...1000, heavy: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Enhanced immune function", "Reduced cold severity", "Shorter illness duration", "Mild tingling in mouth", "Anti-inflammatory effects"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Immune Activation", description: "A sense of the immune system being bolstered, particularly when taken at the first sign of a cold."),
                SubjectiveEffect(name: "Cold Symptom Reduction", description: "Milder cold symptoms and faster recovery when supplementation is started early in illness onset."),
                SubjectiveEffect(name: "Mouth Tingling", description: "A distinctive tingling or numbing sensation on the tongue and lips, especially with liquid extracts."),
                SubjectiveEffect(name: "General Wellness", description: "A sense of being better protected against seasonal illnesses with consistent prophylactic use."),
                SubjectiveEffect(name: "Anti-Inflammatory Comfort", description: "A mild reduction in inflammatory symptoms like sore throat and nasal congestion during illness."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: 44. Elderberry

        Substance(
            name: "Elderberry",
            aliases: ["Sambucus nigra", "Black Elderberry"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 150...300, common: 300...600, strong: 600...1000, heavy: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Enhanced immune support", "Reduced cold and flu symptoms", "Antioxidant protection", "Anti-inflammatory effects", "Better respiratory health"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Flu Recovery", description: "Shorter duration and reduced severity of cold and flu symptoms when taken at symptom onset."),
                SubjectiveEffect(name: "Immune Fortification", description: "A sense of enhanced immune readiness during cold and flu season with regular prophylactic use."),
                SubjectiveEffect(name: "Respiratory Relief", description: "Improved breathing comfort and reduced congestion during upper respiratory infections."),
                SubjectiveEffect(name: "Pleasant Taste", description: "A naturally sweet, berry-like flavor that makes supplementation enjoyable, especially in syrup form."),
                SubjectiveEffect(name: "General Wellness", description: "An overall sense of being better protected against seasonal illness with consistent use."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: 45. Saw Palmetto

        Substance(
            name: "Saw Palmetto",
            aliases: ["Serenoa repens", "Sabal Palm"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 80, light: 160...200, common: 200...320, strong: 320...500, heavy: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Improved prostate health", "Reduced urinary frequency", "Anti-androgenic effects", "Better urinary flow", "Reduced hair loss", "Mild stomach discomfort"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Urinary Improvement", description: "A gradual reduction in urinary frequency and urgency, with better flow and less nighttime waking."),
                SubjectiveEffect(name: "Prostate Comfort", description: "Reduced discomfort and pressure associated with prostate enlargement over weeks of use."),
                SubjectiveEffect(name: "Hair Preservation", description: "A slowing of hair thinning for some users, potentially related to DHT-blocking properties."),
                SubjectiveEffect(name: "Sleep Improvement", description: "Better sleep quality from reduced nighttime urination frequency."),
                SubjectiveEffect(name: "Stomach Discomfort", description: "Mild stomach upset that some users experience, typically manageable by taking with food."),
            ],
            halfLifeMinutes: 90
        ),

        // MARK: 46. Maca Root

        Substance(
            name: "Maca Root",
            aliases: ["Lepidium meyenii", "Maca", "Peruvian Ginseng"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 250, light: 500...1000, common: 1000...2000, strong: 2000...3000, heavy: 3000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Increased energy", "Improved libido", "Enhanced fertility", "Better hormonal balance", "Improved mood", "Enhanced exercise performance"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Energy Increase", description: "A noticeable boost in daily energy and stamina that develops within the first week of use."),
                SubjectiveEffect(name: "Libido Enhancement", description: "An increase in sexual desire and arousal that is commonly reported by both men and women."),
                SubjectiveEffect(name: "Mood Uplift", description: "A gentle improvement in baseline mood and emotional well-being with consistent use."),
                SubjectiveEffect(name: "Hormonal Balance", description: "A sense of improved hormonal equilibrium, with more stable energy and mood throughout the day."),
                SubjectiveEffect(name: "Exercise Performance", description: "Improved physical endurance and strength during workouts, with better recovery afterward."),
                SubjectiveEffect(name: "Adaptogenic Resilience", description: "An improved ability to cope with physical and mental stress without feeling depleted."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: - Other Supplements

        // MARK: 47. Fish Oil

        Substance(
            name: "Fish Oil",
            aliases: ["Omega-3", "EPA/DHA", "EPA", "DHA", "Omega-3 Fatty Acids"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 250, light: 500...1000, common: 1000...2000, strong: 2000...4000, heavy: 4000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 360, max: 720),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: ["Reduced inflammation", "Improved cardiovascular health", "Better brain function", "Improved mood", "Fishy aftertaste", "Better joint mobility", "Improved skin hydration"],
            halfLifeMinutes: 1200
        ),

        // MARK: 48. CoQ10

        Substance(
            name: "CoQ10",
            aliases: ["Coenzyme Q10", "Ubiquinol", "Ubiquinone"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 30, light: 50...100, common: 100...200, strong: 200...400, heavy: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 360, max: 720),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: ["Improved cellular energy", "Enhanced heart health", "Reduced statin side effects", "Antioxidant protection", "Better exercise recovery", "Reduced migraines"],
            halfLifeMinutes: 2040
        ),

        // MARK: 49. Melatonin

        Substance(
            name: "Melatonin",
            aliases: ["N-Acetyl-5-methoxytryptamine"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.1, light: 0.25...0.5, common: 0.5...3, strong: 3...5, heavy: 5
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 300, max: 480)
                )),
                SubstanceRoute(route: .sublingual, unit: "mg", doses: DoseRange(
                    threshold: 0.1, light: 0.25...0.5, common: 0.5...2, strong: 2...5, heavy: 5
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 20),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 420)
                )),
            ],
            effects: ["Improved sleep onset", "Better circadian rhythm regulation", "Drowsiness", "Vivid dreams", "Morning grogginess", "Antioxidant effects", "Reduced jet lag"],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 14, buildRate: "slow"),
            halfLifeMinutes: 40
        ),

        // MARK: 50. Probiotics

        Substance(
            name: "Probiotics",
            aliases: ["Lactobacillus", "Bifidobacterium", "Probiotic"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "CFU", doses: DoseRange(
                    threshold: 1, light: 5...10, common: 10...25, strong: 25...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 360, max: 720),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: ["Improved gut health", "Better digestion", "Reduced bloating", "Enhanced immune function", "Improved bowel regularity", "Initial gas and bloating"],
            halfLifeMinutes: 720
        ),

        // MARK: 51. Collagen

        Substance(
            name: "Collagen",
            aliases: ["Collagen Peptides", "Hydrolyzed Collagen", "Collagen Protein"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "g", doses: DoseRange(
                    threshold: 2, light: 5...10, common: 10...15, strong: 15...25, heavy: 25
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 1080)
                )),
            ],
            effects: ["Improved skin elasticity", "Better joint comfort", "Stronger nails", "Improved hair health", "Enhanced gut lining", "Reduced wrinkles"],
            halfLifeMinutes: 840
        ),

        // MARK: 52. MCT Oil

        Substance(
            name: "MCT Oil",
            aliases: ["Medium-Chain Triglycerides", "MCT", "Caprylic Acid"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mL", doses: DoseRange(
                    threshold: 5, light: 5...10, common: 10...15, strong: 15...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 720)
                )),
            ],
            effects: ["Quick energy boost", "Enhanced mental clarity", "Improved ketone production", "Better fat metabolism", "Gastrointestinal discomfort", "Reduced appetite"],
            halfLifeMinutes: 360
        ),

        // MARK: 53. Apple Cider Vinegar

        Substance(
            name: "Apple Cider Vinegar",
            aliases: ["ACV"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mL", doses: DoseRange(
                    threshold: 5, light: 5...10, common: 10...15, strong: 15...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Improved blood sugar regulation", "Better digestion", "Reduced appetite", "Throat irritation", "Improved satiety", "Nausea at high doses"],
            halfLifeMinutes: 360
        ),

        // MARK: 54. Berberine

        Substance(
            name: "Berberine",
            aliases: ["Berberine HCl", "Berberine Hydrochloride"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 200...500, common: 500...1000, strong: 1000...1500, heavy: 1500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 300, max: 600)
                )),
            ],
            effects: ["Improved blood sugar control", "Better cholesterol levels", "Enhanced insulin sensitivity", "Gastrointestinal discomfort", "Reduced inflammation", "Weight management support"],
            halfLifeMinutes: 180
        ),

        // MARK: 55. Quercetin

        Substance(
            name: "Quercetin",
            aliases: ["Quercetin Dihydrate", "Quercetin Phytosome"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 250...500, common: 500...1000, strong: 1000...1500, heavy: 1500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 300),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 720)
                )),
            ],
            effects: ["Reduced allergy symptoms", "Anti-inflammatory effects", "Antioxidant protection", "Improved cardiovascular health", "Enhanced exercise performance", "Better immune regulation"],
            halfLifeMinutes: 660
        ),

        // MARK: 56. Resveratrol

        Substance(
            name: "Resveratrol",
            aliases: ["Trans-Resveratrol"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...250, common: 250...500, strong: 500...1000, heavy: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 300, max: 600)
                )),
            ],
            effects: ["Antioxidant protection", "Improved cardiovascular health", "Anti-aging effects", "Reduced inflammation", "Better blood sugar regulation"],
            halfLifeMinutes: 90
        ),

        // MARK: 57. Alpha-Lipoic Acid

        Substance(
            name: "Alpha-Lipoic Acid",
            aliases: ["ALA", "Lipoic Acid", "R-Lipoic Acid", "R-ALA"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...600, strong: 600...1200, heavy: 1200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Antioxidant protection", "Improved blood sugar regulation", "Enhanced nerve function", "Better mitochondrial energy", "Reduced neuropathy symptoms", "Nausea on empty stomach"],
            halfLifeMinutes: 30
        ),

        // MARK: 58. PQQ

        Substance(
            name: "PQQ",
            aliases: ["Pyrroloquinoline Quinone", "BioPQQ"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...10, common: 10...20, strong: 20...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 1080)
                )),
            ],
            effects: ["Improved mitochondrial function", "Enhanced cognitive performance", "Better sleep quality", "Increased cellular energy", "Neuroprotective effects"],
            halfLifeMinutes: 360
        ),

        // MARK: 59. Astaxanthin

        Substance(
            name: "Astaxanthin",
            aliases: ["AstaReal", "Haematococcus pluvialis"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 4...6, common: 6...12, strong: 12...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 360, max: 720),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: ["Potent antioxidant protection", "Improved skin health", "Reduced UV damage", "Better exercise recovery", "Enhanced eye health", "Reduced joint inflammation"],
            halfLifeMinutes: 360
        ),

        // MARK: 60. Glucosamine

        Substance(
            name: "Glucosamine",
            aliases: ["Glucosamine Sulfate", "Glucosamine HCl", "Glucosamine Chondroitin"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 250, light: 500...750, common: 750...1500, strong: 1500...2000, heavy: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 1080)
                )),
            ],
            effects: ["Improved joint comfort", "Reduced joint stiffness", "Enhanced cartilage repair", "Better joint mobility", "Mild gastrointestinal effects", "Reduced inflammation"],
            halfLifeMinutes: 900
        ),

        // MARK: - Herbal & Ethnobotanical

        // MARK: 61. Chamomile

        Substance(
            name: "Chamomile",
            aliases: ["Matricaria chamomilla", "German Chamomile", "Apigenin"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 200...400, common: 400...800, strong: 800...1500, heavy: 1500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Calming", "Sleep aid", "Anti-inflammatory", "Digestive aid"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Gentle Relaxation", description: "A soft, calming warmth that settles over the body within 30-60 minutes, easing tension without heavy sedation."),
                SubjectiveEffect(name: "Sleep Onset Support", description: "A gradual drowsiness that makes falling asleep feel natural and unforced, particularly effective when taken as a tea before bed."),
                SubjectiveEffect(name: "Anxiety Softening", description: "A mild reduction in anxious thoughts and physical tension, attributed to apigenin binding at GABA-A receptors."),
                SubjectiveEffect(name: "Digestive Soothing", description: "A noticeable calming of stomach discomfort, bloating, and mild cramping, especially when consumed as a warm infusion after meals."),
                SubjectiveEffect(name: "Mood Stabilization", description: "A subtle evening-out of emotional ups and downs, with irritability and restlessness feeling less prominent."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "A gentle loosening of physical tension, particularly in the jaw, shoulders, and neck, that complements the mental calming effect."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: 62. Passionflower

        Substance(
            name: "Passionflower",
            aliases: ["Passiflora incarnata", "Maypop", "Passion Vine"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 200...400, common: 400...700, strong: 700...1000, heavy: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Anxiety relief", "Sleep improvement", "GABAergic calming"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Anxiolytic Calm", description: "A noticeable quieting of anxious thoughts and nervous tension that develops within an hour, often compared to a mild benzodiazepine-like tranquility."),
                SubjectiveEffect(name: "Sleep Quality Enhancement", description: "Improved ability to fall asleep and stay asleep, with deeper rest and fewer nighttime awakenings over consistent use."),
                SubjectiveEffect(name: "Mental Quieting", description: "A reduction in racing thoughts and mental chatter, making it easier to relax and disengage from the stresses of the day."),
                SubjectiveEffect(name: "Muscle Tension Relief", description: "A gentle loosening of physical tension held in the body, particularly noticeable in those who carry stress physically."),
                SubjectiveEffect(name: "Mood Stabilization", description: "A subtle smoothing of emotional reactivity, with less irritability and a more even emotional baseline throughout the day."),
                SubjectiveEffect(name: "GABAergic Sedation", description: "A mild sedating quality mediated by GABA-A receptor modulation, producing a gentle heaviness that promotes rest without cognitive impairment."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 14, buildRate: "slow"),
            halfLifeMinutes: 360
        ),

        // MARK: 63. Lemon Balm

        Substance(
            name: "Lemon Balm",
            aliases: ["Melissa officinalis", "Melissa"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 200...400, common: 400...800, strong: 800...1600, heavy: 1600
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Calming", "Cognitive enhancement", "Antiviral", "Mild sedation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Calm Focus", description: "A unique combination of mental clarity and relaxation, where anxious distraction diminishes while cognitive sharpness is maintained or improved."),
                SubjectiveEffect(name: "Anxiety Reduction", description: "A gentle easing of nervous tension and worry that develops within 30-60 minutes, without the drowsiness of heavier sedatives."),
                SubjectiveEffect(name: "Improved Attention", description: "A subtle sharpening of sustained attention and working memory, supported by the rosmarinic acid content inhibiting GABA transaminase."),
                SubjectiveEffect(name: "Digestive Comfort", description: "A soothing effect on the gastrointestinal tract, reducing bloating and spasms when consumed as a tea or extract with meals."),
                SubjectiveEffect(name: "Mood Brightening", description: "A mild elevation of mood and sense of well-being that develops over the first hour, making daily tasks feel slightly more pleasant."),
                SubjectiveEffect(name: "Gentle Sedation", description: "At higher doses, a comfortable drowsiness that supports sleep onset without the heavy grogginess of stronger sedative herbs."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 14, buildRate: "slow"),
            halfLifeMinutes: 360
        ),

        // MARK: 64. Gotu Kola

        Substance(
            name: "Gotu Kola",
            aliases: ["Centella asiatica", "Brahmi"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 250...500, common: 500...1000, strong: 1000...2000, heavy: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 300, max: 600)
                )),
            ],
            effects: ["Cognitive enhancement", "Wound healing", "Anxiety reduction", "Venous health"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mental Clarity", description: "A gradual improvement in cognitive function, memory, and concentration that develops over days to weeks of consistent supplementation."),
                SubjectiveEffect(name: "Anxiety Relief", description: "A noticeable reduction in nervousness and stress reactivity, with a calming effect that does not impair alertness or cognitive performance."),
                SubjectiveEffect(name: "Improved Circulation", description: "A sense of better blood flow in the legs and reduced heaviness or swelling, particularly for those with venous insufficiency."),
                SubjectiveEffect(name: "Skin and Wound Support", description: "Improved healing of minor cuts, scars, and skin blemishes over weeks, attributed to increased collagen synthesis from triterpenoid compounds."),
                SubjectiveEffect(name: "Meditative Calm", description: "A contemplative, centered quality traditionally valued for meditation practice, with reduced mental restlessness and improved equanimity."),
                SubjectiveEffect(name: "Adaptogenic Balance", description: "A general sense of improved stress resilience and mental stamina that accumulates over consistent long-term use."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: 65. Blue Lotus

        Substance(
            name: "Blue Lotus",
            aliases: ["Nymphaea caerulea", "Blue Water Lily", "Sacred Blue Lily"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "g", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...10, strong: 10...15, heavy: 15
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Mild euphoria", "Relaxation", "Dream enhancement", "Mild psychoactivity"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Gentle Euphoria", description: "A mild, warm sense of well-being and contentment that develops within 30-60 minutes, sometimes described as a subtle opiate-like glow."),
                SubjectiveEffect(name: "Physical Relaxation", description: "A soothing loosening of bodily tension with a sensation of warmth spreading through the limbs, encouraging stillness and rest."),
                SubjectiveEffect(name: "Dream Enhancement", description: "Markedly more vivid, colorful, and memorable dreams when consumed before sleep, with some users reporting lucid dreaming."),
                SubjectiveEffect(name: "Mild Psychoactivity", description: "A subtle shift in perception with slightly enhanced colors and a dreamy, contemplative quality to awareness, attributed to nuciferine and aporphine alkaloids."),
                SubjectiveEffect(name: "Anxiolytic Calm", description: "A reduction in anxious thoughts and stress-related tension, with a tranquil mental state that promotes rest and introspection."),
                SubjectiveEffect(name: "Aphrodisiac Quality", description: "A subtle increase in sensuality and tactile awareness traditionally associated with the flower in ancient Egyptian use."),
                SubjectiveEffect(name: "Meditative State", description: "A contemplative, inward-focused quality to consciousness that supports meditation and quiet reflection."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 10, buildRate: "moderate"),
            halfLifeMinutes: 360
        ),

        // MARK: 65.5. Kanna

        Substance(
            name: "Kanna",
            aliases: ["Sceletium tortuosum", "Channa", "Kougoed"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...500, heavy: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 120, max: 300)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 15, light: 25...50, common: 50...100, strong: 100...200, heavy: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 2, max: 10),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 20, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: nil,
                    total: TimeRange(min: 45, max: 120)
                )),
                SubstanceRoute(route: .sublingual, unit: "mg", doses: DoseRange(
                    threshold: 15, light: 25...75, common: 75...150, strong: 150...300, heavy: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 45, max: 90),
                    offset: TimeRange(min: 45, max: 90),
                    afterglow: nil,
                    total: TimeRange(min: 90, max: 210)
                )),
            ],
            effects: ["Mood lift", "Euphoria", "Anxiety relief", "Empathogenic effects", "Appetite suppression", "Serotonin activity"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mood Elevation", description: "A noticeable lift in mood and sense of well-being that develops within 30-60 minutes orally or within minutes when insufflated, driven by serotonin reuptake inhibition."),
                SubjectiveEffect(name: "Empathogenic Warmth", description: "A gentle increase in emotional openness, compassion, and feelings of connection to others that has drawn comparisons to low-dose MDMA."),
                SubjectiveEffect(name: "Anxiolytic Calm", description: "A pronounced reduction in anxiety and social inhibition that makes social interaction feel easier and more rewarding."),
                SubjectiveEffect(name: "Mild Euphoria", description: "A pleasant, warm sense of contentment and happiness that ranges from subtle at low doses to pronounced at higher doses, particularly via insufflation."),
                SubjectiveEffect(name: "Cognitive Clarity", description: "An improved sense of mental clarity and present-moment awareness, with reduced rumination and mental noise."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A moderate reduction in hunger that accompanies the serotonergic effects, similar to other serotonin-active compounds."),
                SubjectiveEffect(name: "Tactile Enhancement", description: "A subtle increase in sensitivity to physical touch and a pleasurable quality to tactile sensations at higher doses."),
                SubjectiveEffect(name: "Nasal Irritation", description: "When insufflated, a significant burning sensation in the nasal passages that can be intensely unpleasant for several minutes before subsiding."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 360
        ),

        // MARK: 66. Wild Dagga

        Substance(
            name: "Wild Dagga",
            aliases: ["Leonotis leonurus", "Lion's Tail", "Lion's Ear"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "g", doses: DoseRange(
                    threshold: 0.5, light: 1...2, common: 2...4, strong: 4...6, heavy: 6
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 120, max: 300)
                )),
                SubstanceRoute(route: .inhalation, unit: "g", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1, common: 1...2, strong: 2...3, heavy: 3
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 15, max: 45),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: nil,
                    total: TimeRange(min: 45, max: 120)
                )),
            ],
            effects: ["Mild euphoria", "Relaxation", "Mild sedation", "Cannabis-like effects"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mild Euphoria", description: "A gentle, pleasant mood lift with a warm, content feeling that is subtle but noticeable, sometimes compared to a mild cannabis experience."),
                SubjectiveEffect(name: "Physical Relaxation", description: "A soothing loosening of muscular tension and a sense of bodily comfort that promotes rest and stillness."),
                SubjectiveEffect(name: "Mild Sedation", description: "A gentle drowsiness at higher doses that encourages relaxation and sleep without heavy cognitive impairment."),
                SubjectiveEffect(name: "Cannabis-Like Calm", description: "A subtle alteration of awareness with mild perceptual softening and relaxation that draws comparisons to low-dose cannabis."),
                SubjectiveEffect(name: "Headspace Lightening", description: "A reduction in mental noise and worry, with thoughts becoming simpler and less burdened by daily concerns."),
                SubjectiveEffect(name: "Visual Softening", description: "A very mild perceptual shift where colors may appear slightly warmer and the visual field takes on a gentle, dreamy quality when smoked."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 10, buildRate: "moderate"),
            halfLifeMinutes: 360
        ),

        // MARK: 67. Skullcap

        Substance(
            name: "Skullcap",
            aliases: ["Scutellaria lateriflora", "American Skullcap", "Mad-Dog Skullcap"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 200...500, common: 500...1000, strong: 1000...2000, heavy: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Anxiety relief", "Muscle relaxation", "Mild sedation", "GABAergic activity"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Nervous System Calming", description: "A noticeable quieting of anxious restlessness and nervous tension, with the mind feeling less agitated and more composed."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "A gentle loosening of physical tension and muscle tightness, particularly in the neck, shoulders, and jaw."),
                SubjectiveEffect(name: "Sleep Support", description: "Improved ability to fall asleep when taken before bed, with a gentle sedation that does not produce heavy morning grogginess."),
                SubjectiveEffect(name: "GABAergic Calm", description: "A GABA-mediated reduction in overactive neural excitation, producing a calm, grounded feeling without significant cognitive impairment."),
                SubjectiveEffect(name: "Emotional Steadiness", description: "A subtle stabilization of emotional reactivity, with less tendency toward irritability, frustration, or mood swings."),
                SubjectiveEffect(name: "Tension Headache Relief", description: "A reduction in tension headaches and stress-related head pressure, particularly when the headache is associated with muscular tightness."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 14, buildRate: "slow"),
            halfLifeMinutes: 360
        ),

        // MARK: 68. Damiana

        Substance(
            name: "Damiana",
            aliases: ["Turnera diffusa", "Turnera aphrodisiaca"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "g", doses: DoseRange(
                    threshold: 0.5, light: 1...2, common: 2...4, strong: 4...8, heavy: 8
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 120, max: 300)
                )),
            ],
            effects: ["Mild euphoria", "Aphrodisiac effects", "Relaxation", "Mood lift"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mild Euphoria", description: "A gentle uplift in mood with a warm, pleasant feeling of contentment that develops within 30-60 minutes of ingestion."),
                SubjectiveEffect(name: "Aphrodisiac Enhancement", description: "A subtle increase in sexual desire and arousal, traditionally used as a libido enhancer for centuries in Central and South American herbalism."),
                SubjectiveEffect(name: "Physical Relaxation", description: "A gentle loosening of bodily tension and a warm, comfortable physical state that encourages leisure and social interaction."),
                SubjectiveEffect(name: "Mood Brightening", description: "A mild improvement in emotional outlook with reduced feelings of melancholy and increased enjoyment of simple pleasures."),
                SubjectiveEffect(name: "Mild Anxiolysis", description: "A subtle reduction in anxiety and social inhibition, sometimes compared to a very mild alcohol-like social ease."),
                SubjectiveEffect(name: "Sensory Warmth", description: "A slight enhancement of tactile sensitivity and a warm, tingling quality to physical sensations throughout the body."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 14, buildRate: "slow"),
            halfLifeMinutes: 360
        ),

        // MARK: 69. Mulungu

        Substance(
            name: "Mulungu",
            aliases: ["Erythrina mulungu", "Mulungu Bark"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 200...500, common: 500...1000, strong: 1000...2000, heavy: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Anxiety relief", "Sedation", "Sleep aid", "Muscle relaxation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Anxiolytic Effect", description: "A pronounced calming of anxious thoughts and nervous tension, with the bark extract traditionally used in Brazilian folk medicine for anxiety and insomnia."),
                SubjectiveEffect(name: "Sedation", description: "A moderate drowsiness and physical heaviness that develops within an hour, making it well-suited for evening use as a sleep preparation."),
                SubjectiveEffect(name: "Muscle Relaxation", description: "A noticeable loosening of muscular tension and physical stress, with the body feeling heavier and more relaxed."),
                SubjectiveEffect(name: "Sleep Quality Improvement", description: "Deeper, more restorative sleep with easier onset and fewer nighttime awakenings when taken consistently before bed."),
                SubjectiveEffect(name: "Emotional Calming", description: "A reduction in emotional reactivity and stress response, with daily worries feeling less pressing and urgent."),
                SubjectiveEffect(name: "Mild Mood Elevation", description: "A gentle improvement in overall mood and sense of well-being that accompanies the anxiolytic and relaxing effects."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 14, buildRate: "slow"),
            halfLifeMinutes: 360
        ),

        // MARK: 70. Cordyceps

        Substance(
            name: "Cordyceps",
            aliases: ["Cordyceps militaris", "Cordyceps sinensis", "Caterpillar Fungus"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 250, light: 500...1000, common: 1000...2000, strong: 2000...4000, heavy: 4000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 300),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 300, max: 720)
                )),
            ],
            effects: ["Improved endurance", "Energy boost", "Immune support", "Respiratory support"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Endurance Enhancement", description: "A noticeable improvement in physical stamina and exercise capacity that develops over days of consistent use, attributed to improved oxygen utilization."),
                SubjectiveEffect(name: "Sustained Energy", description: "A gentle, non-jittery increase in daily energy levels that feels more like improved vitality than stimulant-driven alertness."),
                SubjectiveEffect(name: "Respiratory Improvement", description: "A subtle sense of deeper, easier breathing during exertion, historically valued by Tibetan herders at high altitudes."),
                SubjectiveEffect(name: "Immune Resilience", description: "A general sense of improved resistance to seasonal illness and faster recovery from minor infections with regular use."),
                SubjectiveEffect(name: "Libido Enhancement", description: "A mild increase in sexual energy and vitality reported by some users, consistent with traditional use as a kidney tonic."),
                SubjectiveEffect(name: "Recovery Support", description: "Reduced post-exercise fatigue and faster recovery between workouts, with less lingering soreness and tiredness."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: 71. Reishi Mushroom

        Substance(
            name: "Reishi Mushroom",
            aliases: ["Ganoderma lucidum", "Lingzhi", "Reishi"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 250, light: 500...1000, common: 1000...2000, strong: 2000...4000, heavy: 4000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 300),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 300, max: 720)
                )),
            ],
            effects: ["Immune modulation", "Stress reduction", "Improved sleep", "Anti-inflammatory"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Stress Resilience", description: "A gradual improvement in the ability to handle stress without becoming overwhelmed, developing over weeks of consistent supplementation."),
                SubjectiveEffect(name: "Sleep Deepening", description: "Improved sleep quality with deeper rest and a more relaxed transition to sleep, particularly noticeable after 1-2 weeks of daily use."),
                SubjectiveEffect(name: "Immune Strengthening", description: "A sense of improved immune function with fewer and milder colds, attributed to beta-glucan-mediated immune modulation."),
                SubjectiveEffect(name: "Calming Effect", description: "A gentle, grounding sense of calm that accumulates over time, reducing baseline anxiety and nervous tension."),
                SubjectiveEffect(name: "Anti-Inflammatory Comfort", description: "A subtle reduction in chronic aches and inflammatory discomfort over weeks of consistent use."),
                SubjectiveEffect(name: "General Vitality", description: "An overall sense of improved health, resilience, and well-being that develops gradually with long-term supplementation."),
            ],
            halfLifeMinutes: 360
        ),

        // MARK: 72. Turkey Tail Mushroom

        Substance(
            name: "Turkey Tail Mushroom",
            aliases: ["Trametes versicolor", "Coriolus versicolor", "PSK"],
            category: .supplement,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 250, light: 500...1000, common: 1000...2000, strong: 2000...4000, heavy: 4000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 300),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 300, max: 720)
                )),
            ],
            effects: ["Immune support", "Gut health", "Antioxidant"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Immune Enhancement", description: "A gradual strengthening of immune function noticed as fewer colds and faster recovery from illness, attributed to polysaccharopeptides PSK and PSP."),
                SubjectiveEffect(name: "Digestive Improvement", description: "Better gut health and regularity over weeks of use, as the prebiotic polysaccharides support beneficial gut bacteria growth."),
                SubjectiveEffect(name: "General Well-Being", description: "A subtle but steady improvement in overall vitality and sense of health that develops with consistent long-term supplementation."),
                SubjectiveEffect(name: "Energy Steadiness", description: "A mild stabilization of daily energy levels with fewer dips and crashes, likely related to improved gut and immune function."),
                SubjectiveEffect(name: "Reduced Inflammation", description: "A gradual decrease in background inflammatory discomfort and joint stiffness over weeks of consistent use."),
            ],
            halfLifeMinutes: 360
        ),

    ]
    // swiftlint:enable function_body_length
}
