import Foundation

extension SubstanceLibrary {
    static let researchChemicalsPsychedelics: [Substance] = [

        // MARK: - Tryptamines

        // MARK: 4-AcO-MALT

        Substance(
            name: "4-AcO-MALT",
            aliases: ["4-Acetoxy-N-methyl-N-allyltryptamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...35, strong: 35...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 360),
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Introspection", "Color enhancement", "Geometric visual patterns", "Nausea", "Body load", "Thought connectivity", "Emotional enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Geometric Visual Patterns", description: "Intricate, symmetrical geometric patterns that overlay surfaces and closed-eye visuals, often with a crystalline or organic quality unique to tryptamines."),
                SubjectiveEffect(name: "Euphoria", description: "A warm, enveloping sense of joy and well-being that permeates the experience, often feeling deeply meaningful and connected."),
                SubjectiveEffect(name: "Thought Connectivity", description: "A tendency for thoughts to link together in novel and unexpected ways, creating chains of insight and association not normally accessible."),
                SubjectiveEffect(name: "Emotional Enhancement", description: "An amplification of emotional responses where feelings become more vivid, layered, and deeply felt than in ordinary consciousness."),
                SubjectiveEffect(name: "Color Enhancement", description: "A dramatic intensification of colors where the visual world appears more saturated, luminous, and aesthetically striking."),
                SubjectiveEffect(name: "Time Distortion", description: "A warping of time perception where the normal flow of seconds and minutes becomes unreliable and subjective experience stretches or compresses."),
                SubjectiveEffect(name: "Nausea", description: "An onset-phase stomach discomfort typical of 4-acetoxy tryptamines that usually passes within the first hour as effects develop."),
                SubjectiveEffect(name: "Introspection", description: "A natural pull toward examining one's inner world, memories, and emotional patterns with an unusual sense of honesty and perspective."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120
        ),

        // MARK: 4-AcO-DALT

        Substance(
            name: "4-AcO-DALT",
            aliases: ["4-Acetoxy-N,N-diallyltryptamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 15...25, common: 25...40, strong: 40...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 50),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 300),
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Mild visual hallucinations", "Euphoria", "Time distortion", "Sedation", "Body high", "Dream potentiation", "Nausea", "Introspection", "Thought deceleration"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Sedation", description: "A pronounced calming and drowsy quality unusual for psychedelics, creating a dreamy, relaxed headspace rather than stimulating alertness."),
                SubjectiveEffect(name: "Body High", description: "A pleasant, warm physical sensation spreading through the body that feels deeply relaxing and comfortable, with a gentle tingling quality."),
                SubjectiveEffect(name: "Dream Potentiation", description: "A notable enhancement of dream vividness, recall, and lucidity that can persist for days after the experience, making sleep feel immersive."),
                SubjectiveEffect(name: "Thought Deceleration", description: "A slowing of mental processes that creates a spacious, unhurried quality to thinking, opposite to the thought acceleration of most psychedelics."),
                SubjectiveEffect(name: "Mild Visual Enhancements", description: "Subtle visual effects including gentle color enhancement and mild pattern recognition, less pronounced than typical tryptamine visuals."),
                SubjectiveEffect(name: "Euphoria", description: "A gentle, dreamy sense of pleasure and contentment that complements the sedating character rather than creating energetic excitement."),
                SubjectiveEffect(name: "Introspection", description: "A reflective, meditative mental state that encourages contemplation without the intense emotional confrontation of stronger psychedelics."),
                SubjectiveEffect(name: "Nausea", description: "A moderate stomach discomfort during the onset that is common with diallyltryptamines and may persist longer than with other analogs."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120
        ),

        // MARK: 5-Cl-AMT

        Substance(
            name: "5-Cl-AMT",
            aliases: ["5-Chloro-alpha-methyltryptamine", "5-Chloro-AMT"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 5...10, common: 10...20, strong: 20...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 240, max: 720),
                    total: TimeRange(min: 480, max: 840)
                )),
            ],
            effects: ["Visual hallucinations", "Stimulation", "Euphoria", "Time distortion", "Nausea", "Insomnia", "Body load", "Introspection", "Empathogenic effects", "Mood elevation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Stimulation", description: "A notable physical and mental energy that sets this apart from most tryptamines, creating an active, engaged headspace more reminiscent of an amphetamine-psychedelic hybrid."),
                SubjectiveEffect(name: "Empathogenic Effects", description: "A warm, MDMA-like emotional openness and desire for human connection, reflecting this compound's serotonin-releasing properties in addition to psychedelic action."),
                SubjectiveEffect(name: "Mood Elevation", description: "A significant and sustained uplift in mood that feels profoundly positive and life-affirming, often persisting well after the peak."),
                SubjectiveEffect(name: "Visual Hallucinations", description: "Colorful, flowing visual distortions with geometric patterning, enhanced by the compound's dual psychedelic and stimulant character."),
                SubjectiveEffect(name: "Insomnia", description: "A stimulant-driven inability to sleep that can persist for many hours after the psychedelic effects resolve, due to the compound's monoamine releasing properties."),
                SubjectiveEffect(name: "Body Load", description: "A physical tension and heaviness that can be more pronounced than other tryptamines, sometimes accompanied by cardiovascular awareness."),
                SubjectiveEffect(name: "Time Distortion", description: "A warping of temporal perception that makes the experience feel much longer than clock time would suggest."),
                SubjectiveEffect(name: "Introspection", description: "A natural tendency toward self-examination combined with the stimulant energy, creating a unique mix of active reflection and emotional clarity."),
                SubjectiveEffect(name: "Nausea", description: "A stomach discomfort during the onset that can be more pronounced than with simpler tryptamines, potentially requiring anti-nausea preparation."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 480
        ),

        // MARK: O-Acetylbufotenin

        Substance(
            name: "O-Acetylbufotenin",
            aliases: ["5-AcO-DMT-analog", "Acetylbufotenine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...35, strong: 35...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 360),
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Introspection", "Color enhancement", "Nausea", "Body load", "Emotional enhancement", "Thought connectivity"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Visual Hallucinations", description: "Psilocin-like visual distortions including flowing surfaces, enhanced textures, and colorful geometric patterns typical of 4-hydroxy tryptamines."),
                SubjectiveEffect(name: "Euphoria", description: "A gentle, warm sense of well-being and contentment characteristic of bufotenin analogs, with a distinctly organic and earthy quality."),
                SubjectiveEffect(name: "Emotional Enhancement", description: "An amplification of emotional depth where feelings become more vivid and textured, allowing for deeper emotional processing."),
                SubjectiveEffect(name: "Thought Connectivity", description: "An increase in associative thinking where ideas link together in unexpected but often insightful chains of meaning and connection."),
                SubjectiveEffect(name: "Color Enhancement", description: "A vivid intensification of colors that makes the visual world appear extraordinarily beautiful and luminous."),
                SubjectiveEffect(name: "Time Distortion", description: "An altered sense of time passage where the experience can feel much longer or shorter than actual elapsed time."),
                SubjectiveEffect(name: "Introspection", description: "A natural inward focus that encourages examination of personal patterns, memories, and emotional states with gentle clarity."),
                SubjectiveEffect(name: "Nausea", description: "A common onset-phase stomach discomfort that tends to resolve as the psychedelic effects fully develop."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 1, fullResetDays: 7, buildRate: "rapid"),
            halfLifeMinutes: 30
        ),

        // MARK: 4-HO-DSBT

        Substance(
            name: "4-HO-DSBT",
            aliases: ["4-Hydroxy-N,N-di-sec-butyltryptamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...35, strong: 35...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 50),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 360),
                    total: TimeRange(min: 210, max: 420)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Introspection", "Geometric visual patterns", "Nausea", "Body load", "Sedation", "Color enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Sedation", description: "A notable calming and relaxing quality that distinguishes this tryptamine from more stimulating analogs, creating a dreamy, laid-back headspace."),
                SubjectiveEffect(name: "Geometric Visual Patterns", description: "Complex, interlocking geometric shapes visible with eyes open and closed, often with an organic, flowing quality typical of 4-hydroxy tryptamines."),
                SubjectiveEffect(name: "Euphoria", description: "A mellow, warm sense of pleasure and contentment that feels deeply peaceful rather than energetically exciting."),
                SubjectiveEffect(name: "Introspection", description: "A contemplative mental state that encourages gentle self-reflection without the forceful emotional confrontation of stronger psychedelics."),
                SubjectiveEffect(name: "Color Enhancement", description: "An enrichment of visual color where hues become deeper, more vibrant, and emotionally resonant."),
                SubjectiveEffect(name: "Time Distortion", description: "A slowing and stretching of perceived time that makes the experience feel spacious and unhurried."),
                SubjectiveEffect(name: "Body Load", description: "A physical heaviness and potential stomach discomfort that can ground the experience in bodily awareness."),
                SubjectiveEffect(name: "Nausea", description: "A stomach queasiness common during the onset phase of 4-hydroxy tryptamines, typically fading as effects plateau."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120
        ),

        // MARK: 5-MeO-EIPT

        Substance(
            name: "5-MeO-EIPT",
            aliases: ["5-Methoxy-N-ethyl-N-isopropyltryptamine"],
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
                    afterglow: TimeRange(min: 60, max: 300),
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Ego dissolution", "Visual hallucinations", "Euphoria", "Time distortion", "Nausea", "Body load", "Anxiety", "Physical euphoria", "Perspective shifts", "Unity and interconnectedness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Ego Dissolution", description: "A loosening and potential complete dissolution of the sense of self, characteristic of 5-MeO tryptamines, that can feel both liberating and terrifying."),
                SubjectiveEffect(name: "Physical Euphoria", description: "A powerful, wave-like bodily pleasure that can feel like electricity or warmth spreading through every cell, typical of 5-MeO compounds."),
                SubjectiveEffect(name: "Perspective Shifts", description: "Radical changes in how one perceives reality, identity, and meaning that can feel like fundamental truths being revealed."),
                SubjectiveEffect(name: "Unity and Interconnectedness", description: "A dissolving of perceived boundaries between self and environment, creating a profound sense that everything is one unified consciousness."),
                SubjectiveEffect(name: "Visual Hallucinations", description: "Vivid visual effects that can range from enhanced colors and patterns to complete visual transformation at higher doses."),
                SubjectiveEffect(name: "Anxiety", description: "An intense apprehension that frequently accompanies the powerful ego-dissolving effects, especially during rapid onset periods."),
                SubjectiveEffect(name: "Body Load", description: "A significant physical pressure and tension in the body that can feel overwhelming, sometimes accompanied by cardiovascular awareness."),
                SubjectiveEffect(name: "Nausea", description: "A notable stomach discomfort during onset that can be more pronounced with 5-MeO tryptamines than their 4-substituted counterparts."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 1, fullResetDays: 7, buildRate: "rapid"),
            halfLifeMinutes: 60
        ),

        // MARK: 5-MeO-NIPT

        Substance(
            name: "5-MeO-NIPT",
            aliases: ["5-Methoxy-N-isopropyl-N-propyltryptamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...10, common: 10...18, strong: 18...25, heavy: 25
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 40),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 300),
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Ego dissolution", "Visual hallucinations", "Euphoria", "Time distortion", "Nausea", "Body load", "Anxiety", "Introspection", "Physical euphoria", "Perspective shifts"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Ego Dissolution", description: "A 5-MeO tryptamine-class dissolution of self-boundaries that can range from gentle loosening of identity to total loss of the sense of being a separate self."),
                SubjectiveEffect(name: "Physical Euphoria", description: "A deep, resonating bodily pleasure characteristic of 5-MeO tryptamines, often described as a vibrating or humming sensation of pure well-being."),
                SubjectiveEffect(name: "Introspection", description: "A natural inward turn of awareness that combines the ego-dissolving qualities of 5-MeO compounds with a contemplative, examining quality."),
                SubjectiveEffect(name: "Perspective Shifts", description: "Sudden reframings of how one views one's life, relationships, and place in the world that can feel permanently transformative."),
                SubjectiveEffect(name: "Visual Hallucinations", description: "Visual effects ranging from subtle enhancements to immersive visionary experiences, with a character somewhat different from 4-substituted tryptamines."),
                SubjectiveEffect(name: "Anxiety", description: "An intense unease that commonly accompanies the rapid onset and powerful ego dissolution, particularly for unprepared users."),
                SubjectiveEffect(name: "Body Load", description: "A physical weight and tension that can be significant, sometimes described as feeling pressed into the ground or pulled in multiple directions."),
                SubjectiveEffect(name: "Nausea", description: "A stomach discomfort during onset that can be considerable with 5-MeO compounds and may benefit from fasting beforehand."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120
        ),

        // MARK: 4-Pro-DMT

        Substance(
            name: "4-Pro-DMT",
            aliases: ["4-Propanoyloxy-DMT", "4-Propionyloxy-N,N-dimethyltryptamine"],
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
                    afterglow: TimeRange(min: 60, max: 360),
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Introspection", "Color enhancement", "Geometric visual patterns", "Nausea", "Body load", "Thought connectivity", "Emotional enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Visual Hallucinations", description: "Psilocin-like visual effects including flowing surfaces, geometric overlays, and vivid color shifts characteristic of 4-substituted tryptamines."),
                SubjectiveEffect(name: "Geometric Visual Patterns", description: "Complex, symmetrical patterns visible on surfaces and behind closed eyes, often with a crystalline or organic fractal quality."),
                SubjectiveEffect(name: "Euphoria", description: "A warm, mushroom-like sense of joy and wonder that permeates the experience, creating a deeply positive emotional backdrop."),
                SubjectiveEffect(name: "Thought Connectivity", description: "An enhanced ability to see connections between disparate ideas, creating a web of associations that can feel profoundly insightful."),
                SubjectiveEffect(name: "Emotional Enhancement", description: "A deepening of emotional experience where feelings become more textured, vivid, and meaningfully connected to thoughts and memories."),
                SubjectiveEffect(name: "Color Enhancement", description: "A striking intensification of color perception where the world appears painted in impossibly rich and luminous hues."),
                SubjectiveEffect(name: "Introspection", description: "A pull toward inner examination that combines emotional depth with conceptual clarity, enabling meaningful self-understanding."),
                SubjectiveEffect(name: "Body Load", description: "A physical heaviness and potential tension that grounds the experience in bodily awareness, sometimes with stomach discomfort."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 150
        ),

        // MARK: MCPT

        Substance(
            name: "MCPT",
            aliases: ["N-Methyl-N-cyclopropyltryptamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...35, strong: 35...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 300),
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Visual hallucinations", "Euphoria", "Time distortion", "Introspection", "Color enhancement", "Nausea", "Body load", "Thought connectivity", "Pattern recognition enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Visual Hallucinations", description: "Flowing, colorful visual distortions with a character similar to 4-HO-McPT, featuring organic patterning and enhanced textures on surfaces."),
                SubjectiveEffect(name: "Pattern Recognition Enhancement", description: "A heightened ability to perceive meaningful patterns in visual noise and textures, with fractal-like structures appearing in natural surfaces."),
                SubjectiveEffect(name: "Thought Connectivity", description: "An enhanced linking of ideas and concepts that creates novel associations, fostering creative thinking and conceptual exploration."),
                SubjectiveEffect(name: "Euphoria", description: "A warm, contented sense of pleasure characteristic of base tryptamines, providing an emotionally positive foundation for the experience."),
                SubjectiveEffect(name: "Color Enhancement", description: "A noticeable intensification of color perception that makes the visual environment feel more vivid and aesthetically rich."),
                SubjectiveEffect(name: "Introspection", description: "A tendency toward thoughtful self-examination that can yield insights about personal habits, relationships, and thought patterns."),
                SubjectiveEffect(name: "Time Distortion", description: "An altered perception of time passing where minutes may feel like extended periods of rich experience."),
                SubjectiveEffect(name: "Body Load", description: "A physical heaviness and potential digestive discomfort typical of tryptamine compounds, varying in intensity with dose."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 150
        ),

        // MARK: - NBOHs

        // MARK: 25E-NBOH

        Substance(
            name: "25E-NBOH",
            aliases: ["2C-E-NBOH"],
            category: .psychedelic,
            defaultRoute: .sublingual,
            routes: [
                SubstanceRoute(route: .sublingual, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1, common: 1...1.5, strong: 1.5...2.5, heavy: 2.5
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Intense visual hallucinations", "Color enhancement", "Geometric visual patterns", "Euphoria", "Time distortion", "Stimulation", "Vasoconstriction", "Body load", "Nausea", "Thought acceleration"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Intense Visual Hallucinations", description: "Extremely vivid and colorful visual distortions including complex geometric lattices, morphing surfaces, and intense color shifting typical of NBOx compounds."),
                SubjectiveEffect(name: "Geometric Visual Patterns", description: "Highly detailed, symmetrical patterns that overlay all visual surfaces, often appearing as intricate crystalline or kaleidoscopic structures."),
                SubjectiveEffect(name: "Color Enhancement", description: "A dramatic amplification of color saturation and vibrancy that can make the visual world appear almost neon-like in intensity."),
                SubjectiveEffect(name: "Stimulation", description: "A pronounced physical energy and mental alertness characteristic of phenethylamine psychedelics, making sedation unlikely during the experience."),
                SubjectiveEffect(name: "Thought Acceleration", description: "A rapid quickening of mental processes where thoughts race and ideas flow faster than can be comfortably processed."),
                SubjectiveEffect(name: "Euphoria", description: "A strong mood elevation with a stimulating, energetic quality that can feel intensely positive and life-affirming."),
                SubjectiveEffect(name: "Vasoconstriction", description: "A tightening of blood vessels that can cause cold extremities, numbness, and physical discomfort, a significant concern with NBOx compounds."),
                SubjectiveEffect(name: "Body Load", description: "A heavy physical tension and discomfort that can include muscle cramping, stomach pain, and cardiovascular awareness."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180
        ),

        // MARK: - Phenethylamines

        // MARK: 2C-B-AN

        Substance(
            name: "2C-B-AN",
            aliases: ["2C-B-aminonitrite", "25B-NH2"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 30, light: 50...80, common: 80...120, strong: 120...175, heavy: 175
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 60),
                    comeup: TimeRange(min: 15, max: 45),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 240, max: 480)
                )),
            ],
            effects: ["Visual hallucinations", "Color enhancement", "Euphoria", "Body high", "Nausea", "Time distortion", "Empathogenic effects", "Tactile enhancement", "Introspection"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Visual Hallucinations", description: "2C-B-like visual effects including flowing surfaces, color shifts, and geometric patterns, though typically requiring higher doses than 2C-B itself."),
                SubjectiveEffect(name: "Empathogenic Effects", description: "A warm emotional openness similar to 2C-B, creating feelings of connection and emotional intimacy without full entactogenic intensity."),
                SubjectiveEffect(name: "Tactile Enhancement", description: "A heightened sensitivity to physical touch where skin contact feels extraordinarily pleasurable and textures become fascinating."),
                SubjectiveEffect(name: "Body High", description: "A pleasurable physical sensation spreading through the body, often described as warm tingling waves that enhance physical awareness."),
                SubjectiveEffect(name: "Color Enhancement", description: "A vivid amplification of color perception characteristic of the 2C-x class, making the visual world appear radiantly colorful."),
                SubjectiveEffect(name: "Euphoria", description: "A warm, body-centered pleasure that combines psychedelic wonder with empathogenic warmth, typical of the 2C-B family."),
                SubjectiveEffect(name: "Introspection", description: "A gentle self-reflective quality that allows for personal insight without the heavy emotional confrontation of deeper psychedelics."),
                SubjectiveEffect(name: "Nausea", description: "A stomach discomfort during onset common with phenethylamine psychedelics, sometimes accompanied by body load."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 300
        ),

        // MARK: 2C-B-CB

        Substance(
            name: "2C-B-CB",
            aliases: ["2C-B-cyclobenzyl"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 20...35, common: 35...55, strong: 55...80, heavy: 80
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 60),
                    comeup: TimeRange(min: 15, max: 45),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 240, max: 480)
                )),
            ],
            effects: ["Visual hallucinations", "Color enhancement", "Euphoria", "Body high", "Nausea", "Time distortion", "Empathogenic effects", "Tactile enhancement", "Geometric visual patterns"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Visual Hallucinations", description: "2C-B-like visual effects with geometric patterning and flowing surfaces, potentially with unique characteristics from the cyclobenzyl substitution."),
                SubjectiveEffect(name: "Geometric Visual Patterns", description: "Intricate geometric shapes and patterns overlaying visual surfaces, characteristic of the 2C-x phenethylamine class."),
                SubjectiveEffect(name: "Empathogenic Effects", description: "A warm sense of emotional connection and openness typical of the 2C-B family, fostering feelings of closeness and understanding."),
                SubjectiveEffect(name: "Tactile Enhancement", description: "An amplified sensitivity to physical sensation where touch becomes extraordinarily pleasurable and textured surfaces feel fascinating."),
                SubjectiveEffect(name: "Body High", description: "A pleasurable tingling warmth spreading through the body that enhances physical awareness and can feel deeply satisfying."),
                SubjectiveEffect(name: "Color Enhancement", description: "A marked intensification of color vibrancy that gives the visual world an unusually rich and beautiful quality."),
                SubjectiveEffect(name: "Euphoria", description: "A moderate, warm mood elevation combining psychedelic awe with empathogenic emotional warmth."),
                SubjectiveEffect(name: "Nausea", description: "A stomach discomfort during the onset phase common to phenethylamine psychedelics, varying in severity by individual."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 300
        ),

        // MARK: 2C-G

        Substance(
            name: "2C-G",
            aliases: ["2,5-Dimethoxy-3,4-dimethylphenethylamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 8, light: 15...22, common: 22...35, strong: 35...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 180),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 360, max: 720),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: TimeRange(min: 360, max: 720),
                    total: TimeRange(min: 1080, max: 1800)
                )),
            ],
            effects: ["Visual hallucinations", "Color enhancement", "Euphoria", "Introspection", "Long duration", "Nausea", "Body load", "Time distortion", "Geometric visual patterns", "Thought connectivity"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Long Duration", description: "An unusually extended experience lasting 18-30+ hours, requiring significant time commitment and planning that sets it apart from most psychedelics."),
                SubjectiveEffect(name: "Visual Hallucinations", description: "Gradual, building visual effects with geometric patterns and color shifts that develop slowly over the extended onset period."),
                SubjectiveEffect(name: "Geometric Visual Patterns", description: "Complex geometric overlays and patterns on surfaces that build and evolve over the exceptionally long duration of the experience."),
                SubjectiveEffect(name: "Thought Connectivity", description: "An enhanced capacity for associative thinking where ideas connect in novel ways, sustained over the lengthy experience."),
                SubjectiveEffect(name: "Introspection", description: "A deep, sustained self-reflective quality that the long duration allows to develop into thorough personal exploration."),
                SubjectiveEffect(name: "Color Enhancement", description: "A vivid intensification of color perception characteristic of the 2C-x class, building gradually with the extended onset."),
                SubjectiveEffect(name: "Body Load", description: "A significant physical heaviness and discomfort that can be particularly challenging over the extremely long duration."),
                SubjectiveEffect(name: "Nausea", description: "A persistent stomach discomfort that may recur throughout the extended experience rather than resolving after onset as with shorter psychedelics."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 1200
        ),

        // MARK: 2C-N

        Substance(
            name: "2C-N",
            aliases: ["2,5-Dimethoxy-4-nitrophenethylamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 80...110, common: 110...150, strong: 150...200, heavy: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 60),
                    comeup: TimeRange(min: 15, max: 45),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 300),
                    total: TimeRange(min: 240, max: 480)
                )),
            ],
            effects: ["Mild visual hallucinations", "Color enhancement", "Euphoria", "Introspection", "Nausea", "Body load", "Time distortion", "Stimulation", "Thought connectivity"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mild Visual Hallucinations", description: "Subtle visual enhancements with gentle color shifts and mild patterning, less visually intense than most other 2C-x compounds at standard doses."),
                SubjectiveEffect(name: "Stimulation", description: "A noticeable physical and mental activation that adds an alert, energized quality to the otherwise subtle psychedelic effects."),
                SubjectiveEffect(name: "Color Enhancement", description: "A modest intensification of color perception that adds visual richness without overwhelming visual distortion."),
                SubjectiveEffect(name: "Thought Connectivity", description: "An increased tendency to link ideas and concepts in novel ways, providing mild cognitive enhancement alongside the subtle psychedelia."),
                SubjectiveEffect(name: "Euphoria", description: "A gentle mood elevation that provides a positive emotional backdrop without the intensity of more potent 2C-x compounds."),
                SubjectiveEffect(name: "Introspection", description: "A mild reflective quality that encourages contemplation without the forceful depth of stronger psychedelics."),
                SubjectiveEffect(name: "Body Load", description: "A physical heaviness and potential discomfort that can feel disproportionate to the relatively mild mental effects."),
                SubjectiveEffect(name: "Nausea", description: "A stomach queasiness during onset that is common across the phenethylamine psychedelic class."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 300
        ),

        // MARK: 2C-O-4

        Substance(
            name: "2C-O-4",
            aliases: ["2,5-Dimethoxy-4-methoxyphenethylamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 20...40, common: 40...60, strong: 60...80, heavy: 80
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 60),
                    comeup: TimeRange(min: 15, max: 45),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 240, max: 480)
                )),
            ],
            effects: ["Visual hallucinations", "Color enhancement", "Euphoria", "Introspection", "Nausea", "Body load", "Time distortion", "Geometric visual patterns", "Thought connectivity"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Visual Hallucinations", description: "Flowing, colorful visual distortions with geometric patterning characteristic of 2C-x compounds, developing gradually over the onset."),
                SubjectiveEffect(name: "Geometric Visual Patterns", description: "Intricate, symmetrical geometric overlays on visual surfaces that can become increasingly complex with dose."),
                SubjectiveEffect(name: "Color Enhancement", description: "A vivid intensification of color perception that makes the environment appear richly chromatic and aesthetically beautiful."),
                SubjectiveEffect(name: "Thought Connectivity", description: "Enhanced associative thinking that links concepts in creative and unexpected ways, supporting contemplation and insight."),
                SubjectiveEffect(name: "Euphoria", description: "A moderate, warm mood elevation that provides a positive emotional foundation for the psychedelic experience."),
                SubjectiveEffect(name: "Introspection", description: "A contemplative quality that encourages personal reflection and examination of beliefs, habits, and relationships."),
                SubjectiveEffect(name: "Body Load", description: "A physical heaviness and tension that can vary from mild to uncomfortable, common among 2C-x phenethylamines."),
                SubjectiveEffect(name: "Nausea", description: "A stomach discomfort during onset typical of phenethylamine psychedelics, sometimes persisting into the early peak."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 300
        ),

        // MARK: 2C-T-4

        Substance(
            name: "2C-T-4",
            aliases: ["2,5-Dimethoxy-4-isopropylthiophenethylamine"],
            category: .psychedelic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 5...8, common: 8...15, strong: 15...25, heavy: 25
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 90),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 180, max: 480),
                    total: TimeRange(min: 720, max: 960)
                )),
            ],
            effects: ["Visual hallucinations", "Color enhancement", "Euphoria", "Introspection", "Nausea", "Body load", "Time distortion", "Empathogenic effects", "Long duration", "Emotional enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Empathogenic Effects", description: "A warm emotional openness and desire for connection that gives 2C-T-4 a distinctly empathogenic character among the 2C-x compounds."),
                SubjectiveEffect(name: "Long Duration", description: "A notably extended experience lasting 12-16 hours, significantly longer than most 2C-x compounds and requiring careful planning."),
                SubjectiveEffect(name: "Emotional Enhancement", description: "A profound deepening of emotional experience where feelings become vivid, layered, and meaningfully connected to memory and identity."),
                SubjectiveEffect(name: "Visual Hallucinations", description: "Rich visual effects with flowing patterns and color enhancements that develop and evolve over the compound's extended duration."),
                SubjectiveEffect(name: "Color Enhancement", description: "A vivid amplification of color perception characteristic of thio-substituted 2C compounds, with warm and rich visual qualities."),
                SubjectiveEffect(name: "Introspection", description: "A sustained, deep self-reflective quality supported by the long duration, allowing thorough exploration of personal themes."),
                SubjectiveEffect(name: "Body Load", description: "A physical heaviness and potential gastrointestinal discomfort that can be challenging over the extended duration of the experience."),
                SubjectiveEffect(name: "Nausea", description: "A stomach discomfort that can be more pronounced with thio-substituted 2C compounds and may recur periodically during the long experience."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 900
        ),
    ]
}
