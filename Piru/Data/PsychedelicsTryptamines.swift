import Foundation

extension SubstanceLibrary {
    // swiftlint:disable function_body_length
    static let psychedelicsTryptamines: [Substance] = [

        // MARK: - 1. Psilocybin (Magic Mushrooms)
        Substance(
            name: "Psilocybin",
            aliases: ["Magic Mushrooms", "Shrooms", "Psilocybe", "Mushrooms"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "g", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1.5, common: 1.5...3.5, strong: 3.5...5.0, heavy: 5.0
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Introspection", "Nausea", "Ego dissolution", "Enhanced pattern recognition", "Emotional intensification", "Synesthesia", "Giggles"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Visual Enhancements", description: "Colors appear more vivid and saturated, surfaces may breathe or shift, and closed-eye visuals feature intricate fractal-like patterns."),
                SubjectiveEffect(name: "Emotional Amplification", description: "Existing emotions become dramatically intensified, often cycling between profound joy, nostalgia, and occasional waves of sadness or awe."),
                SubjectiveEffect(name: "Body High", description: "A warm, tingling sensation spreads through the body, sometimes accompanied by waves of pleasurable energy radiating from the core."),
                SubjectiveEffect(name: "Ego Dissolution", description: "At higher doses, the boundary between self and environment softens or dissolves entirely, producing a sense of merging with surroundings."),
                SubjectiveEffect(name: "Time Distortion", description: "Minutes can feel like hours and vice versa, with time sometimes appearing to loop, slow down dramatically, or lose all meaning."),
                SubjectiveEffect(name: "Introspective Depth", description: "Thoughts become deeply reflective, often centering on personal relationships, life purpose, and behavioral patterns with unusual clarity."),
                SubjectiveEffect(name: "Fits of Laughter", description: "Spontaneous, uncontrollable giggling often arises from mundane observations or absurd thought loops, especially during the come-up."),
                SubjectiveEffect(name: "Nature Connectedness", description: "A profound feeling of connection to the natural world, where plants, animals, and landscapes seem alive with significance and beauty."),
                SubjectiveEffect(name: "Nausea", description: "Mild to moderate stomach discomfort typically occurs during the onset, sometimes accompanied by a heavy feeling in the gut."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: - 2. Psilocin (4-HO-DMT)
        Substance(
            name: "Psilocin",
            aliases: ["4-HO-DMT"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 8...15, common: 15...25, strong: 25...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 120, max: 240),
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Introspection", "Nausea", "Ego dissolution", "Enhanced color perception", "Emotional intensification", "Body high", "Synesthesia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Rapid Visual Onset", description: "Visuals come on faster and feel more fluid than psilocybin, with flowing geometric overlays and morphing surfaces appearing quickly after ingestion."),
                SubjectiveEffect(name: "Warm Body High", description: "A deeply comfortable, almost sedating warmth permeates the body, often described as feeling wrapped in a soft blanket of energy."),
                SubjectiveEffect(name: "Color Saturation", description: "Colors become extraordinarily vivid and rich, with the world taking on an almost hyper-real, high-definition quality."),
                SubjectiveEffect(name: "Emotional Sensitivity", description: "Emotions become raw and immediate, with a tendency toward deep empathy and an increased capacity to feel moved by small details."),
                SubjectiveEffect(name: "Ego Softening", description: "The sense of self gradually loosens, leading to feelings of unity with one's environment and a dissolution of personal boundaries."),
                SubjectiveEffect(name: "Synesthetic Blending", description: "Sensory crossover occurs where sounds may produce visual patterns, or textures may evoke tastes, blurring the lines between senses."),
                SubjectiveEffect(name: "Introspective Clarity", description: "Thoughts become unusually clear and self-reflective, often producing insights about personal habits and emotional patterns."),
                SubjectiveEffect(name: "Gastrointestinal Discomfort", description: "Nausea and stomach cramping are common during the come-up, though typically less intense than with whole mushrooms."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 108
        ),

        // MARK: - 3. DMT (N,N-DMT)
        Substance(
            name: "DMT",
            aliases: ["N,N-DMT", "Dimitri", "The Spirit Molecule"],
            category: .psychedelic,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 0.5),
                    comeup: TimeRange(min: 0.5, max: 2),
                    peak: TimeRange(min: 3, max: 10),
                    offset: TimeRange(min: 10, max: 20),
                    afterglow: TimeRange(min: 15, max: 60),
                    total: TimeRange(min: 15, max: 30)
                )),
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 20, light: 30...60, common: 60...100, strong: 100...150, heavy: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Breakthrough experiences", "Intense visual hallucinations", "Ego dissolution", "Entity contact", "Time distortion", "Euphoria", "Auditory hallucinations", "Rapid onset", "Out-of-body experiences", "Anxiety"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Breakthrough Experience", description: "At sufficient doses, reality completely dissolves and is replaced by an entirely alien landscape of impossible geometry, light, and meaning."),
                SubjectiveEffect(name: "Entity Contact", description: "Many users report encounters with seemingly autonomous beings or presences that communicate through gesture, telepathy, or visual language."),
                SubjectiveEffect(name: "Ego Death", description: "Complete and sudden dissolution of personal identity, often described as dying and being reborn within minutes."),
                SubjectiveEffect(name: "Hyperdimensional Geometry", description: "Intensely detailed, self-transforming geometric structures in impossible colors that feel more real than ordinary waking reality."),
                SubjectiveEffect(name: "Time Annihilation", description: "Time ceases to exist entirely during the peak, with the experience feeling simultaneously instantaneous and eternal."),
                SubjectiveEffect(name: "Auditory Hallucinations", description: "Carrier waves, buzzing, high-pitched tones, and alien-sounding language or music often accompany the visual experience."),
                SubjectiveEffect(name: "Pre-flight Anxiety", description: "Intense anticipatory nervousness or fear as the rapid onset begins, often described as being launched from a cannon."),
                SubjectiveEffect(name: "Profound Awe", description: "An overwhelming sense of wonder, sacredness, or cosmic significance that can leave lasting impressions on one's worldview."),
                SubjectiveEffect(name: "Rapid Return to Baseline", description: "Effects dissipate remarkably quickly when smoked, with near-complete sobriety returning within 15-30 minutes."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 1, fullResetDays: 7, buildRate: "rapid"),
            halfLifeMinutes: 15
        ),

