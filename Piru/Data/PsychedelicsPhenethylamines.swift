import Foundation

extension SubstanceLibrary {
    static let psychedelicsPhenethylamines: [Substance] = [

        // MARK: - 2C-x Series

        // MARK: 2C-B

        Substance(
            name: "2C-B",
            aliases: ["Nexus", "Bees", "Venus", "2CB"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 5...15, common: 15...25, strong: 25...45, heavy: 45
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 90, max: 150),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 240, max: 420)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...10, strong: 10...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 60, max: 90),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 120, max: 240)
                )),
                SubstanceRoute(route: .rectal, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 3...10, common: 10...20, strong: 20...35, heavy: 35
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 30),
                    comeup: TimeRange(min: 10, max: 25),
                    peak: TimeRange(min: 75, max: 135),
                    offset: TimeRange(min: 45, max: 100),
                    afterglow: TimeRange(min: 90, max: 300),
                    total: TimeRange(min: 200, max: 360)
                )),
            ],
            effects: ["Visual enhancement", "Color intensification", "Euphoria", "Tactile enhancement", "Body high", "Nausea", "Increased empathy", "Pattern recognition enhancement", "Giggling", "Sensory enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Tactile Enhancement", description: "A dramatic increase in sensitivity to physical touch, where textures feel extraordinarily detailed and pleasurable and skin contact becomes intensely gratifying."),
                SubjectiveEffect(name: "Color Intensification", description: "Colors appear vibrant and hyper-saturated, with the visual world seeming to glow as though lit from within, especially at common to strong doses."),
                SubjectiveEffect(name: "Body High", description: "A warm, pleasurable tingling sensation that spreads through the body in waves, often described as an electric warmth radiating from the core."),
                SubjectiveEffect(name: "Empathogenic Warmth", description: "A gentle increase in feelings of emotional openness and connection to others that gives 2C-B a reputation for bridging psychedelic and entactogenic effects."),
                SubjectiveEffect(name: "Visual Patterning", description: "Colorful, flowing visual patterns that overlay surfaces, often more organic and rounded than the sharp geometry of lysergamides, with a neon quality."),
                SubjectiveEffect(name: "Nausea on Come-Up", description: "Stomach discomfort and queasiness during the onset phase that typically resolves once peak effects are reached, more common with higher oral doses."),
                SubjectiveEffect(name: "Spontaneous Giggling", description: "Frequent fits of laughter triggered by minor observations, contributing to an overall lighthearted and playful quality to the experience."),
                SubjectiveEffect(name: "Sensory Enhancement", description: "A global increase in sensory acuity where all senses feel sharpened and enriched, from taste and smell to visual detail and sound quality."),
                SubjectiveEffect(name: "Manageable Headspace", description: "A relatively clear and lucid mental state compared to other psychedelics, with less thought confusion and a sense of being able to function."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 90
        ),

        // MARK: 2C-C

        Substance(
            name: "2C-C",
            aliases: ["2CC"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 15...25, common: 25...50, strong: 50...80, heavy: 80
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 180),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 240, max: 420)
                )),
            ],
            effects: ["Mild visuals", "Relaxation", "Euphoria", "Sedation", "Color enhancement", "Gentle body high", "Mood lift", "Reduced anxiety"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Gentle Sedation", description: "A calming, relaxing quality that distinguishes 2C-C from more stimulating phenethylamines, with a sense of physical heaviness and contentment."),
                SubjectiveEffect(name: "Mild Visual Enhancement", description: "Subtle visual effects including gentle color brightening and slight surface breathing, without the intense patterning of stronger 2C compounds."),
                SubjectiveEffect(name: "Anxiolytic Warmth", description: "A pronounced reduction in anxiety and worry, with a warm blanket-like sense of safety and comfort that feels deeply reassuring."),
                SubjectiveEffect(name: "Gentle Body High", description: "A soft, warm physical sensation that is more relaxing than stimulating, encouraging stillness and comfortable repose."),
                SubjectiveEffect(name: "Mood Elevation", description: "A reliable but gentle lift in mood and outlook, producing quiet contentment rather than intense euphoria."),
                SubjectiveEffect(name: "Color Enhancement", description: "Mild intensification of color saturation where the world appears slightly more vivid and appealing without dramatic distortion."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 120
        ),

        // MARK: 2C-D

        Substance(
            name: "2C-D",
            aliases: ["2CD"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...25, common: 25...50, strong: 50...75, heavy: 75
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 90, max: 150),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Mental clarity", "Mild visuals", "Cognitive enhancement", "Mood lift", "Increased focus", "Light body high", "Color enhancement", "Thought acceleration"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Cognitive Enhancement", description: "A noticeable sharpening of mental clarity and analytical thinking, often described as a psychedelic nootropic that enhances focus and conceptual reasoning."),
                SubjectiveEffect(name: "Thought Acceleration", description: "Increased speed of thought processing with enhanced ability to make connections between ideas, producing a stimulated and productive mental state."),
                SubjectiveEffect(name: "Mild Visual Enhancement", description: "Subtle visual effects limited to slight color enhancement and mild pattern recognition, making it one of the least visually active 2C compounds."),
                SubjectiveEffect(name: "Mood Lift", description: "A clean, functional improvement in mood and motivation without the emotional overwhelm of stronger psychedelics."),
                SubjectiveEffect(name: "Increased Focus", description: "Enhanced ability to concentrate on tasks and ideas, making 2C-D sometimes described as a tool compound rather than a recreational one."),
                SubjectiveEffect(name: "Light Body High", description: "A subtle physical stimulation and warmth that provides mild energizing effects without significant body load or discomfort."),
                SubjectiveEffect(name: "Color Enhancement", description: "Gentle brightening and enrichment of colors that makes the visual environment appear slightly more vivid and defined."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 120
        ),

        // MARK: 2C-E

        Substance(
            name: "2C-E",
            aliases: ["2CE", "Aquarust"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 5...10, common: 10...20, strong: 20...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 480),
                    total: TimeRange(min: 360, max: 600)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...10, strong: 10...15, heavy: 15
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 10, max: 30),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 300),
                    total: TimeRange(min: 240, max: 420)
                )),
            ],
            effects: ["Intense visuals", "Deep introspection", "Body load", "Nausea", "Geometric patterns", "Thought loops", "Emotional intensity", "Synesthesia", "Time distortion", "Difficulty communicating"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Intense Visual Geometry", description: "Highly detailed, complex geometric patterns that can rival tryptamines in visual intensity, with deeply layered fractal structures and rapid morphing at higher doses."),
                SubjectiveEffect(name: "Significant Body Load", description: "Pronounced physical discomfort including nausea, muscle tension, and gastrointestinal distress that is a hallmark of the 2C-E experience, particularly during come-up."),
                SubjectiveEffect(name: "Deep Introspection", description: "A powerful inward pull toward examining personal psychology, memories, and emotional patterns with sometimes uncomfortable but often transformative honesty."),
                SubjectiveEffect(name: "Emotional Overwhelm", description: "Intense amplification of emotional states that can shift rapidly between profound beauty and challenging difficulty, requiring careful management of set and setting."),
                SubjectiveEffect(name: "Thought Loops", description: "Repetitive cognitive cycling where the same thoughts or questions recur persistently, sometimes with an unsettling quality at higher doses."),
                SubjectiveEffect(name: "Synesthesia", description: "Cross-sensory experiences where sounds produce colors, textures carry emotional weight, and sensory modalities blend in unusual combinations."),
                SubjectiveEffect(name: "Communication Difficulty", description: "A marked difficulty in formulating and expressing thoughts verbally, with ideas feeling too complex or abstract to translate into language."),
                SubjectiveEffect(name: "Time Distortion", description: "Significant warping of temporal perception where the long duration of the experience is further stretched by subjective time dilation."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 120
        ),

        // MARK: 2C-I

        Substance(
            name: "2C-I",
            aliases: ["2CI"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 5...12, common: 12...22, strong: 22...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 180, max: 300),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 420, max: 660)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...10, strong: 10...18, heavy: 18
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 10, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Visual enhancement", "Stimulation", "Euphoria", "Pattern recognition", "Color intensification", "Body high", "Increased sociability", "Nausea", "Vasoconstriction"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Vivid Visual Enhancement", description: "Rich, colorful visual effects featuring flowing patterns, enhanced textures, and saturated colors that are visually engaging without being overwhelming."),
                SubjectiveEffect(name: "Physical Stimulation", description: "A notable stimulating energy that encourages physical activity and movement, with a buzzing, energized quality to the body high."),
                SubjectiveEffect(name: "Enhanced Sociability", description: "Increased comfort and fluency in social interactions, with greater empathy and an easy, flowing conversational style."),
                SubjectiveEffect(name: "Color Intensification", description: "Dramatic enhancement of color perception where the visual world appears painted in brighter, more vivid tones with rich saturation."),
                SubjectiveEffect(name: "Pattern Recognition", description: "Enhanced ability to perceive patterns and meaning in textures, surfaces, and visual noise, with ordinary objects becoming fascinating and detailed."),
                SubjectiveEffect(name: "Body High", description: "A warm, tingling physical sensation that complements the stimulating quality, often described as an electric buzz radiating through the limbs."),
                SubjectiveEffect(name: "Euphoria", description: "Positive mood elevation with a sense of well-being and contentment that feels natural and socially enhancing."),
                SubjectiveEffect(name: "Vasoconstriction", description: "Mild to moderate tightening of blood vessels that can cause cold fingers and toes, and an uncomfortable feeling of physical tension."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 120
        ),

        // MARK: 2C-P

        Substance(
            name: "2C-P",
            aliases: ["2CP"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...4, common: 4...8, strong: 8...12, heavy: 12, fatal: 80
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 240, max: 360),
                    offset: TimeRange(min: 180, max: 300),
                    afterglow: TimeRange(min: 240, max: 720),
                    total: TimeRange(min: 600, max: 960)
                )),
            ],
            effects: ["Intense visuals", "Very long duration", "Deep introspection", "Severe body load", "Nausea", "Emotional amplification", "Geometric hallucinations", "Time distortion", "Vasoconstriction", "Thought loops"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Extreme Duration", description: "An exceptionally long experience lasting 10-16 hours, with a very slow onset of 2-3 hours that requires patience and can lead to dangerous redosing if not respected."),
                SubjectiveEffect(name: "Intense Visual Geometry", description: "Deeply complex and overwhelming geometric hallucinations that can fill the entire visual field, with intricate fractal structures and vivid color spectra."),
                SubjectiveEffect(name: "Severe Body Load", description: "Significant physical discomfort including intense nausea, vasoconstriction, muscle tension, and gastrointestinal distress that persists throughout the experience."),
                SubjectiveEffect(name: "Deep Introspection", description: "An extremely powerful inward pull that forces confrontation with deep psychological material, making it one of the most introspective phenethylamines."),
                SubjectiveEffect(name: "Emotional Amplification", description: "Dramatic intensification of emotional states where feelings become overwhelming and all-encompassing, requiring careful preparation and setting."),
                SubjectiveEffect(name: "Thought Loops", description: "Persistent recursive thinking patterns that can become distressing at higher doses, with the same ideas cycling with increasing intensity."),
                SubjectiveEffect(name: "Vasoconstriction", description: "Pronounced blood vessel constriction causing cold extremities, numbness, and physical discomfort that is more severe than most other 2C compounds."),
                SubjectiveEffect(name: "Time Distortion", description: "Profound temporal distortion where the already long duration feels dramatically extended, with hours feeling like days at higher doses."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 180
        ),

        // MARK: 2C-T-2

        Substance(
            name: "2C-T-2",
            aliases: ["2CT2"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 5...10, common: 10...20, strong: 20...30, heavy: 30, fatal: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 180),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Visual enhancement", "Euphoria", "Body high", "Nausea", "Introspection", "Color shifting", "Emotional warmth", "Stimulation", "Geometric patterns"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Visual Enhancement", description: "Moderately intense visual effects with flowing patterns, color shifting, and enhanced textures that have a warm, organic quality."),
                SubjectiveEffect(name: "Emotional Warmth", description: "A gentle empathogenic quality with increased feelings of emotional openness, compassion, and connection to others."),
                SubjectiveEffect(name: "Color Shifting", description: "Colors appear to change and morph dynamically, with hues drifting and surfaces taking on iridescent, shifting qualities."),
                SubjectiveEffect(name: "Body High", description: "A warm, pleasurable physical sensation with tingling and waves of comfort, sometimes accompanied by mild stimulating energy."),
                SubjectiveEffect(name: "Nausea", description: "Gastrointestinal discomfort during onset that is common with thio-substituted 2C compounds, sometimes requiring anti-nausea preparation."),
                SubjectiveEffect(name: "Geometric Patterns", description: "Colorful geometric overlays on surfaces and in closed-eye vision, with a softer and more organic character than the sharp geometry of tryptamines."),
                SubjectiveEffect(name: "Introspective Quality", description: "A moderate pull toward self-examination and emotional processing, balanced with enough outward engagement to remain social."),
                SubjectiveEffect(name: "Stimulation", description: "A mild to moderate physical energization that encourages activity and movement without the jittery quality of amphetamine stimulants."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 360
        ),

        // MARK: 2C-T-7

        Substance(
            name: "2C-T-7",
            aliases: ["2CT7", "Blue Mystic"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...15, common: 15...25, strong: 25...40, heavy: 40, fatal: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 360, max: 540)
                )),
            ],
            effects: ["Vivid visuals", "Euphoria", "Nausea", "Body load", "Introspection", "Emotional sensitivity", "Color enhancement", "Pattern recognition", "Spiritual experiences"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Vivid Visual Patterning", description: "Rich, colorful visual patterns that are notably vivid and immersive, with flowing organic geometry and saturated neon colors at higher doses."),
                SubjectiveEffect(name: "Emotional Sensitivity", description: "Heightened emotional receptivity where feelings become more intense and nuanced, with deep empathy and vulnerability to emotional stimuli."),
                SubjectiveEffect(name: "Spiritual Quality", description: "A tendency toward mystical or transcendent experiences, with feelings of cosmic connection, unity, and existential significance."),
                SubjectiveEffect(name: "Body Load", description: "Moderate to significant physical discomfort including nausea and muscle tension, typical of thio-substituted phenethylamines."),
                SubjectiveEffect(name: "Nausea", description: "Gastrointestinal distress that is particularly prominent during onset and can be severe, sometimes leading to vomiting before the psychedelic effects fully manifest."),
                SubjectiveEffect(name: "Color Enhancement", description: "Dramatic intensification and shifting of colors, with the visual world appearing richly painted and luminous."),
                SubjectiveEffect(name: "Deep Introspection", description: "A powerful orientation toward inner exploration and processing of emotional and psychological material with transformative potential."),
                SubjectiveEffect(name: "Euphoria", description: "Waves of intense well-being and bliss that can have a profound, spiritually-tinged quality distinct from simple pleasure."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 480
        ),

        // MARK: 2C-T-21

        Substance(
            name: "2C-T-21",
            aliases: ["2CT21"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 4...8, common: 8...12, strong: 12...18, heavy: 18
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 180),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Mild visuals", "Euphoria", "Color enhancement", "Body high", "Introspection", "Mood lift", "Nausea", "Gentle stimulation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mild Visual Enhancement", description: "Subtle visual effects including gentle color brightening and mild pattern enhancement, consistent with the gentler character of this thio-substituted compound."),
                SubjectiveEffect(name: "Gentle Euphoria", description: "A mild, warm sense of well-being and contentment that feels soft and manageable rather than overwhelming."),
                SubjectiveEffect(name: "Color Enhancement", description: "Modest intensification of color perception where the world appears slightly more vibrant and visually appealing."),
                SubjectiveEffect(name: "Mood Lift", description: "A reliable improvement in mood and outlook with a positive, optimistic quality that feels natural and grounded."),
                SubjectiveEffect(name: "Body High", description: "A gentle, pleasant physical warmth and tingling that complements the mild psychedelic effects without significant discomfort."),
                SubjectiveEffect(name: "Gentle Introspection", description: "A mild tendency toward self-reflection that feels productive and non-threatening, without the intense psychological depth of stronger compounds."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 360
        ),

        // MARK: 2C-B-FLY

        Substance(
            name: "2C-B-FLY",
            aliases: ["2CBFLY"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 5...10, common: 10...18, strong: 18...25, heavy: 25
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 75),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 180, max: 300),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 480, max: 720)
                )),
            ],
            effects: ["Visual enhancement", "Long duration", "Euphoria", "Body load", "Color intensification", "Stimulation", "Nausea", "Pattern recognition", "Tactile enhancement", "Vasoconstriction"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Extended Duration", description: "A notably long experience lasting 8-12 hours, significantly longer than standard 2C-B, requiring commitment to a full-day experience."),
                SubjectiveEffect(name: "Visual Enhancement", description: "Colorful visual effects with flowing patterns and color intensification that share 2C-B's visual character but persist much longer."),
                SubjectiveEffect(name: "Tactile Enhancement", description: "Heightened sensitivity to touch and physical sensation, similar to 2C-B, with textures feeling more detailed and pleasurable."),
                SubjectiveEffect(name: "Body Load", description: "Moderate physical discomfort and tension that is more pronounced than 2C-B, likely due to the fused ring system and longer duration."),
                SubjectiveEffect(name: "Stimulation", description: "A sustained physical and mental energy that persists throughout the long duration, sometimes making it difficult to rest or sleep."),
                SubjectiveEffect(name: "Color Intensification", description: "Strong enhancement of color saturation and vibrancy, with the visual world appearing deeply colorful and luminous."),
                SubjectiveEffect(name: "Vasoconstriction", description: "Noticeable blood vessel constriction causing cold extremities and physical tension, more pronounced than with standard 2C-B."),
                SubjectiveEffect(name: "Pattern Recognition", description: "Enhanced perception of patterns and visual detail in surfaces and textures, with ordinary objects becoming visually fascinating."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 480
        ),

        // MARK: 2C-H

        Substance(
            name: "2C-H",
            aliases: ["2CH", "2,5-Dimethoxyphenethylamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...400, strong: 400...600, heavy: 600
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 60),
                    comeup: TimeRange(min: 20, max: 45),
                    peak: TimeRange(min: 90, max: 240),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 240, max: 540)
                )),
            ],
            effects: ["Very mild visuals", "Subtle mood lift", "Light body high", "Slight color enhancement", "Minimal psychedelic effects", "Mild stimulation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Minimal Psychedelic Activity", description: "Extremely subtle psychedelic effects even at high doses, as 2C-H is the unsubstituted parent compound of the 2C series with very low potency."),
                SubjectiveEffect(name: "Subtle Mood Lift", description: "A barely perceptible improvement in mood and slight sense of well-being, more akin to a mild stimulant than a psychedelic."),
                SubjectiveEffect(name: "Light Body High", description: "A faint physical warmth and slight tingling that is more noticeable than any visual or cognitive effects."),
                SubjectiveEffect(name: "Slight Color Enhancement", description: "Minimal brightening of color perception that requires attention to notice, representing the threshold of phenethylamine psychedelic activity."),
                SubjectiveEffect(name: "Mild Stimulation", description: "A very gentle increase in physical energy and alertness, consistent with the phenethylamine backbone but without significant psychedelic overlay."),
                SubjectiveEffect(name: "High Dose Requirement", description: "Doses of several hundred milligrams are needed for any perceptible effects, making it impractical and rarely used as a standalone psychedelic."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 240
        ),

        // MARK: - DOx Series

        // MARK: DOM

        Substance(
            name: "DOM",
            aliases: ["STP", "2,5-Dimethoxy-4-methylamphetamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...3, common: 3...5, strong: 5...10, heavy: 10
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 300, max: 480),
                    offset: TimeRange(min: 180, max: 300),
                    afterglow: TimeRange(min: 360, max: 720),
                    total: TimeRange(min: 840, max: 1440)
                )),
            ],
            effects: ["Very long duration", "Visual enhancement", "Stimulation", "Euphoria", "Introspection", "Geometric patterns", "Color intensification", "Body load", "Vasoconstriction", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Extreme Duration", description: "An exceptionally long experience lasting 14-20 hours, with a slow 2-3 hour onset that requires patience and commitment to a multi-day schedule disruption."),
                SubjectiveEffect(name: "Pronounced Stimulation", description: "Strong amphetamine-like physical and mental stimulation that persists throughout the entire duration, making sleep impossible for many hours after dosing."),
                SubjectiveEffect(name: "Visual Geometry", description: "Complex, angular geometric patterns with vivid color spectra that emerge slowly but become richly detailed and immersive at the peak."),
                SubjectiveEffect(name: "Vasoconstriction", description: "Significant blood vessel constriction causing cold extremities, physical tension, and an uncomfortable tightness that persists throughout the long experience."),
                SubjectiveEffect(name: "Color Intensification", description: "Dramatic enhancement of color perception with vivid, almost electric quality to hues, making the visual world appear painted in neon tones."),
                SubjectiveEffect(name: "Body Load", description: "Persistent physical discomfort including muscle tension, jaw clenching, and restless energy that compounds over the long duration."),
                SubjectiveEffect(name: "Insomnia", description: "Inability to sleep for 16-24 hours after dosing due to the powerful stimulant effects, requiring careful timing and recovery planning."),
                SubjectiveEffect(name: "Deep Introspection", description: "Extended periods of deep self-examination facilitated by the long duration, allowing thorough processing of psychological material over many hours."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 900
        ),

        // MARK: DOC

        Substance(
            name: "DOC",
            aliases: ["2,5-Dimethoxy-4-chloroamphetamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 1...1.5, common: 1.5...3, strong: 3...5, heavy: 5, fatal: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 300, max: 480),
                    offset: TimeRange(min: 180, max: 300),
                    afterglow: TimeRange(min: 360, max: 720),
                    total: TimeRange(min: 720, max: 1200)
                )),
            ],
            effects: ["Very long duration", "Intense visuals", "Strong stimulation", "Euphoria", "Vasoconstriction", "Introspection", "Geometric patterns", "Body load", "Insomnia", "Time distortion"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Intense Visual Geometry", description: "Highly detailed and complex geometric patterns considered among the most visually impressive of the DOx series, with vivid colors and deep layering."),
                SubjectiveEffect(name: "Extreme Duration", description: "An experience lasting 12-24 hours with a very slow 1-3 hour onset, requiring a full day commitment and careful planning around sleep and responsibilities."),
                SubjectiveEffect(name: "Strong Stimulation", description: "Powerful amphetamine-like energy and mental activation that persists throughout, creating a wired, alert state that prevents rest."),
                SubjectiveEffect(name: "Vasoconstriction", description: "Pronounced blood vessel constriction causing cold, pale extremities and physical tension that is a hallmark discomfort of the DOx class."),
                SubjectiveEffect(name: "Time Distortion", description: "Severe warping of temporal perception where the already extreme duration feels further extended, with hours feeling like days."),
                SubjectiveEffect(name: "Euphoria", description: "Waves of intense well-being and bliss that can be very rewarding but alternate with periods of physical discomfort."),
                SubjectiveEffect(name: "Insomnia", description: "Inability to sleep for 18-30 hours after dosing, with the stimulant effects outlasting the psychedelic effects and requiring recovery time."),
                SubjectiveEffect(name: "Body Load", description: "Significant and persistent physical discomfort from vasoconstriction, muscle tension, and stimulant effects compounding over the long duration."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 1200
        ),

        // MARK: DOB

        Substance(
            name: "DOB",
            aliases: ["2,5-Dimethoxy-4-bromoamphetamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.2, light: 0.5...1, common: 1...2, strong: 2...3, heavy: 3, fatal: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 360, max: 600),
                    offset: TimeRange(min: 240, max: 360),
                    afterglow: TimeRange(min: 360, max: 720),
                    total: TimeRange(min: 1080, max: 1800)
                )),
            ],
            effects: ["Very long duration", "Intense visuals", "Strong stimulation", "Vasoconstriction", "Euphoria", "Body load", "Geometric patterns", "Color shifting", "Insomnia", "Nausea"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Extreme Duration", description: "One of the longest-lasting psychedelics with effects persisting 18-30 hours, requiring extreme commitment and planning for safe use."),
                SubjectiveEffect(name: "Intense Visual Hallucinations", description: "Powerfully vivid geometric patterns and visual distortions with color shifting and morphing that can become overwhelming at higher doses."),
                SubjectiveEffect(name: "Severe Vasoconstriction", description: "Very pronounced blood vessel constriction that is among the most significant of any psychedelic phenethylamine, causing serious physical discomfort."),
                SubjectiveEffect(name: "Strong Stimulation", description: "Intense amphetamine-type stimulation with physical restlessness, jaw clenching, and an inability to relax throughout the multi-day experience."),
                SubjectiveEffect(name: "Color Shifting", description: "Dynamic changes in perceived color where hues morph, shift, and flow across surfaces in constantly evolving patterns."),
                SubjectiveEffect(name: "Nausea", description: "Gastrointestinal distress that commonly accompanies the onset and may persist, adding to the overall physical challenge of the experience."),
                SubjectiveEffect(name: "Insomnia", description: "Profound inability to sleep for 24-36 hours, with stimulant effects far outlasting the psychedelic components and causing exhaustion."),
                SubjectiveEffect(name: "Body Load", description: "Severe and persistent physical discomfort that is a defining characteristic, with vasoconstriction, tension, and nausea compounding throughout."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 1080
        ),

        // MARK: DOI

        Substance(
            name: "DOI",
            aliases: ["2,5-Dimethoxy-4-iodoamphetamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 1...1.5, common: 1.5...3, strong: 3...5, heavy: 5
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 300, max: 480),
                    offset: TimeRange(min: 180, max: 300),
                    afterglow: TimeRange(min: 360, max: 720),
                    total: TimeRange(min: 840, max: 1440)
                )),
            ],
            effects: ["Very long duration", "Intense visuals", "Stimulation", "Vasoconstriction", "Body load", "Euphoria", "Geometric hallucinations", "Introspection", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Extreme Duration", description: "A very long experience of 16-24 hours that is characteristic of the DOx class, with a slow onset that demands patience and preparation."),
                SubjectiveEffect(name: "Intense Visual Geometry", description: "Detailed, complex geometric hallucinations with bright color spectra and deep layering, considered highly visual even within the DOx series."),
                SubjectiveEffect(name: "Stimulation", description: "Significant amphetamine-like stimulation with increased physical energy, mental alertness, and an inability to sit still or relax."),
                SubjectiveEffect(name: "Vasoconstriction", description: "Prominent blood vessel constriction causing peripheral coldness, numbness, and an uncomfortable tightness throughout the body."),
                SubjectiveEffect(name: "Body Load", description: "Persistent physical discomfort from the combination of vasoconstriction, stimulation, and muscle tension sustained over many hours."),
                SubjectiveEffect(name: "Deep Introspection", description: "The extended duration facilitates very deep psychological exploration, allowing extended processing of emotional and existential themes."),
                SubjectiveEffect(name: "Euphoria", description: "Periods of intense bliss and well-being interspersed with the physical challenges, creating a rollercoaster quality to the emotional experience."),
                SubjectiveEffect(name: "Insomnia", description: "Inability to sleep for 20-28 hours after dosing due to persistent stimulant activity, requiring careful scheduling and recovery time."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 1080
        ),

        // MARK: DON

        Substance(
            name: "DON",
            aliases: ["2,5-Dimethoxy-4-nitroamphetamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...3, common: 3...5, strong: 5...7, heavy: 7
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 300, max: 480),
                    offset: TimeRange(min: 180, max: 300),
                    afterglow: TimeRange(min: 360, max: 720),
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Long duration", "Visual enhancement", "Stimulation", "Body load", "Vasoconstriction", "Introspection", "Color enhancement", "Nausea"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Long Duration", description: "An extended experience of 8-15 hours, shorter than some DOx compounds but still requiring significant time commitment and planning."),
                SubjectiveEffect(name: "Visual Enhancement", description: "Moderate visual effects with color enhancement and geometric patterning, less intense than DOC or DOI but sustained over the long duration."),
                SubjectiveEffect(name: "Stimulation", description: "Amphetamine-like physical and mental energy that produces restlessness and alertness throughout the experience."),
                SubjectiveEffect(name: "Vasoconstriction", description: "Blood vessel constriction typical of the DOx class, causing cold extremities and physical tension."),
                SubjectiveEffect(name: "Body Load", description: "Moderate physical discomfort from sustained stimulation, vasoconstriction, and muscle tension over the extended duration."),
                SubjectiveEffect(name: "Nausea", description: "Gastrointestinal discomfort during onset that can be significant, sometimes requiring preparation with anti-nausea measures."),
                SubjectiveEffect(name: "Color Enhancement", description: "Mild to moderate brightening and enrichment of color perception, with the visual world appearing more vivid and saturated."),
                SubjectiveEffect(name: "Introspection", description: "A moderate tendency toward self-examination and contemplation facilitated by the extended duration of the experience."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 960
        ),

        // MARK: - NBOMe Series

        // MARK: 25I-NBOMe

        Substance(
            name: "25I-NBOMe",
            aliases: ["N-Bomb", "25I", "Smiles", "Nova"],
            category: .psychedelic,
            defaultRoute: .sublingual,
            routes: [
                SubstanceRoute(route: .sublingual, unit: "µg", doses: DoseRange(
                    threshold: 50, light: 200...400, common: 400...700, strong: 700...1000, heavy: 1000, fatal: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Intense visuals", "Strong stimulation", "Euphoria", "Vasoconstriction", "Color intensification", "Pattern recognition", "Body load", "Numbness at application site", "Confusion", "Tachycardia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Intense Visual Geometry", description: "Extremely vivid, neon-colored geometric patterns and visual distortions that are among the most visually intense of any psychedelic, with rapid morphing."),
                SubjectiveEffect(name: "Sublingual Numbness", description: "Pronounced chemical numbness and metallic bitter taste at the application site, which is a distinguishing characteristic used to identify NBOMe compounds."),
                SubjectiveEffect(name: "Strong Stimulation", description: "Intense physical stimulation with increased heart rate, body temperature, and restless energy that can feel overwhelming."),
                SubjectiveEffect(name: "Vasoconstriction", description: "Significant blood vessel constriction causing cold, blue-tinged extremities and physical tension that can be medically concerning at higher doses."),
                SubjectiveEffect(name: "Tachycardia", description: "Noticeably elevated heart rate that can become uncomfortably rapid and is a source of anxiety, particularly at higher doses."),
                SubjectiveEffect(name: "Color Intensification", description: "Extreme enhancement of color perception where the world appears painted in impossibly vivid, almost fluorescent tones."),
                SubjectiveEffect(name: "Cognitive Confusion", description: "Significant mental disorganization and difficulty thinking clearly, with a chaotic quality to the thought process that can be disorienting."),
                SubjectiveEffect(name: "Body Load", description: "Substantial physical discomfort from the combination of vasoconstriction, stimulation, and elevated heart rate, more severe than most psychedelics."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: 25C-NBOMe

        Substance(
            name: "25C-NBOMe",
            aliases: ["25C", "NBOMe-2C-C"],
            category: .psychedelic,
            defaultRoute: .sublingual,
            routes: [
                SubstanceRoute(route: .sublingual, unit: "µg", doses: DoseRange(
                    threshold: 50, light: 150...300, common: 300...500, strong: 500...800, heavy: 800, fatal: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Visual enhancement", "Stimulation", "Euphoria", "Vasoconstriction", "Color shifting", "Body load", "Numbness at application site", "Tachycardia", "Nausea"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Visual Enhancement", description: "Moderately intense visual effects with color shifting and pattern enhancement, considered somewhat less visually overwhelming than 25I-NBOMe."),
                SubjectiveEffect(name: "Sublingual Numbness", description: "A bitter, chemically numbing sensation at the application site characteristic of all NBOMe compounds, often described as unpleasant."),
                SubjectiveEffect(name: "Stimulation", description: "Significant physical and mental stimulation with increased energy and alertness, though generally less intense than 25I-NBOMe."),
                SubjectiveEffect(name: "Vasoconstriction", description: "Blood vessel constriction causing cold extremities and physical tension, a consistent concern with the NBOMe class."),
                SubjectiveEffect(name: "Color Shifting", description: "Dynamic changes in color perception where hues drift and morph across surfaces, creating a visually shifting environment."),
                SubjectiveEffect(name: "Tachycardia", description: "Elevated heart rate that can become pronounced and anxiety-inducing, particularly during the peak of the experience."),
                SubjectiveEffect(name: "Nausea", description: "Gastrointestinal discomfort that may accompany the come-up phase, adding to the overall physical burden of the experience."),
                SubjectiveEffect(name: "Body Load", description: "Moderate to significant physical discomfort from the combined effects of vasoconstriction, stimulation, and cardiovascular strain."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: 25B-NBOMe

        Substance(
            name: "25B-NBOMe",
            aliases: ["25B", "NBOMe-2C-B"],
            category: .psychedelic,
            defaultRoute: .sublingual,
            routes: [
                SubstanceRoute(route: .sublingual, unit: "µg", doses: DoseRange(
                    threshold: 50, light: 100...250, common: 250...500, strong: 500...750, heavy: 750, fatal: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Intense visuals", "Euphoria", "Stimulation", "Color intensification", "Vasoconstriction", "Body load", "Numbness at application site", "Pattern recognition", "Tachycardia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Intense Visual Patterning", description: "Vivid, colorful visual patterns and geometric overlays that are highly visually engaging, with bright neon qualities and rapid morphological changes."),
                SubjectiveEffect(name: "Sublingual Numbness", description: "Pronounced numbing and bitter chemical taste at the sublingual application site, a hallmark of NBOMe compound administration."),
                SubjectiveEffect(name: "Euphoria", description: "Strong waves of physical and emotional pleasure that can be very rewarding, considered by some to be the most euphoric of the NBOMe series."),
                SubjectiveEffect(name: "Color Intensification", description: "Extreme enhancement of color saturation where the world appears fluorescently vivid and almost unnaturally bright."),
                SubjectiveEffect(name: "Stimulation", description: "Significant physical energization with increased heart rate and body temperature, creating a wired and alert state."),
                SubjectiveEffect(name: "Vasoconstriction", description: "Blood vessel constriction causing peripheral coldness, tension, and discomfort that is a persistent concern with NBOMe compounds."),
                SubjectiveEffect(name: "Tachycardia", description: "Noticeably rapid heart rate that can be anxiety-producing and represents a genuine physiological concern at higher doses."),
                SubjectiveEffect(name: "Pattern Recognition", description: "Enhanced perception of patterns in textures and surfaces, with visual details becoming richly apparent and fascinating."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: 25D-NBOMe

        Substance(
            name: "25D-NBOMe",
            aliases: ["25D", "NBOMe-2C-D"],
            category: .psychedelic,
            defaultRoute: .sublingual,
            routes: [
                SubstanceRoute(route: .sublingual, unit: "µg", doses: DoseRange(
                    threshold: 50, light: 100...300, common: 300...500, strong: 500...800, heavy: 800
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Visual enhancement", "Stimulation", "Color enhancement", "Vasoconstriction", "Body load", "Numbness at application site", "Mood lift", "Tachycardia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Visual Enhancement", description: "Moderate visual effects with color brightening and gentle pattern enhancement, generally milder than the more potent NBOMe variants."),
                SubjectiveEffect(name: "Sublingual Numbness", description: "Chemical numbing and bitter taste at the application site characteristic of all NBOMe compounds, serving as an identifying feature."),
                SubjectiveEffect(name: "Stimulation", description: "Physical and mental energization with increased alertness and restlessness, consistent with the stimulating NBOMe profile."),
                SubjectiveEffect(name: "Mood Lift", description: "A positive elevation of mood and outlook with a sense of well-being, though less intensely euphoric than 25B or 25I variants."),
                SubjectiveEffect(name: "Color Enhancement", description: "Mild to moderate brightening of color perception where the visual world appears more vivid and saturated."),
                SubjectiveEffect(name: "Vasoconstriction", description: "Blood vessel constriction causing peripheral coldness and tension, a consistent feature of NBOMe pharmacology."),
                SubjectiveEffect(name: "Tachycardia", description: "Elevated heart rate that can cause anxiety and discomfort, a physiological concern shared across the NBOMe class."),
                SubjectiveEffect(name: "Body Load", description: "Moderate physical discomfort from cardiovascular strain, vasoconstriction, and stimulant effects acting in combination."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: 25E-NBOMe

        Substance(
            name: "25E-NBOMe",
            aliases: ["25E", "NBOMe-2C-E"],
            category: .psychedelic,
            defaultRoute: .sublingual,
            routes: [
                SubstanceRoute(route: .sublingual, unit: "µg", doses: DoseRange(
                    threshold: 50, light: 100...250, common: 250...500, strong: 500...750, heavy: 750
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Intense visuals", "Stimulation", "Introspection", "Vasoconstriction", "Body load", "Numbness at application site", "Geometric patterns", "Emotional intensity", "Tachycardia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Intense Visual Geometry", description: "Complex, detailed geometric patterns with deep layering and vivid coloration, reflecting the visual potency of 2C-E translated through the NBOMe framework."),
                SubjectiveEffect(name: "Sublingual Numbness", description: "Pronounced numbing and intensely bitter taste at the application site, characteristic of NBOMe compounds and useful for identification."),
                SubjectiveEffect(name: "Emotional Intensity", description: "Powerful amplification of emotional states that can produce both profound beauty and challenging psychological difficulty, similar to 2C-E."),
                SubjectiveEffect(name: "Deep Introspection", description: "A strong pull toward inner examination of psychological material, inherited from the introspective character of the 2C-E parent compound."),
                SubjectiveEffect(name: "Geometric Patterns", description: "Intricate, fractal-like visual overlays on surfaces and in closed-eye space, with a complexity and depth that can be visually overwhelming."),
                SubjectiveEffect(name: "Vasoconstriction", description: "Significant blood vessel constriction with cold extremities and physical tension, amplified by the NBOMe binding profile."),
                SubjectiveEffect(name: "Stimulation", description: "Pronounced physical and mental energization with restlessness, elevated heart rate, and an inability to relax."),
                SubjectiveEffect(name: "Tachycardia", description: "Elevated heart rate that can feel alarming and contribute to anxiety, a physiological burden characteristic of the NBOMe class."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: - NBOH Series

        // MARK: 25B-NBOH

        Substance(
            name: "25B-NBOH",
            aliases: ["NBOH-2C-B"],
            category: .psychedelic,
            defaultRoute: .sublingual,
            routes: [
                SubstanceRoute(route: .sublingual, unit: "µg", doses: DoseRange(
                    threshold: 50, light: 100...300, common: 300...600, strong: 600...900, heavy: 900
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Visual enhancement", "Stimulation", "Euphoria", "Color intensification", "Body load", "Vasoconstriction", "Pattern recognition", "Mood lift"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Visual Enhancement", description: "Colorful visual effects with pattern enhancement and color intensification that share the visual character of 25B-NBOMe but with a reportedly smoother quality."),
                SubjectiveEffect(name: "Reduced Oral Numbness", description: "Less pronounced numbing at the application site compared to NBOMe compounds, as the hydroxyl group produces less local anesthetic effect."),
                SubjectiveEffect(name: "Euphoria", description: "Positive emotional elevation with waves of pleasure and well-being, reflecting the euphoric potential of the 2C-B parent compound."),
                SubjectiveEffect(name: "Color Intensification", description: "Significant enhancement of color saturation and vibrancy, with the visual world appearing brighter and more colorful."),
                SubjectiveEffect(name: "Stimulation", description: "Moderate physical and mental stimulation with increased energy, though generally reported as less intense than the NBOMe equivalent."),
                SubjectiveEffect(name: "Vasoconstriction", description: "Blood vessel constriction causing cold extremities and tension, present but potentially less severe than with NBOMe compounds."),
                SubjectiveEffect(name: "Pattern Recognition", description: "Enhanced perception of patterns in textures and surfaces, with visual details becoming more apparent and engaging."),
                SubjectiveEffect(name: "Mood Lift", description: "A reliable improvement in mood and outlook that contributes to an overall positive and enjoyable experience."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: 25C-NBOH

        Substance(
            name: "25C-NBOH",
            aliases: ["NBOH-2C-C"],
            category: .psychedelic,
            defaultRoute: .sublingual,
            routes: [
                SubstanceRoute(route: .sublingual, unit: "µg", doses: DoseRange(
                    threshold: 50, light: 100...300, common: 300...600, strong: 600...1000, heavy: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Visual enhancement", "Stimulation", "Euphoria", "Color shifting", "Body load", "Vasoconstriction", "Mood lift", "Gentle introspection"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Visual Enhancement", description: "Moderate visual effects with color shifting and gentle pattern overlay, considered less visually intense than the corresponding NBOMe compound."),
                SubjectiveEffect(name: "Color Shifting", description: "Dynamic changes in color perception where hues drift and morph gently across surfaces, creating a subtly shifting visual environment."),
                SubjectiveEffect(name: "Euphoria", description: "A pleasant sense of well-being and positive mood that is moderate and manageable in intensity."),
                SubjectiveEffect(name: "Gentle Introspection", description: "A mild pull toward self-reflection and contemplation that is more gentle and less forced than the deeper introspection of stronger compounds."),
                SubjectiveEffect(name: "Stimulation", description: "Moderate physical energy and mental alertness that creates an active, engaged state without extreme restlessness."),
                SubjectiveEffect(name: "Vasoconstriction", description: "Mild to moderate blood vessel constriction with some peripheral coldness, potentially less severe than the NBOMe equivalent."),
                SubjectiveEffect(name: "Mood Lift", description: "A positive elevation of emotional baseline with increased optimism and appreciation for surroundings."),
                SubjectiveEffect(name: "Body Load", description: "Moderate physical discomfort that is noticeable but generally more tolerable than with the corresponding NBOMe compound."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: 25I-NBOH

        Substance(
            name: "25I-NBOH",
            aliases: ["NBOH-2C-I", "Cimbi-27"],
            category: .psychedelic,
            defaultRoute: .sublingual,
            routes: [
                SubstanceRoute(route: .sublingual, unit: "µg", doses: DoseRange(
                    threshold: 50, light: 100...300, common: 300...600, strong: 600...900, heavy: 900
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Intense visuals", "Stimulation", "Euphoria", "Color intensification", "Body load", "Vasoconstriction", "Pattern recognition", "Tachycardia", "Mood lift"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Intense Visual Effects", description: "Vivid, colorful visual patterns and distortions reflecting the potency of the iodo-substituted parent compound, with neon-hued geometry and rapid morphing."),
                SubjectiveEffect(name: "Strong Stimulation", description: "Pronounced physical and mental stimulation with elevated energy, heart rate, and restlessness, more intense than the chloro or bromo variants."),
                SubjectiveEffect(name: "Euphoria", description: "Waves of intense pleasure and positive emotion that can be very rewarding but occur alongside significant physical load."),
                SubjectiveEffect(name: "Color Intensification", description: "Extreme enhancement of color perception with vivid, almost electric saturation that makes the visual world appear hyper-real."),
                SubjectiveEffect(name: "Tachycardia", description: "Noticeably elevated heart rate that can be uncomfortable and anxiety-producing, a significant physiological concern with this compound."),
                SubjectiveEffect(name: "Vasoconstriction", description: "Significant blood vessel constriction causing cold extremities and physical tension, a serious consideration at higher doses."),
                SubjectiveEffect(name: "Pattern Recognition", description: "Dramatically enhanced perception of visual patterns and textures, with surfaces appearing richly detailed and endlessly fascinating."),
                SubjectiveEffect(name: "Body Load", description: "Substantial physical discomfort from the combination of stimulation, vasoconstriction, and cardiovascular effects acting simultaneously."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: - Mescaline and Relatives

        // MARK: Mescaline

        Substance(
            name: "Mescaline",
            aliases: ["Peyote", "San Pedro", "3,4,5-Trimethoxyphenethylamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...300, strong: 300...500, heavy: 500, fatal: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 90),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 180, max: 300),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 360, max: 720),
                    total: TimeRange(min: 480, max: 720)
                )),
            ],
            effects: ["Vivid visuals", "Euphoria", "Nausea", "Deep introspection", "Color intensification", "Spiritual experiences", "Body high", "Emotional openness", "Geometric patterns", "Synesthesia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Color Intensification", description: "Extraordinarily vivid and saturated colors that are a hallmark of the mescaline experience, with the visual world appearing as though lit from within."),
                SubjectiveEffect(name: "Nausea on Onset", description: "Significant gastrointestinal discomfort and nausea during the come-up, especially when consumed as cactus material, often called the purge in traditional contexts."),
                SubjectiveEffect(name: "Deep Spiritual Quality", description: "A profound sense of sacredness and connection to something greater, with feelings of cosmic unity and existential meaning central to the experience."),
                SubjectiveEffect(name: "Emotional Openness", description: "A dramatic increase in emotional vulnerability and openness, with feelings of love, compassion, and deep connection to others and nature."),
                SubjectiveEffect(name: "Organic Visual Geometry", description: "Rounded, flowing geometric patterns with a soft organic quality distinct from the sharp geometry of tryptamines, often featuring mandala-like structures."),
                SubjectiveEffect(name: "Body High", description: "A warm, full-body euphoria that feels grounded and earthy, with waves of pleasurable sensation and a sense of physical connection to the earth."),
                SubjectiveEffect(name: "Synesthesia", description: "Cross-sensory experiences where sounds carry color and physical sensations have emotional textures, blending perceptual channels."),
                SubjectiveEffect(name: "Nature Connection", description: "An intense feeling of kinship and unity with the natural world, where plants, landscapes, and animals feel alive with consciousness and meaning."),
                SubjectiveEffect(name: "Extended Duration", description: "A long experience of 8-12 hours with a gradual, gentle trajectory that allows for sustained exploration and integration."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 360
        ),

        // MARK: Escaline

        Substance(
            name: "Escaline",
            aliases: ["3,5-Dimethoxy-4-ethoxyphenethylamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 15, light: 30...60, common: 60...100, strong: 100...150, heavy: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 360, max: 540)
                )),
            ],
            effects: ["Visual enhancement", "Euphoria", "Body high", "Nausea", "Color enhancement", "Mood lift", "Introspection", "Gentle stimulation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mescaline-Like Visual Quality", description: "Visual effects reminiscent of mescaline with warm, flowing color enhancement and gentle patterning, though less intense and overwhelming."),
                SubjectiveEffect(name: "Warm Euphoria", description: "A pleasant, warm sense of well-being and contentment that shares mescaline's earthy, grounded emotional quality."),
                SubjectiveEffect(name: "Gentle Body High", description: "A comfortable, warm physical sensation that is more manageable than mescaline, without the intensity of the parent compound."),
                SubjectiveEffect(name: "Color Enhancement", description: "Moderate brightening and enrichment of color perception, giving the visual world a warmer and more vibrant appearance."),
                SubjectiveEffect(name: "Nausea", description: "Mild to moderate gastrointestinal discomfort during onset, less severe than mescaline but still present in many experiences."),
                SubjectiveEffect(name: "Mood Lift", description: "A reliable improvement in mood and emotional outlook with a positive, grateful quality characteristic of the mescaline family."),
                SubjectiveEffect(name: "Gentle Introspection", description: "A mild tendency toward self-reflection and contemplation, less forceful than mescaline but sharing its contemplative character."),
                SubjectiveEffect(name: "Gentle Stimulation", description: "A subtle increase in physical energy and engagement with the environment, encouraging gentle activity and social interaction."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 360
        ),

        // MARK: Allylescaline

        Substance(
            name: "Allylescaline",
            aliases: ["AL"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...15, common: 15...25, strong: 25...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 300, max: 540)
                )),
            ],
            effects: ["Mild visuals", "Euphoria", "Body high", "Color enhancement", "Mood lift", "Introspection", "Gentle stimulation", "Nausea"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mild Visual Enhancement", description: "Subtle visual effects limited to gentle color enhancement and slight surface breathing, representing a lighter version of the mescaline visual character."),
                SubjectiveEffect(name: "Gentle Euphoria", description: "A mild, warm sense of well-being and contentment that is pleasant without being overwhelming or intense."),
                SubjectiveEffect(name: "Comfortable Body High", description: "A soft, warm physical sensation without significant body load, more comfortable than many other phenethylamines."),
                SubjectiveEffect(name: "Color Enhancement", description: "Mild brightening of colors where the world appears slightly more vivid and warm, consistent with the mescaline family aesthetic."),
                SubjectiveEffect(name: "Mood Lift", description: "A gentle positive shift in emotional outlook with increased appreciation for surroundings and a sense of quiet contentment."),
                SubjectiveEffect(name: "Gentle Introspection", description: "A light, non-demanding pull toward self-reflection that feels optional and easily redirected toward external engagement."),
                SubjectiveEffect(name: "Mild Nausea", description: "Slight gastrointestinal discomfort during onset that is typically mild and short-lived compared to mescaline."),
                SubjectiveEffect(name: "Gentle Stimulation", description: "A subtle increase in energy and motivation that encourages light activity without restlessness or agitation."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 360
        ),

        // MARK: Methallylescaline

        Substance(
            name: "Methallylescaline",
            aliases: ["MAL"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 360, max: 540)
                )),
            ],
            effects: ["Visual enhancement", "Euphoria", "Long duration", "Body high", "Nausea", "Color intensification", "Introspection", "Mood lift", "Gentle body load"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Extended Duration", description: "A longer experience than most mescaline analogs, often lasting 8-12 hours, requiring commitment to a full-day psychedelic session."),
                SubjectiveEffect(name: "Mescaline-Like Visuals", description: "Visual effects that closely resemble mescaline with warm, organic color enhancement and flowing geometric patterns at higher doses."),
                SubjectiveEffect(name: "Color Intensification", description: "Notable enhancement of color saturation and warmth, giving the visual world a rich, painted quality consistent with the mescaline family."),
                SubjectiveEffect(name: "Warm Euphoria", description: "A pleasurable sense of warmth and contentment that develops gradually and sustains through the long duration of the experience."),
                SubjectiveEffect(name: "Body High", description: "A warm, grounded physical sensation that shares mescaline's earthy quality, with waves of comfortable pleasure spreading through the body."),
                SubjectiveEffect(name: "Nausea", description: "Gastrointestinal discomfort during onset that is moderate and typical of the mescaline analog family."),
                SubjectiveEffect(name: "Gentle Body Load", description: "A mild physical heaviness and tension that is present but manageable, less intense than mescaline at equivalent psychedelic doses."),
                SubjectiveEffect(name: "Introspective Warmth", description: "A contemplative, reflective quality that encourages gentle self-examination with the emotional warmth characteristic of the mescaline family."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 360
        ),

        // MARK: Proscaline

        Substance(
            name: "Proscaline",
            aliases: ["3,5-Dimethoxy-4-propoxyphenethylamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 15...25, common: 25...40, strong: 40...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 180, max: 300),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 180, max: 360),
                    total: TimeRange(min: 420, max: 600)
                )),
            ],
            effects: ["Visual enhancement", "Euphoria", "Color enhancement", "Body high", "Nausea", "Introspection", "Mood lift", "Emotional warmth"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mescaline-Like Character", description: "An experience profile that closely resembles mescaline with warm, organic visual and emotional qualities, considered one of the most mescaline-like analogs."),
                SubjectiveEffect(name: "Emotional Warmth", description: "A deep sense of emotional openness and warmth that encourages connection, compassion, and tender feelings toward others and oneself."),
                SubjectiveEffect(name: "Visual Enhancement", description: "Moderate visual effects with color enhancement and gentle flowing patterns that share mescaline's soft, organic visual aesthetic."),
                SubjectiveEffect(name: "Color Enhancement", description: "Warm intensification of color perception with a rich, saturated quality that makes the natural world appear particularly beautiful."),
                SubjectiveEffect(name: "Body High", description: "A comfortable, grounded physical warmth that feels nurturing and earthy, consistent with the mescaline family body experience."),
                SubjectiveEffect(name: "Nausea", description: "Mild gastrointestinal discomfort during the come-up that is less severe than mescaline and typically resolves before the peak."),
                SubjectiveEffect(name: "Mood Lift", description: "A gentle but reliable elevation of mood with feelings of gratitude, appreciation, and quiet joy."),
                SubjectiveEffect(name: "Gentle Introspection", description: "A warm, contemplative pull toward self-reflection that feels nurturing and productive rather than challenging or confrontational."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 420
        ),

        // MARK: - TMA Series

        // MARK: TMA-2

        Substance(
            name: "TMA-2",
            aliases: ["Trimethoxyamphetamine-2", "2,4,5-Trimethoxyamphetamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 180, max: 300),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 180, max: 360),
                    total: TimeRange(min: 420, max: 600)
                )),
            ],
            effects: ["Visual enhancement", "Stimulation", "Euphoria", "Body load", "Nausea", "Introspection", "Color enhancement", "Long duration", "Mood lift"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Amphetamine-Like Stimulation", description: "Notable physical and mental stimulation from the amphetamine backbone, producing increased energy, alertness, and a wired quality throughout the long experience."),
                SubjectiveEffect(name: "Extended Duration", description: "A long experience of 8-12 hours due to the trimethoxyamphetamine structure, requiring dedication to a full-day session."),
                SubjectiveEffect(name: "Visual Enhancement", description: "Moderate visual effects with color enhancement and geometric patterning that develop gradually over the extended come-up period."),
                SubjectiveEffect(name: "Body Load", description: "Significant physical discomfort from the combination of stimulation, nausea, and muscle tension that is characteristic of the TMA series."),
                SubjectiveEffect(name: "Nausea", description: "Gastrointestinal distress during onset that can be pronounced, a common challenge with trimethoxyamphetamine compounds."),
                SubjectiveEffect(name: "Color Enhancement", description: "Moderate intensification of color perception with a warmer, mescaline-influenced visual quality due to the trimethoxy substitution pattern."),
                SubjectiveEffect(name: "Introspection", description: "A moderate pull toward self-examination and contemplation of personal themes, facilitated by the long duration."),
                SubjectiveEffect(name: "Mood Lift", description: "A positive shift in emotional outlook that combines the mescaline family warmth with the confidence of amphetamine stimulation."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 480
        ),

        // MARK: TMA-6

        Substance(
            name: "TMA-6",
            aliases: ["Trimethoxyamphetamine-6", "2,4,6-Trimethoxyamphetamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 15...25, common: 25...50, strong: 50...75, heavy: 75
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 180, max: 300),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 180, max: 420),
                    total: TimeRange(min: 480, max: 840)
                )),
            ],
            effects: ["Visual enhancement", "Stimulation", "Body load", "Nausea", "Introspection", "Color enhancement", "Mood lift", "Long duration"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Extended Duration", description: "A long-lasting experience of 8-14 hours driven by the trimethoxyamphetamine structure, with a slow onset that demands patience."),
                SubjectiveEffect(name: "Stimulation", description: "Amphetamine-type physical and mental energization with increased alertness, restlessness, and difficulty relaxing."),
                SubjectiveEffect(name: "Body Load", description: "Significant physical discomfort including nausea, tension, and vasoconstriction that is characteristic of TMA compounds."),
                SubjectiveEffect(name: "Nausea", description: "Prominent gastrointestinal distress during the onset phase that can be a major challenge, sometimes requiring anti-nausea preparation."),
                SubjectiveEffect(name: "Visual Enhancement", description: "Moderate visual effects with color enhancement and subtle patterning that emerge gradually during the extended come-up."),
                SubjectiveEffect(name: "Color Enhancement", description: "Mild to moderate brightening and warmth in color perception, reflecting the mescaline-related trimethoxy substitution pattern."),
                SubjectiveEffect(name: "Introspection", description: "A contemplative quality that develops over the long duration, allowing for sustained periods of self-reflection and inner exploration."),
                SubjectiveEffect(name: "Mood Lift", description: "A modest positive shift in emotional baseline that helps counterbalance the physical discomfort of the experience."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 480
        ),

        // MARK: - Other Phenethylamines

        // MARK: 3C-E

        Substance(
            name: "3C-E",
            aliases: ["4-Ethoxy-3,5-dimethoxyphenylpropylamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 20...30, common: 30...60, strong: 60...80, heavy: 80
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 360, max: 600)
                )),
            ],
            effects: ["Visual enhancement", "Stimulation", "Body load", "Introspection", "Color enhancement", "Euphoria", "Nausea", "Mood lift"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Visual Enhancement", description: "Moderate visual effects with color enhancement and geometric patterning that reflects the escaline parent compound's warm visual character."),
                SubjectiveEffect(name: "Stimulation", description: "Notable physical and mental stimulation from the phenylpropylamine backbone, producing increased energy and an active, engaged state."),
                SubjectiveEffect(name: "Body Load", description: "Moderate physical discomfort including tension and gastrointestinal distress that is a common feature of 3C compounds."),
                SubjectiveEffect(name: "Introspection", description: "A moderate tendency toward self-reflection and inner contemplation, facilitated by the psychedelic headspace."),
                SubjectiveEffect(name: "Color Enhancement", description: "Brightening and enrichment of color perception with a warm quality inherited from the mescaline family substitution pattern."),
                SubjectiveEffect(name: "Euphoria", description: "A positive emotional elevation with a stimulated quality that blends psychedelic warmth with amphetamine-like confidence."),
                SubjectiveEffect(name: "Nausea", description: "Gastrointestinal discomfort during the onset that is moderate and typical of this structural class of compounds."),
                SubjectiveEffect(name: "Mood Lift", description: "An improvement in mood and emotional outlook that combines the warm positivity of the mescaline family with stimulant energy."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 360
        ),

        // MARK: 3C-P

        Substance(
            name: "3C-P",
            aliases: ["4-Propoxy-3,5-DMPEA"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...10, common: 10...20, strong: 20...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 180, max: 480),
                    total: TimeRange(min: 600, max: 960)
                )),
            ],
            effects: ["Visual enhancement", "Long duration", "Stimulation", "Body load", "Introspection", "Color enhancement", "Euphoria", "Nausea"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Very Long Duration", description: "An extended experience that can last 10-16 hours, making it one of the longest-lasting 3C compounds and requiring significant time commitment."),
                SubjectiveEffect(name: "Visual Enhancement", description: "Moderate visual effects with color enhancement and patterning that persist over the extended duration, gaining depth at higher doses."),
                SubjectiveEffect(name: "Stimulation", description: "Sustained physical and mental energy from the phenylpropylamine structure, producing a stimulated state that persists throughout the long experience."),
                SubjectiveEffect(name: "Body Load", description: "Significant physical discomfort that compounds over the very long duration, including tension, nausea, and vasoconstriction."),
                SubjectiveEffect(name: "Introspection", description: "A strong contemplative quality facilitated by the extended duration, allowing for deep and sustained self-examination."),
                SubjectiveEffect(name: "Color Enhancement", description: "Moderate intensification of color with a warm, organic quality from the proscaline-related substitution pattern."),
                SubjectiveEffect(name: "Nausea", description: "Gastrointestinal discomfort that can be significant, particularly during the onset phase of this long-acting compound."),
                SubjectiveEffect(name: "Euphoria", description: "A warm, positive emotional quality that emerges at the peak and can sustain through portions of the extended experience."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 600
        ),

        // MARK: BOD

        Substance(
            name: "BOD",
            aliases: ["2C-B-Dragonfly", "Beta-methoxy-2C-D"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 8...15, common: 15...25, strong: 25...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 45),
                    comeup: TimeRange(min: 20, max: 45),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 240, max: 420)
                )),
            ],
            effects: ["Visual enhancement", "Euphoria", "Body high", "Stimulation", "Color enhancement", "Introspection", "Nausea", "Pattern recognition"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Visual Enhancement", description: "Moderate visual effects with color enhancement and pattern recognition that share some character with 2C-D but with a distinctive methoxy-influenced quality."),
                SubjectiveEffect(name: "Euphoria", description: "A pleasant sense of well-being and contentment with a stimulated, engaged quality that encourages activity and exploration."),
                SubjectiveEffect(name: "Body High", description: "A comfortable, warm physical sensation that combines the phenethylamine body high with gentle stimulating energy."),
                SubjectiveEffect(name: "Stimulation", description: "Moderate physical and mental energization that creates an active, alert state suitable for engaging with environment and activities."),
                SubjectiveEffect(name: "Color Enhancement", description: "Brightening and enrichment of color perception with the visual world appearing more vibrant and engaging."),
                SubjectiveEffect(name: "Pattern Recognition", description: "Enhanced ability to perceive patterns and details in surfaces and textures, making the environment visually interesting."),
                SubjectiveEffect(name: "Introspection", description: "A moderate pull toward contemplation and self-reflection that is balanced with enough outward engagement to remain functional."),
                SubjectiveEffect(name: "Nausea", description: "Mild gastrointestinal discomfort during onset that typically resolves as the experience progresses to the peak."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 240
        ),

        // MARK: BOH

        Substance(
            name: "BOH",
            aliases: ["Beta-methoxy-2C-H"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 40, light: 60...120, common: 120...200, strong: 200...300, heavy: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 60),
                    comeup: TimeRange(min: 20, max: 45),
                    peak: TimeRange(min: 90, max: 240),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 240, max: 540)
                )),
            ],
            effects: ["Mild visuals", "Subtle mood lift", "Light body high", "Slight color enhancement", "Minimal psychedelic effects", "Mild stimulation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Minimal Psychedelic Activity", description: "Extremely subtle effects even at high doses, as BOH is a beta-methoxy analog of the weakly active 2C-H, resulting in very low psychedelic potency."),
                SubjectiveEffect(name: "Subtle Mood Lift", description: "A barely perceptible improvement in mood that is more consistent with mild stimulant activity than meaningful psychedelic engagement."),
                SubjectiveEffect(name: "Light Body High", description: "A faint warmth and physical awareness that is the most noticeable effect, though still quite mild."),
                SubjectiveEffect(name: "Slight Color Enhancement", description: "Minimal brightening of color perception that requires focused attention to detect, at the very threshold of psychedelic visual activity."),
                SubjectiveEffect(name: "Mild Stimulation", description: "A gentle increase in alertness and energy consistent with the phenethylamine backbone but without significant psychedelic overlay."),
                SubjectiveEffect(name: "High Dose Requirement", description: "Very large doses are needed for any perceptible effects, reflecting the low inherent potency of the unsubstituted 2C-H parent structure."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 240
        ),

        // MARK: Bk-2C-B

        Substance(
            name: "Bk-2C-B",
            aliases: ["beta-keto 2C-B", "βk-2C-B"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 20, light: 40...60, common: 60...100, strong: 100...150, heavy: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 90, max: 150),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 240, max: 420)
                )),
            ],
            effects: ["Mild visuals", "Empathogenic warmth", "Stimulation", "Euphoria", "Color enhancement", "Body high", "Nausea", "Mood lift", "Increased sociability"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Empathogenic Warmth", description: "A prominent MDMA-like emotional warmth and increased feelings of connection, empathy, and social openness that distinguishes it from typical psychedelics."),
                SubjectiveEffect(name: "Mild Visual Enhancement", description: "Subtle visual effects limited to gentle color enhancement and slight pattern recognition, more empathogenic than visually psychedelic."),
                SubjectiveEffect(name: "Stimulation", description: "Moderate physical and mental energy with a stimulated, engaged quality similar to empathogens like MDMA."),
                SubjectiveEffect(name: "Euphoria", description: "A warm, socially-oriented euphoria that emphasizes emotional connection and well-being over psychedelic awe."),
                SubjectiveEffect(name: "Increased Sociability", description: "Enhanced comfort and fluency in social situations with a desire to connect, communicate, and share experiences with others."),
                SubjectiveEffect(name: "Color Enhancement", description: "Mild brightening of color perception that adds a subtle visual richness to the predominantly empathogenic experience."),
                SubjectiveEffect(name: "Nausea", description: "Gastrointestinal discomfort during onset that can be moderate, requiring attention to timing of food intake."),
                SubjectiveEffect(name: "Body High", description: "A warm, pleasant physical sensation with a tactile quality that enhances the empathogenic and social aspects of the experience."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 360
        ),

        // MARK: βk-2C-B

        Substance(
            name: "βk-2C-B",
            aliases: ["beta-keto 2C-B", "Bk-2C-B"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 20, light: 40...60, common: 60...100, strong: 100...150, heavy: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 90, max: 150),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 240, max: 420)
                )),
            ],
            effects: ["Mild visuals", "Empathogenic warmth", "Stimulation", "Euphoria", "Color enhancement", "Body high", "Nausea", "Mood lift", "Increased sociability"],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 360
        ),

        // MARK: DESOXY

        Substance(
            name: "DESOXY",
            aliases: ["MMDA-2", "2,3-MMDA"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...30, strong: 30...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 240, max: 480)
                )),
            ],
            effects: ["Empathogenic warmth", "Mild visuals", "Mood lift", "Introspection", "Body high", "Nausea", "Stimulation", "Emotional openness"],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 300
        ),

        // MARK: - Natural Mescaline Sources

        // MARK: San Pedro Cactus

        Substance(
            name: "San Pedro Cactus",
            aliases: ["Echinopsis pachanoi", "Huachuma", "Wachuma", "Trichocereus pachanoi"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "g", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 45, max: 120),
                    comeup: TimeRange(min: 60, max: 150),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 360, max: 720),
                    total: TimeRange(min: 600, max: 840)
                )),
            ],
            effects: ["Visual enhancement", "Euphoria", "Introspection", "Nausea", "Body high", "Empathy", "Nature connectedness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mescaline-Driven Visuals", description: "Rich, warm visual enhancement with flowing organic geometry, vivid color saturation, and breathing surfaces that develop gradually over the 10-14 hour experience."),
                SubjectiveEffect(name: "Intense Nausea Phase", description: "A pronounced period of nausea and often vomiting during the first 1-3 hours as the body processes the bitter cactus material, sometimes called the purge in ceremonial contexts."),
                SubjectiveEffect(name: "Nature Connection", description: "A profound, almost overwhelming sense of unity with the natural world, where plants and landscapes feel alive with consciousness and deeply meaningful."),
                SubjectiveEffect(name: "Extended Duration", description: "An exceptionally long experience lasting 10-14 hours with a slow, gradual onset of 1-3 hours, requiring a full day commitment and patience."),
                SubjectiveEffect(name: "Warm Body Euphoria", description: "A deeply grounded, earthy physical pleasure that radiates through the body in waves, feeling connected to the earth and one's physical existence."),
                SubjectiveEffect(name: "Empathogenic Openness", description: "A dramatic increase in emotional vulnerability, compassion, and feelings of love and connection toward others and the world at large."),
                SubjectiveEffect(name: "Spiritual Depth", description: "A sense of sacredness and contact with something transcendent, traditionally used in Andean ceremony for thousands of years as a tool for spiritual healing."),
                SubjectiveEffect(name: "Gentle Body Load", description: "A moderate physical heaviness and mild gastrointestinal discomfort that persists after the initial nausea phase, less intense than peyote but still noticeable."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 360
        ),

        // MARK: Peyote

        Substance(
            name: "Peyote",
            aliases: ["Lophophora williamsii", "Mescal Button", "Hikuri"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "g", doses: DoseRange(
                    threshold: 3, light: 7...15, common: 15...27, strong: 27...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 45, max: 120),
                    comeup: TimeRange(min: 60, max: 150),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 360, max: 720),
                    total: TimeRange(min: 600, max: 840)
                )),
            ],
            effects: ["Visual distortions", "Spiritual experience", "Nausea", "Body high", "Introspection"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Spiritual Visions", description: "A profoundly sacred visionary experience with vivid imagery of spiritual and personal significance, deeply embedded in thousands of years of ceremonial use among indigenous peoples."),
                SubjectiveEffect(name: "Extreme Nausea", description: "The most physically challenging aspect of the experience, with severe nausea and often repeated vomiting during the first 1-2 hours, considered a spiritual purification in traditional contexts."),
                SubjectiveEffect(name: "Mescaline Visuals", description: "Extraordinarily vivid color enhancement, flowing mandala-like patterns, and organic geometric overlays with a warm, sacred quality unique to natural mescaline."),
                SubjectiveEffect(name: "Deep Body High", description: "An intensely grounded, earthy physical sensation with waves of warmth and pleasure alternating with periods of heaviness and gastrointestinal discomfort."),
                SubjectiveEffect(name: "Ceremonial Depth", description: "An experience quality that naturally lends itself to introspection and ceremony, with a gravity and spiritual significance that distinguishes it from synthetic psychedelics."),
                SubjectiveEffect(name: "Emotional Catharsis", description: "Powerful emotional release involving tears, laughter, or deep feelings of gratitude and connection, often described as profoundly healing and transformative."),
                SubjectiveEffect(name: "Extended Duration", description: "A very long experience of 10-14 hours with an extremely slow onset through the nausea phase, requiring full-day dedication in a supportive setting."),
                SubjectiveEffect(name: "Bitter Taste", description: "An intensely bitter, unpleasant taste from the alkaloid-rich cactus flesh that many describe as one of the most difficult parts of the experience to endure."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 360
        ),
    ]
}
