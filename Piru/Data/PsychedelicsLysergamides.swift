import Foundation

extension SubstanceLibrary {
    static let psychedelicsLysergamides: [Substance] = [

        // MARK: - LSD

        Substance(
            name: "LSD",
            aliases: ["Acid", "Lucy", "Tabs", "Blotter", "Lysergic acid diethylamide"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 15, light: 25...75, common: 75...150, strong: 150...300, heavy: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 45, max: 90),
                    peak: TimeRange(min: 180, max: 300),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 360, max: 720),
                    total: TimeRange(min: 480, max: 720)
                )),
                SubstanceRoute(route: .sublingual, unit: "µg", doses: DoseRange(
                    threshold: 15, light: 25...75, common: 75...150, strong: 150...300, heavy: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 180, max: 300),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 360, max: 720),
                    total: TimeRange(min: 420, max: 660)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Introspection", "Synesthesia", "Enhanced pattern recognition", "Thought loops", "Anxiety", "Increased music appreciation", "Ego dissolution"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Visual Geometry", description: "Intricate, self-transforming geometric patterns that overlay surfaces and closed-eye vision, often described as fractal, crystalline, or kaleidoscopic in nature."),
                SubjectiveEffect(name: "Thought Loops", description: "Recursive cycles of thinking where the same sequence of ideas repeats with a persistent sense of deja vu, more common at higher doses."),
                SubjectiveEffect(name: "Ego Dissolution", description: "A progressive loss of the sense of self and the boundary between observer and environment, which can range from mild depersonalization to complete unity experiences."),
                SubjectiveEffect(name: "Time Distortion", description: "A profound alteration in the perception of time, where minutes can feel like hours and temporal sequence becomes nonlinear or meaningless."),
                SubjectiveEffect(name: "Synesthesia", description: "A blending of sensory modalities where sounds may produce visual patterns, colors may carry texture, or music may be perceived as geometric forms."),
                SubjectiveEffect(name: "Emotional Amplification", description: "A dramatic intensification of whatever emotional state is present, with rapid shifts between euphoria, awe, anxiety, and deep sentimentality."),
                SubjectiveEffect(name: "Music Enhancement", description: "Music sounds extraordinarily rich and layered, with a perceived ability to hear individual instruments with crystalline clarity and deep emotional resonance."),
                SubjectiveEffect(name: "Conceptual Thinking", description: "Abstract, philosophical, or metaphysical ideas arise spontaneously and feel profoundly meaningful, often with a sense of deep personal insight."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 210,
            sources: ["PsychonautWiki", "Erowid", "PubMed", "Goodman & Gilman's"]
        ),

        // MARK: - 1P-LSD

        Substance(
            name: "1P-LSD",
            aliases: ["1-Propionyl-LSD", "1-Propionyl-lysergic acid diethylamide"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 15, light: 25...75, common: 75...150, strong: 150...300, heavy: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 45, max: 90),
                    comeup: TimeRange(min: 45, max: 90),
                    peak: TimeRange(min: 180, max: 300),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 360, max: 720),
                    total: TimeRange(min: 480, max: 720)
                )),
                SubstanceRoute(route: .sublingual, unit: "µg", doses: DoseRange(
                    threshold: 15, light: 25...75, common: 75...150, strong: 150...300, heavy: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 45, max: 90),
                    peak: TimeRange(min: 180, max: 300),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 360, max: 720),
                    total: TimeRange(min: 450, max: 690)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Introspection", "Synesthesia", "Enhanced pattern recognition", "Thought loops", "Anxiety", "Increased music appreciation", "Ego dissolution"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Visual Geometry", description: "Complex geometric overlays on surfaces and in closed-eye vision, virtually identical to LSD as 1P-LSD is metabolized into LSD in the body."),
                SubjectiveEffect(name: "Gradual Onset", description: "A notably slower come-up compared to LSD, often taking 60-90 minutes before effects fully manifest, due to the prodrug conversion process."),
                SubjectiveEffect(name: "Thought Loops", description: "Recursive thinking patterns where the same ideas cycle repeatedly, sometimes with an accompanying sense of temporal confusion."),
                SubjectiveEffect(name: "Ego Dissolution", description: "Progressive dissolution of self-identity boundaries at higher doses, experienced as merging with surroundings or loss of the concept of being a separate entity."),
                SubjectiveEffect(name: "Time Distortion", description: "Significant warping of temporal perception where the passage of time may feel dramatically slowed, accelerated, or entirely meaningless."),
                SubjectiveEffect(name: "Emotional Amplification", description: "Heightened emotional sensitivity with rapid oscillation between states, from deep euphoria and awe to introspective melancholy."),
                SubjectiveEffect(name: "Music Enhancement", description: "Dramatically enriched perception of music with enhanced emotional connection, spatial audio perception, and a feeling that music guides the experience."),
                SubjectiveEffect(name: "Color Enhancement", description: "Colors appear significantly more vivid, saturated, and luminous, with surfaces appearing to breathe or shift in hue."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 210,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - 1cP-LSD

        Substance(
            name: "1cP-LSD",
            aliases: ["1-Cyclopropionyl-LSD", "1-Cyclopropionyl-lysergic acid diethylamide"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 15, light: 25...75, common: 75...150, strong: 150...300, heavy: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 45, max: 90),
                    comeup: TimeRange(min: 45, max: 90),
                    peak: TimeRange(min: 180, max: 300),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 360, max: 720),
                    total: TimeRange(min: 480, max: 720)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Introspection", "Synesthesia", "Enhanced pattern recognition", "Thought loops", "Anxiety", "Increased music appreciation", "Ego dissolution"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Visual Geometry", description: "Detailed geometric patterning consistent with the LSD experience, as 1cP-LSD converts to LSD in vivo through hydrolysis of the cyclopropionyl group."),
                SubjectiveEffect(name: "Extended Come-Up", description: "A longer onset period compared to LSD, typically 90-120 minutes to full effects, attributed to the prodrug metabolism requiring an additional conversion step."),
                SubjectiveEffect(name: "Thought Acceleration", description: "Racing, interconnected thoughts that flow rapidly from one concept to the next, creating a sense of heightened mental activity and insight."),
                SubjectiveEffect(name: "Ego Dissolution", description: "At higher doses, a dissolving of personal identity and the sense of being a separate self, sometimes described as cosmic unity or oceanic boundlessness."),
                SubjectiveEffect(name: "Synesthesia", description: "Cross-wiring of sensory channels where sounds become visual, colors take on tactile qualities, and music may be perceived as flowing geometry."),
                SubjectiveEffect(name: "Emotional Lability", description: "Rapidly shifting emotional states with heightened sensitivity to environmental stimuli, set, and setting."),
                SubjectiveEffect(name: "Pattern Recognition Enhancement", description: "An increased tendency to perceive meaningful patterns in textures, surfaces, and abstract visual noise, with ordinary objects appearing deeply significant."),
                SubjectiveEffect(name: "Body High", description: "A diffuse, tingling, electric sensation that radiates through the body, sometimes described as waves of energy or a buzzing feeling beneath the skin."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 210,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - 1V-LSD

        Substance(
            name: "1V-LSD",
            aliases: ["Valerie", "1-Valeroyl-LSD", "1-Valeroyl-lysergic acid diethylamide"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 15, light: 25...75, common: 75...150, strong: 150...300, heavy: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 45, max: 90),
                    comeup: TimeRange(min: 45, max: 90),
                    peak: TimeRange(min: 180, max: 300),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 360, max: 720),
                    total: TimeRange(min: 480, max: 720)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Introspection", "Synesthesia", "Enhanced pattern recognition", "Thought loops", "Anxiety", "Increased music appreciation", "Ego dissolution"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Visual Geometry", description: "LSD-type geometric hallucinations that emerge after the prodrug conversion, with intricate patterns overlaying the visual field at common and higher doses."),
                SubjectiveEffect(name: "Delayed Onset", description: "A notably slow come-up often exceeding 2 hours to peak effects, as the valeroyl group requires more time for metabolic cleavage to release active LSD."),
                SubjectiveEffect(name: "Thought Loops", description: "Repeating cycles of cognition where the same thought sequence plays out multiple times, often with diminishing anxiety on each repetition."),
                SubjectiveEffect(name: "Time Distortion", description: "Altered temporal perception where time may feel dramatically dilated or compressed, with difficulty gauging how much time has actually passed."),
                SubjectiveEffect(name: "Emotional Amplification", description: "Intensification of emotional responses to stimuli, with environmental factors having an outsized influence on mood and inner experience."),
                SubjectiveEffect(name: "Music Enhancement", description: "Heightened appreciation and emotional resonance with music, where compositions feel deeply personal and multi-layered."),
                SubjectiveEffect(name: "Conceptual Thinking", description: "Spontaneous generation of abstract, philosophical ideas that feel loaded with personal significance and existential meaning."),
                SubjectiveEffect(name: "Color Shifting", description: "Colors appear more vivid and may shift or morph fluidly, with surfaces taking on an iridescent or breathing quality."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 210,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - 1B-LSD

        Substance(
            name: "1B-LSD",
            aliases: ["1-Butanoyl-LSD", "1-Butanoyl-lysergic acid diethylamide"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 15, light: 25...75, common: 75...150, strong: 150...300, heavy: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 45, max: 90),
                    comeup: TimeRange(min: 45, max: 90),
                    peak: TimeRange(min: 180, max: 300),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 360, max: 720),
                    total: TimeRange(min: 480, max: 720)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Introspection", "Synesthesia", "Enhanced pattern recognition", "Thought loops", "Anxiety", "Increased music appreciation", "Ego dissolution"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Visual Geometry", description: "LSD-characteristic geometric hallucinations with fractal and symmetrical patterning, emerging after metabolic conversion from the butanoyl prodrug."),
                SubjectiveEffect(name: "Moderate Onset Delay", description: "A come-up that is somewhat slower than LSD but generally faster than 1V-LSD, typically reaching full effects within 60-90 minutes."),
                SubjectiveEffect(name: "Ego Dissolution", description: "Loosening or complete loss of the sense of personal identity at higher doses, experienced as dissolution into the environment or universal consciousness."),
                SubjectiveEffect(name: "Synesthesia", description: "Sensory crossover experiences where music produces visual impressions and textures carry emotional or auditory qualities."),
                SubjectiveEffect(name: "Time Distortion", description: "Distorted perception of time with moments feeling stretched or collapsed, making clocks seem unreliable or meaningless."),
                SubjectiveEffect(name: "Thought Acceleration", description: "Rapid, branching thought processes where ideas connect in novel ways, sometimes overwhelming in their speed and density."),
                SubjectiveEffect(name: "Emotional Sensitivity", description: "Greatly increased sensitivity to emotional content in art, music, conversation, and memory, with deep feelings of empathy and connectedness."),
                SubjectiveEffect(name: "Introspective Insight", description: "A tendency toward deep self-examination with moments of clarity about personal patterns, relationships, and life direction."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 210,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - ALD-52

        Substance(
            name: "ALD-52",
            aliases: ["1-Acetyl-LSD", "Orange Sunshine", "1-Acetyl-lysergic acid diethylamide"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 15, light: 25...75, common: 75...150, strong: 150...300, heavy: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 45, max: 90),
                    peak: TimeRange(min: 180, max: 300),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 360, max: 720),
                    total: TimeRange(min: 480, max: 720)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Gentle introspection", "Synesthesia", "Enhanced pattern recognition", "Thought acceleration", "Reduced body load", "Increased music appreciation", "Ego dissolution"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Clean Visual Geometry", description: "Crisp, well-defined geometric patterns and visual distortions that feel smooth and organized, often described as a gentler and cleaner version of LSD visuals."),
                SubjectiveEffect(name: "Reduced Body Load", description: "Noticeably less physical tension, jaw clenching, and stomach discomfort compared to LSD, contributing to a more physically comfortable experience."),
                SubjectiveEffect(name: "Gentle Euphoria", description: "A warm, steady sense of well-being and contentment that feels less manic and more grounded than the euphoria produced by LSD."),
                SubjectiveEffect(name: "Smooth Headspace", description: "A clear, lucid cognitive state with less anxious thought looping and confusion than LSD, making the mental experience feel more manageable."),
                SubjectiveEffect(name: "Time Distortion", description: "Altered time perception characteristic of lysergamides, though often reported as somewhat less disorienting than with LSD itself."),
                SubjectiveEffect(name: "Music Enhancement", description: "Enhanced emotional and perceptual depth when listening to music, with increased appreciation for compositional nuance and emotional content."),
                SubjectiveEffect(name: "Color Enhancement", description: "Vivid intensification of colors throughout the visual field, with objects appearing to have an inner glow or luminescence."),
                SubjectiveEffect(name: "Introspective Clarity", description: "A gentle tendency toward self-reflection that feels productive and insightful rather than overwhelming or anxious."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 210,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - AL-LAD

        Substance(
            name: "AL-LAD",
            aliases: ["Aladdin", "6-Allyl-6-nor-LSD"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...225, strong: 225...350, heavy: 350
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 90, max: 150),
                    afterglow: TimeRange(min: 180, max: 360),
                    total: TimeRange(min: 360, max: 540)
                )),
                SubstanceRoute(route: .sublingual, unit: "µg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...225, strong: 225...350, heavy: 350
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 20, max: 45),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 90, max: 150),
                    afterglow: TimeRange(min: 180, max: 360),
                    total: TimeRange(min: 330, max: 510)
                )),
            ],
            effects: ["Vivid visual hallucinations", "Euphoria", "Time distortion", "Light headspace", "Color enhancement", "Enhanced pattern recognition", "Reduced anxiety", "Giggles", "Increased music appreciation", "Geometric visuals"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Vivid Visual Geometry", description: "Exceptionally colorful and well-defined geometric patterns that are often more vivid than LSD, featuring bright neon hues and rapidly shifting fractal structures."),
                SubjectiveEffect(name: "Light Headspace", description: "A notably clear and lucid mental state with minimal confusion or thought loops, allowing for a recreational and manageable experience even at moderate doses."),
                SubjectiveEffect(name: "Spontaneous Laughter", description: "Frequent, uncontrollable fits of giggling and laughter, often triggered by mundane observations that feel absurdly funny."),
                SubjectiveEffect(name: "Color Intensification", description: "Dramatic enhancement of color saturation and brightness, with the world appearing as though a vivid color filter has been applied."),
                SubjectiveEffect(name: "Reduced Anxiety", description: "A lower tendency toward anxious or challenging thought patterns compared to LSD, making the experience feel more reliably positive and lighthearted."),
                SubjectiveEffect(name: "Music Enhancement", description: "Music sounds richer and more emotionally engaging, with enhanced spatial perception of sound and a joyful, dance-inducing quality."),
                SubjectiveEffect(name: "Shorter Duration", description: "The experience resolves within 6-8 hours rather than the 8-12 typical of LSD, which many users find more convenient and less fatiguing."),
                SubjectiveEffect(name: "Body Lightness", description: "A sensation of physical buoyancy and energetic lightness, as though the body weighs less, accompanied by an urge to move and dance."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - ETH-LAD

        Substance(
            name: "ETH-LAD",
            aliases: ["6-Ethyl-6-nor-LSD"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 15, light: 25...60, common: 60...100, strong: 100...200, heavy: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 45, max: 90),
                    peak: TimeRange(min: 180, max: 300),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 240, max: 480),
                    total: TimeRange(min: 420, max: 660)
                )),
            ],
            effects: ["Intense visual hallucinations", "Euphoria", "Time distortion", "Introspection", "Nausea", "Body load", "Enhanced pattern recognition", "Thought loops", "Confusion", "Geometric visuals"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Intense Visual Geometry", description: "Remarkably complex and detailed geometric hallucinations that can exceed LSD in visual intensity, with deeply layered fractal structures and rapid morphing."),
                SubjectiveEffect(name: "Significant Body Load", description: "Prominent physical discomfort including nausea, muscle tension, and stomach cramping that is notably heavier than other lysergamides, especially during the come-up."),
                SubjectiveEffect(name: "Steep Dose-Response Curve", description: "Small increases in dose produce disproportionately large increases in effect intensity, making careful dosing critical for managing the experience."),
                SubjectiveEffect(name: "Deep Introspection", description: "A powerful inward focus that can produce profound personal insights but also confusing or overwhelming recursive thought patterns."),
                SubjectiveEffect(name: "Cognitive Confusion", description: "A tendency toward disorganized thinking and difficulty maintaining a coherent train of thought, especially at moderate to high doses."),
                SubjectiveEffect(name: "Time Distortion", description: "Severe distortion of temporal perception where time may appear to stop, reverse, or loop, more pronounced than with standard LSD."),
                SubjectiveEffect(name: "Emotional Intensity", description: "Powerful and sometimes unpredictable emotional surges that can shift rapidly between ecstatic bliss and challenging psychological territory."),
                SubjectiveEffect(name: "Nausea", description: "Significant gastrointestinal discomfort that commonly occurs during the onset phase and can persist into the peak, more reliably present than with other lysergamides."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 240,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - PRO-LAD

        Substance(
            name: "PRO-LAD",
            aliases: ["6-Propyl-6-nor-LSD"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 15, light: 25...75, common: 75...150, strong: 150...300, heavy: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 45, max: 90),
                    peak: TimeRange(min: 180, max: 300),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 240, max: 480),
                    total: TimeRange(min: 420, max: 660)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Introspection", "Synesthesia", "Enhanced pattern recognition", "Thought acceleration", "Anxiety", "Increased music appreciation", "Color enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Visual Geometry", description: "Geometric visual distortions comparable to LSD, with patterning that some users describe as slightly warmer and more organic in character."),
                SubjectiveEffect(name: "Thought Acceleration", description: "A noticeable increase in the speed and fluidity of thought, with ideas connecting rapidly and a sense of heightened cognitive throughput."),
                SubjectiveEffect(name: "Color Enhancement", description: "Colors appear more saturated and distinct, with enhanced contrast and a tendency for hues to shift or breathe subtly."),
                SubjectiveEffect(name: "Synesthesia", description: "Blending of sensory experiences where sounds may generate visual impressions and tactile stimuli carry emotional or chromatic qualities."),
                SubjectiveEffect(name: "Time Distortion", description: "Altered sense of time passage characteristic of lysergamides, with subjective time dilation making the experience feel longer than clock time."),
                SubjectiveEffect(name: "Emotional Amplification", description: "Intensified emotional responses to stimuli, with a heightened capacity for both joy and anxiety depending on set and setting."),
                SubjectiveEffect(name: "Music Enhancement", description: "Enhanced perception of musical detail and emotional content, with an increased sense that music carries personal or cosmic significance."),
                SubjectiveEffect(name: "Introspective Depth", description: "A pull toward self-examination and contemplation of personal history, motivations, and relationships with greater emotional honesty."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 240,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - LSA

        Substance(
            name: "LSA",
            aliases: ["Ergine", "Morning Glory", "HBWR", "Hawaiian Baby Woodrose", "d-Lysergic acid amide"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 100, light: 200...500, common: 500...1000, strong: 1000...2000, heavy: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 90),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 240, max: 720),
                    total: TimeRange(min: 360, max: 600)
                )),
            ],
            effects: ["Sedation", "Nausea", "Visual hallucinations", "Euphoria", "Time distortion", "Introspection", "Vasoconstriction", "Dreamlike state", "Body load", "Muscle cramps"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Dreamlike State", description: "A heavy, trance-like quality to the experience that feels more sedating and oneiric than other lysergamides, resembling a waking dream with vivid imagery."),
                SubjectiveEffect(name: "Severe Nausea", description: "Pronounced gastrointestinal discomfort and nausea during onset that is considered a hallmark of the LSA experience, especially when consuming raw seed material."),
                SubjectiveEffect(name: "Vasoconstriction", description: "Noticeable tightening of blood vessels causing cold extremities, leg cramps, and an uncomfortable heavy feeling in the limbs."),
                SubjectiveEffect(name: "Sedation", description: "A strong tendency toward physical lethargy and drowsiness that distinguishes LSA from the stimulating character of LSD and its analogs."),
                SubjectiveEffect(name: "Muscle Cramping", description: "Uncomfortable muscle tension and cramping, particularly in the legs and abdomen, caused by ergot alkaloid vasoconstriction."),
                SubjectiveEffect(name: "Visual Distortions", description: "Softer, more flowing visual effects than LSD, with wavering surfaces, enhanced colors, and closed-eye imagery that feels dreamlike rather than geometric."),
                SubjectiveEffect(name: "Introspective Depth", description: "A strong pull toward deep self-examination and contemplation, often with a solemn or spiritual quality distinct from the playful introspection of LSD."),
                SubjectiveEffect(name: "Euphoric Waves", description: "Intermittent waves of warm euphoria that alternate with periods of physical discomfort, creating an experience that oscillates between pleasant and challenging."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - LSZ

        Substance(
            name: "LSZ",
            aliases: ["Lysergic acid 2,4-dimethylazetidide", "LA-SS-Az", "Diazedine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 50, light: 75...150, common: 150...300, strong: 300...400, heavy: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 45, max: 90),
                    peak: TimeRange(min: 180, max: 300),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 240, max: 480),
                    total: TimeRange(min: 420, max: 660)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Introspection", "Color enhancement", "Enhanced pattern recognition", "Thought acceleration", "Anxiety", "Geometric visuals", "Increased music appreciation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Sharp Visual Geometry", description: "Highly detailed and angular geometric patterns that have a distinctive crystalline sharpness, often described as more structured and less fluid than LSD visuals."),
                SubjectiveEffect(name: "Thought Acceleration", description: "Rapid-fire thought processes with ideas connecting in unexpected and creative ways, producing a stimulated and mentally active headspace."),
                SubjectiveEffect(name: "Color Enhancement", description: "Significant intensification of color perception with enhanced saturation and contrast, making the visual environment feel hyper-real and vibrant."),
                SubjectiveEffect(name: "Longer Duration", description: "An extended experience timeline that can exceed LSD at comparable doses, with effects sometimes persisting for 10-14 hours."),
                SubjectiveEffect(name: "Time Distortion", description: "Profound alteration of temporal perception where subjective experience of time diverges dramatically from clock time."),
                SubjectiveEffect(name: "Music Enhancement", description: "Deeply enhanced musical appreciation with an ability to perceive intricate structural details and emotional layers within compositions."),
                SubjectiveEffect(name: "Introspective Focus", description: "A strong drive toward inner contemplation and examination of personal beliefs, habits, and emotional patterns."),
                SubjectiveEffect(name: "Stimulation", description: "A physically and mentally energizing quality that creates restlessness and a desire for activity, more stimulating than many other lysergamides."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 240,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - LSM-775

        Substance(
            name: "LSM-775",
            aliases: ["Lysergic acid morpholide"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 50, light: 75...200, common: 200...500, strong: 500...750, heavy: 750
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 90, max: 150),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 300, max: 540)
                )),
            ],
            effects: ["Mild visual hallucinations", "Sedation", "Time distortion", "Introspection", "Dreamlike state", "Reduced stimulation", "Thought deceleration", "Body load", "Color enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Dreamlike Sedation", description: "A heavy, drowsy quality that distinguishes this lysergamide from more stimulating analogs, producing a dreamy half-asleep state with mild psychedelic undertones."),
                SubjectiveEffect(name: "Subtle Visual Enhancement", description: "Mild visual effects limited to gentle color enhancement and slight wavering of surfaces, without the complex geometry typical of LSD."),
                SubjectiveEffect(name: "Thought Deceleration", description: "A slowing of cognitive processes that feels contemplative and meditative rather than stimulating, with thoughts becoming spacious and unhurried."),
                SubjectiveEffect(name: "Body Load", description: "A noticeable physical heaviness and lethargy that can feel uncomfortable, with a sedating weight settling into the limbs."),
                SubjectiveEffect(name: "Gentle Introspection", description: "A mild, non-confrontational tendency toward self-reflection that lacks the intensity or depth of stronger lysergamides."),
                SubjectiveEffect(name: "Time Distortion", description: "A subtle stretching of temporal perception where time feels slow and languid, consistent with the overall sedating character of the experience."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 200,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - MiPLA

        Substance(
            name: "MiPLA",
            aliases: ["MIPLA", "N-Methyl-N-isopropyllysergamide"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 10, light: 20...50, common: 50...100, strong: 100...200, heavy: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 180),
                    offset: TimeRange(min: 90, max: 120),
                    afterglow: TimeRange(min: 120, max: 240),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Mild visual enhancement", "Euphoria", "Time distortion", "Light headspace", "Color enhancement", "Increased music appreciation", "Mild thought acceleration", "Reduced anxiety", "Sociability"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Microdose-Like Clarity", description: "A remarkably clear and functional headspace even at full doses, producing a gentle psychedelic enhancement without significant cognitive impairment."),
                SubjectiveEffect(name: "Subtle Visual Enhancement", description: "Gentle visual effects limited to enhanced color saturation, slight surface breathing, and mild pattern enhancement without complex geometry."),
                SubjectiveEffect(name: "Mood Lift", description: "A reliable, gentle elevation of mood and sense of well-being that feels natural and unforced, without the intensity of a full LSD euphoria."),
                SubjectiveEffect(name: "Enhanced Sociability", description: "Increased comfort in social situations with greater verbal fluency and empathetic engagement, making it feel suitable for social settings."),
                SubjectiveEffect(name: "Music Enhancement", description: "Mild but pleasant enhancement of musical appreciation, with subtle increases in emotional resonance and enjoyment of rhythm and melody."),
                SubjectiveEffect(name: "Color Enhancement", description: "Colors appear slightly more vivid and defined, with a subtle but noticeable increase in the richness of the visual world."),
                SubjectiveEffect(name: "Reduced Anxiety", description: "A calming, anxiolytic quality that makes the experience feel safe and manageable, with minimal risk of challenging thought patterns."),
                SubjectiveEffect(name: "Mild Time Distortion", description: "A subtle alteration in the perception of time that is far less pronounced than with full-potency lysergamides."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - PARGY-LAD

        Substance(
            name: "PARGY-LAD",
            aliases: ["6-Propargyl-6-nor-LSD"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...400, heavy: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 45, max: 90),
                    peak: TimeRange(min: 180, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 240, max: 480),
                    total: TimeRange(min: 420, max: 600)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Introspection", "Enhanced pattern recognition", "Thought acceleration", "Anxiety", "Geometric visuals", "Increased music appreciation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Visual Geometry", description: "Geometric visual distortions with a character similar to other nor-LSD derivatives, featuring colorful patterning and surface morphing at common doses."),
                SubjectiveEffect(name: "Thought Acceleration", description: "Noticeably faster thought processes with ideas flowing rapidly and connecting in unexpected configurations, producing a mentally stimulated state."),
                SubjectiveEffect(name: "Euphoria", description: "Waves of positive affect and well-being that arise spontaneously, sometimes accompanied by a sense of gratitude or wonder about ordinary things."),
                SubjectiveEffect(name: "Time Distortion", description: "Altered temporal perception where the subjective experience of duration diverges from clock time, typical of the lysergamide class."),
                SubjectiveEffect(name: "Pattern Recognition", description: "Enhanced tendency to perceive meaningful patterns in visual textures, sounds, and abstract concepts, with ordinary surfaces becoming richly detailed."),
                SubjectiveEffect(name: "Music Enhancement", description: "Heightened emotional and perceptual engagement with music, where songs feel more layered, spatial, and personally meaningful."),
                SubjectiveEffect(name: "Introspective Focus", description: "A drawing inward of attention toward personal thoughts, memories, and emotional states with heightened reflective capacity."),
                SubjectiveEffect(name: "Anxiety Potential", description: "A susceptibility to anxious thought spirals, particularly during onset or in unfamiliar settings, that requires careful attention to set and setting."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 200,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - Ergometrine

        Substance(
            name: "Ergometrine",
            aliases: ["Ergonovine", "Ergobasine", "d-Lysergic acid beta-propanolamide"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 250, light: 500...1000, common: 1000...2000, strong: 2000...4000, heavy: 4000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 90, max: 150),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 300, max: 540)
                )),
            ],
            effects: ["Mild visual hallucinations", "Vasoconstriction", "Nausea", "Uterine contractions", "Anxiety", "Time distortion", "Body load", "Introspection", "Muscle cramps"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Severe Vasoconstriction", description: "Pronounced tightening of blood vessels causing cold, numb extremities and uncomfortable cramping in the limbs, a dominant feature of the experience."),
                SubjectiveEffect(name: "Intense Nausea", description: "Strong gastrointestinal discomfort that can include nausea, vomiting, and abdominal cramping, often overshadowing any psychedelic effects."),
                SubjectiveEffect(name: "Muscle Cramping", description: "Painful involuntary muscle contractions, particularly in the legs and uterine smooth muscle, caused by potent ergot alkaloid activity."),
                SubjectiveEffect(name: "Mild Visual Distortions", description: "Subtle psychedelic visual effects limited to slight color enhancement and gentle surface undulation, far less pronounced than LSD."),
                SubjectiveEffect(name: "Anxiety", description: "Physical discomfort frequently produces anxious, unsettled feelings that are more somatic than psychological in origin."),
                SubjectiveEffect(name: "Body Load", description: "A pervasive sense of physical heaviness and discomfort that dominates the experience, with the body feeling tense and constricted."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - Methysergide

        Substance(
            name: "Methysergide",
            aliases: ["Sansert", "Deseril", "1-Methyl-d-lysergic acid butanolamide"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 250, light: 500...1000, common: 1000...2000, strong: 2000...4000, heavy: 4000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 90, max: 150),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 300, max: 540)
                )),
            ],
            effects: ["Mild visual hallucinations", "Vasoconstriction", "Nausea", "Sedation", "Time distortion", "Body load", "Introspection", "Muscle cramps", "Anxiety"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Vasoconstriction", description: "Significant blood vessel constriction causing cold extremities, numbness, and an uncomfortable tightness throughout the body."),
                SubjectiveEffect(name: "Sedation", description: "A drowsy, fatigued quality that distinguishes it from more stimulating lysergamides, with a heavy and lethargic feeling that discourages physical activity."),
                SubjectiveEffect(name: "Nausea", description: "Persistent gastrointestinal discomfort and queasiness that is a prominent feature, stemming from ergot alkaloid pharmacology."),
                SubjectiveEffect(name: "Minimal Psychedelic Effects", description: "Very subtle psychedelic activity limited to mild visual brightening and gentle thought alteration, far below the threshold of a full psychedelic experience."),
                SubjectiveEffect(name: "Muscle Cramping", description: "Uncomfortable tension and cramping in skeletal muscles, particularly in the extremities, due to vasoconstrictive activity."),
                SubjectiveEffect(name: "Anxiety", description: "A low-level anxious restlessness driven primarily by physical discomfort rather than psychedelic cognitive effects."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 240,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - 1P-ETH-LAD

        Substance(
            name: "1P-ETH-LAD",
            aliases: ["1-Propionyl-6-ethyl-6-nor-LSD"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 15, light: 25...60, common: 60...100, strong: 100...200, heavy: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 45, max: 90),
                    comeup: TimeRange(min: 45, max: 90),
                    peak: TimeRange(min: 180, max: 300),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 240, max: 480),
                    total: TimeRange(min: 450, max: 690)
                )),
            ],
            effects: ["Intense visual hallucinations", "Euphoria", "Time distortion", "Introspection", "Nausea", "Body load", "Enhanced pattern recognition", "Thought loops", "Confusion", "Geometric visuals"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Intense Visual Geometry", description: "Complex, highly detailed geometric patterns characteristic of ETH-LAD, emerging after prodrug conversion, with deep layering and rapid morphological changes."),
                SubjectiveEffect(name: "Significant Body Load", description: "Pronounced physical discomfort including nausea and muscle tension inherited from the ETH-LAD pharmacological profile, often more intense than LSD."),
                SubjectiveEffect(name: "Delayed Onset", description: "A slower come-up than ETH-LAD itself due to the additional metabolic step of propionyl group removal before conversion to the active compound."),
                SubjectiveEffect(name: "Cognitive Confusion", description: "A tendency toward disoriented and nonlinear thinking, with difficulty maintaining focus on a single train of thought."),
                SubjectiveEffect(name: "Thought Loops", description: "Repetitive cycling of thought patterns that can feel disorienting, with the same ideas recurring in slightly altered forms."),
                SubjectiveEffect(name: "Deep Introspection", description: "A powerful pull toward internal examination that can produce valuable insights but also overwhelming or challenging psychological content."),
                SubjectiveEffect(name: "Nausea", description: "Gastrointestinal discomfort that is a reliable feature of the experience, often beginning during onset and potentially persisting into the peak."),
                SubjectiveEffect(name: "Emotional Intensity", description: "Strong and sometimes unpredictable emotional responses that amplify whatever feelings are present in the psychological environment."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 240,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - 1cP-AL-LAD

        Substance(
            name: "1cP-AL-LAD",
            aliases: ["1-Cyclopropionyl-6-allyl-6-nor-LSD"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "µg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...225, strong: 225...350, heavy: 350
                ), duration: DurationProfile(
                    onset: TimeRange(min: 45, max: 90),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 90, max: 150),
                    afterglow: TimeRange(min: 180, max: 360),
                    total: TimeRange(min: 390, max: 570)
                )),
            ],
            effects: ["Vivid visual hallucinations", "Euphoria", "Time distortion", "Light headspace", "Color enhancement", "Enhanced pattern recognition", "Reduced anxiety", "Giggles", "Increased music appreciation", "Geometric visuals"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Vivid Visual Geometry", description: "Bright, colorful geometric patterns characteristic of AL-LAD that emerge after prodrug conversion, with neon hues and kaleidoscopic structures."),
                SubjectiveEffect(name: "Light Headspace", description: "A clear and manageable mental state inherited from the AL-LAD profile, with minimal cognitive confusion and a recreational, lighthearted quality."),
                SubjectiveEffect(name: "Delayed Onset", description: "A slower come-up than AL-LAD due to the cyclopropionyl prodrug requiring metabolic activation before the active compound is released."),
                SubjectiveEffect(name: "Spontaneous Laughter", description: "Frequent fits of uncontrollable giggling triggered by ordinary observations, consistent with the playful character of the AL-LAD experience."),
                SubjectiveEffect(name: "Color Intensification", description: "Dramatic enhancement of color saturation where the world appears painted in brighter, more vivid tones with enhanced contrast."),
                SubjectiveEffect(name: "Reduced Anxiety", description: "A notably lower tendency toward anxious or challenging mental states compared to LSD, contributing to a reliably positive experience profile."),
                SubjectiveEffect(name: "Music Enhancement", description: "Joyful enhancement of musical perception with increased emotional resonance and a desire to move and dance to rhythm."),
                SubjectiveEffect(name: "Physical Euphoria", description: "A warm, tingling body euphoria accompanied by a sense of lightness and energetic well-being that encourages physical activity."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - Natural LSA Sources

        // MARK: - Morning Glory Seeds

        Substance(
            name: "Morning Glory Seeds",
            aliases: ["Ipomoea tricolor", "Heavenly Blue", "Tlitlitzin"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "seeds", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...250, strong: 250...400, heavy: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 90),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 240, max: 720),
                    total: TimeRange(min: 360, max: 600)
                )),
            ],
            effects: ["Visual distortions", "Introspection", "Nausea", "Vasoconstriction", "Dreamy state"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Dreamy Psychedelic State", description: "A heavy, trance-like quality with flowing, dream-like imagery and introspective depth, distinctly more sedating and oneiric than LSD due to the LSA content."),
                SubjectiveEffect(name: "Severe Nausea", description: "Intense gastrointestinal distress is nearly universal and often the dominant experience during the first 1-2 hours, caused by glycoside compounds in the seed coating."),
                SubjectiveEffect(name: "Vasoconstriction", description: "Pronounced tightening of blood vessels causing cold, cramping extremities and an uncomfortable heaviness in the legs, a hallmark of ergine alkaloid activity."),
                SubjectiveEffect(name: "Visual Distortions", description: "Soft, flowing visual effects with enhanced colors, wavering surfaces, and closed-eye imagery that feels dreamlike rather than geometric, distinct from LSD's sharp visuals."),
                SubjectiveEffect(name: "Physical Sedation", description: "A strong tendency toward lethargy and drowsiness that distinguishes morning glory from the stimulating character of LSD, often pinning users to a couch or bed."),
                SubjectiveEffect(name: "Introspective Depth", description: "A solemn, contemplative quality to the experience that encourages deep self-examination, often with themes of personal growth and spiritual significance."),
                SubjectiveEffect(name: "Abdominal Cramping", description: "Painful stomach cramps and gastrointestinal spasms that can persist for much of the experience, caused by the plant material and ergot alkaloids."),
                SubjectiveEffect(name: "Euphoric Waves", description: "Intermittent waves of warm bliss that alternate with periods of physical discomfort, creating an experience that oscillates between pleasant and challenging."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - Hawaiian Baby Woodrose

        Substance(
            name: "Hawaiian Baby Woodrose",
            aliases: ["HBWR", "Argyreia nervosa", "Elephant Creeper"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "seeds", doses: DoseRange(
                    threshold: 1, light: 2...4, common: 4...8, strong: 8...12, heavy: 12
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 90),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 240, max: 720),
                    total: TimeRange(min: 360, max: 600)
                )),
            ],
            effects: ["Psychedelic visuals", "Sedation", "Nausea", "Vasoconstriction", "Introspection"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Potent LSA Effects", description: "Significantly stronger LSA content per seed than morning glory, producing a full psychedelic experience from just a handful of seeds with intense dreamy visuals and introspection."),
                SubjectiveEffect(name: "Heavy Sedation", description: "A pronounced physical lethargy and drowsiness that is more intense than morning glory, often leaving users immobile and deeply inward-focused for hours."),
                SubjectiveEffect(name: "Severe Nausea and Vomiting", description: "Intense gastrointestinal distress that frequently includes vomiting, considered one of the most challenging aspects and often occurring within the first hour."),
                SubjectiveEffect(name: "Extreme Vasoconstriction", description: "Painful tightening of blood vessels with cold, numb extremities and leg cramps that can be more severe than with morning glory due to higher alkaloid concentration."),
                SubjectiveEffect(name: "Dreamlike Visuals", description: "Rich, flowing closed-eye imagery with enhanced colors and soft visual distortions that have a deeply oneiric, trance-like quality distinct from the sharp geometry of LSD."),
                SubjectiveEffect(name: "Deep Introspection", description: "A powerful inward focus with contemplation of life patterns, relationships, and spiritual themes, often described as having a serious, ceremonial quality."),
                SubjectiveEffect(name: "Body Load", description: "A pervasive physical heaviness and discomfort that includes cramping, tension, and a general sense of the body being under strain from the ergot alkaloids."),
                SubjectiveEffect(name: "Extended Duration", description: "Effects can last 6-10 hours with a slow onset of 1-3 hours, requiring patience and commitment to a lengthy, physically demanding experience."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),
    ]
}
