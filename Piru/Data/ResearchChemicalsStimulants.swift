import Foundation

extension SubstanceLibrary {
    static let researchChemicalsStimulants: [Substance] = [

        // MARK: - Fluorinated Amphetamines

        // MARK: 2-FMA

        Substance(
            name: "2-FMA",
            aliases: ["2-Fluoromethamphetamine"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...35, strong: 35...50, heavy: 50, fatal: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 180, max: 300),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 240),
                    total: TimeRange(min: 360, max: 540)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 5...15, common: 15...25, strong: 25...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 90, max: 150),
                    afterglow: TimeRange(min: 120, max: 240),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Focus enhancement", "Stimulation", "Motivation enhancement", "Appetite suppression", "Wakefulness", "Increased heart rate", "Anxiety", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Clean Stimulation", description: "A smooth, focused energy that feels functional rather than recreational, often compared to a more potent version of prescription stimulants without excessive euphoria."),
                SubjectiveEffect(name: "Focus Enhancement", description: "A pronounced sharpening of concentration that makes sustained work on detailed tasks feel natural and effortless for extended periods."),
                SubjectiveEffect(name: "Motivation Enhancement", description: "A steady internal drive to begin and complete tasks, making productivity feel intrinsically rewarding rather than forced."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A significant reduction in hunger signals that can persist for the full duration, making it easy to forget meals entirely."),
                SubjectiveEffect(name: "Wakefulness", description: "A persistent alertness that resists drowsiness, keeping the mind clear and attentive well beyond normal waking hours."),
                SubjectiveEffect(name: "Physical Stimulation", description: "A subtle bodily activation felt as increased energy and slight restlessness, without the jitteriness of caffeine."),
                SubjectiveEffect(name: "Anxiety", description: "A dose-dependent nervousness that can manifest as racing thoughts or physical tension, particularly during the comedown phase."),
                SubjectiveEffect(name: "Insomnia", description: "A sustained inability to fall asleep that can persist for many hours after the primary effects have faded due to the compound's long duration."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 10, buildRate: "moderate"),
            halfLifeMinutes: 360,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: 3-FMA

        Substance(
            name: "3-FMA",
            aliases: ["3-Fluoromethamphetamine"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 180, max: 300),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 240),
                    total: TimeRange(min: 360, max: 540)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 5...15, common: 15...30, strong: 30...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 90, max: 150),
                    afterglow: TimeRange(min: 120, max: 240),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Euphoria", "Stimulation", "Empathy enhancement", "Focus enhancement", "Appetite suppression", "Jaw clenching", "Increased heart rate", "Insomnia", "Anxiety"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Euphoria", description: "A warm, rolling wave of pleasure and well-being that combines stimulant energy with mild serotonergic warmth, creating a balanced positive mood."),
                SubjectiveEffect(name: "Empathy Enhancement", description: "A noticeable increase in emotional openness and connection to others, making conversations feel more meaningful and genuine."),
                SubjectiveEffect(name: "Stimulation", description: "A strong physical and mental energy boost that drives desire for activity and social interaction, felt throughout the body."),
                SubjectiveEffect(name: "Focus Enhancement", description: "An improved ability to concentrate on tasks, though less laser-focused than 2-FMA due to the added serotonergic component."),
                SubjectiveEffect(name: "Jaw Clenching", description: "An involuntary tightening of the jaw muscles that can become persistent and uncomfortable, reflecting the compound's serotonin activity."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A marked reduction in hunger that persists throughout the experience, often only noticed after the effects wear off."),
                SubjectiveEffect(name: "Increased Heart Rate", description: "A noticeable acceleration of heartbeat that can feel pronounced during physical activity or anxious moments."),
                SubjectiveEffect(name: "Comedown", description: "A period of low mood, fatigue, and irritability following the peak effects, often proportional to the dose taken."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 10, buildRate: "moderate"),
            halfLifeMinutes: 360,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: 2-FA

        Substance(
            name: "2-FA",
            aliases: ["2-Fluoroamphetamine"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 45),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 360, max: 540)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 5...15, common: 15...30, strong: 30...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Focus enhancement", "Stimulation", "Motivation enhancement", "Appetite suppression", "Wakefulness", "Increased heart rate", "Anxiety", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Clean Stimulation", description: "A smooth, functional stimulant effect that feels less pushy than amphetamine, providing clear-headed energy without excessive peripheral side effects."),
                SubjectiveEffect(name: "Focus Enhancement", description: "A reliable improvement in sustained attention and task engagement, making it popular as a study or productivity aid among users."),
                SubjectiveEffect(name: "Motivation Enhancement", description: "A gentle but persistent drive to engage in productive activities, without the compulsive quality of more recreational stimulants."),
                SubjectiveEffect(name: "Wakefulness", description: "A consistent alertness that pushes back sleepiness, maintaining cognitive sharpness across the experience duration."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A reliable dampening of hunger signals that persists throughout the duration and may extend into the comedown."),
                SubjectiveEffect(name: "Mild Mood Lift", description: "A subtle but noticeable improvement in baseline mood that feels natural rather than euphoric, helping maintain positive engagement with tasks."),
                SubjectiveEffect(name: "Physical Stimulation", description: "A light increase in bodily energy and restlessness, typically milder and smoother than traditional amphetamine."),
                SubjectiveEffect(name: "Anxiety", description: "A low-level nervousness that can emerge at higher doses, manifesting as physical tension or racing thoughts during the peak."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 10, buildRate: "moderate"),
            halfLifeMinutes: 300,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: 3-FA

        Substance(
            name: "3-FA",
            aliases: ["3-Fluoroamphetamine"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 45),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 360, max: 540)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 5...15, common: 15...30, strong: 30...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Euphoria", "Stimulation", "Focus enhancement", "Sociability enhancement", "Appetite suppression", "Jaw clenching", "Increased heart rate", "Insomnia", "Anxiety"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Euphoria", description: "A well-rounded stimulant euphoria that blends dopaminergic reward with mild serotonergic warmth, creating an enjoyable but not overwhelming mood lift."),
                SubjectiveEffect(name: "Stimulation", description: "A strong physical and mental energy boost that encourages activity and social engagement, more recreational-feeling than the 2-position isomer."),
                SubjectiveEffect(name: "Sociability Enhancement", description: "An increased desire to interact and communicate, with reduced social anxiety and greater ease in conversation."),
                SubjectiveEffect(name: "Focus Enhancement", description: "An improved ability to concentrate, though with more recreational distraction potential than purely functional fluorinated amphetamines."),
                SubjectiveEffect(name: "Jaw Clenching", description: "An involuntary tightening and grinding of jaw muscles that reflects the compound's serotonergic activity, sometimes uncomfortable."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A strong reduction in hunger throughout the duration that can make eating feel unpleasant or unappealing."),
                SubjectiveEffect(name: "Increased Heart Rate", description: "A noticeable cardiovascular stimulation that can feel uncomfortable during physical exertion or anxious moments."),
                SubjectiveEffect(name: "Comedown Irritability", description: "A period of reduced mood, mental fatigue, and irritability following the peak effects as neurotransmitter levels recover."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 10, buildRate: "moderate"),
            halfLifeMinutes: 360,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: - Fluorinated Ethamphetamines

        // MARK: 2-FEA

        Substance(
            name: "2-FEA",
            aliases: ["2-Fluoroethamphetamine"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 15...30, common: 30...50, strong: 50...70, heavy: 70
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 150, max: 270),
                    offset: TimeRange(min: 90, max: 150),
                    afterglow: TimeRange(min: 120, max: 240),
                    total: TimeRange(min: 330, max: 510)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 120, max: 210),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 240),
                    total: TimeRange(min: 270, max: 450)
                )),
            ],
            effects: ["Stimulation", "Focus enhancement", "Appetite suppression", "Wakefulness", "Motivation enhancement", "Increased heart rate", "Anxiety", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Functional Stimulation", description: "A clean, task-oriented energy that promotes productivity without significant euphoria, similar in character to 2-FMA but with a slightly different duration profile."),
                SubjectiveEffect(name: "Focus Enhancement", description: "A reliable sharpening of attention that helps with sustained mental work, making detailed tasks feel more manageable."),
                SubjectiveEffect(name: "Wakefulness", description: "A smooth resistance to fatigue and drowsiness that maintains alertness without the jittery quality of excessive caffeine."),
                SubjectiveEffect(name: "Motivation Enhancement", description: "A steady internal push toward task completion that makes starting and finishing work feel more natural."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A noticeable dampening of hunger cues that can cause users to unintentionally skip meals throughout the duration."),
                SubjectiveEffect(name: "Physical Stimulation", description: "A mild increase in bodily energy and slight restlessness, typically well-tolerated and not overwhelming."),
                SubjectiveEffect(name: "Anxiety", description: "A potential for nervousness and physical tension, especially at higher doses or in anxiety-prone individuals."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty initiating sleep that can persist beyond the primary effects, requiring careful timing of doses."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 10, buildRate: "moderate"),
            halfLifeMinutes: 240,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: 3-FEA

        Substance(
            name: "3-FEA",
            aliases: ["3-Fluoroethamphetamine"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 15...30, common: 30...50, strong: 50...80, heavy: 80
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 15, max: 25),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 240, max: 420)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...25, common: 25...40, strong: 40...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 45, max: 90),
                    afterglow: TimeRange(min: 120, max: 300),
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Euphoria", "Empathy enhancement", "Stimulation", "Sociability enhancement", "Mood lift", "Jaw clenching", "Appetite suppression", "Increased heart rate", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Euphoria", description: "A warm, empathogenic euphoria with significant serotonergic character, often described as having MDMA-like qualities with a shorter duration."),
                SubjectiveEffect(name: "Empathy Enhancement", description: "A pronounced increase in emotional openness, compassion, and desire for meaningful connection, making it popular in social settings."),
                SubjectiveEffect(name: "Sociability Enhancement", description: "A strong urge to engage socially with lowered inhibitions and enhanced conversational flow, making interactions feel deeply rewarding."),
                SubjectiveEffect(name: "Mood Lift", description: "A significant elevation in overall mood that can feel like a profound sense of contentment and appreciation for the present moment."),
                SubjectiveEffect(name: "Stimulation", description: "A moderate physical and mental energy increase that is less pushy than pure stimulants, serving more as a background energizer."),
                SubjectiveEffect(name: "Jaw Clenching", description: "Involuntary tension in the jaw and facial muscles that reflects the compound's substantial serotonin releasing activity."),
                SubjectiveEffect(name: "Music Enhancement", description: "An increased appreciation for music where sounds feel richer, more emotionally resonant, and deeply satisfying."),
                SubjectiveEffect(name: "Serotonergic Comedown", description: "A period of low mood, emotional flatness, and fatigue in the days following use due to temporary serotonin depletion."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 10, buildRate: "moderate"),
            halfLifeMinutes: 240,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: - Synthetic Cathinones (Pyrovalerones)

        // MARK: NEP

        Substance(
            name: "NEP",
            aliases: ["N-Ethylpentedrone", "N-Ethyl-Pentedrone"],
            category: .stimulant,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 15...25, common: 25...40, strong: 40...60, heavy: 60, fatal: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 120, max: 180)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...35, strong: 35...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 1, max: 3),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 15, max: 30),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 60, max: 120)
                )),
            ],
            effects: ["Euphoria", "Stimulation", "Compulsive redosing", "Increased confidence", "Appetite suppression", "Vasoconstriction", "Increased heart rate", "Insomnia", "Anxiety", "Paranoia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Euphoria", description: "A sharp, intense rush of pleasure that peaks quickly when insufflated, often described as cocaine-like but with a slightly longer duration and different character."),
                SubjectiveEffect(name: "Stimulation", description: "A potent burst of physical and mental energy that creates a strong desire for activity and engagement, with a notably short duration."),
                SubjectiveEffect(name: "Compulsive Redosing", description: "A powerful urge to take more as the short-lived euphoria fades, creating a cycle of repeated dosing that can be difficult to control."),
                SubjectiveEffect(name: "Confidence Enhancement", description: "An amplified sense of self-assurance and social boldness that can feel empowering but may lead to overestimation of one's abilities."),
                SubjectiveEffect(name: "Vasoconstriction", description: "A tightening of blood vessels felt as cold extremities, numbness in fingers and toes, and a general sense of physical constriction."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A complete loss of appetite that persists through repeated dosing sessions and well into the recovery period."),
                SubjectiveEffect(name: "Paranoia", description: "An escalating suspicion and anxiety that typically emerges after extended use sessions, sometimes progressing to irrational fears."),
                SubjectiveEffect(name: "Crash", description: "A pronounced period of exhaustion, low mood, and irritability following binge use, often accompanied by strong cravings."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 120,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: Hexen

        Substance(
            name: "Hexen",
            aliases: ["N-Ethylhexedrone", "NEH", "Hex-En"],
            category: .stimulant,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 15...25, common: 25...50, strong: 50...75, heavy: 75, fatal: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 120, max: 180)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...35, strong: 35...50, heavy: 50, fatal: 250
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 1, max: 3),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 15, max: 30),
                    afterglow: nil,
                    total: TimeRange(min: 60, max: 90)
                )),
            ],
            effects: ["Euphoria", "Stimulation", "Compulsive redosing", "Increased confidence", "Appetite suppression", "Vasoconstriction", "Increased heart rate", "Insomnia", "Anxiety", "Paranoia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Euphoria", description: "An intense, cocaine-like rush of pleasure that arrives quickly when insufflated, characterized by a sharp dopaminergic reward with a short peak duration."),
                SubjectiveEffect(name: "Stimulation", description: "A powerful burst of both physical and mental energy that creates an urgent desire for activity, often described as more intense than traditional stimulants."),
                SubjectiveEffect(name: "Compulsive Redosing", description: "A strong, difficult-to-resist urge to redose as the brief euphoria fades, making binge sessions common and hard to stop once started."),
                SubjectiveEffect(name: "Confidence Enhancement", description: "A pronounced increase in self-assurance and assertiveness that can feel grandiose at higher doses."),
                SubjectiveEffect(name: "Vasoconstriction", description: "Noticeable narrowing of blood vessels causing cold hands and feet, pallor, and potential discomfort in extremities."),
                SubjectiveEffect(name: "Paranoia", description: "A creeping sense of suspicion and fear that typically intensifies with extended use sessions, potentially becoming severe."),
                SubjectiveEffect(name: "Insomnia", description: "A stubborn inability to sleep that can persist for many hours after the last dose, often accompanied by residual stimulation."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A total loss of interest in food that spans the entire session and well into recovery."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 120,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: A-PHP

        Substance(
            name: "A-PHP",
            aliases: ["Alpha-Pyrrolidinohexanophenone", "alpha-PHP", "PV-7"],
            category: .stimulant,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 8...15, common: 15...25, strong: 25...40, heavy: 40, fatal: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 180, max: 300)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...10, common: 10...20, strong: 20...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 1, max: 3),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 120, max: 180)
                )),
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 3...8, common: 8...15, strong: 15...25, heavy: 25, fatal: 80
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 1),
                    comeup: TimeRange(min: 0.5, max: 2),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 15, max: 30),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 60, max: 120)
                )),
            ],
            effects: ["Intense euphoria", "Stimulation", "Compulsive redosing", "Increased focus", "Appetite suppression", "Paranoia", "Vasoconstriction", "Increased heart rate", "Insomnia", "Psychosis"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Intense Euphoria", description: "An extremely powerful rush of dopaminergic pleasure, especially when vaporized, often described as one of the most intensely euphoric stimulant experiences available."),
                SubjectiveEffect(name: "Stimulation", description: "An overwhelming surge of physical and mental energy that can feel electrically charged, driving frantic activity and restlessness."),
                SubjectiveEffect(name: "Compulsive Redosing", description: "An exceptionally strong compulsion to redose that dominates decision-making, making it extremely difficult to stop once a session begins."),
                SubjectiveEffect(name: "Hyperfocus", description: "An intense but narrow concentration that can lock onto a single task or activity obsessively, sometimes for hours without awareness of time passing."),
                SubjectiveEffect(name: "Paranoia", description: "An escalating and often severe suspicion and fear that can progress rapidly with repeated dosing, sometimes involving shadow people and surveillance fears."),
                SubjectiveEffect(name: "Vasoconstriction", description: "Significant blood vessel constriction causing pale, cold extremities and potential chest tightness, especially during extended sessions."),
                SubjectiveEffect(name: "Psychosis", description: "A potential loss of contact with reality including hallucinations, delusions, and disorganized thinking that can emerge after prolonged use or high doses."),
                SubjectiveEffect(name: "Severe Crash", description: "A devastating comedown characterized by profound depression, exhaustion, intense cravings, and an inability to experience pleasure for extended periods."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 2, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: A-PVP

        Substance(
            name: "A-PVP",
            aliases: ["Alpha-PVP", "Flakka", "Gravel", "alpha-Pyrrolidinopentiophenone"],
            category: .stimulant,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...10, common: 10...20, strong: 20...35, heavy: 35, fatal: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 180, max: 360)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 3...5, common: 5...10, strong: 10...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 1, max: 3),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 120, max: 240)
                )),
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...10, strong: 10...20, heavy: 20, fatal: 80
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 1),
                    comeup: TimeRange(min: 0.5, max: 2),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 15, max: 30),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 60, max: 120)
                )),
            ],
            effects: ["Intense euphoria", "Stimulation", "Compulsive redosing", "Paranoia", "Psychosis", "Appetite suppression", "Vasoconstriction", "Increased heart rate", "Insomnia", "Delusions"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Intense Euphoria", description: "An extremely powerful and immediate rush of pleasure, especially when vaporized, that is widely regarded as among the most potent stimulant euphoria available."),
                SubjectiveEffect(name: "Overwhelming Stimulation", description: "A massive surge of manic energy that can feel uncontrollable, driving compulsive movement, talking, and activity for extended periods."),
                SubjectiveEffect(name: "Compulsive Redosing", description: "A nearly irresistible drive to redose that frequently overrides rational judgment, making this compound notoriously difficult to use in a controlled manner."),
                SubjectiveEffect(name: "Paranoia", description: "Severe and often debilitating suspicion that commonly involves beliefs of being watched, followed, or conspired against, escalating rapidly with use."),
                SubjectiveEffect(name: "Psychosis", description: "A breakdown in reality testing that may include vivid hallucinations, paranoid delusions, and bizarre behavior, especially after prolonged wakefulness."),
                SubjectiveEffect(name: "Delusions", description: "Fixed false beliefs that feel absolutely real, often involving persecution or grandiosity, that persist even when contradicted by evidence."),
                SubjectiveEffect(name: "Vasoconstriction", description: "Severe constriction of blood vessels that can cause significant physical discomfort, cold extremities, and cardiovascular strain."),
                SubjectiveEffect(name: "Devastating Crash", description: "A profound physical and psychological collapse following binge use, marked by severe depression, anhedonia, and extended recovery periods."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 2, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: A-PIHP

        Substance(
            name: "A-PIHP",
            aliases: ["Alpha-Pyrrolidinoisohexanophenone", "alpha-PiHP"],
            category: .stimulant,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...15, common: 15...25, strong: 25...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 180, max: 300)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...10, common: 10...20, strong: 20...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 1, max: 3),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 120, max: 180)
                )),
            ],
            effects: ["Intense euphoria", "Stimulation", "Compulsive redosing", "Increased focus", "Appetite suppression", "Paranoia", "Vasoconstriction", "Increased heart rate", "Insomnia", "Anxiety"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Intense Euphoria", description: "A strong dopaminergic rush of pleasure comparable to A-PHP, arriving rapidly when insufflated or vaporized with a compelling but short-lived peak."),
                SubjectiveEffect(name: "Stimulation", description: "A powerful physical and mental activation that creates restless energy and an urgent desire for activity or engagement."),
                SubjectiveEffect(name: "Compulsive Redosing", description: "A very strong urge to take additional doses as the brief euphoria fades, a hallmark of the pyrovalerone class that makes moderation difficult."),
                SubjectiveEffect(name: "Hyperfocus", description: "An intense narrowing of attention onto a single activity that can consume hours, often fixating on repetitive or meaningless tasks."),
                SubjectiveEffect(name: "Paranoia", description: "A dose-dependent increase in suspicion and anxiety that escalates with repeated dosing, potentially becoming irrational and distressing."),
                SubjectiveEffect(name: "Vasoconstriction", description: "Uncomfortable tightening of blood vessels resulting in cold extremities, pallor, and potential cardiovascular discomfort."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A total elimination of hunger signals that persists throughout the session and well beyond the last dose."),
                SubjectiveEffect(name: "Crash", description: "A period of significant fatigue, depression, and irritability following use, with intensity correlating to session length and total dosage."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 2, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: A-PCyP

        Substance(
            name: "A-PCyP",
            aliases: ["Alpha-Pyrrolidinocyclohexylphenone"],
            category: .stimulant,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...15, common: 15...25, strong: 25...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 180, max: 300)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...10, common: 10...20, strong: 20...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 1, max: 3),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 120, max: 180)
                )),
            ],
            effects: ["Euphoria", "Stimulation", "Compulsive redosing", "Appetite suppression", "Increased heart rate", "Vasoconstriction", "Paranoia", "Insomnia", "Anxiety"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Euphoria", description: "A strong dopaminergic pleasure rush typical of the pyrovalerone class, arriving quickly and fading rapidly, driving desire for more."),
                SubjectiveEffect(name: "Stimulation", description: "A potent surge of energy that can feel frantic and difficult to direct, creating restless body movement and racing thoughts."),
                SubjectiveEffect(name: "Compulsive Redosing", description: "A characteristic pyrovalerone-class compulsion to redose frequently, making controlled use very challenging once a session begins."),
                SubjectiveEffect(name: "Vasoconstriction", description: "A constriction of blood vessels felt as cold hands and feet, tingling, and general circulatory discomfort that worsens with repeated doses."),
                SubjectiveEffect(name: "Paranoia", description: "Escalating suspicion and anxiety that builds with continued use, potentially reaching distressing levels during extended sessions."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A complete loss of appetite that persists throughout use and lingers well into the recovery period."),
                SubjectiveEffect(name: "Anxiety", description: "A background nervousness that can spike into panic, especially during the comedown or after extended use periods."),
                SubjectiveEffect(name: "Insomnia", description: "A persistent inability to sleep that can last many hours after the last dose, compounded by residual anxiety and stimulation."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 2, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: MDPHP

        Substance(
            name: "MDPHP",
            aliases: ["3,4-Methylenedioxy-\u{03B1}-pyrrolidinohexiophenone", "3,4-MD-a-PHP"],
            category: .stimulant,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...15, common: 15...25, strong: 25...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 180, max: 360)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...10, common: 10...20, strong: 20...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 1, max: 3),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 120, max: 240)
                )),
            ],
            effects: ["Intense euphoria", "Stimulation", "Empathy enhancement", "Compulsive redosing", "Appetite suppression", "Increased heart rate", "Vasoconstriction", "Paranoia", "Insomnia", "Jaw clenching"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Intense Euphoria", description: "A powerful rush combining pyrovalerone-class dopaminergic euphoria with mild entactogenic warmth from the methylenedioxy group, creating a unique stimulant-empathogen hybrid experience."),
                SubjectiveEffect(name: "Empathy Enhancement", description: "A noticeable increase in emotional warmth and desire for connection, more pronounced than other pyrovalerones due to the MDMA-like structural component."),
                SubjectiveEffect(name: "Stimulation", description: "A strong physical and mental energy surge that drives activity and social engagement, with both stimulant push and empathogenic warmth."),
                SubjectiveEffect(name: "Compulsive Redosing", description: "A potent urge to take more as the euphoria wanes, characteristic of the pyrovalerone class and exacerbated by the entactogenic component."),
                SubjectiveEffect(name: "Jaw Clenching", description: "Involuntary tension in the jaw and facial muscles reflecting the compound's serotonergic activity from the methylenedioxy group."),
                SubjectiveEffect(name: "Vasoconstriction", description: "Constriction of blood vessels causing cold extremities and physical tension, a persistent cardiovascular side effect."),
                SubjectiveEffect(name: "Paranoia", description: "Escalating suspicion and anxiety typical of the pyrovalerone class that intensifies with extended use sessions."),
                SubjectiveEffect(name: "Crash", description: "A pronounced comedown involving both stimulant fatigue and serotonergic depletion, potentially combining the worst of both classes."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 2, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: MDPV

        Substance(
            name: "MDPV",
            aliases: ["Methylenedioxypyrovalerone", "Bath Salts", "Super Coke"],
            category: .stimulant,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 5...10, common: 10...20, strong: 20...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 180, max: 360)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 3...5, common: 5...10, strong: 10...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 1, max: 3),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 120, max: 240),
                    total: TimeRange(min: 120, max: 240)
                )),
                SubstanceRoute(route: .intravenous, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...10, strong: 10...15, heavy: 15
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 0.5),
                    comeup: TimeRange(min: 0.5, max: 1),
                    peak: TimeRange(min: 15, max: 45),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 90, max: 180)
                )),
            ],
            effects: ["Intense euphoria", "Extreme stimulation", "Compulsive redosing", "Paranoia", "Psychosis", "Tachycardia", "Hyperthermia", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Extreme Euphoria", description: "One of the most intensely euphoric stimulants known, producing a powerful dopaminergic rush that has been compared to IV cocaine but with substantially longer duration."),
                SubjectiveEffect(name: "Compulsive Redosing", description: "Perhaps the most fiendish redosing urge of any stimulant, driving users into multi-day binges with escalating doses and deteriorating mental state."),
                SubjectiveEffect(name: "Intense Stimulation", description: "An overwhelming physical and mental energy that can feel uncontrollable, with extreme restlessness, pacing, and inability to sit still."),
                SubjectiveEffect(name: "Paranoid Psychosis", description: "Rapidly escalating paranoia and persecutory delusions that can emerge even after a single extended session, with hallucinations of shadow people being commonly reported."),
                SubjectiveEffect(name: "Hyperthermia", description: "Dangerous elevation of body temperature that can reach life-threatening levels, especially during physical activity or in warm environments."),
                SubjectiveEffect(name: "Cardiovascular Crisis", description: "Severe tachycardia, hypertension, and chest pain that represent genuine medical emergencies, particularly during binge sessions."),
                SubjectiveEffect(name: "Extreme Insomnia", description: "An absolute inability to sleep that can persist for days after the last dose, often accompanied by lingering paranoia and shadow hallucinations."),
                SubjectiveEffect(name: "Aggression", description: "Unpredictable hostile and aggressive behavior that contributed to the compound's notorious reputation and widespread media coverage."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 2, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: Pyrovalerone

        Substance(
            name: "Pyrovalerone",
            aliases: ["Centroton", "Thymergix"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 5...10, common: 10...20, strong: 20...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Stimulation", "Euphoria", "Appetite suppression", "Wakefulness", "Increased heart rate", "Anxiety"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Stimulation", description: "A moderate dopaminergic stimulation that feels functional and alert, serving as the parent compound of the entire pyrovalerone class."),
                SubjectiveEffect(name: "Euphoria", description: "A mild-to-moderate mood elevation that is notably less intense than its more potent descendants like A-PVP and MDPV."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A reliable reduction in hunger that was historically its primary therapeutic application before more selective agents replaced it."),
                SubjectiveEffect(name: "Wakefulness", description: "A sustained alertness and resistance to fatigue that made it useful for narcolepsy and chronic fatigue before its withdrawal."),
                SubjectiveEffect(name: "Cardiovascular Effects", description: "Increased heart rate and blood pressure reflecting norepinephrine reuptake inhibition activity common to the class."),
                SubjectiveEffect(name: "Anxiety", description: "A dose-dependent nervousness and restlessness that can emerge at higher doses, though less severe than with more potent pyrovalerones."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 2, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: A-PBP

        Substance(
            name: "A-PBP",
            aliases: ["α-Pyrrolidinobutyrophenone", "Alpha-PBP"],
            category: .stimulant,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 20...40, common: 40...80, strong: 80...120, heavy: 120
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: nil,
                    total: TimeRange(min: 90, max: 150)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...25, common: 25...50, strong: 50...80, heavy: 80
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 1, max: 3),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 15, max: 30),
                    afterglow: nil,
                    total: TimeRange(min: 60, max: 120)
                )),
            ],
            effects: ["Stimulation", "Mild euphoria", "Short duration", "Compulsive redosing", "Appetite suppression", "Increased heart rate"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mild Euphoria", description: "A lighter rush compared to longer-chain pyrovalerones, providing stimulation with less overwhelming dopaminergic intensity."),
                SubjectiveEffect(name: "Short Duration", description: "Effects lasting only 1-2 hours that contribute to frequent redosing, as the brief window of action drives users to maintain the stimulation."),
                SubjectiveEffect(name: "Stimulation", description: "A moderate physical and mental activation that feels less potent than A-PVP but still distinctly stimulating and functional."),
                SubjectiveEffect(name: "Compulsive Redosing", description: "The short duration creates a strong cycle of redosing that can lead to consuming large total amounts over a session."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A reduction in hunger that persists through use sessions despite the short individual dose duration."),
                SubjectiveEffect(name: "Restlessness", description: "A jittery, uncomfortable physical agitation that becomes more pronounced with repeated dosing throughout a session."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 2, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 120,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: A-PPP

        Substance(
            name: "A-PPP",
            aliases: ["α-Pyrrolidinopropiophenone", "Alpha-PPP"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 20...40, common: 40...80, strong: 80...150, heavy: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 20, max: 40),
                    afterglow: nil,
                    total: TimeRange(min: 60, max: 120)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 15...30, common: 30...60, strong: 60...100, heavy: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 1, max: 3),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 10, max: 20),
                    afterglow: nil,
                    total: TimeRange(min: 45, max: 90)
                )),
            ],
            effects: ["Mild stimulation", "Slight euphoria", "Short duration", "Appetite suppression", "Restlessness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mild Stimulation", description: "The weakest of the common pyrovalerones, providing a gentle alertness and energy boost that lacks the overwhelming intensity of its longer-chain relatives."),
                SubjectiveEffect(name: "Slight Euphoria", description: "A subtle mood elevation that is barely noticeable compared to A-PVP or MDPV, making it one of the least reinforcing pyrovalerones."),
                SubjectiveEffect(name: "Short Duration", description: "A brief 1-2 hour window of effects that necessitates frequent redosing for sustained stimulation."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A mild reduction in hunger consistent with its dopaminergic mechanism of action."),
                SubjectiveEffect(name: "Restlessness", description: "A low-grade physical agitation that becomes the primary experience at higher doses as euphoria remains limited."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 2, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 90,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: A-PHiP

        Substance(
            name: "A-PHiP",
            aliases: ["α-Pyrrolidinohexanophenone", "Alpha-PHiP", "α-PHP isomer"],
            category: .stimulant,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...35, strong: 35...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 45, max: 90),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 120, max: 210)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...10, common: 10...20, strong: 20...35, heavy: 35
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 1, max: 3),
                    peak: TimeRange(min: 20, max: 45),
                    offset: TimeRange(min: 20, max: 45),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 90, max: 150)
                )),
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 5...10, common: 10...15, strong: 15...25, heavy: 25
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 1),
                    comeup: TimeRange(min: 0.5, max: 2),
                    peak: TimeRange(min: 10, max: 25),
                    offset: TimeRange(min: 15, max: 30),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 60, max: 120)
                )),
            ],
            effects: ["Intense euphoria", "Stimulation", "Compulsive redosing", "Short duration", "Appetite suppression", "Paranoia", "Vasoconstriction"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Intense Rush", description: "A powerful dopaminergic euphoria comparable to A-PHP when vaporized, with a rapid onset that produces an intensely pleasurable but fleeting rush."),
                SubjectiveEffect(name: "Compulsive Redosing", description: "An exceptionally strong drive to redose that rivals A-PVP and A-PHP, with the short duration amplifying the cycle of chasing the initial rush."),
                SubjectiveEffect(name: "Short Duration", description: "Effects lasting roughly 1-3 hours depending on route, with vaporization producing the shortest but most intense window of action."),
                SubjectiveEffect(name: "Stimulation", description: "A pronounced physical and mental activation with restlessness and increased energy that can feel overwhelming at higher doses."),
                SubjectiveEffect(name: "Paranoia", description: "Escalating suspicion and anxiety that typically emerges during extended binge sessions, characteristic of the pyrovalerone class."),
                SubjectiveEffect(name: "Vasoconstriction", description: "Cold and numb extremities from peripheral blood vessel constriction, a persistent cardiovascular side effect."),
                SubjectiveEffect(name: "Crash", description: "A sharp and uncomfortable comedown featuring exhaustion, dysphoria, and strong cravings that can persist for hours after the last dose."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 2, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 150,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: 3,4-DMMC-PVP

        Substance(
            name: "A-D2PV",
            aliases: ["α-Pyrrolidinodimethylcathinone", "A-DMVP"],
            category: .stimulant,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...35, strong: 35...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 180, max: 300)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...15, common: 15...25, strong: 25...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 1, max: 3),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 120, max: 180)
                )),
            ],
            effects: ["Euphoria", "Stimulation", "Compulsive redosing", "Vasoconstriction", "Appetite suppression", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Euphoria", description: "A moderate-to-strong dopaminergic euphoria that falls between A-PBP and A-PHP in intensity, providing a satisfying but less overwhelming rush."),
                SubjectiveEffect(name: "Stimulation", description: "A clear physical and mental activation that drives productivity and social engagement with characteristic pyrovalerone-class energy."),
                SubjectiveEffect(name: "Compulsive Redosing", description: "A persistent urge to redose as effects wane, typical of the pyrovalerone class though somewhat less extreme than with A-PVP."),
                SubjectiveEffect(name: "Vasoconstriction", description: "Peripheral blood vessel constriction causing cold extremities and physical tension, a cardiovascular effect common to all pyrovalerones."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A marked reduction in hunger that persists through the session and into the comedown period."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty initiating sleep that can persist for many hours after the last dose due to residual dopaminergic stimulation."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 2, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: 4F-A-PVP

        Substance(
            name: "4F-A-PVP",
            aliases: ["4-Fluoro-α-PVP", "4-Fluoro-α-Pyrrolidinopentiophenone", "para-Fluoro-A-PVP"],
            category: .stimulant,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...10, common: 10...20, strong: 20...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 180, max: 360)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 3...7, common: 7...15, strong: 15...25, heavy: 25
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 1, max: 3),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 120, max: 240)
                )),
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 3...5, common: 5...10, strong: 10...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 1),
                    comeup: TimeRange(min: 0.5, max: 2),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 15, max: 30),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 60, max: 120)
                )),
            ],
            effects: ["Intense euphoria", "Stimulation", "Compulsive redosing", "Paranoia", "Vasoconstriction", "Tachycardia", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Intense Euphoria", description: "A powerful rush of pleasure comparable to A-PVP, with the fluorine substitution subtly altering the character toward a slightly smoother but still intense dopaminergic high."),
                SubjectiveEffect(name: "Compulsive Redosing", description: "An extremely strong compulsion to redose that matches or exceeds A-PVP, making controlled use very difficult."),
                SubjectiveEffect(name: "Stimulation", description: "Overwhelming physical and mental energy that can feel uncontrollable at higher doses, with extreme restlessness and psychomotor agitation."),
                SubjectiveEffect(name: "Paranoia", description: "Rapidly escalating suspicion and persecutory ideation during extended sessions, potentially reaching psychotic intensity."),
                SubjectiveEffect(name: "Vasoconstriction", description: "Significant peripheral vasoconstriction causing cold, pale extremities and uncomfortable physical tension."),
                SubjectiveEffect(name: "Cardiovascular Strain", description: "Pronounced tachycardia and hypertension that represent genuine health risks, especially during binge sessions."),
                SubjectiveEffect(name: "Extended Insomnia", description: "An absolute inability to sleep lasting well beyond the primary effects, often accompanied by residual paranoia and visual disturbances."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 2, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: 4-Cl-A-PVP

        Substance(
            name: "4-Cl-A-PVP",
            aliases: ["4-Chloro-α-PVP", "4-Chloro-α-Pyrrolidinopentiophenone"],
            category: .stimulant,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...10, common: 10...20, strong: 20...35, heavy: 35
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 180, max: 360)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 3...7, common: 7...15, strong: 15...25, heavy: 25
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 1, max: 3),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 120, max: 240)
                )),
            ],
            effects: ["Euphoria", "Stimulation", "Compulsive redosing", "Paranoia", "Vasoconstriction", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Euphoria", description: "A strong dopaminergic rush similar to A-PVP but with user reports suggesting a slightly dirtier or less clean-feeling stimulation."),
                SubjectiveEffect(name: "Stimulation", description: "A powerful physical and mental activation with pronounced restlessness and psychomotor drive typical of the pyrovalerone class."),
                SubjectiveEffect(name: "Compulsive Redosing", description: "A strong drive to redose that is characteristic of the pyrovalerone class, making moderation extremely difficult once a session begins."),
                SubjectiveEffect(name: "Paranoia", description: "Escalating anxiety and paranoid ideation that can develop rapidly during binge sessions, with the chloro substitution potentially worsening this effect."),
                SubjectiveEffect(name: "Physical Side Effects", description: "Pronounced vasoconstriction, sweating, and jaw clenching that can be more uncomfortable than with unsubstituted pyrovalerones."),
                SubjectiveEffect(name: "Harsh Comedown", description: "A particularly unpleasant crash period featuring dysphoria, exhaustion, and persistent cravings for redosing."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 2, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: - Phenidate Analogues

        // MARK: Ethylphenidate

        Substance(
            name: "Ethylphenidate",
            aliases: ["EPH"],
            category: .stimulant,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 20...40, common: 40...60, strong: 60...100, heavy: 100, fatal: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 90),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 120, max: 240)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 1, max: 3),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 15, max: 30),
                    afterglow: nil,
                    total: TimeRange(min: 60, max: 120)
                )),
            ],
            effects: ["Stimulation", "Euphoria", "Focus enhancement", "Increased confidence", "Appetite suppression", "Increased heart rate", "Anxiety", "Compulsive redosing", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Euphoria", description: "A cocaine-like rush of pleasure when insufflated that arrives quickly and fades fast, creating a more recreational profile than methylphenidate."),
                SubjectiveEffect(name: "Stimulation", description: "A sharp burst of energy and mental activation that feels more recreational and pushy than its parent compound methylphenidate."),
                SubjectiveEffect(name: "Focus Enhancement", description: "An improvement in concentration that is present but often overshadowed by the more recreational euphoric effects, especially at higher doses."),
                SubjectiveEffect(name: "Confidence Enhancement", description: "An amplified self-assurance that makes social situations feel easy and empowering, similar to cocaine's confidence-boosting effects."),
                SubjectiveEffect(name: "Compulsive Redosing", description: "A notable urge to redose as the short-lived euphoria fades, more pronounced than with methylphenidate due to the quicker offset."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A marked reduction in hunger that persists through the experience and into the comedown period."),
                SubjectiveEffect(name: "Nasal Irritation", description: "Significant burning and irritation of nasal passages when insufflated, with potential for tissue damage with repeated use."),
                SubjectiveEffect(name: "Anxiety", description: "A jittery nervousness that can emerge at higher doses or during the comedown, sometimes accompanied by cardiovascular awareness."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: Isopropylphenidate

        Substance(
            name: "Isopropylphenidate",
            aliases: ["IPH", "IPPH"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 180, max: 300)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 5...15, common: 15...30, strong: 30...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 45, max: 90),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 120, max: 240)
                )),
            ],
            effects: ["Focus enhancement", "Stimulation", "Motivation enhancement", "Wakefulness", "Appetite suppression", "Increased heart rate", "Anxiety", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Focus Enhancement", description: "A clean, reliable improvement in sustained concentration that feels functional and work-oriented, often compared favorably to methylphenidate for productivity."),
                SubjectiveEffect(name: "Smooth Stimulation", description: "A gentle, consistent energy that supports mental work without the jitteriness or euphoric distraction of more recreational compounds."),
                SubjectiveEffect(name: "Motivation Enhancement", description: "A steady drive toward task completion that makes work feel purposeful and rewarding, without the compulsive quality of stronger stimulants."),
                SubjectiveEffect(name: "Wakefulness", description: "A clear-headed alertness that resists drowsiness effectively, maintaining cognitive performance over extended periods."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A moderate dampening of hunger signals that persists through the duration but is less aggressive than amphetamine-class compounds."),
                SubjectiveEffect(name: "Minimal Euphoria", description: "Very little recreational euphoria at typical doses, making it feel purely functional rather than pleasurable."),
                SubjectiveEffect(name: "Anxiety", description: "A potential for dose-dependent nervousness, especially in those sensitive to stimulants or at higher dose ranges."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty falling asleep if taken too late in the day, though typically less prolonged than amphetamine-class compounds."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 300,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: 4F-MPH

        Substance(
            name: "4F-MPH",
            aliases: ["4-Fluoromethylphenidate", "4-FMPH"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 5...10, common: 10...15, strong: 15...25, heavy: 25, fatal: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 240),
                    total: TimeRange(min: 300, max: 480)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 3...7, common: 7...12, strong: 12...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 90, max: 150),
                    afterglow: TimeRange(min: 120, max: 240),
                    total: TimeRange(min: 240, max: 420)
                )),
            ],
            effects: ["Focus enhancement", "Stimulation", "Motivation enhancement", "Wakefulness", "Appetite suppression", "Increased heart rate", "Vasoconstriction", "Anxiety", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Focus Enhancement", description: "A potent and sustained sharpening of concentration that is notably stronger mg-for-mg than methylphenidate, enabling deep work for extended periods."),
                SubjectiveEffect(name: "Stimulation", description: "A strong physical and mental activation that is more pronounced than standard methylphenidate, providing robust energy throughout the long duration."),
                SubjectiveEffect(name: "Motivation Enhancement", description: "A powerful drive toward productivity that can make even tedious tasks feel engaging and worthwhile."),
                SubjectiveEffect(name: "Wakefulness", description: "An extended period of alertness and resistance to fatigue that can persist for many hours due to the compound's high potency."),
                SubjectiveEffect(name: "Vasoconstriction", description: "A noticeable tightening of blood vessels that can cause cold extremities and physical discomfort, more prominent than with standard methylphenidate."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A strong and long-lasting reduction in hunger that can make it difficult to eat even when trying to."),
                SubjectiveEffect(name: "Anxiety", description: "A dose-dependent nervousness with physical tension that can become uncomfortable, especially given the compound's high potency."),
                SubjectiveEffect(name: "Prolonged Insomnia", description: "An extended inability to sleep that can last well over 12 hours from the time of dosing due to the long duration of action."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 420,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: 3,4-CTMP

        Substance(
            name: "3,4-CTMP",
            aliases: ["3,4-Dichloromethylphenidate"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...4, common: 4...6, strong: 6...10, heavy: 10
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: TimeRange(min: 240, max: 480),
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Focus enhancement", "Stimulation", "Wakefulness", "Motivation enhancement", "Appetite suppression", "Increased heart rate", "Anxiety", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Focus Enhancement", description: "A very strong improvement in concentration that persists for an extremely long duration, reflecting the compound's potent and long-lasting DAT inhibition."),
                SubjectiveEffect(name: "Stimulation", description: "A notable physical and mental activation that can feel intense and difficult to modulate due to the compound's high potency."),
                SubjectiveEffect(name: "Wakefulness", description: "An exceptionally prolonged alertness that can keep users awake for 24 hours or more from a single dose."),
                SubjectiveEffect(name: "Motivation Enhancement", description: "A persistent drive to be productive that can extend far beyond what is comfortable, continuing even when rest is needed."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A profound loss of appetite persisting for the full extremely long duration, requiring conscious effort to eat."),
                SubjectiveEffect(name: "Anxiety", description: "A significant potential for anxiety that can feel inescapable due to the compound's extended duration with no way to shorten the experience."),
                SubjectiveEffect(name: "Extreme Duration", description: "Effects lasting 12-24+ hours from a single dose, which users frequently report as uncomfortably long and difficult to manage."),
                SubjectiveEffect(name: "Insomnia", description: "An inability to sleep that can persist for an entire day or longer, making timing critical and overdosing particularly dangerous."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 720,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: HDMP-28

        Substance(
            name: "HDMP-28",
            aliases: ["Methylnaphthidate"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 5...10, common: 10...20, strong: 20...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 90, max: 150),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 300, max: 480)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 3...7, common: 7...15, strong: 15...25, heavy: 25
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 240, max: 420)
                )),
            ],
            effects: ["Focus enhancement", "Stimulation", "Motivation enhancement", "Euphoria", "Wakefulness", "Appetite suppression", "Increased heart rate", "Anxiety", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Focus Enhancement", description: "A pronounced improvement in sustained attention and task engagement, reported as more potent than standard methylphenidate with a smoother character."),
                SubjectiveEffect(name: "Euphoria", description: "A mild to moderate mood elevation that provides a pleasant backdrop to the functional stimulant effects, more recreational than isopropylphenidate."),
                SubjectiveEffect(name: "Stimulation", description: "A robust physical and mental energy boost that supports extended work or activity, with moderate peripheral stimulation."),
                SubjectiveEffect(name: "Motivation Enhancement", description: "A strong drive toward productivity and task completion that makes work feel inherently rewarding and engaging."),
                SubjectiveEffect(name: "Wakefulness", description: "A sustained resistance to drowsiness that maintains cognitive sharpness well beyond normal waking hours."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A significant dampening of hunger signals throughout the duration, requiring deliberate effort to maintain normal eating patterns."),
                SubjectiveEffect(name: "Anxiety", description: "A potential for dose-dependent nervousness and physical tension, particularly noticeable at higher doses or during the comedown."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty falling asleep that can extend for hours beyond the perceived end of primary effects."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 360,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: - Other RC Stimulants

        // MARK: Methiopropamine

        Substance(
            name: "Methiopropamine",
            aliases: ["MPA"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 15...30, common: 30...50, strong: 50...70, heavy: 70
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 180, max: 300)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...35, strong: 35...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 3, max: 10),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 30, max: 60),
                    total: TimeRange(min: 90, max: 180)
                )),
            ],
            effects: ["Stimulation", "Focus enhancement", "Wakefulness", "Appetite suppression", "Increased heart rate", "Vasoconstriction", "Anxiety", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Stimulation", description: "A methamphetamine-like stimulation that feels sharp and pushy, providing significant physical and mental energy with a somewhat rough character."),
                SubjectiveEffect(name: "Focus Enhancement", description: "An improvement in concentration and task engagement, though less refined than dedicated functional stimulants like 2-FMA."),
                SubjectiveEffect(name: "Wakefulness", description: "A sustained alertness that effectively prevents sleep and maintains awareness throughout the duration."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A reliable reduction in hunger that persists throughout the experience and lingers afterward."),
                SubjectiveEffect(name: "Vasoconstriction", description: "A noticeable constriction of blood vessels causing cold extremities and potential physical discomfort."),
                SubjectiveEffect(name: "Anxiety", description: "A jittery, nervous energy that can be more pronounced than with other stimulants, reflecting the compound's somewhat harsh pharmacological profile."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty falling asleep that persists for hours after the primary effects subside."),
                SubjectiveEffect(name: "Rough Body Load", description: "A physical heaviness and tension that many users report as less comfortable than smoother stimulant compounds."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 240,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: N-Ethyl-Pentylone

        Substance(
            name: "N-Ethyl-Pentylone",
            aliases: ["Ephylone", "bk-EBDP", "BK-EBDP"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 75...125, common: 125...200, strong: 200...300, heavy: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 25),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 240, max: 420)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...80, common: 80...150, strong: 150...225, heavy: 225
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 45, max: 90),
                    afterglow: TimeRange(min: 120, max: 300),
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Euphoria", "Stimulation", "Empathy enhancement", "Sociability enhancement", "Compulsive redosing", "Jaw clenching", "Appetite suppression", "Increased heart rate", "Insomnia", "Anxiety"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Euphoria", description: "A strong serotonergic euphoria with MDMA-like qualities, providing warm emotional pleasure and a sense of profound well-being."),
                SubjectiveEffect(name: "Empathy Enhancement", description: "A significant increase in emotional warmth, compassion, and desire for connection, making it feel like a cathinone-class empathogen."),
                SubjectiveEffect(name: "Sociability Enhancement", description: "A strong drive to communicate and connect with others, with reduced inhibitions and enhanced conversational flow."),
                SubjectiveEffect(name: "Stimulation", description: "A moderate to strong physical energy that supports dancing and social activity without feeling overly pushy or manic."),
                SubjectiveEffect(name: "Compulsive Redosing", description: "A notable urge to take more as the empathogenic warmth fades, which can lead to extended sessions and serotonergic depletion."),
                SubjectiveEffect(name: "Jaw Clenching", description: "Persistent involuntary jaw tension and teeth grinding reflecting substantial serotonin release activity."),
                SubjectiveEffect(name: "Insomnia", description: "A difficulty falling asleep that can persist for hours after the emotional effects have subsided, driven by residual stimulation."),
                SubjectiveEffect(name: "Serotonergic Comedown", description: "A potentially severe multi-day period of emotional flatness, depression, and fatigue following use, reflecting significant serotonin depletion."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 300,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: 3-FPM

        Substance(
            name: "3-FPM",
            aliases: ["3-Fluorophenmetrazine", "PAL-593"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 15...30, common: 30...50, strong: 50...80, heavy: 80, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 10, max: 25),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 300, max: 480)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 60, max: 150),
                    offset: TimeRange(min: 45, max: 90),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 210, max: 390)
                )),
            ],
            effects: ["Stimulation", "Euphoria", "Focus enhancement", "Sociability enhancement", "Mood lift", "Appetite suppression", "Increased heart rate", "Anxiety", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Euphoria", description: "A smooth, moderate mood elevation that combines stimulant energy with a warm, sociable quality, less intense but more rounded than amphetamine."),
                SubjectiveEffect(name: "Stimulation", description: "A balanced physical and mental energy boost that feels cleaner and less jittery than many cathinones, with a moderate duration."),
                SubjectiveEffect(name: "Focus Enhancement", description: "An improvement in concentration and task engagement that supports both work and social activities without feeling overly narrow."),
                SubjectiveEffect(name: "Sociability Enhancement", description: "An increased desire to talk and interact socially, with enhanced conversational ease and reduced self-consciousness."),
                SubjectiveEffect(name: "Mood Lift", description: "A reliable elevation of baseline mood that creates a sense of optimism and contentment without overwhelming euphoria."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A moderate reduction in hunger that persists through the experience but is less aggressive than amphetamine-class compounds."),
                SubjectiveEffect(name: "Anxiety", description: "A potential for nervousness, particularly at higher doses, though generally considered less anxiety-inducing than many stimulants."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty initiating sleep if taken later in the day, though the moderate duration makes timing somewhat manageable."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 360,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: 2-DPMP

        Substance(
            name: "2-DPMP",
            aliases: ["Desoxypipradrol", "2-Diphenylmethylpiperidine"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 1...2, common: 2...4, strong: 4...6, heavy: 6, fatal: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 360, max: 720),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: TimeRange(min: 480, max: 1440),
                    total: TimeRange(min: 1440, max: 4320)
                )),
            ],
            effects: ["Stimulation", "Focus enhancement", "Wakefulness", "Extreme duration", "Appetite suppression", "Increased heart rate", "Insomnia", "Anxiety", "Paranoia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Extreme Duration", description: "Effects lasting 24-72+ hours from a single dose, making this one of the longest-acting stimulants known and extremely difficult to manage safely."),
                SubjectiveEffect(name: "Stimulation", description: "A potent and relentless physical and mental activation that persists far beyond what is comfortable, impossible to turn off once initiated."),
                SubjectiveEffect(name: "Focus Enhancement", description: "An intense concentration that becomes obsessive over the extremely long duration, transitioning from productive to distressing."),
                SubjectiveEffect(name: "Wakefulness", description: "A forced wakefulness lasting days that prevents any possibility of sleep, leading to significant cognitive and physical deterioration."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A complete elimination of hunger for the entire multi-day duration, posing serious risks of dehydration and malnutrition."),
                SubjectiveEffect(name: "Paranoia", description: "Severe paranoid thinking that commonly develops during the extended duration, exacerbated by forced sleep deprivation."),
                SubjectiveEffect(name: "Anxiety", description: "An escalating, inescapable anxiety that builds throughout the extremely long experience, with no option to end the effects."),
                SubjectiveEffect(name: "Psychosis Risk", description: "A high risk of stimulant psychosis due to the forced multi-day wakefulness, with hallucinations and delusions reported at standard doses."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 960,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: Modafiendz

        Substance(
            name: "Modafiendz",
            aliases: ["Diphenylprolinol", "D2PM"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 20...40, common: 40...80, strong: 80...120, heavy: 120
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 480, max: 960)
                )),
            ],
            effects: ["Stimulation", "Wakefulness", "Focus enhancement", "Appetite suppression", "Increased heart rate", "Anxiety", "Insomnia", "Nausea"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Stimulation", description: "A moderate stimulant effect that provides energy and alertness, though users commonly report it as less clean-feeling than other options."),
                SubjectiveEffect(name: "Wakefulness", description: "An extended period of alertness and resistance to sleep that can persist well beyond the desired window of activity."),
                SubjectiveEffect(name: "Focus Enhancement", description: "A modest improvement in concentration that may support task engagement but is generally considered unremarkable compared to dedicated focus aids."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A reduction in hunger signals throughout the experience, consistent with other stimulant compounds."),
                SubjectiveEffect(name: "Nausea", description: "A stomach discomfort and queasiness that many users report, particularly during the onset phase or at higher doses."),
                SubjectiveEffect(name: "Anxiety", description: "A potential for uncomfortable nervousness and restlessness that can become the dominant experience at higher doses."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty sleeping that can persist for an extended period, reflecting the compound's long duration of action."),
                SubjectiveEffect(name: "Headache", description: "A vasoconstriction-related headache that some users report, particularly during the comedown phase."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 720,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: Eutylone

        Substance(
            name: "Eutylone",
            aliases: ["bk-EBDB", "EU"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...350, heavy: 350
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 25),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 240, max: 420)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 15, light: 30...75, common: 75...150, strong: 150...250, heavy: 250
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 45, max: 90),
                    afterglow: TimeRange(min: 120, max: 300),
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Euphoria", "Stimulation", "Empathogenic effects", "Compulsive redosing", "Insomnia", "Comedown", "Jaw clenching", "Increased heart rate"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Euphoria", description: "A warm, serotonergic euphoria with MDMA-like qualities that can feel deeply pleasurable, though often described as less refined and more stimulating than MDMA itself."),
                SubjectiveEffect(name: "Stimulation", description: "A pronounced physical and mental energy boost that drives activity and social engagement, with a pushy, restless quality at higher doses."),
                SubjectiveEffect(name: "Empathogenic warmth", description: "An increase in emotional openness and desire for connection that mimics MDMA's entactogenic effects, though typically with less depth and more stimulant edge."),
                SubjectiveEffect(name: "Compulsive redosing", description: "A strong and persistent urge to take additional doses as effects wane, making binge sessions common and contributing to significant serotonergic depletion."),
                SubjectiveEffect(name: "Jaw clenching and bruxism", description: "Involuntary tightening and grinding of jaw muscles reflecting the compound's serotonin-releasing activity, often uncomfortable and persistent."),
                SubjectiveEffect(name: "Insomnia", description: "A stubborn inability to sleep that can persist for many hours after the last dose, often accompanied by residual stimulation and racing thoughts."),
                SubjectiveEffect(name: "Severe comedown", description: "A potentially harsh period of depression, emotional flatness, and exhaustion that can last several days, reflecting depletion of serotonin and dopamine."),
                SubjectiveEffect(name: "Appetite suppression", description: "A complete loss of interest in food that spans the entire session and often extends well into the recovery period."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 300,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA", "PubMed"]
        ),

        // MARK: Diethylpropion

        Substance(
            name: "Diethylpropion",
            aliases: ["Amfepramone", "Tenuate"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 12.5, light: 25...50, common: 50...75, strong: 75...100, heavy: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Appetite suppression", "Mild stimulation", "Restlessness", "Dry mouth", "Insomnia", "Increased heart rate"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Appetite suppression", description: "The primary therapeutic effect, a reliable and significant reduction in hunger signals that was historically prescribed for weight management."),
                SubjectiveEffect(name: "Mild stimulation", description: "A gentle increase in energy and alertness that feels subtle and functional, lacking the intense euphoria of stronger amphetamine-class compounds."),
                SubjectiveEffect(name: "Restlessness", description: "A low-grade physical agitation and inability to sit still that can become noticeable and uncomfortable at higher doses."),
                SubjectiveEffect(name: "Dry mouth", description: "A persistent reduction in salivation that is common across the stimulant class and can become bothersome during extended use."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty initiating sleep if taken later in the day, requiring careful timing to avoid disrupting normal sleep patterns."),
                SubjectiveEffect(name: "Mild mood elevation", description: "A subtle improvement in baseline mood and motivation that feels natural rather than euphoric, contributing to its low abuse potential."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 10, buildRate: "rapid"),
            halfLifeMinutes: 240,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: Benzphetamine

        Substance(
            name: "Benzphetamine",
            aliases: ["Didrex"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 12.5, light: 25...50, common: 50...100, strong: 100...150, heavy: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 360, max: 540)
                )),
            ],
            effects: ["Appetite suppression", "Stimulation", "Mild euphoria", "Insomnia", "Dry mouth", "Increased heart rate"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Appetite suppression", description: "A pronounced reduction in hunger that serves as the compound's primary therapeutic effect, historically prescribed for short-term weight loss management."),
                SubjectiveEffect(name: "Stimulation", description: "A moderate increase in physical and mental energy that feels more noticeable than diethylpropion but less intense than amphetamine, as benzphetamine is a prodrug that metabolizes to methamphetamine and amphetamine."),
                SubjectiveEffect(name: "Mild euphoria", description: "A gentle mood elevation and sense of well-being that can feel pleasantly motivating without the intense rush of direct-acting amphetamines."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty falling asleep that can persist if taken too late in the day, requiring morning or early afternoon dosing for best results."),
                SubjectiveEffect(name: "Dry mouth", description: "A common anticholinergic-like side effect causing reduced salivation and oral discomfort throughout the duration."),
                SubjectiveEffect(name: "Increased heart rate", description: "A noticeable cardiovascular stimulation that reflects the compound's sympathomimetic activity, requiring caution in those with heart conditions."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 360,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),
    ]
}
