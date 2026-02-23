import Foundation

extension SubstanceLibrary {
    static let dissociatives: [Substance] = [

        // MARK: - Arylcyclohexylamines

        // MARK: - Ketamine

        Substance(
            name: "Ketamine",
            aliases: ["K", "Ket", "Special K", "Vitamin K", "Kit Kat"],
            category: .dissociative,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 15...30, common: 30...75, strong: 75...150, heavy: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 2, max: 5),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 60, max: 120)
                )),
                SubstanceRoute(route: .intramuscular, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...25, common: 25...50, strong: 50...100, heavy: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 2, max: 5),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 60, max: 120)
                )),
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 50...100, common: 100...200, strong: 200...300, heavy: 300, fatal: 4000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 45, max: 90),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 90, max: 180)
                )),
                SubstanceRoute(route: .intravenous, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...15, common: 15...30, strong: 30...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 1),
                    comeup: TimeRange(min: 1, max: 3),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 30, max: 45),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 45, max: 90)
                )),
                SubstanceRoute(route: .rectal, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...300, heavy: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 10, max: 15),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 60, max: 120)
                )),
            ],
            effects: ["Dissociation", "Euphoria", "K-hole", "Analgesia", "Visual distortions", "Depersonalization", "Sedation", "Ataxia", "Nausea", "Memory suppression"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Dissociative Anesthesia", description: "A progressive disconnection from the body and physical sensations, as if floating outside oneself or observing from a distance."),
                SubjectiveEffect(name: "K-Hole", description: "At higher doses, a complete dissociation from external reality into an internal abstract space, often described as falling through a void or entering another dimension."),
                SubjectiveEffect(name: "Cognitive Disconnection", description: "Thoughts become fragmented and difficult to follow, with a sense that normal logical thinking has been suspended or rearranged."),
                SubjectiveEffect(name: "Physical Euphoria", description: "A warm, tingling, full-body euphoria that feels like being wrapped in a soft blanket, often accompanied by a pleasant heaviness."),
                SubjectiveEffect(name: "Visual Geometry", description: "Closed-eye visuals consisting of dark, symmetric, and slowly morphing geometric patterns, often with a mechanical or crystalline quality."),
                SubjectiveEffect(name: "Time Distortion", description: "The perception of time becomes heavily distorted, with minutes feeling like hours or time appearing to stop entirely."),
                SubjectiveEffect(name: "Rubber Body", description: "The body feels elastic, rubbery, or as if it is stretching and warping in unusual ways, with limbs feeling disproportionate to their actual size."),
                SubjectiveEffect(name: "Music Enhancement", description: "Music sounds richer, more layered, and more emotionally resonant, with individual instruments becoming distinctly perceptible."),
                SubjectiveEffect(name: "Environmental Unreality", description: "Surroundings appear dreamlike, artificial, or as though viewed through frosted glass, with a sense that the external world is not quite real."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 150,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: - PCP

        Substance(
            name: "PCP",
            aliases: ["Phencyclidine", "Angel Dust", "Wet", "Sherman"],
            category: .dissociative,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...4, common: 4...7, strong: 7...12, heavy: 12, fatal: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 300),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 360, max: 1440),
                    total: TimeRange(min: 360, max: 600)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 1...3, common: 3...5, strong: 5...10, heavy: 10
                ), duration: DurationProfile(
                    onset: TimeRange(min: 2, max: 5),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 240, max: 720),
                    total: TimeRange(min: 240, max: 420)
                )),
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 1...3, common: 3...5, strong: 5...10, heavy: 10
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 2, max: 10),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 240, max: 720),
                    total: TimeRange(min: 240, max: 420)
                )),
            ],
            effects: ["Dissociation", "Euphoria", "Mania", "Analgesia", "Depersonalization", "Hallucinations", "Paranoia", "Aggression", "Slurred speech", "Numbness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Manic Invincibility", description: "An overwhelming sense of power, invulnerability, and godlike confidence that can override rational judgment and pain perception."),
                SubjectiveEffect(name: "Dissociative Delirium", description: "At higher doses, a complete break from consensus reality with vivid hallucinations that are indistinguishable from real events, often with bizarre or violent themes."),
                SubjectiveEffect(name: "Full-Body Numbness", description: "A profound anesthetic numbness that spreads across the entire body, making it possible to sustain injuries without feeling pain."),
                SubjectiveEffect(name: "Cognitive Mania", description: "Racing thoughts with a feeling of profound insight or understanding, often accompanied by pressured speech and grandiose ideation."),
                SubjectiveEffect(name: "Paranoid Ideation", description: "An intense, irrational suspicion that others have hostile intentions, which can escalate rapidly into aggressive or defensive behavior."),
                SubjectiveEffect(name: "Robotic Movement", description: "A stiff, mechanical quality to physical movement with loss of fine motor control, giving a sense that the body is moving on autopilot."),
                SubjectiveEffect(name: "Environmental Distortion", description: "The surrounding environment appears to tilt, stretch, or pulse, with objects appearing closer or farther than they actually are."),
                SubjectiveEffect(name: "Emotional Flattening", description: "A blunting of normal emotional responses, where events that would normally provoke fear, sadness, or joy produce little to no emotional reaction."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 1260,
            sources: ["PsychonautWiki", "Erowid", "DEA", "StatPearls"]
        ),

        // MARK: - 3-MeO-PCP

        Substance(
            name: "3-MeO-PCP",
            aliases: ["3-Methoxyphencyclidine"],
            category: .dissociative,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...10, strong: 10...15, heavy: 15, fatal: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 360, max: 720),
                    total: TimeRange(min: 360, max: 600)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...4, common: 4...8, strong: 8...12, heavy: 12, fatal: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 240, max: 480),
                    total: TimeRange(min: 240, max: 420)
                )),
            ],
            effects: ["Dissociation", "Mania", "Euphoria", "Depersonalization", "Cognitive stimulation", "Delusions of sobriety", "Analgesia", "Paranoia", "Grandiosity", "Conceptual thinking"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Delusions of Sobriety", description: "A uniquely dangerous phenomenon where users feel completely sober and in control despite being heavily intoxicated, often leading to compulsive redosing."),
                SubjectiveEffect(name: "Manic Stimulation", description: "A strong stimulant-like push with hyperactive thoughts, pressured speech, and an intense drive to move or engage in activities."),
                SubjectiveEffect(name: "Grandiose Ideation", description: "Feelings of exaggerated self-importance, special knowledge, or unique cosmic significance that feel completely genuine in the moment."),
                SubjectiveEffect(name: "Conceptual Thinking", description: "Thoughts become highly abstract and philosophical, with a sense of accessing deep structural patterns underlying reality."),
                SubjectiveEffect(name: "Dissociative Euphoria", description: "A clean, clear-headed euphoria distinct from opioids or stimulants, characterized by a sense of lightness and detachment from worry."),
                SubjectiveEffect(name: "Paranoid Escalation", description: "Suspicion and distrust that can build incrementally over the duration, sometimes not recognized as drug-induced due to the sobriety delusion."),
                SubjectiveEffect(name: "Physical Disconnection", description: "Progressive loss of body awareness where physical sensations become muted or absent, with the sense of being a disembodied mind."),
                SubjectiveEffect(name: "Hole Resistance", description: "Unlike ketamine, higher doses tend to produce mania and psychosis rather than a traditional dissociative hole, with users remaining ambulatory."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 660,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - 3-HO-PCP

        Substance(
            name: "3-HO-PCP",
            aliases: ["3-Hydroxyphencyclidine"],
            category: .dissociative,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 1...3, common: 3...5, strong: 5...8, heavy: 8, fatal: 25
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 240, max: 480),
                    total: TimeRange(min: 300, max: 480)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 1...2, common: 2...4, strong: 4...6, heavy: 6, fatal: 15
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 10),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Dissociation", "Euphoria", "Warmth", "Analgesia", "Sedation", "Depersonalization", "Opioid-like effects", "Nausea", "Cognitive suppression", "Anxiety suppression"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Opioid-Like Warmth", description: "A deep, spreading warmth throughout the body reminiscent of opioid effects, likely due to its significant mu-opioid receptor activity."),
                SubjectiveEffect(name: "Anxiolytic Dissociation", description: "A calm, peaceful detachment from worry and anxiety that feels soothing rather than disorienting, often described as a warm blanket over the mind."),
                SubjectiveEffect(name: "Gentle Sedation", description: "A pleasantly drowsy, relaxed state that encourages lying down and closing the eyes without the heavy cognitive impairment of other PCP analogs."),
                SubjectiveEffect(name: "Physical Euphoria", description: "A strong, body-centered euphoria with tingling warmth that many users compare to a combination of a dissociative and an opioid."),
                SubjectiveEffect(name: "Hole Potential", description: "At higher doses, the ability to enter a deep, immersive dissociative hole with a warmer and more comfortable character than ketamine."),
                SubjectiveEffect(name: "Respiratory Depression Risk", description: "Due to opioid receptor activity, users may experience slowed breathing, especially at higher doses or in combination with other depressants."),
                SubjectiveEffect(name: "Cognitive Smoothing", description: "Thoughts become simplified and slowed in a way that feels comfortable rather than confusing, with reduced mental chatter."),
                SubjectiveEffect(name: "Pain Dissolution", description: "Physical pain becomes distant and irrelevant, as if it belongs to someone else, with strong analgesic effects lasting well beyond the main experience."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 660,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - 3-MeO-PCE

        Substance(
            name: "3-MeO-PCE",
            aliases: ["3-Methoxyeticyclidine"],
            category: .dissociative,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 3...6, common: 6...12, strong: 12...20, heavy: 20, fatal: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 240, max: 480),
                    total: TimeRange(min: 300, max: 480)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...10, strong: 10...16, heavy: 16
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 240, max: 420)
                )),
            ],
            effects: ["Dissociation", "Mania", "Euphoria", "Cognitive stimulation", "Depersonalization", "Visual distortions", "Analgesia", "Paranoia", "Conceptual thinking", "Music enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Stimulating Dissociation", description: "A uniquely energetic dissociative state that combines mental stimulation with detachment, producing a wired yet disconnected feeling."),
                SubjectiveEffect(name: "Manic Euphoria", description: "An intense, elated mood with racing thoughts and a strong urge to talk, create, or engage in activities, similar to a hypomanic episode."),
                SubjectiveEffect(name: "Conceptual Expansion", description: "Thoughts take on a highly abstract, interconnected quality where concepts seem to branch and merge in novel and meaningful ways."),
                SubjectiveEffect(name: "Music Appreciation", description: "Music becomes profoundly enhanced with a multi-dimensional quality, feeling as though one can physically inhabit the sound."),
                SubjectiveEffect(name: "Visual Scenery", description: "Vivid, colorful open and closed-eye visuals with more psychedelic character than typical arylcyclohexylamines, including flowing patterns and color shifts."),
                SubjectiveEffect(name: "Sobriety Delusion", description: "Similar to 3-MeO-PCP, a tendency to believe one is more sober than one actually is, which can lead to unsafe redosing decisions."),
                SubjectiveEffect(name: "Social Disinhibition", description: "A marked reduction in social anxiety with increased talkativeness and sociability that can cross into inappropriate oversharing."),
                SubjectiveEffect(name: "Residual Stimulation", description: "A long-lasting afterglow of mental stimulation that can persist well after the primary dissociative effects have subsided, sometimes interfering with sleep."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 360,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - 3-HO-PCE

        Substance(
            name: "3-HO-PCE",
            aliases: ["3-Hydroxyeticyclidine"],
            category: .dissociative,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...10, strong: 10...15, heavy: 15
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 240, max: 480),
                    total: TimeRange(min: 300, max: 480)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...4, common: 4...8, strong: 8...12, heavy: 12
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Dissociation", "Euphoria", "Warmth", "Sedation", "Depersonalization", "Analgesia", "Opioid-like effects", "Visual distortions", "Cognitive suppression", "Nausea"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Warm Dissociation", description: "A comforting, enveloping warmth that accompanies the dissociative state, making the experience feel cozy and physically pleasant."),
                SubjectiveEffect(name: "Opioid Crossover", description: "Noticeable opioid-like qualities including a nodding, drowsy euphoria and pain relief, though less pronounced than its PCP counterpart 3-HO-PCP."),
                SubjectiveEffect(name: "Gentle Euphoria", description: "A mellow, contented euphoria that lacks the manic edge of PCP analogs, more akin to a warm emotional glow."),
                SubjectiveEffect(name: "Soft Visual Distortions", description: "Mild visual warping and softening of edges, with the environment taking on a dreamy, slightly out-of-focus quality."),
                SubjectiveEffect(name: "Immersive Hole", description: "At sufficient doses, a warm and immersive dissociative hole that users describe as more comfortable and less disorienting than ketamine."),
                SubjectiveEffect(name: "Physical Relaxation", description: "Deep muscular relaxation and heaviness that encourages stillness and makes physical movement feel unnecessary."),
                SubjectiveEffect(name: "Cognitive Quieting", description: "Mental chatter reduces significantly, producing a meditative state of mental stillness and present-moment awareness."),
                SubjectiveEffect(name: "Anxiolytic Afterglow", description: "A lingering sense of calm and reduced anxiety that persists for hours to days after the primary effects have worn off."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 360,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - O-PCE

        Substance(
            name: "O-PCE",
            aliases: ["2-Oxo-PCE", "Eticyclidone", "2'-Oxo-PCE"],
            category: .dissociative,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...10, strong: 10...15, heavy: 15, fatal: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 240, max: 480),
                    total: TimeRange(min: 300, max: 480)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...4, common: 4...8, strong: 8...12, heavy: 12
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 10),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 240, max: 420)
                )),
            ],
            effects: ["Dissociation", "Euphoria", "Stimulation", "Depersonalization", "Visual distortions", "Analgesia", "Mania", "Anxiety", "Cognitive suppression", "Memory suppression"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Cold Dissociation", description: "A sharp, clinical feeling of detachment that users often describe as colder and more sterile than ketamine, with a distinctly mechanical quality."),
                SubjectiveEffect(name: "Stimulant Edge", description: "An energizing undercurrent beneath the dissociation that can produce restlessness and a wired, alert feeling even while deeply dissociated."),
                SubjectiveEffect(name: "Deep Hole Potential", description: "Capable of producing extremely deep, immersive dissociative holes with vivid internal landscapes that can feel more intense than ketamine."),
                SubjectiveEffect(name: "Manic Acceleration", description: "At certain dose ranges, a rapid escalation of mood and thought speed that can shift suddenly from calm dissociation into full mania."),
                SubjectiveEffect(name: "Anxiogenic Undertone", description: "An undercurrent of unease or anxiety that can accompany the experience, particularly on the comeup or at moderate doses."),
                SubjectiveEffect(name: "Visual Sharpening", description: "The visual field can appear unusually crisp and high-contrast, as if reality has been digitally enhanced, before giving way to distortions at higher doses."),
                SubjectiveEffect(name: "Memory Blackout", description: "Strong doses frequently produce complete amnesia for the experience, with users unable to recall anything that occurred during peak effects."),
                SubjectiveEffect(name: "Long Duration", description: "Effects last significantly longer than ketamine, with residual dissociation and cognitive effects persisting for many hours after dosing."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 480,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - MXE

        Substance(
            name: "MXE",
            aliases: ["Methoxetamine", "Mexxy", "M-ket"],
            category: .dissociative,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60, fatal: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 240, max: 480),
                    total: TimeRange(min: 240, max: 360)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 5...15, common: 15...25, strong: 25...45, heavy: 45, fatal: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 10),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 180, max: 300)
                )),
                SubstanceRoute(route: .intramuscular, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 5...10, common: 10...25, strong: 25...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 2, max: 10),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 120, max: 240)
                )),
            ],
            effects: ["Dissociation", "Euphoria", "Warmth", "K-hole", "Depersonalization", "Visual distortions", "Analgesia", "Mania", "Nausea", "Music enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Magical Dissociation", description: "Users frequently describe MXE as having a uniquely magical or mystical quality, with the dissociative state feeling enchanted and wonder-filled."),
                SubjectiveEffect(name: "M-Hole", description: "A signature deep dissociative state distinct from the K-hole, often described as warmer, more colorful, and more narrative-driven with complex internal worlds."),
                SubjectiveEffect(name: "Hypomanic Euphoria", description: "A distinctive manic euphoria with grandiose feelings and creative inspiration that can persist well into the afterglow period."),
                SubjectiveEffect(name: "Warm Body High", description: "An enveloping physical warmth and comfort that distinguishes MXE from the colder dissociation of ketamine, often described as being hugged by the universe."),
                SubjectiveEffect(name: "Psychedelic Visuals", description: "More colorful and elaborate visuals than ketamine, with flowing geometric patterns, color enhancement, and sometimes full psychedelic-like imagery."),
                SubjectiveEffect(name: "Music Synesthesia", description: "Music becomes an extraordinarily immersive experience, often producing synesthetic effects where sound is felt physically or perceived as visual patterns."),
                SubjectiveEffect(name: "Walking on Clouds", description: "A distinctive locomotion alteration where walking feels as though treading on soft, springy clouds, with each step feeling cushioned and bouncy."),
                SubjectiveEffect(name: "Conceptual Exploration", description: "Complex philosophical and existential thoughts arise spontaneously, with a sense of profound personal insight and universal understanding."),
                SubjectiveEffect(name: "Extended Afterglow", description: "A positive mood lift and cognitive enhancement that can persist for days after the experience, often described as a lasting antidepressant effect."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - MXiPr

        Substance(
            name: "MXiPr",
            aliases: ["Methoxisopropylamine", "MXiPr"],
            category: .dissociative,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 15...25, common: 25...45, strong: 45...70, heavy: 70
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 240, max: 360)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...35, strong: 35...55, heavy: 55
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 10),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 240),
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Dissociation", "Euphoria", "Warmth", "Visual distortions", "Depersonalization", "Sedation", "Analgesia", "Nausea", "Cognitive suppression", "Music enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Gentle Warm Dissociation", description: "A smooth, gradual onset of dissociation with a warm, comfortable quality that feels like slowly sinking into a heated pool."),
                SubjectiveEffect(name: "Ketamine-Like Hole", description: "At higher doses, a dissociative hole experience that closely resembles ketamine but with a warmer undertone and slightly longer duration."),
                SubjectiveEffect(name: "Sensory Softening", description: "External sensory input becomes muffled and soft, as if the world is being experienced through a comfortable layer of cotton."),
                SubjectiveEffect(name: "Euphoric Sedation", description: "A pleasantly sedating euphoria that encourages relaxation and stillness, making it well-suited for lying down with music."),
                SubjectiveEffect(name: "Visual Morphing", description: "Surfaces and textures appear to slowly breathe, shift, and morph, with colors becoming slightly more vivid and saturated."),
                SubjectiveEffect(name: "Music Immersion", description: "Music takes on a deeply immersive, three-dimensional quality with enhanced emotional resonance and a sense of being inside the sound."),
                SubjectiveEffect(name: "Physical Heaviness", description: "The body feels pleasantly heavy and anchored, with movement requiring conscious effort but not feeling unpleasant."),
                SubjectiveEffect(name: "Cognitive Slowing", description: "Thought processes decelerate in a relaxing way, with a reduced sense of urgency and a peaceful mental quiet."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - MXPr

        Substance(
            name: "MXPr",
            aliases: ["Methoxpropamine", "3-MeO-2'-Oxo-PCPr"],
            category: .dissociative,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 15...30, common: 30...55, strong: 55...80, heavy: 80
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 180, max: 360)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...25, common: 25...40, strong: 40...65, heavy: 65
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 10),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 240),
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Dissociation", "Euphoria", "Visual distortions", "Depersonalization", "Sedation", "Analgesia", "Nausea", "Cognitive suppression", "Warmth", "Music enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Balanced Dissociation", description: "A middle-ground dissociative experience that balances sedation and clarity, feeling neither too stimulating nor too sedating."),
                SubjectiveEffect(name: "Warm Euphoria", description: "A gentle, warm euphoria that gradually builds and persists throughout the experience, with a comforting physical glow."),
                SubjectiveEffect(name: "Visual Waviness", description: "The visual field develops a wavy, undulating quality where straight lines curve and surfaces ripple like water."),
                SubjectiveEffect(name: "Dissociative Hole", description: "Capable of producing a deep hole experience at higher doses with characteristics between ketamine and MXE, featuring abstract internal spaces."),
                SubjectiveEffect(name: "Sedating Comedown", description: "The latter portion of the experience becomes increasingly sedating, often transitioning smoothly into restful sleep."),
                SubjectiveEffect(name: "Music Enhancement", description: "Music gains additional depth and emotional weight, with sounds appearing to come from unusual spatial locations."),
                SubjectiveEffect(name: "Physical Comfort", description: "A pervasive sense of physical ease and comfort, with minor aches and tensions dissolving into pleasant numbness."),
                SubjectiveEffect(name: "Mild Nausea", description: "A common queasy feeling during the onset phase that typically resolves once the peak effects establish themselves."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - DMXE

        Substance(
            name: "DMXE",
            aliases: ["Deoxymethoxetamine", "3-Me-2'-Oxo-PCE"],
            category: .dissociative,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...25, common: 25...50, strong: 50...80, heavy: 80
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 240, max: 420)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...65, heavy: 65
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 10),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 240),
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Dissociation", "Euphoria", "Mania", "Stimulation", "Depersonalization", "Visual distortions", "Analgesia", "Anxiety", "Cognitive suppression", "Music enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Stimulating Dissociation", description: "A notably energetic dissociative profile that combines mental acceleration with detachment, producing a stimulated yet disconnected state."),
                SubjectiveEffect(name: "Manic Push", description: "A strong hypomanic drive with racing thoughts, increased confidence, and a compulsive urge to engage in activities or conversation."),
                SubjectiveEffect(name: "Euphoric Rush", description: "An initial rush of euphoria during onset that can feel almost empathogenic, with a surge of positive emotion and social warmth."),
                SubjectiveEffect(name: "Visual Complexity", description: "Rich, detailed visual distortions with more color saturation and patterning than typical ketamine analogs, sometimes approaching psychedelic intensity."),
                SubjectiveEffect(name: "Musical Rapture", description: "An intensely pleasurable response to music where songs feel deeply meaningful and sounds seem to have physical texture and spatial dimension."),
                SubjectiveEffect(name: "Anxious Undercurrent", description: "A subtle but persistent nervous energy that can accompany the stimulation, occasionally tipping into uncomfortable anxiety at higher doses."),
                SubjectiveEffect(name: "Compulsive Redosing", description: "A notable urge to take more during the experience, driven by the stimulating and euphoric nature of the effects."),
                SubjectiveEffect(name: "Residual Wakefulness", description: "Difficulty sleeping for many hours after the primary effects subside due to lingering stimulation and mental activation."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - FXE

        Substance(
            name: "FXE",
            aliases: ["Fluorexetamine", "3-F-2'-Oxo-PCE"],
            category: .dissociative,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 20...40, common: 40...80, strong: 80...120, heavy: 120
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 240, max: 420)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 15...30, common: 30...60, strong: 60...100, heavy: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 10),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 300),
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Dissociation", "Euphoria", "Stimulation", "Visual distortions", "Depersonalization", "Analgesia", "Warmth", "Nausea", "Cognitive suppression", "Music enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Ketamine-Adjacent Dissociation", description: "A dissociative profile that closely resembles ketamine but with slightly more stimulation and a warmer body feel."),
                SubjectiveEffect(name: "Stimulated Euphoria", description: "A euphoria that carries a stimulant edge, producing feelings of excitement and energy rather than pure sedation."),
                SubjectiveEffect(name: "Vivid Visual Distortions", description: "Colorful and dynamic visual effects including geometric patterning, color enhancement, and environmental distortion that lean toward psychedelic."),
                SubjectiveEffect(name: "Warm Physical Glow", description: "A pleasant warmth radiating through the body that enhances physical comfort and touch sensitivity."),
                SubjectiveEffect(name: "Social Enhancement", description: "At lower doses, an increase in sociability and conversational fluency with reduced social anxiety."),
                SubjectiveEffect(name: "Musical Dimension", description: "Music becomes deeply engaging with a sense of three-dimensional space within the sound, enhancing both electronic and acoustic genres."),
                SubjectiveEffect(name: "Onset Nausea", description: "A wave of nausea that commonly occurs during the onset period, particularly when taken orally, which typically passes as effects plateau."),
                SubjectiveEffect(name: "Cognitive Fog", description: "A progressive mental fogginess at higher doses where forming coherent thoughts becomes difficult and attention fragments."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 150,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - 2-FDCK

        Substance(
            name: "2-FDCK",
            aliases: ["2-Fluorodeschloroketamine", "2F-Ketamine"],
            category: .dissociative,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 30, light: 50...100, common: 100...200, strong: 200...350, heavy: 350
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 120, max: 240)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 20...50, common: 50...100, strong: 100...175, heavy: 175
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 10),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 45, max: 90),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 120, max: 300),
                    total: TimeRange(min: 120, max: 180)
                )),
            ],
            effects: ["Dissociation", "Euphoria", "K-hole", "Analgesia", "Visual distortions", "Depersonalization", "Sedation", "Ataxia", "Nausea", "Memory suppression"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Ketamine-Lite", description: "A dissociative experience widely described as a milder, more functional version of ketamine with a similar overall character but reduced intensity."),
                SubjectiveEffect(name: "Gradual Onset", description: "Effects build more slowly and smoothly than ketamine, with a gentler transition into dissociation that feels less abrupt."),
                SubjectiveEffect(name: "Functional Dissociation", description: "At low to moderate doses, a lucid dissociative state where basic cognitive and motor functions remain relatively intact."),
                SubjectiveEffect(name: "Mild Hole", description: "The dissociative hole is achievable but typically requires higher relative doses and is described as less vivid and immersive than a ketamine K-hole."),
                SubjectiveEffect(name: "Visual Softening", description: "The visual field becomes soft and slightly blurred, with gentle distortions and a dreamlike quality to the environment."),
                SubjectiveEffect(name: "Physical Numbness", description: "A spreading numbness and analgesia that can make the body feel distant and somewhat robotic in its movements."),
                SubjectiveEffect(name: "Extended Duration", description: "Effects last noticeably longer than ketamine, providing a more sustained experience but also requiring more time for full recovery."),
                SubjectiveEffect(name: "Subtle Euphoria", description: "A mild, pleasant mood lift that is less intense than ketamine but persists throughout the duration of effects."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - DCK

        Substance(
            name: "DCK",
            aliases: ["Deschloroketamine", "2'-Oxo-PCM", "DXE"],
            category: .dissociative,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 5...10, common: 10...20, strong: 20...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 240, max: 720),
                    total: TimeRange(min: 300, max: 480)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 3...8, common: 8...15, strong: 15...25, heavy: 25
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Dissociation", "Euphoria", "K-hole", "Sedation", "Depersonalization", "Visual distortions", "Analgesia", "Nausea", "Memory suppression", "Ataxia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Potent Dissociation", description: "A strong dissociative effect relative to dose, with deep detachment from body and environment achievable at modest milligram amounts."),
                SubjectiveEffect(name: "Deep Hole Experience", description: "Capable of producing profound, immersive dissociative holes with vivid internal experiences and complete loss of external awareness."),
                SubjectiveEffect(name: "Heavy Sedation", description: "A strong sedating quality that can make standing or moving very difficult, encouraging full physical stillness."),
                SubjectiveEffect(name: "Visual Distortion", description: "Significant visual warping and geometric patterning at moderate to high doses, with the environment appearing to fold or tunnel."),
                SubjectiveEffect(name: "Long Duration", description: "Effects persist for an extended period compared to ketamine, with the full experience lasting several hours and aftereffects lingering further."),
                SubjectiveEffect(name: "Amnesia", description: "Pronounced memory suppression where entire portions of the experience may be impossible to recall afterward."),
                SubjectiveEffect(name: "Motor Impairment", description: "Significant loss of coordination and balance, with walking becoming extremely difficult and potentially dangerous."),
                SubjectiveEffect(name: "Residual Dissociation", description: "A lingering sense of detachment and cognitive fog that can persist for a day or more after heavy use."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 240,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - HXE

        Substance(
            name: "HXE",
            aliases: ["Hydroxetamine", "3-HO-2'-Oxo-PCE"],
            category: .dissociative,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 20...40, common: 40...80, strong: 80...120, heavy: 120
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 240),
                    total: TimeRange(min: 180, max: 300)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 15...30, common: 30...60, strong: 60...100, heavy: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 10),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 90, max: 180)
                )),
            ],
            effects: ["Dissociation", "Euphoria", "Warmth", "Sedation", "Depersonalization", "Analgesia", "Opioid-like effects", "Visual distortions", "Nausea", "Cognitive suppression"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Warm Sedating Dissociation", description: "A cozy, sedating dissociative state with prominent warmth that combines the qualities of a dissociative and a gentle opioid."),
                SubjectiveEffect(name: "Opioid Qualities", description: "Notable opioid-like effects including warmth, contentment, and pain relief due to hydroxyl-group affinity for mu-opioid receptors."),
                SubjectiveEffect(name: "Comfortable Hole", description: "At higher doses, a warm and gentle dissociative hole that users describe as more nurturing and less chaotic than ketamine."),
                SubjectiveEffect(name: "Physical Analgesia", description: "Strong pain-relieving effects that can persist well beyond the main experience, with the body feeling numb and insulated from discomfort."),
                SubjectiveEffect(name: "Soft Visuals", description: "Gentle visual distortions with a soft, hazy quality rather than sharp geometric patterns, giving the world a gauzy appearance."),
                SubjectiveEffect(name: "Emotional Warmth", description: "A sense of emotional comfort and well-being that feels nurturing, with worries and anxieties feeling distant and unimportant."),
                SubjectiveEffect(name: "Cognitive Dampening", description: "Thought processes slow and simplify in a comfortable way, with complex worries becoming difficult to maintain."),
                SubjectiveEffect(name: "Respiratory Caution", description: "Like 3-HO-PCP, the opioid activity carries a risk of respiratory depression, particularly when combined with other depressant substances."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - Diphenidine

        Substance(
            name: "Diphenidine",
            aliases: ["DPD", "1,2-DEP"],
            category: .dissociative,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 20, light: 30...60, common: 60...90, strong: 90...120, heavy: 120, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Dissociation", "Euphoria", "Depersonalization", "Stimulation", "Hallucinations", "Analgesia", "Nausea", "Paranoia", "Slurred speech", "Memory suppression"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Stimulating Dissociation", description: "A notably stimulating dissociative profile that produces a wired, alert state of disconnection rather than the sedation of ketamine-type substances."),
                SubjectiveEffect(name: "Hallucinatory States", description: "At higher doses, vivid hallucinations that can be difficult to distinguish from reality, sometimes featuring complex scenarios or entity encounters."),
                SubjectiveEffect(name: "Internal Dialogue", description: "An unusual effect where users report hearing or generating internal voices and complex narratives that feel autonomous and separate from their own thoughts."),
                SubjectiveEffect(name: "Physical Stimulation", description: "Increased heart rate, body temperature, and a sense of physical energy that distinguishes it from sedating dissociatives."),
                SubjectiveEffect(name: "Paranoid Thinking", description: "Suspicion and distrust that can develop during the experience, sometimes escalating into full paranoid episodes at higher doses."),
                SubjectiveEffect(name: "Speech Impairment", description: "Increasingly slurred and difficult-to-produce speech as the dose increases, with thoughts becoming hard to articulate verbally."),
                SubjectiveEffect(name: "Amnesia", description: "Significant memory impairment during peak effects, with large portions of the experience often impossible to recall afterward."),
                SubjectiveEffect(name: "Long Onset", description: "A notably slow onset when taken orally, sometimes taking over an hour to reach full effects, which can lead to dangerous premature redosing."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 360,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - Ephenidine

        Substance(
            name: "Ephenidine",
            aliases: ["NEDPA", "N-Ethyl-1,2-diphenylethylamine"],
            category: .dissociative,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 30, light: 40...70, common: 70...100, strong: 100...150, heavy: 150, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 240, max: 480),
                    total: TimeRange(min: 360, max: 600)
                )),
            ],
            effects: ["Dissociation", "Euphoria", "Sedation", "Depersonalization", "Analgesia", "Visual distortions", "Nausea", "Slurred speech", "Cognitive suppression", "Memory suppression"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Gradual Sedating Dissociation", description: "A slow-building dissociative state that progressively deepens over an extended period, with a distinctly sedating and calming character."),
                SubjectiveEffect(name: "Mellow Euphoria", description: "A gentle, understated euphoria that lacks the intensity of arylcyclohexylamines but provides a sustained, comfortable positive mood."),
                SubjectiveEffect(name: "Deep Physical Numbness", description: "Prominent anesthetic effects that produce thorough numbness throughout the body, making physical sensations feel very distant."),
                SubjectiveEffect(name: "Visual Dreaminess", description: "Soft, dreamlike visual distortions where the world takes on an unreal, almost cinematic quality with muted colors and soft focus."),
                SubjectiveEffect(name: "Cognitive Fog", description: "A dense mental fog that makes complex thinking very difficult, with thoughts feeling slow, scattered, and hard to hold onto."),
                SubjectiveEffect(name: "Very Long Duration", description: "An extremely long duration of effects, often lasting 6-8 hours or more, which can be challenging for unprepared users."),
                SubjectiveEffect(name: "Speech Difficulty", description: "Progressive difficulty with speech production where words become slurred and sentences become hard to complete coherently."),
                SubjectiveEffect(name: "Slow Onset Danger", description: "A very gradual onset that can take 1-2 hours to fully manifest, creating a significant risk of impatient redosing."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 300,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - MXP

        Substance(
            name: "MXP",
            aliases: ["Methoxphenidine", "2-MeO-Diphenidine"],
            category: .dissociative,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 20, light: 40...75, common: 75...120, strong: 120...175, heavy: 175
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Dissociation", "Euphoria", "Depersonalization", "Sedation", "Stimulation", "Analgesia", "Nausea", "Slurred speech", "Memory suppression", "Cognitive suppression"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mixed Stimulation-Sedation", description: "An unusual combination of stimulating and sedating qualities that alternate or coexist, creating an unpredictable and sometimes confusing experience."),
                SubjectiveEffect(name: "Diarylethylamine Dissociation", description: "A dissociative character distinct from arylcyclohexylamines, often described as heavier, foggier, and less clean-feeling."),
                SubjectiveEffect(name: "Moderate Euphoria", description: "A moderate, unremarkable euphoria that is present but not as pronounced as with more popular dissociatives."),
                SubjectiveEffect(name: "Physical Anesthesia", description: "Strong numbing of physical sensations with pronounced analgesic effects that make the body feel distant and insubstantial."),
                SubjectiveEffect(name: "Nausea Prominence", description: "Notable nausea that can be more prominent than with other dissociatives, sometimes persisting throughout the experience."),
                SubjectiveEffect(name: "Cognitive Impairment", description: "Significant mental impairment with difficulty forming coherent thoughts, following conversations, or performing basic mental tasks."),
                SubjectiveEffect(name: "Slow Onset", description: "A slow oral onset typical of diarylethylamines, requiring patience and carrying the risk of premature redosing."),
                SubjectiveEffect(name: "Extended Duration", description: "Long-lasting effects that can persist for many hours, with a gradual and sometimes incomplete feeling return to baseline."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 360,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - 2-MDP

        Substance(
            name: "2-MDP",
            aliases: ["2-Methyl-Diphenidine", "2-Methyldiphenidine"],
            category: .dissociative,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 20, light: 40...75, common: 75...120, strong: 120...175, heavy: 175
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Dissociation", "Euphoria", "Depersonalization", "Stimulation", "Analgesia", "Visual distortions", "Nausea", "Slurred speech", "Memory suppression", "Cognitive suppression"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Under-Explored Dissociation", description: "A relatively obscure diarylethylamine with limited user reports, producing a dissociative state with characteristics typical of its class."),
                SubjectiveEffect(name: "Stimulating Edge", description: "A stimulating quality that produces mental and physical energy alongside the dissociative effects, distinguishing it from purely sedating compounds."),
                SubjectiveEffect(name: "Moderate Euphoria", description: "A moderate positive mood enhancement that provides some recreational value but is generally considered less euphoric than popular dissociatives."),
                SubjectiveEffect(name: "Visual Effects", description: "Visual distortions including warping, color changes, and soft geometric patterns that become more pronounced at higher doses."),
                SubjectiveEffect(name: "Physical Numbness", description: "Significant anesthetic numbness that progressively spreads through the body, reducing sensitivity to touch and pain."),
                SubjectiveEffect(name: "Memory Impairment", description: "Difficulty forming new memories during the experience, with portions of the peak often lost to amnesia."),
                SubjectiveEffect(name: "Long Duration", description: "Effects that persist for an extended period typical of oral diarylethylamines, requiring significant time commitment."),
                SubjectiveEffect(name: "Speech Deterioration", description: "Progressive slurring and difficulty producing coherent speech as the dose increases and effects deepen."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 360,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - Tiletamine

        Substance(
            name: "Tiletamine",
            aliases: ["Tiletamine"],
            category: .dissociative,
            defaultRoute: .intramuscular,
            routes: [
                SubstanceRoute(route: .intramuscular, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 20...40, common: 40...80, strong: 80...150, heavy: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 2, max: 5),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 60, max: 180)
                )),
            ],
            effects: ["Dissociation", "Analgesia", "Sedation", "Amnesia", "Depersonalization", "Ataxia", "Nausea", "Visual distortions", "Confusion", "Muscle rigidity"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Veterinary Dissociation", description: "A heavy, sedating dissociative state originally developed for veterinary anesthesia, producing deep disconnection from the body and surroundings."),
                SubjectiveEffect(name: "Profound Amnesia", description: "Extremely strong memory suppression where the entire experience may be completely unrecoverable from memory."),
                SubjectiveEffect(name: "Cataleptic State", description: "A rigid, frozen quality to the body where muscles become stiff and the user may be unable to move voluntarily."),
                SubjectiveEffect(name: "Deep Anesthesia", description: "Complete loss of pain sensation and physical awareness, reflecting its medical use as a surgical anesthetic agent."),
                SubjectiveEffect(name: "Heavy Confusion", description: "Profound disorientation and confusion during emergence from the dissociative state, with difficulty understanding where one is or what is happening."),
                SubjectiveEffect(name: "Nausea and Vomiting", description: "Significant gastrointestinal distress that commonly accompanies the experience, particularly during onset and emergence phases."),
                SubjectiveEffect(name: "Visual Blurring", description: "Severe blurring and doubling of vision that makes visual processing extremely difficult and disorienting."),
                SubjectiveEffect(name: "Emergence Delirium", description: "A period of intense confusion, agitation, and hallucination that can occur when regaining awareness, a well-documented phenomenon in clinical settings."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 240,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - Other Dissociatives

        // MARK: - DXM

        Substance(
            name: "DXM",
            aliases: ["Dextromethorphan", "Robo", "DXM", "Robitussin", "Dex"],
            category: .dissociative,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 75, light: 100...200, common: 200...400, strong: 400...700, heavy: 700, fatal: 1500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 240, max: 720),
                    total: TimeRange(min: 360, max: 600)
                )),
            ],
            effects: ["Dissociation", "Euphoria", "Visual distortions", "Music enhancement", "Depersonalization", "Nausea", "Sedation", "Robo-walk", "Slurred speech", "Itching"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Plateau Progression", description: "A unique dose-dependent progression through four distinct plateaus, each with qualitatively different effects ranging from mild stimulation to complete dissociation."),
                SubjectiveEffect(name: "Robo-Walk", description: "A distinctive stiff, robotic gait with arms held rigidly at the sides, caused by cerebellar disruption and a hallmark of DXM intoxication."),
                SubjectiveEffect(name: "Sigma Plateau", description: "At very high doses, a delirious and potentially psychotic state combining dissociative and serotonergic effects that can be extremely disorienting and frightening."),
                SubjectiveEffect(name: "Music Euphoria", description: "An extraordinarily intense enhancement of music that many users consider the defining positive effect, with songs producing overwhelming emotional and physical responses."),
                SubjectiveEffect(name: "Histamine Itch", description: "A widespread itching sensation caused by histamine release, sometimes accompanied by a rash, which can be mitigated with antihistamines."),
                SubjectiveEffect(name: "Double Vision", description: "A distinctive nystagmus-driven doubling of vision that makes reading impossible and gives the visual field a jittering, unstable quality."),
                SubjectiveEffect(name: "Serotonergic Warmth", description: "A warm, empathogenic body feeling at lower plateaus that reflects DXM's serotonin reuptake inhibition, creating an MDMA-like quality."),
                SubjectiveEffect(name: "Gravity Distortion", description: "A sensation that gravity is shifting or that the body is being pulled in unusual directions, contributing to severe balance impairment."),
                SubjectiveEffect(name: "Nausea and Vomiting", description: "Prominent gastrointestinal distress, especially during onset, which is exacerbated by inactive ingredients in many OTC formulations."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 30, buildRate: "slow"),
            halfLifeMinutes: 360,
            sources: ["PsychonautWiki", "Erowid", "Drugs.com", "PubMed"]
        ),

        // MARK: - Nitrous Oxide

        Substance(
            name: "Nitrous Oxide",
            aliases: ["N2O", "Laughing Gas", "Whippets", "Nangs", "Nos", "Balloons"],
            category: .dissociative,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "cartridge", doses: DoseRange(
                    threshold: 1, light: 1...1, common: 1...2, strong: 2...3, heavy: 3
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 0.25),
                    comeup: TimeRange(min: 0.1, max: 0.5),
                    peak: TimeRange(min: 0.5, max: 2),
                    offset: TimeRange(min: 2, max: 5),
                    afterglow: TimeRange(min: 5, max: 15),
                    total: TimeRange(min: 2, max: 5)
                )),
            ],
            effects: ["Dissociation", "Euphoria", "Laughter", "Auditory distortions", "Depersonalization", "Dizziness", "Numbness", "Tingling", "Analgesia", "Brief duration"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Wah-Wah Auditory Effect", description: "A signature pulsating, oscillating distortion of all sounds that produces a rhythmic wah-wah or wub-wub pattern, as if reality is stuttering."),
                SubjectiveEffect(name: "Instant Euphoric Rush", description: "An immediate, intense wave of euphoria and warmth that hits within seconds of inhalation and peaks almost instantly."),
                SubjectiveEffect(name: "Uncontrollable Laughter", description: "Spontaneous, often uncontrollable fits of laughter that arise without any clear trigger, reflecting its common name of laughing gas."),
                SubjectiveEffect(name: "Brief Ego Dissolution", description: "At higher doses, a fleeting but complete loss of personal identity and sense of self that resolves within minutes."),
                SubjectiveEffect(name: "Tingling Numbness", description: "A pins-and-needles tingling sensation that spreads from the extremities inward, accompanied by progressive numbness."),
                SubjectiveEffect(name: "Deja Vu Loops", description: "A powerful sensation of having experienced the current moment before, sometimes cycling in repetitive loops that feel infinitely recursive."),
                SubjectiveEffect(name: "Time Stopping", description: "A perception that time has completely frozen or that the present moment is stretching infinitely, despite the experience only lasting minutes."),
                SubjectiveEffect(name: "Combination Potentiation", description: "When combined with other substances, particularly psychedelics or cannabis, a dramatic and sometimes overwhelming potentiation of the other substance's effects."),
                SubjectiveEffect(name: "Rapid Return to Baseline", description: "Effects dissipate almost completely within 1-5 minutes, with full sobriety returning remarkably quickly after cessation of inhalation."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 1, fullResetDays: 3, buildRate: "rapid"),
            halfLifeMinutes: 5,
            sources: ["PsychonautWiki", "Erowid", "Drugs.com", "PubMed"]
        ),

        // MARK: - Memantine

        Substance(
            name: "Memantine",
            aliases: ["Namenda", "Ebixa", "Axura", "Akatinol"],
            category: .dissociative,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...25, common: 25...50, strong: 50...100, heavy: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 180),
                    comeup: TimeRange(min: 120, max: 240),
                    peak: TimeRange(min: 240, max: 720),
                    offset: TimeRange(min: 480, max: 1440),
                    afterglow: TimeRange(min: 1440, max: 4320),
                    total: TimeRange(min: 1440, max: 4320)
                )),
            ],
            effects: ["Dissociation", "Stimulation", "Depersonalization", "Cognitive alteration", "Visual distortions", "Insomnia", "Dizziness", "Nausea", "Long duration", "Analgesia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Ultra-Long Duration", description: "Effects that persist for 24-72 hours or even longer, making this one of the longest-lasting dissociatives known, requiring careful planning around responsibilities."),
                SubjectiveEffect(name: "Subtle Dissociation", description: "A mild, background dissociative state that is more subtle and functional than classical dissociatives, often described as a persistent slight detachment."),
                SubjectiveEffect(name: "Stimulant Quality", description: "A notable stimulating effect that can produce wakefulness, mental energy, and difficulty sleeping for the entire multi-day duration."),
                SubjectiveEffect(name: "Cognitive Strangeness", description: "A persistent sense that thinking feels slightly different or alien, as if cognitive processes have been subtly rearranged in ways that are hard to articulate."),
                SubjectiveEffect(name: "Visual Drifting", description: "Mild visual distortions including drifting, slight color enhancement, and a sense that the visual field is not quite stable."),
                SubjectiveEffect(name: "Cumulative Insomnia", description: "Severe difficulty falling or staying asleep that can compound over the multi-day duration, becoming the most problematic effect for many users."),
                SubjectiveEffect(name: "Tolerance Persistence", description: "Tolerance that builds very slowly but also takes an extremely long time to fully resolve, reflecting memantine's slow pharmacokinetics."),
                SubjectiveEffect(name: "Functional Disconnection", description: "The ability to remain outwardly functional while experiencing an internal sense of subtle unreality and detachment that persists for days."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 45, buildRate: "slow"),
            halfLifeMinutes: 4200,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki", "PubMed"]
        ),

        // MARK: - Salvia divinorum

        Substance(
            name: "Salvia divinorum",
            aliases: ["Salvia", "Sally D", "Diviner's Sage", "Ska Maria Pastora"],
            category: .dissociative,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .sublingual, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 3...10, common: 10...25, strong: 25...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 20),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 60, max: 120)
                )),
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...500, heavy: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.5, max: 1),
                    comeup: TimeRange(min: 0.5, max: 1),
                    peak: TimeRange(min: 1, max: 5),
                    offset: TimeRange(min: 5, max: 10),
                    afterglow: TimeRange(min: 15, max: 60),
                    total: TimeRange(min: 5, max: 15)
                )),
            ],
            effects: ["Dissociation", "Hallucinations", "Depersonalization", "Dysphoria", "Gravity distortion", "Uncontrollable laughter", "Loss of identity", "Visual distortions", "Anxiety", "Short duration"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Reality Unzipping", description: "A sensation that the fabric of reality is peeling apart, unzipping, or folding away to reveal layers underneath, unique to salvinorin A's kappa-opioid agonism."),
                SubjectiveEffect(name: "Gravitational Pull", description: "An overwhelming, directional force that feels like being pulled, dragged, or compressed in a specific direction by an irresistible gravitational or magnetic force."),
                SubjectiveEffect(name: "Object Merging", description: "A dissolution of boundaries between self and nearby objects, with the sensation of becoming part of furniture, walls, or the floor."),
                SubjectiveEffect(name: "Entity Contact", description: "Encounters with seemingly autonomous presences or beings that may communicate, guide, or observe, often described as feminine or plant-like intelligences."),
                SubjectiveEffect(name: "Complete Identity Loss", description: "Absolute and total loss of all personal identity, memories, and knowledge of being human, with no awareness that a drug was consumed."),
                SubjectiveEffect(name: "Hysterical Laughter", description: "Intense, uncontrollable laughter that arises spontaneously and may persist despite the experience being terrifying or confusing."),
                SubjectiveEffect(name: "Geometric Flattening", description: "The three-dimensional world appears to flatten into two dimensions or fold like pages of a book, with reality taking on a paper-thin quality."),
                SubjectiveEffect(name: "Rapid Onset and Offset", description: "When smoked, effects hit within 30 seconds, peak at 1-2 minutes, and largely resolve within 5-10 minutes, making it one of the shortest-acting dissociatives."),
                SubjectiveEffect(name: "Dysphoric Terror", description: "Unlike most dissociatives, the experience is frequently described as deeply uncomfortable, frightening, or existentially threatening rather than pleasurable."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 1, fullResetDays: 3, buildRate: "rapid"),
            halfLifeMinutes: 60,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - Ibogaine

        Substance(
            name: "Ibogaine",
            aliases: ["Iboga", "Tabernanthe iboga"],
            category: .dissociative,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 50...200, common: 200...500, strong: 500...1000, heavy: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 180),
                    comeup: TimeRange(min: 120, max: 240),
                    peak: TimeRange(min: 480, max: 1440),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: TimeRange(min: 1440, max: 4320),
                    total: TimeRange(min: 1440, max: 2160)
                )),
            ],
            effects: ["Dissociation", "Hallucinations", "Introspection", "Nausea", "Ataxia", "Vomiting", "Dream-like visions", "Depersonalization", "Long duration", "Tremors"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Visionary State", description: "An extended, dreamlike visionary experience lasting 24-36 hours featuring vivid, narrative-driven hallucinations often involving autobiographical life review."),
                SubjectiveEffect(name: "Life Review", description: "A panoramic replay of significant life events, often from childhood, presented in vivid detail as if reliving them, frequently with therapeutic or revelatory qualities."),
                SubjectiveEffect(name: "Addiction Interruption", description: "A unique property where the experience can dramatically reduce or eliminate cravings and withdrawal symptoms for opioids and other substances."),
                SubjectiveEffect(name: "Severe Purging", description: "Intense nausea and vomiting that is considered a core part of the experience in traditional contexts, often occurring in waves throughout the session."),
                SubjectiveEffect(name: "Physical Incapacitation", description: "Complete loss of motor coordination and the inability to stand or walk safely, requiring a supervised setting with a sitter present."),
                SubjectiveEffect(name: "Waking Dream Visions", description: "Elaborate, symbolic dream-like visions that occur with eyes closed while the user remains partially conscious, often featuring archetypal imagery."),
                SubjectiveEffect(name: "Emotional Catharsis", description: "Powerful emotional release including intense crying, grief processing, or feelings of forgiveness that many users describe as deeply healing."),
                SubjectiveEffect(name: "Cardiac Risk", description: "Ibogaine affects cardiac ion channels and can cause fatal arrhythmias, making medical screening and cardiac monitoring essential for safe use."),
                SubjectiveEffect(name: "Extended Recovery", description: "A prolonged recovery period of several days following the acute experience, with lingering fatigue, introspection, and sensitivity to stimulation."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 30, buildRate: "slow"),
            halfLifeMinutes: 2160,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - Xenon

        Substance(
            name: "Xenon",
            aliases: ["Xe"],
            category: .dissociative,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "% v/v", doses: DoseRange(
                    threshold: 10, light: 15...25, common: 25...35, strong: 35...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 0.5),
                    comeup: TimeRange(min: 0.25, max: 1),
                    peak: TimeRange(min: 1, max: 3),
                    offset: TimeRange(min: 2, max: 5),
                    afterglow: TimeRange(min: 5, max: 15),
                    total: TimeRange(min: 3, max: 8)
                )),
            ],
            effects: ["Dissociation", "Euphoria", "Analgesia", "Dizziness", "Numbness", "Depersonalization", "Sedation", "Brief duration", "Auditory distortions", "Warmth"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Clean Euphoria", description: "A remarkably pure and pleasant euphoria often described as cleaner and smoother than nitrous oxide, with a luxurious quality reflecting its rarity and cost."),
                SubjectiveEffect(name: "Rapid Onset", description: "Effects begin almost immediately upon inhalation, with a quick wash of dissociation and warmth that develops within seconds."),
                SubjectiveEffect(name: "Gentle Dissociation", description: "A smooth, comfortable dissociative state that feels soft and enveloping rather than disorienting or confusing."),
                SubjectiveEffect(name: "Physical Warmth", description: "A spreading warmth throughout the body that feels deeply comforting and pleasant, more pronounced than with nitrous oxide."),
                SubjectiveEffect(name: "Auditory Changes", description: "Sound takes on a muffled, reverberating quality with a slight pitch shift, as if hearing through a gentle echo chamber."),
                SubjectiveEffect(name: "Brief Duration", description: "Effects are short-lived, resolving within minutes of discontinuing inhalation, making it highly controllable."),
                SubjectiveEffect(name: "Minimal Side Effects", description: "Notably fewer adverse effects than most dissociatives, with minimal nausea, confusion, or hangover, reflecting its favorable pharmacological profile."),
                SubjectiveEffect(name: "Neuroprotective Profile", description: "Unlike most NMDA antagonists, xenon is considered neuroprotective rather than neurotoxic, and does not produce the concerning Olney's lesions seen with other dissociatives."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 1, fullResetDays: 3, buildRate: "rapid"),
            halfLifeMinutes: 5,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),

        // MARK: - Dizocilpine

        Substance(
            name: "Dizocilpine",
            aliases: ["MK-801"],
            category: .dissociative,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.01, light: 0.02...0.05, common: 0.05...0.1, strong: 0.1...0.15, heavy: 0.15, fatal: 1
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: TimeRange(min: 480, max: 1440),
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Dissociation", "Hallucinations", "Ataxia", "Depersonalization", "Cognitive suppression", "Memory suppression", "Analgesia", "Nausea", "Anxiety", "Neurotoxicity risk"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Extreme Potency", description: "Active in microgram-level doses, producing profound dissociation from tiny amounts, making accurate dosing exceptionally difficult and dangerous."),
                SubjectiveEffect(name: "Irreversible Binding", description: "As an open-channel blocker with extremely slow unbinding kinetics, effects can persist far longer than expected and accumulate unpredictably."),
                SubjectiveEffect(name: "Severe Ataxia", description: "Profound loss of motor coordination and balance that can render the user completely unable to walk or maintain posture."),
                SubjectiveEffect(name: "Cognitive Devastation", description: "Severe impairment of all cognitive functions including memory, attention, language, and executive function at even moderate doses."),
                SubjectiveEffect(name: "Neurotoxic Potential", description: "Known to cause Olney's lesions and neuronal vacuolization in animal studies, representing a serious risk of irreversible brain damage."),
                SubjectiveEffect(name: "Hallucinatory States", description: "Vivid and often disturbing hallucinations that can be indistinguishable from reality, with a delirious quality distinct from other dissociatives."),
                SubjectiveEffect(name: "Protracted Duration", description: "Due to its binding characteristics, effects can persist for an unusually long and unpredictable duration, sometimes lasting far longer than anticipated."),
                SubjectiveEffect(name: "Research Chemical Danger", description: "Primarily a research tool not intended for human consumption, with extremely limited human experience data and a narrow margin between active and dangerous doses."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 45, buildRate: "slow"),
            halfLifeMinutes: 720,
            sources: ["PsychonautWiki", "Erowid", "PubMed"]
        ),
    ]
}