        // MARK: - 4. 5-MeO-DMT (Toad)
        Substance(
            name: "5-MeO-DMT",
            aliases: ["Toad", "Bufo", "Five-methoxy", "5MeO"],
            category: .psychedelic,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 3...5, common: 5...12, strong: 12...20, heavy: 20, fatal: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 0.5),
                    comeup: TimeRange(min: 1, max: 3),
                    peak: TimeRange(min: 5, max: 15),
                    offset: TimeRange(min: 15, max: 30),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 20, max: 45)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...10, common: 10...18, strong: 18...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 2, max: 5),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 10, max: 30),
                    offset: TimeRange(min: 20, max: 40),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 30, max: 60)
                )),
            ],
            effects: ["Ego dissolution", "Unity experience", "Intense body load", "Euphoria", "Nausea", "Overwhelming intensity", "Time distortion", "White-out experiences", "Emotional release", "Anxiety"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Unity Experience", description: "A total merging with existence itself, often described as becoming everything and nothing simultaneously in a boundless white light."),
                SubjectiveEffect(name: "Complete Ego Dissolution", description: "The sense of self is obliterated almost instantly, far more forcefully than with most other psychedelics, leaving only pure awareness."),
                SubjectiveEffect(name: "White-Out", description: "Vision is overwhelmed by blinding white light as all visual detail dissolves into an undifferentiated field of luminous energy."),
                SubjectiveEffect(name: "Intense Body Load", description: "Powerful physical sensations including pressure, vibration, and energy surges through the body that can feel overwhelming or ecstatic."),
                SubjectiveEffect(name: "Emotional Catharsis", description: "Uncontrollable crying, screaming, or laughing as deeply buried emotions surface and release with tremendous force."),
                SubjectiveEffect(name: "Overwhelming Intensity", description: "The experience can feel far beyond what one prepared for, with a sense of being completely overpowered by the substance."),
                SubjectiveEffect(name: "Existential Terror", description: "Confrontation with apparent death or the void can produce extreme fear, particularly for those unprepared for the intensity."),
                SubjectiveEffect(name: "Oceanic Boundlessness", description: "A feeling of infinite expansion and dissolution into a vast, peaceful ocean of consciousness beyond individual identity."),
                SubjectiveEffect(name: "Afterglow Clarity", description: "A lasting sense of peace, gratitude, and emotional openness that can persist for days or weeks following the experience."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 1, fullResetDays: 7, buildRate: "rapid"),
            halfLifeMinutes: 16
        ),

        // MARK: - 5. 4-AcO-DMT (Psilacetin)
        Substance(
            name: "4-AcO-DMT",
            aliases: ["Psilacetin", "O-Acetylpsilocin", "4-Acetoxy-DMT"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...15, common: 15...25, strong: 25...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 240, max: 360)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...10, common: 10...20, strong: 20...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 45, max: 90),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 120, max: 240)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Introspection", "Nausea", "Ego dissolution", "Enhanced color perception", "Emotional intensification", "Sedation", "Synesthesia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mushroom-Like Visuals", description: "Visual effects closely resemble psilocybin, with breathing surfaces, flowing patterns, and rich color enhancement, as it is believed to be a prodrug of psilocin."),
                SubjectiveEffect(name: "Gentle Sedation", description: "A calming, slightly sedating body sensation that encourages lying down and surrendering to the experience."),
                SubjectiveEffect(name: "Emotional Depth", description: "Feelings become layered and nuanced, with a tendency toward deep emotional exploration and processing of personal material."),
                SubjectiveEffect(name: "Smooth Come-Up", description: "The onset tends to be gentler and more gradual than mushrooms, with less nausea since no plant material is involved."),
                SubjectiveEffect(name: "Ego Dissolution", description: "At higher doses, boundaries of self soften and dissolve in a manner very similar to high-dose psilocybin experiences."),
                SubjectiveEffect(name: "Synesthetic Perception", description: "Sounds may take on visual qualities and colors may seem to have textures, with sensory channels bleeding into one another."),
                SubjectiveEffect(name: "Time Warping", description: "Temporal perception becomes elastic, with moments stretching into what feels like hours and periods of timelessness."),
                SubjectiveEffect(name: "Contemplative Headspace", description: "A deeply thoughtful mental state that naturally gravitates toward philosophical questions and personal insight."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: - 6. 4-HO-MET (Metocin)
        Substance(
            name: "4-HO-MET",
            aliases: ["Metocin", "Colour", "Methylcybin"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 8...15, common: 15...25, strong: 25...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 90),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 180, max: 300)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...10, common: 10...20, strong: 20...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 45, max: 75),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 30, max: 120),
                    total: TimeRange(min: 120, max: 210)
                )),
            ],
            effects: ["Vivid color enhancement", "Visual hallucinations", "Euphoria", "Giggles", "Light body load", "Time distortion", "Enhanced pattern recognition", "Recreational headspace", "Nausea", "Emotional uplift"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Vivid Color Enhancement", description: "Colors become exceptionally bright and saturated, often described as the most colorful of all tryptamines, with a neon-like vibrancy."),
                SubjectiveEffect(name: "Recreational Headspace", description: "The mental effects are lighter and more manageable than psilocybin, making it easier to socialize and enjoy activities."),
                SubjectiveEffect(name: "Geometric Visuals", description: "Intricate, colorful geometric patterns overlay surfaces and fill closed-eye vision, often with a playful, whimsical quality."),
                SubjectiveEffect(name: "Euphoric Giggles", description: "A bubbly, infectious happiness that frequently erupts into fits of laughter, giving the experience a lighthearted character."),
                SubjectiveEffect(name: "Light Body Load", description: "Physical effects are mild and generally pleasant, with a gentle buzzing energy rather than heavy sedation or stimulation."),
                SubjectiveEffect(name: "Emotional Uplift", description: "A consistent mood elevation and positivity throughout the experience, with less emotional turbulence than deeper tryptamines."),
                SubjectiveEffect(name: "Pattern Recognition", description: "Enhanced ability to perceive patterns in textures, nature, and visual fields, with surfaces appearing to tessellate and shift."),
                SubjectiveEffect(name: "Music Enhancement", description: "Music sounds richer and more emotionally resonant, with individual instruments becoming more distinct and spatially defined."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120
        ),

        // MARK: - 7. 4-AcO-MET (Metacetin)
        Substance(
            name: "4-AcO-MET",
            aliases: ["Metacetin", "4-Acetoxy-MET"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...15, common: 15...25, strong: 25...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 90),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 180, max: 300)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...10, common: 10...20, strong: 20...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 45, max: 75),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 30, max: 120),
                    total: TimeRange(min: 120, max: 210)
                )),
            ],
            effects: ["Visual hallucinations", "Color enhancement", "Euphoria", "Giggles", "Time distortion", "Recreational headspace", "Enhanced pattern recognition", "Nausea", "Emotional uplift", "Light body load"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Colorful Visuals", description: "As a prodrug of 4-HO-MET, it produces similarly vivid and colorful visual effects with bright geometric overlays and enhanced color perception."),
                SubjectiveEffect(name: "Playful Headspace", description: "The cognitive effects are light and recreational, encouraging creative thinking and social engagement without heavy introspection."),
                SubjectiveEffect(name: "Gradual Onset", description: "The acetoxy group means onset may be slightly slower than 4-HO-MET as the body converts it, producing a smoother come-up."),
                SubjectiveEffect(name: "Giggly Euphoria", description: "A cheerful, buoyant mood with frequent bouts of laughter and a general sense that everything is amusing and delightful."),
                SubjectiveEffect(name: "Surface Morphing", description: "Walls, ceilings, and textured surfaces appear to breathe, ripple, and shift with colorful overlays and flowing patterns."),
                SubjectiveEffect(name: "Emotional Lightness", description: "A carefree, unburdened emotional state that makes the experience feel fun and approachable rather than heavy or challenging."),
                SubjectiveEffect(name: "Mild Nausea", description: "Some gastrointestinal discomfort may occur during the come-up, though typically less intense than with mushrooms."),
                SubjectiveEffect(name: "Enhanced Sociability", description: "A desire to connect with others and share the experience, with conversations feeling fluid, funny, and meaningful."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: - 8. 4-HO-MiPT (Miprocin)
        Substance(
            name: "4-HO-MiPT",
            aliases: ["Miprocin"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...15, common: 15...25, strong: 25...35, heavy: 35
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Visual hallucinations", "Tactile enhancement", "Euphoria", "Body high", "Time distortion", "Introspection", "Nausea", "Emotional intensification", "Enhanced music appreciation", "Synesthesia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Tactile Enhancement", description: "Physical touch becomes intensely pleasurable and nuanced, with textures feeling extraordinarily detailed and sensual."),
                SubjectiveEffect(name: "Rich Body High", description: "A deeply pleasurable, warm physical sensation that many describe as one of the most body-centric tryptamine experiences."),
                SubjectiveEffect(name: "Music Appreciation", description: "Music takes on profound emotional depth and spatial quality, with layers and textures becoming individually perceptible and moving."),
                SubjectiveEffect(name: "Balanced Headspace", description: "A middle ground between recreational lightness and deep introspection, offering meaningful thoughts without overwhelming intensity."),
                SubjectiveEffect(name: "Flowing Visuals", description: "Visual effects feature fluid, organic morphing and drifting patterns rather than sharp geometric forms, with warm color tones."),
                SubjectiveEffect(name: "Emotional Warmth", description: "A deeply empathetic and loving emotional state that fosters feelings of connection and compassion for others."),
                SubjectiveEffect(name: "Synesthetic Blending", description: "Music and sounds may produce visual patterns or physical sensations, with the senses blending into a unified experience."),
                SubjectiveEffect(name: "Moderate Nausea", description: "Stomach discomfort is common during the onset but typically resolves as the experience progresses into the peak."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: - 9. 4-HO-DiPT (Iprocin)
        Substance(
            name: "4-HO-DiPT",
            aliases: ["Iprocin"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...15, common: 15...25, strong: 25...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Auditory distortions", "Visual hallucinations", "Euphoria", "Time distortion", "Body high", "Introspection", "Nausea", "Enhanced music appreciation", "Tactile enhancement", "Emotional intensification"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Auditory Distortions", description: "Sounds become pitch-shifted, flanged, or echo in unusual ways, making this one of the most auditorily active tryptamines."),
                SubjectiveEffect(name: "Music Transformation", description: "Music can sound alien, with pitch and tempo distortions creating an entirely new listening experience that some find fascinating."),
                SubjectiveEffect(name: "Tactile Sensitivity", description: "Physical sensations are heightened and amplified, with touch producing waves of pleasurable or intense body feelings."),
                SubjectiveEffect(name: "Moderate Visuals", description: "Visual effects are present but less dominant than the auditory component, featuring gentle morphing and color shifts."),
                SubjectiveEffect(name: "Deep Body Sensations", description: "A heavy, immersive body high that grounds the experience in physical awareness and can range from pleasant to overwhelming."),
                SubjectiveEffect(name: "Introspective Depth", description: "The headspace encourages deep self-examination, often with an emotional intensity that can bring buried feelings to the surface."),
                SubjectiveEffect(name: "Gastrointestinal Discomfort", description: "Nausea and stomach upset are commonly reported, particularly during the come-up phase of the experience."),
                SubjectiveEffect(name: "Emotional Intensity", description: "Emotions become amplified and can swing between euphoria and challenging introspective states with notable force."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 240
        ),

        // MARK: - 10. 4-HO-DET (Ethocin)
        Substance(
            name: "4-HO-DET",
            aliases: ["Ethocin", "CZ-74"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...15, common: 15...25, strong: 25...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Introspection", "Color enhancement", "Nausea", "Emotional intensification", "Body high", "Enhanced pattern recognition", "Giggles"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Balanced Visual Profile", description: "Visuals are present with color enhancement and surface morphing, similar to psilocin but with a slightly different character and warmer tones."),
                SubjectiveEffect(name: "Lighthearted Mood", description: "A cheerful, giggly disposition that balances nicely between the recreational character of 4-HO-MET and the depth of psilocin."),
                SubjectiveEffect(name: "Comfortable Body High", description: "A pleasant, manageable physical sensation with gentle warmth and mild energy without the heaviness of some other tryptamines."),
                SubjectiveEffect(name: "Color Enhancement", description: "Colors appear richer and more nuanced, with the world taking on a warm, inviting quality that enhances visual appreciation."),
                SubjectiveEffect(name: "Moderate Introspection", description: "Thoughtful self-reflection occurs naturally but does not dominate the experience, allowing for both inner exploration and outward engagement."),
                SubjectiveEffect(name: "Emotional Fluidity", description: "Emotions flow freely and shift naturally, with a tendency toward positive states and a capacity for genuine emotional processing."),
                SubjectiveEffect(name: "Pattern Enhancement", description: "Textures and natural patterns become more noticeable and interesting, with subtle visual overlays adding geometric complexity."),
                SubjectiveEffect(name: "Mild Nausea", description: "Some stomach discomfort may occur during the onset, though it is generally mild and short-lived compared to other tryptamines."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: - 11. 4-HO-EPT (Eprocin)
        Substance(
            name: "4-HO-EPT",
            aliases: ["Eprocin"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 15...25, common: 25...40, strong: 40...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Mild headspace", "Body high", "Color enhancement", "Nausea", "Introspection", "Relaxation", "Emotional warmth"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mild Cognitive Effects", description: "The headspace is notably lighter than many tryptamines, with gentle shifts in thinking rather than deep psychedelic immersion."),
                SubjectiveEffect(name: "Relaxing Body High", description: "A soothing, comfortable physical sensation that promotes relaxation and a sense of being at ease in one's body."),
                SubjectiveEffect(name: "Gentle Visuals", description: "Visual effects are present but subtle, with soft color enhancement, gentle breathing of surfaces, and mild pattern recognition."),
                SubjectiveEffect(name: "Emotional Warmth", description: "A gentle, affectionate emotional state that fosters feelings of contentment and appreciation for one's surroundings and companions."),
                SubjectiveEffect(name: "Color Brightening", description: "Colors appear slightly more vivid and appealing, giving the visual field a warmer, more inviting quality."),
                SubjectiveEffect(name: "Gentle Euphoria", description: "A mild but consistent sense of well-being and happiness that pervades the experience without being overwhelming."),
                SubjectiveEffect(name: "Light Introspection", description: "Casual self-reflection that feels productive and gentle, without the emotional weight of deeper psychedelic states."),
                SubjectiveEffect(name: "Manageable Nausea", description: "Mild stomach discomfort may occur but is generally brief and does not significantly detract from the experience."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: - 12. 4-AcO-DET (Ethacetin)
        Substance(
            name: "4-AcO-DET",
            aliases: ["Ethacetin", "4-Acetoxy-DET"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...15, common: 15...25, strong: 25...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Introspection", "Color enhancement", "Nausea", "Emotional intensification", "Body high", "Enhanced pattern recognition", "Relaxation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Psilocin-Like Character", description: "As a prodrug of 4-HO-DET, effects closely mirror ethocin with warm, organic visuals and a balanced headspace."),
                SubjectiveEffect(name: "Smooth Onset", description: "The acetoxy group provides a gradual, comfortable come-up that eases users into the experience without abrupt transitions."),
                SubjectiveEffect(name: "Warm Body Sensations", description: "A pleasant physical warmth and relaxation that makes the body feel comfortable and at ease throughout the experience."),
                SubjectiveEffect(name: "Color Enrichment", description: "The visual world takes on deeper, warmer hues with subtle enhancements to contrast and saturation."),
                SubjectiveEffect(name: "Reflective Thinking", description: "Thoughts become contemplative and insightful, with a natural inclination toward self-understanding and emotional clarity."),
                SubjectiveEffect(name: "Emotional Openness", description: "A willingness to engage with feelings and emotional material that might normally be avoided or suppressed."),
                SubjectiveEffect(name: "Pattern Perception", description: "Enhanced awareness of patterns in textures, nature, and abstract visual fields with gentle geometric overlays."),
                SubjectiveEffect(name: "Calming Relaxation", description: "A soothing quality that encourages letting go of tension and anxiety, promoting a peaceful state of mind."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: - 13. 4-HO-DPT
        Substance(
            name: "4-HO-DPT",
            aliases: ["4-Hydroxy-DPT"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 15...30, common: 30...50, strong: 50...80, heavy: 80
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 90, max: 150),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Visual hallucinations", "Ego dissolution", "Time distortion", "Introspection", "Body load", "Nausea", "Emotional intensification", "Auditory distortions", "Anxiety", "Sedation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Heavy Body Load", description: "A pronounced physical heaviness and pressure that can feel uncomfortable, requiring higher doses to achieve full effects."),
                SubjectiveEffect(name: "Dark Introspection", description: "The headspace tends toward deep, sometimes challenging psychological territory, with confrontational self-examination."),
                SubjectiveEffect(name: "Ego Dissolution", description: "At higher doses, the sense of self can dissolve completely, producing experiences of cosmic unity or existential void."),
                SubjectiveEffect(name: "Auditory Effects", description: "Sounds may become distorted, echoed, or take on unusual qualities, adding an auditory dimension to the experience."),
                SubjectiveEffect(name: "Sedating Quality", description: "A heavy, drowsy physical state that encourages lying down and surrendering to the experience rather than remaining active."),
                SubjectiveEffect(name: "Intense Nausea", description: "Gastrointestinal discomfort is frequently reported and can be more pronounced than with other 4-substituted tryptamines."),
                SubjectiveEffect(name: "Emotional Turbulence", description: "Emotions can be volatile and intense, swinging between states of profound insight and challenging confrontation."),
                SubjectiveEffect(name: "Anxiety and Unease", description: "A sense of foreboding or anxious energy that can permeate the experience, particularly during the come-up and peak."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 240
        ),

        // MARK: - 14. 4-HO-McPT
        Substance(
            name: "4-HO-McPT",
            aliases: ["4-Hydroxy-McPT"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 15...25, common: 25...40, strong: 40...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Body high", "Introspection", "Nausea", "Color enhancement", "Emotional intensification", "Relaxation", "Enhanced pattern recognition"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Understudied Character", description: "As a relatively rare and novel tryptamine, the subjective profile is not well documented, with reports varying considerably between individuals."),
                SubjectiveEffect(name: "Moderate Visuals", description: "Visual effects are reported as moderate, with color enhancement and gentle pattern morphing on textured surfaces."),
                SubjectiveEffect(name: "Comfortable Body High", description: "Physical sensations are generally pleasant, with a warm, relaxed feeling that does not dominate the experience."),
                SubjectiveEffect(name: "Gentle Euphoria", description: "A mild but present sense of well-being and contentment that provides a positive emotional backdrop."),
                SubjectiveEffect(name: "Contemplative Thinking", description: "Thoughts become more reflective and philosophical, with a gentle encouragement toward self-examination."),
                SubjectiveEffect(name: "Relaxing Quality", description: "An overall calming effect that promotes ease and comfort without excessive sedation or lethargy."),
                SubjectiveEffect(name: "Color Awareness", description: "Enhanced appreciation of colors in the environment, with subtle increases in vibrancy and saturation."),
                SubjectiveEffect(name: "Mild Gastrointestinal Effects", description: "Some nausea may occur, consistent with the 4-HO tryptamine class, but typically mild and transient."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: - 15. 5-MeO-MiPT (Moxy)
        Substance(
            name: "5-MeO-MiPT",
            aliases: ["Moxy"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...4, common: 4...6, strong: 6...10, heavy: 10
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Tactile enhancement", "Euphoria", "Body high", "Enhanced music appreciation", "Visual hallucinations", "Time distortion", "Nausea", "Empathogenic effects", "Increased heart rate", "Emotional openness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Intense Tactile Enhancement", description: "Physical touch becomes extraordinarily pleasurable and sensitive, making this one of the most tactile psychedelics available."),
                SubjectiveEffect(name: "Empathogenic Warmth", description: "Strong feelings of emotional openness, love, and connection with others that have drawn comparisons to MDMA."),
                SubjectiveEffect(name: "Music Enhancement", description: "Music becomes deeply immersive and emotionally moving, with enhanced spatial perception of individual sounds and instruments."),
                SubjectiveEffect(name: "Stimulating Body High", description: "An energetic, buzzing physical sensation with warmth that encourages movement and physical activity."),
                SubjectiveEffect(name: "Minimal Visuals", description: "Visual effects are relatively subtle compared to other tryptamines, with mild color enhancement and gentle drifting at moderate doses."),
                SubjectiveEffect(name: "Cardiovascular Effects", description: "Noticeably increased heart rate and blood pressure that can cause concern, particularly at higher doses."),
                SubjectiveEffect(name: "Emotional Openness", description: "A profound willingness to express and receive emotions, fostering deep conversations and feelings of interpersonal connection."),
                SubjectiveEffect(name: "Nausea on Come-Up", description: "Stomach discomfort during onset is common and can be pronounced, sometimes accompanied by general body tension."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: - 16. 5-MeO-DiPT (Foxy)
        Substance(
            name: "5-MeO-DiPT",
            aliases: ["Foxy", "Foxy Methoxy"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...8, common: 8...12, strong: 12...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Tactile enhancement", "Auditory distortions", "Euphoria", "Body high", "Enhanced music appreciation", "Nausea", "Time distortion", "Emotional intensification", "Gastrointestinal discomfort", "Visual hallucinations"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Auditory Distortions", description: "Sounds become pitch-shifted and flanged, with music taking on an alien quality as notes bend and stretch unpredictably."),
                SubjectiveEffect(name: "Strong Tactile Enhancement", description: "Physical sensations are dramatically amplified, with touch producing intense waves of pleasure or heightened sensitivity."),
                SubjectiveEffect(name: "Heavy Body Load", description: "A prominent physical component that can include muscle tension, gastrointestinal discomfort, and a weighty feeling in the limbs."),
                SubjectiveEffect(name: "Music Transformation", description: "Music is profoundly altered by pitch and tempo distortions, creating a unique listening experience that can be fascinating or disorienting."),
                SubjectiveEffect(name: "Gastrointestinal Distress", description: "Nausea, cramping, and digestive discomfort are commonly reported and can be more intense than with many other tryptamines."),
                SubjectiveEffect(name: "Moderate Visuals", description: "Visual effects are less prominent than the auditory and tactile components, with gentle morphing and subtle color shifts."),
                SubjectiveEffect(name: "Emotional Waves", description: "Strong emotional fluctuations that can include euphoria, empathy, and moments of emotional vulnerability or intensity."),
                SubjectiveEffect(name: "Time Stretching", description: "Time perception becomes distorted, with the experience feeling significantly longer than its actual clock duration."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: - 17. 5-MeO-DALT
        Substance(
            name: "5-MeO-DALT",
            aliases: ["N,N-Diallyl-5-methoxytryptamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...15, common: 15...25, strong: 25...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 40),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Body high", "Nausea", "Introspection", "Color enhancement", "Mild headspace", "Relaxation", "Emotional warmth"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mild Psychedelic Effects", description: "Overall effects are gentler and less intense than many tryptamines, with a subtle, manageable psychedelic character."),
                SubjectiveEffect(name: "Light Visuals", description: "Visual effects are mild, with gentle color enhancement and soft breathing of surfaces rather than intense hallucinations."),
                SubjectiveEffect(name: "Relaxed Body State", description: "A comfortable, easygoing physical sensation that promotes relaxation without heavy sedation."),
                SubjectiveEffect(name: "Gentle Euphoria", description: "A mild sense of well-being and positivity that provides a pleasant emotional undertone to the experience."),
                SubjectiveEffect(name: "Approachable Headspace", description: "Mental effects are light and clear, allowing for normal functioning while providing subtle perceptual shifts."),
                SubjectiveEffect(name: "Emotional Comfort", description: "A warm, nurturing emotional state that fosters feelings of safety and contentment."),
                SubjectiveEffect(name: "Mild Nausea", description: "Some gastrointestinal discomfort may occur but is typically brief and not severe."),
                SubjectiveEffect(name: "Short to Moderate Duration", description: "The experience tends to be shorter than many oral tryptamines, making it more manageable for those seeking briefer effects."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120
        ),

        // MARK: - 18. 5-MeO-MALT
        Substance(
            name: "5-MeO-MALT",
            aliases: ["5-Methoxy-MALT"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 8...15, common: 15...25, strong: 25...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 40),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Body load", "Nausea", "Introspection", "Emotional intensification", "Color enhancement", "Anxiety", "Relaxation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Understudied Profile", description: "As a relatively obscure 5-MeO tryptamine, the subjective effects are not well documented and reports vary significantly between users."),
                SubjectiveEffect(name: "5-MeO Character", description: "Effects carry the characteristic 5-MeO quality with emphasis on body sensations and consciousness shifts rather than rich visuals."),
                SubjectiveEffect(name: "Body Load", description: "A noticeable physical heaviness and tension that is common among 5-MeO tryptamines and can be uncomfortable at higher doses."),
                SubjectiveEffect(name: "Moderate Visuals", description: "Visual effects are present but secondary to the physical and cognitive components, with some color enhancement and morphing."),
                SubjectiveEffect(name: "Anxious Energy", description: "A restless, anxious quality during the come-up that can persist into the peak, typical of the 5-MeO class."),
                SubjectiveEffect(name: "Introspective Depth", description: "Thoughts may turn inward with a contemplative quality, encouraging reflection on personal matters."),
                SubjectiveEffect(name: "Emotional Amplification", description: "Emotions become intensified and may shift rapidly between positive and challenging states."),
                SubjectiveEffect(name: "Nausea", description: "Gastrointestinal discomfort is commonly reported, consistent with many 5-MeO substituted tryptamines."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120
        ),

        // MARK: - 19. DPT (Dipropyltryptamine)
        Substance(
            name: "DPT",
            aliases: ["Dipropyltryptamine", "The Light"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 75...150, common: 150...250, strong: 250...350, heavy: 350
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 180, max: 300)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 15, light: 25...50, common: 50...100, strong: 100...150, heavy: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 2, max: 10),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 30, max: 120),
                    total: TimeRange(min: 60, max: 180)
                )),
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 15...30, common: 30...60, strong: 60...100, heavy: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.5, max: 2),
                    comeup: TimeRange(min: 2, max: 5),
                    peak: TimeRange(min: 10, max: 30),
                    offset: TimeRange(min: 15, max: 30),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 30, max: 60)
                )),
            ],
            effects: ["Intense visual hallucinations", "Ego dissolution", "Time distortion", "Dark or foreboding headspace", "Auditory hallucinations", "Nausea", "Body load", "Introspection", "Emotional turbulence", "Anxiety"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Dark Headspace", description: "The mental character often has a foreboding, heavy quality that many describe as spiritually intense or confrontational."),
                SubjectiveEffect(name: "Intense Visuals", description: "Powerful visual hallucinations with complex, often dark-themed imagery and rapidly transforming geometric structures."),
                SubjectiveEffect(name: "Ego Dissolution", description: "Complete loss of self-identity is common at moderate to high doses, often accompanied by themes of death and rebirth."),
                SubjectiveEffect(name: "Heavy Body Load", description: "A pronounced physical heaviness with muscle tension, nausea, and a weighted feeling that can be quite uncomfortable."),
                SubjectiveEffect(name: "Auditory Hallucinations", description: "Complex auditory phenomena including voices, alien sounds, and distorted environmental noises that add to the intensity."),
                SubjectiveEffect(name: "Emotional Turbulence", description: "Volatile emotional states that can rapidly shift between terror, ecstasy, grief, and awe with little warning."),
                SubjectiveEffect(name: "Spiritual Intensity", description: "Many users report profoundly spiritual or mystical experiences, with DPT being used sacramentally by the Temple of the True Inner Light."),
                SubjectiveEffect(name: "Challenging Anxiety", description: "Significant anxiety and fear can permeate the experience, particularly during the onset and at higher doses."),
                SubjectiveEffect(name: "Powerful Nausea", description: "Gastrointestinal distress is commonly reported and can be severe, especially when taken orally or insufflated."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120
        ),

        // MARK: - 20. DiPT (Diisopropyltryptamine)
        Substance(
            name: "DiPT",
            aliases: ["Diisopropyltryptamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 15...30, common: 30...50, strong: 50...75, heavy: 75
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 180),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 240, max: 420)
                )),
            ],
            effects: ["Auditory distortions", "Pitch shifting", "Time distortion", "Minimal visual effects", "Introspection", "Nausea", "Body load", "Confusion", "Euphoria", "Tinnitus"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Dramatic Pitch Shifting", description: "The defining effect: all sounds become pitch-shifted downward, making voices sound deep and alien and music unrecognizable."),
                SubjectiveEffect(name: "Auditory-Dominant Experience", description: "Unlike nearly all other psychedelics, the primary effects are auditory rather than visual, making DiPT unique among tryptamines."),
                SubjectiveEffect(name: "Minimal Visuals", description: "Visual effects are remarkably absent or very subtle even at high doses, with the psychedelic action concentrated on hearing."),
                SubjectiveEffect(name: "Persistent Tinnitus", description: "A ringing or buzzing in the ears that can persist for hours or even days after the experience has otherwise resolved."),
                SubjectiveEffect(name: "Cognitive Confusion", description: "Thinking can become muddled and disoriented, with difficulty following trains of thought or communicating clearly."),
                SubjectiveEffect(name: "Disorienting Body Load", description: "Physical discomfort including pressure in the ears, jaw tension, and a general feeling of bodily unease."),
                SubjectiveEffect(name: "Time Distortion", description: "Temporal perception becomes warped, with the experience feeling much longer than its actual duration."),
                SubjectiveEffect(name: "Unsettling Quality", description: "Many users find the auditory distortions disturbing rather than pleasant, giving the experience an eerie, alienating character."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: - 21. MiPT
        Substance(
            name: "MiPT",
            aliases: ["N-Methyl-N-isopropyltryptamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...15, common: 15...25, strong: 25...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 90),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Introspection", "Body high", "Nausea", "Enhanced pattern recognition", "Emotional intensification", "Relaxation", "Color enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Gentle Psychedelic State", description: "A mild, approachable tryptamine experience with a clear-headed quality that allows for functional engagement with the world."),
                SubjectiveEffect(name: "Moderate Visuals", description: "Visual effects are present but not overwhelming, with subtle color enhancement, gentle drifting, and mild pattern recognition."),
                SubjectiveEffect(name: "Comfortable Body High", description: "A warm, pleasant physical sensation without the heaviness or tension that characterizes some other base tryptamines."),
                SubjectiveEffect(name: "Emotional Balance", description: "Feelings become slightly amplified but remain manageable, with a tendency toward warmth and positive emotional states."),
                SubjectiveEffect(name: "Reflective Thinking", description: "Thoughts take on a contemplative quality, with gentle introspection that does not become overwhelming or confrontational."),
                SubjectiveEffect(name: "Relaxing Quality", description: "An overall sense of calm and ease that makes the experience feel comfortable and low-pressure."),
                SubjectiveEffect(name: "Mild Nausea", description: "Some stomach discomfort may occur during onset but is generally mild and passes relatively quickly."),
                SubjectiveEffect(name: "Color Enhancement", description: "Colors appear slightly more vivid and appealing, adding a warm quality to the visual environment."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120
        ),

        // MARK: - 22. MET (Methylethyltryptamine)
        Substance(
            name: "MET",
            aliases: ["Methylethyltryptamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 20, light: 30...50, common: 50...80, strong: 80...120, heavy: 120
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Introspection", "Body high", "Nausea", "Color enhancement", "Enhanced pattern recognition", "Emotional intensification", "Relaxation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "DMT-Like Character", description: "As an asymmetric DMT analogue, MET shares some of DMT's visual and cognitive qualities but with a slower onset and longer duration when taken orally."),
                SubjectiveEffect(name: "Colorful Visuals", description: "Visual effects feature vivid color enhancement and geometric patterning, with a quality reminiscent of DMT but less intense."),
                SubjectiveEffect(name: "Moderate Headspace", description: "Cognitive effects are present but not as overwhelming as DMT, allowing for more coherent thought and self-awareness."),
                SubjectiveEffect(name: "Pleasant Body Sensation", description: "A comfortable, warm physical feeling that complements the visual and mental effects without dominating the experience."),
                SubjectiveEffect(name: "Emotional Depth", description: "Feelings become enriched and more accessible, with an increased capacity for empathy and emotional understanding."),
                SubjectiveEffect(name: "Pattern Recognition", description: "Enhanced ability to see patterns and meaningful structures in visual textures, natural formations, and abstract forms."),
                SubjectiveEffect(name: "Introspective Insights", description: "Thoughtful self-reflection that can yield useful personal insights without the intensity of deeper psychedelics."),
                SubjectiveEffect(name: "Manageable Nausea", description: "Mild gastrointestinal effects may occur, particularly during the come-up phase, but are generally tolerable."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120
        ),

        // MARK: - 23. EPT (N-Ethyl-N-propyltryptamine)
        Substance(
            name: "EPT",
            aliases: ["N-Ethyl-N-propyltryptamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 20, light: 30...50, common: 50...80, strong: 80...120, heavy: 120
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Mild headspace", "Body high", "Nausea", "Color enhancement", "Relaxation", "Introspection", "Emotional warmth"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mild Psychedelic Character", description: "A gentle, understated tryptamine experience with a light cognitive footprint and manageable intensity."),
                SubjectiveEffect(name: "Subtle Visuals", description: "Visual effects are mild, with gentle color shifts and soft surface breathing rather than pronounced geometric patterns."),
                SubjectiveEffect(name: "Relaxed Body State", description: "A comfortable, easygoing physical sensation that promotes relaxation and physical comfort."),
                SubjectiveEffect(name: "Light Euphoria", description: "A mild but pleasant mood elevation that colors the experience with a gentle sense of well-being."),
                SubjectiveEffect(name: "Gentle Introspection", description: "Casual reflective thinking that touches on personal themes without becoming heavy or confrontational."),
                SubjectiveEffect(name: "Emotional Warmth", description: "A nurturing, affectionate emotional quality that fosters feelings of connection and contentment."),
                SubjectiveEffect(name: "Low Nausea", description: "Gastrointestinal effects are typically mild, making EPT relatively comfortable physically."),
                SubjectiveEffect(name: "Understudied Profile", description: "As a rare base tryptamine, the subjective experience is not well documented and individual responses may vary significantly."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120
        ),

        // MARK: - 24. MPT (N-Methyl-N-propyltryptamine)
        Substance(
            name: "MPT",
            aliases: ["N-Methyl-N-propyltryptamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 15, light: 20...40, common: 40...70, strong: 70...100, heavy: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 90),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 180, max: 270)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Introspection", "Body high", "Nausea", "Color enhancement", "Emotional intensification", "Enhanced pattern recognition", "Relaxation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "DMT-Adjacent Character", description: "As an asymmetric DMT analogue with a methyl and propyl group, MPT sits between DMT and DPT in character with moderate intensity."),
                SubjectiveEffect(name: "Moderate Visual Effects", description: "Visuals include color enhancement, geometric patterning, and surface morphing with a quality that blends DMT and DPT characteristics."),
                SubjectiveEffect(name: "Balanced Headspace", description: "The cognitive effects are moderate, providing meaningful perceptual shifts without the overwhelming intensity of DMT or darkness of DPT."),
                SubjectiveEffect(name: "Warm Body High", description: "A comfortable, pleasant physical sensation with warmth that supports the overall psychedelic experience."),
                SubjectiveEffect(name: "Emotional Richness", description: "Feelings become deeper and more textured, with an enhanced capacity for emotional resonance and empathy."),
                SubjectiveEffect(name: "Contemplative Thinking", description: "Thoughts naturally incline toward reflection and self-examination with moderate depth and personal relevance."),
                SubjectiveEffect(name: "Pattern Perception", description: "Enhanced awareness of visual patterns and structures in the environment, with mild geometric overlays on surfaces."),
                SubjectiveEffect(name: "Moderate Nausea", description: "Some gastrointestinal discomfort may occur, particularly during onset, but typically resolves as the experience develops."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120
        ),

        // MARK: - 25. DALT (N,N-Diallyltryptamine)
        Substance(
            name: "DALT",
            aliases: ["N,N-Diallyltryptamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 80...120, common: 120...200, strong: 200...300, heavy: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Mild visual hallucinations", "Euphoria", "Time distortion", "Body high", "Nausea", "Introspection", "Relaxation", "Color enhancement", "Emotional warmth", "Sedation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Subtle Effects", description: "DALT is known for being one of the weakest base tryptamines, requiring high doses to produce noticeable psychedelic effects."),
                SubjectiveEffect(name: "Mild Visuals", description: "Visual effects are minimal even at higher doses, with only gentle color enhancement and very subtle surface distortions."),
                SubjectiveEffect(name: "Sedating Quality", description: "A pronounced drowsy, relaxing physical state that can make the experience feel more like a dreamy sedation than an active trip."),
                SubjectiveEffect(name: "Light Euphoria", description: "A gentle sense of well-being and contentment that provides a mildly pleasant emotional backdrop."),
                SubjectiveEffect(name: "Physical Relaxation", description: "A heavy, comfortable body sensation that encourages stillness and may lead to a sleep-like state."),
                SubjectiveEffect(name: "Mild Introspection", description: "Gentle reflective thoughts that do not carry the intensity or depth of more potent tryptamines."),
                SubjectiveEffect(name: "Emotional Comfort", description: "A warm, nurturing emotional quality that fosters feelings of safety and ease without dramatic emotional shifts."),
                SubjectiveEffect(name: "Nausea at High Doses", description: "Due to the high doses required, gastrointestinal discomfort from the volume of material consumed is a common complaint."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120
        ),

        // MARK: - 26. AMT (Alpha-methyltryptamine)
        Substance(
            name: "AMT",
            aliases: ["Alpha-methyltryptamine", "\u{03B1}MT", "Indopan", "aMT"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...30, strong: 30...50, heavy: 50, fatal: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 90),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 180, max: 300),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 240, max: 720),
                    total: TimeRange(min: 720, max: 960)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Stimulation", "Empathogenic effects", "Nausea", "Time distortion", "Introspection", "Long duration", "Insomnia", "Increased heart rate"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Stimulating Energy", description: "A pronounced stimulant quality that provides physical energy, wakefulness, and motivation, reflecting AMT's MAOI activity."),
                SubjectiveEffect(name: "Empathogenic Warmth", description: "Strong feelings of emotional openness, love, and social connection that have drawn comparisons to MDMA."),
                SubjectiveEffect(name: "Extended Duration", description: "The experience lasts exceptionally long, often 12-16 hours or more, requiring significant time commitment and planning."),
                SubjectiveEffect(name: "Progressive Visuals", description: "Visual effects build slowly over hours, eventually producing vivid color enhancement, morphing, and geometric patterns at higher doses."),
                SubjectiveEffect(name: "Severe Come-Up Nausea", description: "Intense nausea and sometimes vomiting during the first 1-3 hours is very common and considered one of AMT's most challenging aspects."),
                SubjectiveEffect(name: "Euphoric Peak", description: "Once past the nausea, a strong, rolling euphoria develops that combines psychedelic wonder with empathogenic bliss."),
                SubjectiveEffect(name: "Cardiovascular Stimulation", description: "Noticeably increased heart rate and blood pressure, reflecting the substance's monoamine releasing properties."),
                SubjectiveEffect(name: "Post-Experience Insomnia", description: "The stimulating effects make sleep impossible for many hours after the psychedelic effects have faded."),
                SubjectiveEffect(name: "Deep Introspection", description: "Extended periods of deep self-reflection are facilitated by the long duration, often yielding significant personal insights."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 540
        ),

        // MARK: - 27. AET (Alpha-ethyltryptamine)
        Substance(
            name: "AET",
            aliases: ["Alpha-ethyltryptamine", "\u{03B1}ET", "aET"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...75, common: 75...125, strong: 125...175, heavy: 175
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 360, max: 600)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Stimulation", "Empathogenic effects", "Nausea", "Time distortion", "Introspection", "Emotional openness", "Insomnia", "Increased heart rate"],
            subjectiveEffects: [
                SubjectiveEffect(name: "MDMA-Like Empathy", description: "Strong empathogenic effects with emotional openness and feelings of connection that closely resemble MDMA's emotional character."),
                SubjectiveEffect(name: "Stimulating Quality", description: "A noticeable stimulant component providing energy and wakefulness, similar to AMT but with a distinct ethyl-substituted character."),
                SubjectiveEffect(name: "Moderate Visuals", description: "Visual effects develop gradually with color enhancement and gentle morphing, less visually intense than many tryptamines."),
                SubjectiveEffect(name: "Emotional Openness", description: "A profound willingness to engage with emotions and connect with others on a deep, authentic level."),
                SubjectiveEffect(name: "Come-Up Nausea", description: "Significant nausea during the onset phase is common and can be intense, though it typically subsides as the experience develops."),
                SubjectiveEffect(name: "Extended Duration", description: "Effects last considerably longer than many tryptamines, typically 6-10 hours, requiring planning and time commitment."),
                SubjectiveEffect(name: "Cardiovascular Effects", description: "Increased heart rate and blood pressure from the stimulant and monoamine releasing properties of the substance."),
                SubjectiveEffect(name: "Residual Stimulation", description: "Lingering wakefulness and energy that can persist well after the primary psychedelic effects have faded."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 360
        ),

        // MARK: - 28. Bufotenin (5-HO-DMT)
        Substance(
            name: "Bufotenin",
            aliases: ["5-HO-DMT", "5-Hydroxy-DMT", "Bufotenine"],
            category: .psychedelic,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 2, max: 5),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 60, max: 120)
                )),
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 5...10, common: 10...25, strong: 25...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.5, max: 2),
                    comeup: TimeRange(min: 2, max: 5),
                    peak: TimeRange(min: 10, max: 30),
                    offset: TimeRange(min: 15, max: 30),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 30, max: 60)
                )),
            ],
            effects: ["Visual hallucinations", "Facial flushing", "Nausea", "Body load", "Euphoria", "Time distortion", "Chest tightness", "Color enhancement", "Anxiety", "Short duration"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Facial Flushing", description: "Intense reddening and warmth of the face is one of the most distinctive and immediate effects, caused by peripheral vasodilation."),
                SubjectiveEffect(name: "Chest Tightness", description: "A sensation of pressure or constriction in the chest that can be alarming and is related to cardiovascular effects."),
                SubjectiveEffect(name: "DMT-Like Visuals", description: "When active, visual effects can resemble DMT with vivid colors and geometric patterns, though onset is less reliable than other tryptamines."),
                SubjectiveEffect(name: "Short Duration", description: "When smoked or insufflated, effects are relatively brief, typically lasting 30-60 minutes for the main experience."),
                SubjectiveEffect(name: "Heavy Body Load", description: "Significant physical discomfort including nausea, facial pressure, and a weighted feeling that many find quite unpleasant."),
                SubjectiveEffect(name: "Severe Nausea", description: "Gastrointestinal distress is very common and can be one of the most prominent aspects of the experience."),
                SubjectiveEffect(name: "Variable Potency", description: "Effects are notably inconsistent between administrations, with some attempts producing little effect and others being quite intense."),
                SubjectiveEffect(name: "Anxiety and Discomfort", description: "The combination of chest tightness, facial flushing, and nausea often creates significant anxiety about physical safety."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 30
        ),

        // MARK: - 30. 5-MeO-TMT
        Substance(
            name: "5-MeO-TMT",
            aliases: ["5-Methoxy-TMT", "5-Methoxy-2,N,N-trimethyltryptamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 75...125, common: 125...200, strong: 200...300, heavy: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Mild visual hallucinations", "Euphoria", "Time distortion", "Body high", "Relaxation", "Nausea", "Color enhancement", "Introspection", "Emotional warmth", "Sedation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Very Mild Effects", description: "5-MeO-TMT is reported to be one of the least potent 5-MeO tryptamines, producing only subtle psychedelic shifts at typical doses."),
                SubjectiveEffect(name: "Subtle Visuals", description: "Visual effects are minimal even at higher doses, with only gentle color warming and very mild perceptual changes."),
                SubjectiveEffect(name: "Sedating Relaxation", description: "A drowsy, calming quality that promotes physical relaxation and may lead to a dreamy, half-sleep state."),
                SubjectiveEffect(name: "Gentle Mood Lift", description: "A mild sense of well-being and contentment that provides a pleasant but understated emotional coloring."),
                SubjectiveEffect(name: "Physical Comfort", description: "A warm, comfortable body sensation that encourages rest and stillness without significant body load."),
                SubjectiveEffect(name: "Light Introspection", description: "Casual, gentle self-reflection without the depth or intensity characteristic of more potent tryptamines."),
                SubjectiveEffect(name: "Mild Nausea", description: "Some stomach discomfort may occur at higher doses but is generally not prominent."),
                SubjectiveEffect(name: "Emotional Warmth", description: "A gentle emotional softening that fosters feelings of comfort and appreciation without dramatic shifts."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120
        ),

        // MARK: - 31. 4-HO-MPT
        Substance(
            name: "4-HO-MPT",
            aliases: ["4-Hydroxy-MPT"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...15, common: 15...25, strong: 25...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Introspection", "Body high", "Nausea", "Color enhancement", "Emotional intensification", "Enhanced pattern recognition", "Relaxation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Moderate Visuals", description: "Visual effects are present with color enhancement, surface morphing, and pattern recognition at a moderate intensity level."),
                SubjectiveEffect(name: "Balanced Experience", description: "A well-rounded tryptamine experience that sits between recreational lightness and deep introspective potential."),
                SubjectiveEffect(name: "Warm Body High", description: "A comfortable physical warmth that supports the experience without becoming a heavy body load."),
                SubjectiveEffect(name: "Emotional Depth", description: "Feelings become more accessible and intense, allowing for meaningful emotional exploration and processing."),
                SubjectiveEffect(name: "Contemplative Headspace", description: "Thoughts incline naturally toward self-reflection and philosophical wondering with moderate depth."),
                SubjectiveEffect(name: "Color Vibrancy", description: "Colors appear more saturated and vivid, with the environment taking on a warmer, more visually appealing quality."),
                SubjectiveEffect(name: "Pattern Enhancement", description: "Textures and natural patterns become more noticeable and interesting, with subtle geometric overlays."),
                SubjectiveEffect(name: "Mild Gastrointestinal Effects", description: "Some nausea may occur during the come-up but is typically manageable and short-lived."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: - 32. 4-AcO-MiPT
        Substance(
            name: "4-AcO-MiPT",
            aliases: ["4-Acetoxy-MiPT"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 8...14, common: 14...22, strong: 22...35, heavy: 35
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Visual hallucinations", "Tactile enhancement", "Euphoria", "Time distortion", "Body high", "Introspection", "Nausea", "Enhanced music appreciation", "Emotional intensification", "Synesthesia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Tactile Richness", description: "As a prodrug of 4-HO-MiPT, it shares the pronounced tactile enhancement with textures feeling extraordinarily detailed and pleasurable."),
                SubjectiveEffect(name: "Music Immersion", description: "Music takes on profound emotional depth and spatial quality, with layers becoming individually perceptible and deeply moving."),
                SubjectiveEffect(name: "Warm Body High", description: "A deeply comfortable physical sensation with warmth and sensitivity that makes the body feel alive and connected."),
                SubjectiveEffect(name: "Gradual Onset", description: "The acetoxy group provides a smoother, more gradual come-up compared to the direct 4-HO analogue."),
                SubjectiveEffect(name: "Synesthetic Experiences", description: "Sensory crossover where music produces visual impressions and physical sensations blend with emotional states."),
                SubjectiveEffect(name: "Emotional Intimacy", description: "A deep capacity for emotional connection and vulnerability that fosters meaningful interpersonal experiences."),
                SubjectiveEffect(name: "Flowing Visuals", description: "Organic, fluid visual effects with warm color enhancement and gentle morphing of surfaces and patterns."),
                SubjectiveEffect(name: "Moderate Nausea", description: "Some gastrointestinal discomfort during the onset phase, though it tends to resolve as the experience progresses."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: - 33. 4-AcO-DiPT
        Substance(
            name: "4-AcO-DiPT",
            aliases: ["4-Acetoxy-DiPT", "Ipracetin"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...18, common: 18...30, strong: 30...45, heavy: 45
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Auditory distortions", "Visual hallucinations", "Euphoria", "Time distortion", "Body high", "Introspection", "Nausea", "Enhanced music appreciation", "Emotional intensification", "Tactile enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Auditory Focus", description: "As a prodrug of 4-HO-DiPT, it shares the pronounced auditory effects with pitch shifting and sound distortions."),
                SubjectiveEffect(name: "Music Transformation", description: "Music becomes radically altered with pitch and tempo changes, creating an alien but often fascinating listening experience."),
                SubjectiveEffect(name: "Tactile Sensitivity", description: "Physical touch is heightened and amplified, with textures and physical contact producing intensified sensations."),
                SubjectiveEffect(name: "Smooth Come-Up", description: "The acetoxy prodrug mechanism provides a gentler, more gradual onset compared to the direct 4-HO analogue."),
                SubjectiveEffect(name: "Moderate Visuals", description: "Visual effects are secondary to auditory effects but present, with gentle morphing and color enhancement."),
                SubjectiveEffect(name: "Deep Body Sensations", description: "A heavy, immersive body high that grounds the experience in physical awareness and sensory perception."),
                SubjectiveEffect(name: "Emotional Intensity", description: "Emotions become amplified with a capacity for both euphoric highs and challenging introspective depths."),
                SubjectiveEffect(name: "Gastrointestinal Effects", description: "Nausea and stomach discomfort are common during the come-up, consistent with acetoxy tryptamine prodrugs."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 240
        ),

        // MARK: - 34. 4-AcO-EPT
        Substance(
            name: "4-AcO-EPT",
            aliases: ["4-Acetoxy-EPT"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 15...25, common: 25...40, strong: 40...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Mild headspace", "Body high", "Nausea", "Introspection", "Color enhancement", "Relaxation", "Emotional warmth"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mild Character", description: "As a prodrug of 4-HO-EPT, it shares the gentle, understated psychedelic profile with a light cognitive footprint."),
                SubjectiveEffect(name: "Gentle Visuals", description: "Visual effects are subtle and pleasant, with soft color enhancement and mild surface distortions."),
                SubjectiveEffect(name: "Relaxed Body State", description: "A comfortable, easygoing physical sensation that promotes ease without heavy sedation."),
                SubjectiveEffect(name: "Light Euphoria", description: "A mild but consistent sense of well-being that colors the experience with gentle positivity."),
                SubjectiveEffect(name: "Smooth Onset", description: "The acetoxy group provides a gradual, comfortable transition into the psychedelic state."),
                SubjectiveEffect(name: "Emotional Comfort", description: "A warm, nurturing emotional quality that fosters contentment and gentle appreciation."),
                SubjectiveEffect(name: "Casual Introspection", description: "Light self-reflection that feels productive and pleasant without becoming heavy or confrontational."),
                SubjectiveEffect(name: "Mild Nausea", description: "Some gastrointestinal discomfort may occur but is generally brief and manageable."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: - 35. 5-MeO-DET
        Substance(
            name: "5-MeO-DET",
            aliases: ["5-Methoxy-DET", "5-Methoxy-N,N-diethyltryptamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...10, strong: 10...15, heavy: 15
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Body high", "Nausea", "Introspection", "Enhanced color perception", "Emotional intensification", "Anxiety", "Relaxation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "5-MeO Character", description: "Effects carry the typical 5-MeO quality with emphasis on consciousness shifts and body sensations rather than purely visual effects."),
                SubjectiveEffect(name: "Moderate Visuals", description: "Visual effects are present but secondary, with some color enhancement and perceptual shifts typical of the 5-MeO class."),
                SubjectiveEffect(name: "Body-Centric Experience", description: "Physical sensations are prominent, with a warm, buzzing body high that can range from pleasant to overwhelming at higher doses."),
                SubjectiveEffect(name: "Emotional Amplification", description: "Feelings become intensified and may shift between states of euphoria and challenging emotional confrontation."),
                SubjectiveEffect(name: "Anxious Energy", description: "A restless, anxious undercurrent is common, particularly during the come-up, consistent with many 5-MeO tryptamines."),
                SubjectiveEffect(name: "Contemplative Depth", description: "Thoughts become deeply introspective with a philosophical quality that encourages examination of fundamental questions."),
                SubjectiveEffect(name: "Nausea on Onset", description: "Gastrointestinal discomfort is frequently reported during the come-up and may be more intense than with 4-substituted analogues."),
                SubjectiveEffect(name: "Potent at Low Doses", description: "Like other 5-MeO tryptamines, effects can be strong at relatively low milligram doses, requiring careful measurement."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120
        ),

        // MARK: - 36. 5-MeO-EPT
        Substance(
            name: "5-MeO-EPT",
            aliases: ["5-Methoxy-EPT"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 8...15, common: 15...25, strong: 25...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 40),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Body high", "Nausea", "Introspection", "Color enhancement", "Emotional warmth", "Relaxation", "Mild headspace"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Understudied Compound", description: "As a rare 5-MeO tryptamine, the subjective profile is poorly documented with limited user reports available."),
                SubjectiveEffect(name: "5-MeO Qualities", description: "Expected to share general 5-MeO characteristics including body-centric effects and consciousness shifts over visual spectacle."),
                SubjectiveEffect(name: "Moderate Body Effects", description: "Physical sensations are likely prominent, with warmth and body awareness typical of the 5-MeO tryptamine class."),
                SubjectiveEffect(name: "Gentle Euphoria", description: "A mild to moderate sense of well-being and emotional comfort based on available reports."),
                SubjectiveEffect(name: "Mild Visuals", description: "Visual effects are expected to be secondary, with gentle color enhancement and subtle perceptual changes."),
                SubjectiveEffect(name: "Emotional Warmth", description: "A nurturing, comfortable emotional quality that fosters feelings of ease and appreciation."),
                SubjectiveEffect(name: "Relaxing Quality", description: "An overall calming effect that promotes physical and mental relaxation."),
                SubjectiveEffect(name: "Potential Nausea", description: "Gastrointestinal discomfort is likely given the 5-MeO substitution pattern."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120
        ),

        // MARK: - 36.5. Ayahuasca

        Substance(
            name: "Ayahuasca",
            aliases: ["Yagé", "La Purga", "Hoasca", "Caapi Brew"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mL", doses: DoseRange(
                    threshold: 25, light: 50...75, common: 75...125, strong: 125...200, heavy: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Intense visuals", "Purging", "Emotional release", "Ego dissolution", "Spiritual visions", "Entity contact", "Time distortion"],
            subjectiveEffects: [
                SubjectiveEffect(name: "La Purga", description: "Intense nausea and vomiting that is considered a central and essential part of the experience in traditional contexts, viewed as a physical, emotional, and spiritual purification rather than a side effect."),
                SubjectiveEffect(name: "Visionary States", description: "Extraordinarily vivid, narrative visual experiences featuring complex scenes, archetypal imagery, and visions of personal or spiritual significance, driven by orally activated DMT."),
                SubjectiveEffect(name: "Entity Contact", description: "Encounters with seemingly autonomous spiritual beings, plant spirits, or cosmic intelligences that communicate through imagery, emotion, or direct knowing."),
                SubjectiveEffect(name: "Emotional Catharsis", description: "Profound emotional release involving intense crying, laughter, or screaming as deeply buried traumas, grief, and emotional patterns surface and resolve."),
                SubjectiveEffect(name: "Ego Dissolution", description: "A progressive dissolution of personal identity and self-boundaries, leading to experiences of cosmic unity, death-rebirth, or merging with the fabric of existence."),
                SubjectiveEffect(name: "Extended Duration", description: "A 4-8 hour experience with multiple waves of intensity, as the MAOI from the Banisteriopsis caapi vine allows DMT to remain orally active for extended periods."),
                SubjectiveEffect(name: "Physical Purging", description: "Diarrhea may accompany or follow the vomiting, with the entire gastrointestinal tract participating in the purification process that gives ayahuasca its name La Purga."),
                SubjectiveEffect(name: "Time Distortion", description: "Severe warping of temporal perception where minutes feel like hours and the experience can feel like it contains an entire lifetime of insight and emotion."),
                SubjectiveEffect(name: "Afterglow and Integration", description: "A lasting period of emotional clarity, gratitude, and psychological openness that can persist for days or weeks, during which insights from the experience continue to unfold."),
                SubjectiveEffect(name: "MAOI Interaction Sensitivity", description: "The harmine and harmaline MAOIs in the brew create dangerous interactions with tyramine-rich foods, serotonergic drugs, and many medications, requiring strict dietary and pharmacological preparation."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: - 37. 5-MeO-MET
        Substance(
            name: "5-MeO-MET",
            aliases: ["5-Methoxy-MET", "5-Methoxy-N-methyl-N-ethyltryptamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 5...10, common: 10...20, strong: 20...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Body high", "Nausea", "Introspection", "Color enhancement", "Emotional intensification", "Enhanced pattern recognition", "Anxiety"],
            subjectiveEffects: [
                SubjectiveEffect(name: "5-MeO Character", description: "Effects carry the typical 5-MeO signature with emphasis on body sensations and consciousness shifts over visual complexity."),
                SubjectiveEffect(name: "Moderate Visuals", description: "Visual effects are present but not dominant, with color enhancement and gentle perceptual shifts characteristic of 5-MeO compounds."),
                SubjectiveEffect(name: "Body Awareness", description: "A prominent physical component with warmth, buzzing, and heightened bodily awareness throughout the experience."),
                SubjectiveEffect(name: "Emotional Intensity", description: "Feelings become amplified and may include both euphoric states and moments of anxiety or emotional confrontation."),
                SubjectiveEffect(name: "Introspective Quality", description: "Thoughts take on a reflective, philosophical quality with potential for meaningful self-examination."),
                SubjectiveEffect(name: "Anxious Undertone", description: "A restless, anxious energy that is common with 5-MeO tryptamines, particularly during the onset phase."),
                SubjectiveEffect(name: "Pattern Enhancement", description: "Increased awareness of patterns and structures in the visual environment with mild geometric overlays."),
                SubjectiveEffect(name: "Nausea", description: "Gastrointestinal discomfort is commonly reported, consistent with the 5-MeO tryptamine class."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120
        ),

        // MARK: - 38. MALT (N-Methyl-N-allyltryptamine)
        Substance(
            name: "MALT",
            aliases: ["N-Methyl-N-allyltryptamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 20, light: 40...60, common: 60...100, strong: 100...150, heavy: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Body high", "Nausea", "Introspection", "Color enhancement", "Emotional warmth", "Relaxation", "Enhanced pattern recognition"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mild Psychedelic Effects", description: "MALT produces a gentle, understated tryptamine experience with manageable intensity at typical doses."),
                SubjectiveEffect(name: "Subtle Visuals", description: "Visual effects are mild, with gentle color enhancement and soft perceptual shifts rather than pronounced hallucinations."),
                SubjectiveEffect(name: "Comfortable Body State", description: "A warm, relaxed physical sensation that supports the experience without prominent body load or stimulation."),
                SubjectiveEffect(name: "Gentle Euphoria", description: "A mild but pleasant mood elevation that provides a positive emotional backdrop without overwhelming intensity."),
                SubjectiveEffect(name: "Emotional Warmth", description: "A nurturing, affectionate emotional quality that fosters feelings of comfort and interpersonal connection."),
                SubjectiveEffect(name: "Light Introspection", description: "Casual, gentle self-reflection that feels accessible and productive without heavy psychological confrontation."),
                SubjectiveEffect(name: "Pattern Awareness", description: "Mildly enhanced perception of patterns and visual structures in the environment."),
                SubjectiveEffect(name: "Mild Nausea", description: "Some gastrointestinal discomfort may occur but is generally brief and not prominent at moderate doses."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120
        ),

    ]
    // swiftlint:enable function_body_length
}
