import Foundation

extension SubstanceLibrary {
    static let antipsychotics: [Substance] = [

        // MARK: - Second-Generation (Atypical) Antipsychotics

        Substance(
            name: "Quetiapine",
            aliases: ["Seroquel"],
            category: .antipsychotic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 12.5, light: 25...50, common: 50...300, strong: 300...800, heavy: 800, fatal: 10000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 720)
                )),
            ],
            effects: ["Sedation", "Drowsiness", "Reduced psychotic symptoms", "Weight gain", "Dry mouth", "Dizziness", "Metabolic changes", "Emotional blunting"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Heavy Sedation", description: "A powerful drowsiness and mental heaviness that comes on within an hour and can persist well into the next day."),
                SubjectiveEffect(name: "Emotional Blunting", description: "A significant muting of emotions where both positive and negative feelings feel distant and muffled."),
                SubjectiveEffect(name: "Anxiolysis", description: "A strong calming of anxiety and racing thoughts, often experienced as a quieting of mental noise."),
                SubjectiveEffect(name: "Cognitive Dulling", description: "A slowing of thought processes and difficulty with concentration and mental sharpness."),
                SubjectiveEffect(name: "Weight Gain", description: "An increase in appetite, particularly for carbohydrates, that can lead to significant weight gain over months."),
                SubjectiveEffect(name: "Dry Mouth", description: "A persistent cottony dryness in the mouth that develops early in treatment."),
                SubjectiveEffect(name: "Thought Quieting", description: "A reduction in intrusive, paranoid, or delusional thoughts that gradually fades psychotic content from awareness."),
                SubjectiveEffect(name: "Morning Grogginess", description: "A hangover-like heaviness upon waking that can take hours to fully dissipate."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 390
        ),

        Substance(
            name: "Olanzapine",
            aliases: ["Zyprexa"],
            category: .antipsychotic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1.25, light: 2.5...5, common: 5...15, strong: 15...20, heavy: 20, fatal: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Sedation", "Weight gain", "Reduced psychotic symptoms", "Increased appetite", "Drowsiness", "Metabolic changes", "Dry mouth", "Emotional blunting"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Deep Sedation", description: "An overwhelming drowsiness that can feel like being pulled into sleep, particularly pronounced in the first weeks."),
                SubjectiveEffect(name: "Insatiable Appetite", description: "A powerful, sometimes uncontrollable hunger that can lead to rapid and significant weight gain."),
                SubjectiveEffect(name: "Emotional Flattening", description: "A pronounced emotional numbness where patients report feeling like a 'zombie' or completely detached from feelings."),
                SubjectiveEffect(name: "Thought Quieting", description: "A significant reduction in psychotic ideation, racing thoughts, and paranoid thinking over weeks."),
                SubjectiveEffect(name: "Metabolic Changes", description: "Increased blood sugar and lipid levels that may not be subjectively felt but contribute to long-term health risks."),
                SubjectiveEffect(name: "Cognitive Dulling", description: "A heavy mental fog with difficulty thinking clearly, remembering details, or maintaining focus."),
                SubjectiveEffect(name: "Dry Mouth", description: "Persistent oral dryness that accompanies the sedating and anticholinergic effects."),
                SubjectiveEffect(name: "Mood Stabilization", description: "A leveling of mood extremes, particularly helpful in bipolar mania, that develops over days to weeks."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 1800
        ),

        Substance(
            name: "Risperidone",
            aliases: ["Risperdal"],
            category: .antipsychotic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1, common: 1...4, strong: 4...8, heavy: 8, fatal: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Reduced psychotic symptoms", "Akathisia", "Drowsiness", "Weight gain", "Elevated prolactin", "Dizziness", "Emotional blunting", "Fatigue"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Thought Quieting", description: "A gradual reduction in psychotic content, paranoid ideation, and hallucinations over days to weeks."),
                SubjectiveEffect(name: "Akathisia", description: "An intensely uncomfortable inner restlessness and urge to move that can feel like crawling out of one's skin."),
                SubjectiveEffect(name: "Emotional Blunting", description: "A significant flattening of emotional experience, with both pleasure and distress feeling remote."),
                SubjectiveEffect(name: "Drowsiness", description: "A persistent sleepiness that can interfere with daily functioning and concentration."),
                SubjectiveEffect(name: "Hormonal Changes", description: "Elevated prolactin levels that can cause breast tenderness, menstrual changes, or sexual dysfunction."),
                SubjectiveEffect(name: "Weight Gain", description: "A moderate increase in appetite and body weight that develops over weeks of treatment."),
                SubjectiveEffect(name: "Cognitive Dulling", description: "A slowing of mental processing that makes complex tasks and conversations more difficult."),
                SubjectiveEffect(name: "Fatigue", description: "A persistent low energy and tiredness that goes beyond simple drowsiness."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 360
        ),

        Substance(
            name: "Aripiprazole",
            aliases: ["Abilify"],
            category: .antipsychotic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...15, strong: 15...30, heavy: 30, fatal: 3000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 360, max: 720),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: ["Reduced psychotic symptoms", "Akathisia", "Restlessness", "Insomnia", "Nausea", "Anxiety reduction", "Emotional stabilization", "Dizziness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Akathisia", description: "An intense, uncomfortable inner restlessness and compulsive need to move that is one of the most common complaints."),
                SubjectiveEffect(name: "Thought Quieting", description: "A reduction in psychotic thinking and paranoid ideation without the heavy sedation of other antipsychotics."),
                SubjectiveEffect(name: "Emotional Stabilization", description: "A balancing of mood extremes due to partial dopamine agonism, often with preserved emotional range."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty sleeping that is more common than with sedating antipsychotics, sometimes requiring adjunctive treatment."),
                SubjectiveEffect(name: "Activation", description: "A mildly stimulating quality that can feel energizing or anxiety-provoking depending on the individual."),
                SubjectiveEffect(name: "Less Emotional Blunting", description: "A relative preservation of emotional range compared to more sedating antipsychotics, though some flattening may occur."),
                SubjectiveEffect(name: "Nausea", description: "Stomach discomfort that typically occurs during the initial dose titration period."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 45, buildRate: "slow"),
            halfLifeMinutes: 4500
        ),

        Substance(
            name: "Haloperidol",
            aliases: ["Haldol"],
            category: .antipsychotic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...2, common: 2...10, strong: 10...20, heavy: 20, fatal: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
                SubstanceRoute(route: .intramuscular, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 1...2.5, common: 2.5...5, strong: 5...10, heavy: 10
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 20),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 720)
                )),
            ],
            effects: ["Reduced psychotic symptoms", "Sedation", "Akathisia", "Muscle stiffness", "Emotional blunting", "Restlessness", "Dry mouth", "Drowsiness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Profound Thought Quieting", description: "A powerful suppression of psychotic content and agitated thinking that can be felt within hours of dosing."),
                SubjectiveEffect(name: "Muscle Rigidity", description: "A stiffness and tightness in muscles, particularly the jaw, neck, and limbs, that can be uncomfortable and persistent."),
                SubjectiveEffect(name: "Akathisia", description: "An unbearable inner restlessness and compulsive need to pace or shift position that is a hallmark side effect."),
                SubjectiveEffect(name: "Emotional Flattening", description: "A stark emptying of emotional experience, often described as feeling robotic or completely hollow inside."),
                SubjectiveEffect(name: "Sedation", description: "A heavy sedation that can be useful for acute agitation but impairing for daily life."),
                SubjectiveEffect(name: "Cognitive Slowing", description: "A pronounced difficulty with thinking speed, concentration, and mental flexibility."),
                SubjectiveEffect(name: "Dry Mouth", description: "Persistent oral dryness from anticholinergic activity."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 1440
        ),

        Substance(
            name: "Chlorpromazine",
            aliases: ["Thorazine"],
            category: .antipsychotic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 25...50, common: 50...200, strong: 200...800, heavy: 800, fatal: 5000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Sedation", "Reduced psychotic symptoms", "Drowsiness", "Dry mouth", "Dizziness", "Photosensitivity", "Emotional blunting", "Weight gain"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Heavy Sedation", description: "An intense, enveloping drowsiness that can make it difficult to stay awake or engaged in activities."),
                SubjectiveEffect(name: "Thought Quieting", description: "A significant reduction in psychotic symptoms and agitation, historically the first antipsychotic's characteristic effect."),
                SubjectiveEffect(name: "Emotional Blunting", description: "A dulling of emotional responses that can feel like an emotional anesthesia."),
                SubjectiveEffect(name: "Photosensitivity", description: "Increased sensitivity to sunlight resulting in easy sunburning and skin reactions."),
                SubjectiveEffect(name: "Dizziness", description: "Pronounced lightheadedness, particularly upon standing, due to blood pressure lowering."),
                SubjectiveEffect(name: "Weight Gain", description: "A gradual increase in appetite and body weight over the course of treatment."),
                SubjectiveEffect(name: "Dry Mouth", description: "Persistent oral dryness from anticholinergic effects."),
                SubjectiveEffect(name: "Cognitive Slowing", description: "A noticeable reduction in mental speed and processing ability."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 1380
        ),

        Substance(
            name: "Clozapine",
            aliases: ["Clozaril"],
            category: .antipsychotic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 6.25, light: 12.5...25, common: 25...300, strong: 300...900, heavy: 900, fatal: 2500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Sedation", "Reduced psychotic symptoms", "Weight gain", "Increased salivation", "Drowsiness", "Metabolic changes", "Dizziness", "Decreased suicidal ideation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Profound Thought Clearing", description: "A powerful reduction in treatment-resistant psychotic symptoms that can feel like emerging from a long nightmare."),
                SubjectiveEffect(name: "Sedation", description: "A deep drowsiness particularly in the initial weeks, often requiring gradual dose titration."),
                SubjectiveEffect(name: "Excessive Salivation", description: "An unusual and distinctive drooling, especially during sleep, that is unique to clozapine."),
                SubjectiveEffect(name: "Weight Gain", description: "Significant increases in appetite and body weight, often among the most substantial of all antipsychotics."),
                SubjectiveEffect(name: "Reduced Suicidal Thinking", description: "A notable reduction in suicidal ideation and self-harm urges that is clinically unique to this medication."),
                SubjectiveEffect(name: "Emotional Preservation", description: "A relative preservation of emotional warmth and social engagement compared to typical antipsychotics."),
                SubjectiveEffect(name: "Dizziness", description: "Lightheadedness and orthostatic effects, particularly during dose escalation."),
                SubjectiveEffect(name: "Metabolic Effects", description: "Changes in blood sugar and lipid levels that contribute to long-term metabolic health concerns."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 720
        ),

        Substance(
            name: "Ziprasidone",
            aliases: ["Geodon"],
            category: .antipsychotic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 20...40, common: 40...80, strong: 80...160, heavy: 160, fatal: 5000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Reduced psychotic symptoms", "Drowsiness", "Nausea", "Dizziness", "Akathisia", "Emotional blunting", "Restlessness", "Lightheadedness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Thought Quieting", description: "A reduction in psychotic ideation and disorganized thinking that develops over days to weeks."),
                SubjectiveEffect(name: "Akathisia", description: "An uncomfortable inner restlessness and need to keep moving that can be distressing."),
                SubjectiveEffect(name: "Weight Neutrality", description: "Notably less appetite stimulation and weight gain compared to most other atypical antipsychotics."),
                SubjectiveEffect(name: "Drowsiness", description: "Mild to moderate sleepiness that tends to be less intense than with quetiapine or olanzapine."),
                SubjectiveEffect(name: "Nausea", description: "Stomach discomfort that can occur during dose initiation and usually resolves."),
                SubjectiveEffect(name: "Emotional Blunting", description: "Some muting of emotional range, though often less pronounced than with higher-potency agents."),
                SubjectiveEffect(name: "Lightheadedness", description: "Dizziness and feeling faint, particularly when standing up or after meals."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 420
        ),

        Substance(
            name: "Paliperidone",
            aliases: ["Invega"],
            category: .antipsychotic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 1.5...3, common: 3...6, strong: 6...12, heavy: 12
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Reduced psychotic symptoms", "Akathisia", "Weight gain", "Elevated prolactin", "Drowsiness", "Emotional blunting", "Dizziness", "Fatigue"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Thought Quieting", description: "A steady reduction in psychotic symptoms similar to risperidone, as it is the active metabolite."),
                SubjectiveEffect(name: "Akathisia", description: "An uncomfortable restlessness and compulsive urge to move that can be distressing."),
                SubjectiveEffect(name: "Hormonal Changes", description: "Elevated prolactin that may cause breast tenderness, menstrual irregularities, or sexual dysfunction."),
                SubjectiveEffect(name: "Emotional Blunting", description: "A flattening of emotional experience that can make life feel monotone."),
                SubjectiveEffect(name: "Drowsiness", description: "A persistent sleepiness that can impair concentration and daily functioning."),
                SubjectiveEffect(name: "Weight Gain", description: "An increase in appetite and body weight that develops over weeks to months."),
                SubjectiveEffect(name: "Fatigue", description: "A persistent tiredness and low energy that goes beyond simple drowsiness."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 1260
        ),

        Substance(
            name: "Brexpiprazole",
            aliases: ["Rexulti"],
            category: .antipsychotic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...1, common: 1...2, strong: 2...4, heavy: 4
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 360, max: 720),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: ["Reduced psychotic symptoms", "Weight gain", "Akathisia", "Drowsiness", "Emotional stabilization", "Dizziness", "Restlessness", "Fatigue"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Emotional Stabilization", description: "A subtle balancing of mood and emotional reactivity similar to aripiprazole but often perceived as gentler."),
                SubjectiveEffect(name: "Thought Quieting", description: "A gradual reduction in psychotic symptoms with less sedation than many other antipsychotics."),
                SubjectiveEffect(name: "Akathisia", description: "An inner restlessness that is less common than with aripiprazole but still a notable concern."),
                SubjectiveEffect(name: "Drowsiness", description: "Mild to moderate sleepiness that tends to be less intense than with more sedating antipsychotics."),
                SubjectiveEffect(name: "Weight Gain", description: "Moderate weight gain that develops gradually over treatment."),
                SubjectiveEffect(name: "Preserved Cognition", description: "A relative preservation of cognitive function and mental clarity compared to sedating antipsychotics."),
                SubjectiveEffect(name: "Fatigue", description: "A low-grade tiredness that some patients experience alongside treatment."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 45, buildRate: "slow"),
            halfLifeMinutes: 5580
        ),

        Substance(
            name: "Cariprazine",
            aliases: ["Vraylar"],
            category: .antipsychotic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 1...1.5, common: 1.5...3, strong: 3...6, heavy: 6
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 360, max: 720),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: ["Reduced psychotic symptoms", "Akathisia", "Restlessness", "Insomnia", "Nausea", "Emotional stabilization", "Dizziness", "Fatigue"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Emotional Stabilization", description: "A balancing of mood with particular efficacy for bipolar depression and negative symptoms."),
                SubjectiveEffect(name: "Akathisia", description: "An uncomfortable inner restlessness that is a notable side effect of this dopamine partial agonist."),
                SubjectiveEffect(name: "Thought Quieting", description: "A reduction in psychotic thinking with a quality of mental clarity rather than sedation."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty sleeping that reflects the activating nature of this medication."),
                SubjectiveEffect(name: "Restlessness", description: "A motor agitation and inability to sit still that some patients find very distressing."),
                SubjectiveEffect(name: "Nausea", description: "Stomach discomfort during dose initiation that usually resolves within weeks."),
                SubjectiveEffect(name: "Improved Motivation", description: "A subtle increase in drive and engagement that may emerge as negative symptoms improve."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 45, buildRate: "slow"),
            halfLifeMinutes: 4320
        ),

        Substance(
            name: "Lurasidone",
            aliases: ["Latuda"],
            category: .antipsychotic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 20...40, common: 40...80, strong: 80...160, heavy: 160
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Reduced psychotic symptoms", "Akathisia", "Nausea", "Drowsiness", "Emotional stabilization", "Dizziness", "Restlessness", "Fatigue"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Thought Quieting", description: "A gradual clearing of psychotic symptoms with relatively less sedation than older antipsychotics."),
                SubjectiveEffect(name: "Mood Stabilization", description: "A balancing effect on bipolar depression that develops over several weeks with preserved emotional range."),
                SubjectiveEffect(name: "Akathisia", description: "A restless, uncomfortable urge to move that is a common side effect."),
                SubjectiveEffect(name: "Drowsiness", description: "Mild to moderate sleepiness, though generally less intense than with quetiapine or olanzapine."),
                SubjectiveEffect(name: "Weight Neutrality", description: "Less appetite stimulation and weight gain than many other atypical antipsychotics."),
                SubjectiveEffect(name: "Nausea", description: "Stomach discomfort, particularly when not taken with food as the medication requires."),
                SubjectiveEffect(name: "Cognitive Preservation", description: "A relative maintenance of cognitive function and mental clarity during treatment."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 1080
        ),

        Substance(
            name: "Asenapine",
            aliases: ["Saphris"],
            category: .antipsychotic,
            defaultRoute: .sublingual,
            routes: [
                SubstanceRoute(route: .sublingual, unit: "mg", doses: DoseRange(
                    threshold: 1.25, light: 2.5...5, common: 5...10, strong: 10...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 960)
                )),
            ],
            effects: ["Reduced psychotic symptoms", "Sedation", "Drowsiness", "Oral numbness", "Weight gain", "Dizziness", "Akathisia", "Emotional blunting"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Oral Numbness", description: "A distinctive tingling and numbness of the tongue and mouth from sublingual administration that lasts 10-20 minutes."),
                SubjectiveEffect(name: "Sedation", description: "A moderate to heavy drowsiness that develops shortly after dosing."),
                SubjectiveEffect(name: "Thought Quieting", description: "A reduction in psychotic symptoms and disorganized thinking over days to weeks."),
                SubjectiveEffect(name: "Emotional Blunting", description: "A dulling of emotional responses that can make life feel less vivid."),
                SubjectiveEffect(name: "Weight Gain", description: "A moderate increase in appetite and body weight during treatment."),
                SubjectiveEffect(name: "Akathisia", description: "An inner restlessness and compulsive urge to move, though less common than with some other agents."),
                SubjectiveEffect(name: "Dizziness", description: "Lightheadedness and unsteadiness, particularly upon standing."),
                SubjectiveEffect(name: "Taste Alteration", description: "The sublingual tablet can leave a bitter or unpleasant taste that lingers after dissolution."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 1440
        ),

        Substance(
            name: "Iloperidone",
            aliases: ["Fanapt"],
            category: .antipsychotic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...6, common: 6...12, strong: 12...24, heavy: 24
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Reduced psychotic symptoms", "Dizziness", "Drowsiness", "Dry mouth", "Weight gain", "Fatigue", "Orthostatic hypotension", "Emotional blunting"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Thought Quieting", description: "A gradual reduction in psychotic symptoms that develops slowly due to slow dose titration requirements."),
                SubjectiveEffect(name: "Orthostatic Dizziness", description: "Pronounced lightheadedness upon standing that requires careful slow positional changes."),
                SubjectiveEffect(name: "Drowsiness", description: "A moderate sleepiness that tends to be manageable but can interfere with daily activities."),
                SubjectiveEffect(name: "Emotional Blunting", description: "A flattening of emotional range that can develop gradually over weeks of treatment."),
                SubjectiveEffect(name: "Weight Gain", description: "A moderate increase in body weight driven by appetite changes."),
                SubjectiveEffect(name: "Dry Mouth", description: "Persistent oral dryness from anticholinergic activity."),
                SubjectiveEffect(name: "Fatigue", description: "A general tiredness and reduced energy that persists throughout treatment."),
                SubjectiveEffect(name: "Low Akathisia Risk", description: "Notably less inner restlessness compared to many other antipsychotics, which patients find a significant relief."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 1080
        ),

        // MARK: - First-Generation (Typical) Antipsychotics

        Substance(
            name: "Pimozide",
            aliases: ["Orap"],
            category: .antipsychotic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 1...2, common: 2...6, strong: 6...10, heavy: 10, fatal: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Reduced psychotic symptoms", "Sedation", "Muscle stiffness", "Akathisia", "Dry mouth", "Emotional blunting", "Drowsiness", "Constipation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Thought Suppression", description: "A potent silencing of psychotic content and tic-related urges that develops over days to weeks."),
                SubjectiveEffect(name: "Muscle Rigidity", description: "A stiffness and tightness in muscles that can affect movement and facial expression."),
                SubjectiveEffect(name: "Akathisia", description: "An intense inner restlessness and compulsive need to move that can be extremely distressing."),
                SubjectiveEffect(name: "Emotional Flattening", description: "A marked reduction in emotional experience that can feel like emotional anesthesia."),
                SubjectiveEffect(name: "Sedation", description: "A heavy drowsiness that can impair functioning but may reduce agitation."),
                SubjectiveEffect(name: "Constipation", description: "Slowed bowel function from anticholinergic effects."),
                SubjectiveEffect(name: "Dry Mouth", description: "Persistent oral dryness that accompanies the anticholinergic profile."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 3300
        ),

        Substance(
            name: "Fluphenazine",
            aliases: ["Prolixin"],
            category: .antipsychotic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 1...2.5, common: 2.5...10, strong: 10...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Reduced psychotic symptoms", "Sedation", "Muscle stiffness", "Akathisia", "Dry mouth", "Emotional blunting", "Drowsiness", "Restlessness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Thought Quieting", description: "A potent reduction in psychotic symptoms including hallucinations and paranoid thinking."),
                SubjectiveEffect(name: "Muscle Rigidity", description: "A pronounced stiffness in the body, jaw, and limbs that can restrict movement and expression."),
                SubjectiveEffect(name: "Akathisia", description: "An agonizing inner restlessness that creates a compulsive need to pace, shift, or fidget."),
                SubjectiveEffect(name: "Emotional Flattening", description: "A severe dampening of emotional responses that leaves patients feeling hollow or machine-like."),
                SubjectiveEffect(name: "Sedation", description: "A heavy drowsiness that can be both therapeutic for agitation and impairing for daily life."),
                SubjectiveEffect(name: "Restlessness", description: "A motor agitation that can manifest as pacing, leg bouncing, or inability to sit still."),
                SubjectiveEffect(name: "Dry Mouth", description: "Persistent oral dryness from anticholinergic effects."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 1980
        ),

        Substance(
            name: "Perphenazine",
            aliases: ["Trilafon"],
            category: .antipsychotic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 4...8, common: 8...24, strong: 24...64, heavy: 64
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Reduced psychotic symptoms", "Sedation", "Dry mouth", "Muscle stiffness", "Drowsiness", "Emotional blunting", "Akathisia", "Dizziness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Thought Quieting", description: "A reduction in psychotic symptoms with a balanced profile of efficacy and tolerability."),
                SubjectiveEffect(name: "Sedation", description: "Moderate drowsiness that tends to be less extreme than with low-potency typical antipsychotics."),
                SubjectiveEffect(name: "Muscle Stiffness", description: "A moderate rigidity in muscles and joints that may require adjunctive treatment."),
                SubjectiveEffect(name: "Emotional Blunting", description: "A dampening of emotional range that can feel like a permanent state of indifference."),
                SubjectiveEffect(name: "Akathisia", description: "Inner restlessness and motor agitation that can develop during treatment."),
                SubjectiveEffect(name: "Dizziness", description: "Lightheadedness and occasional unsteadiness, particularly during dose changes."),
                SubjectiveEffect(name: "Dry Mouth", description: "Persistent oral dryness from anticholinergic activity."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 570
        ),

        Substance(
            name: "Thioridazine",
            aliases: ["Mellaril"],
            category: .antipsychotic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 25...50, common: 50...200, strong: 200...800, heavy: 800, fatal: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Sedation", "Reduced psychotic symptoms", "Drowsiness", "Dry mouth", "Blurred vision", "Emotional blunting", "Weight gain", "Dizziness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Heavy Sedation", description: "A deep, enveloping drowsiness characteristic of low-potency typical antipsychotics."),
                SubjectiveEffect(name: "Thought Quieting", description: "A reduction in psychotic symptoms and agitated thinking over days to weeks."),
                SubjectiveEffect(name: "Emotional Blunting", description: "A notable flattening of emotional responses that accompanies the antipsychotic effect."),
                SubjectiveEffect(name: "Blurred Vision", description: "Difficulty focusing, particularly on close objects, from anticholinergic effects on the pupil."),
                SubjectiveEffect(name: "Weight Gain", description: "An increase in appetite and body weight, more pronounced than with high-potency agents."),
                SubjectiveEffect(name: "Dizziness", description: "Prominent orthostatic lightheadedness due to blood pressure lowering effects."),
                SubjectiveEffect(name: "Dry Mouth", description: "Persistent oral dryness from strong anticholinergic activity."),
                SubjectiveEffect(name: "Photosensitivity", description: "Increased skin sensitivity to sunlight, similar to other phenothiazines."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 1260
        ),

        Substance(
            name: "Loxapine",
            aliases: ["Loxitane"],
            category: .antipsychotic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...25, common: 25...50, strong: 50...250, heavy: 250, fatal: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...15, strong: 15...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 600)
                )),
            ],
            effects: ["Reduced psychotic symptoms", "Sedation", "Drowsiness", "Dizziness", "Dry mouth", "Muscle stiffness", "Emotional blunting", "Rapid calming"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Rapid Calming", description: "A fast-acting reduction in agitation and acute psychotic distress, particularly effective in the inhaled formulation."),
                SubjectiveEffect(name: "Sedation", description: "A moderate to heavy drowsiness that accompanies the antipsychotic effect."),
                SubjectiveEffect(name: "Thought Quieting", description: "A suppression of psychotic symptoms including hallucinations and paranoid thinking."),
                SubjectiveEffect(name: "Muscle Stiffness", description: "A tightness and rigidity in muscles that can affect movement and expression."),
                SubjectiveEffect(name: "Emotional Blunting", description: "A flattening of emotional responses that develops alongside the antipsychotic effect."),
                SubjectiveEffect(name: "Dizziness", description: "Lightheadedness and unsteadiness, particularly during dose initiation."),
                SubjectiveEffect(name: "Dry Mouth", description: "Persistent oral dryness from anticholinergic effects."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 480
        ),

        Substance(
            name: "Trifluoperazine",
            aliases: ["Stelazine"],
            category: .antipsychotic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...15, strong: 15...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Reduced psychotic symptoms", "Sedation", "Akathisia", "Muscle stiffness", "Dry mouth", "Drowsiness", "Emotional blunting", "Restlessness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Thought Quieting", description: "A potent suppression of psychotic symptoms and anxiety at low doses, with antipsychotic effects at higher doses."),
                SubjectiveEffect(name: "Muscle Rigidity", description: "Stiffness in the jaw, neck, and limbs that can feel like the body is locked in place."),
                SubjectiveEffect(name: "Akathisia", description: "A severely uncomfortable inner restlessness and compulsive urge to move that is common with high-potency agents."),
                SubjectiveEffect(name: "Emotional Flattening", description: "A marked reduction in emotional responsiveness that can feel like emotional amputation."),
                SubjectiveEffect(name: "Sedation", description: "Moderate drowsiness that accompanies the antipsychotic and anxiolytic effects."),
                SubjectiveEffect(name: "Restlessness", description: "Motor agitation manifesting as pacing, fidgeting, or inability to remain seated."),
                SubjectiveEffect(name: "Dry Mouth", description: "Persistent oral dryness from anticholinergic activity."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 1320
        ),
    ]
}
