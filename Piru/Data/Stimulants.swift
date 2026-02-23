import Foundation

extension SubstanceLibrary {
    static let stimulants: [Substance] = [

        // MARK: - Caffeine

        Substance(
            name: "Caffeine",
            aliases: ["Coffee", "Tea", "Guarana"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 20...100, common: 100...300, strong: 300...500, heavy: 500, fatal: 5000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Wakefulness", "Increased focus", "Alertness", "Anxiety", "Restlessness", "Elevated heart rate", "Appetite suppression", "Insomnia", "Diuresis", "Jitteriness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Wakefulness", description: "A sustained resistance to drowsiness and fatigue, making it easier to stay alert and engaged without feeling sleepy."),
                SubjectiveEffect(name: "Focus Enhancement", description: "A mild sharpening of concentration that makes routine tasks feel slightly more engaging and easier to sustain attention on."),
                SubjectiveEffect(name: "Anxiety", description: "A jittery, nervous energy that can manifest as racing thoughts, restlessness, or a sense of unease, especially at higher doses."),
                SubjectiveEffect(name: "Physical Stimulation", description: "A subtle bodily activation felt as slight muscle tension, restless legs, or an urge to move and fidget."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A noticeable reduction in hunger signals, making it easy to skip meals without feeling the urge to eat."),
                SubjectiveEffect(name: "Diuresis", description: "A pronounced increase in the need to urinate, often occurring within 30 minutes of consumption."),
                SubjectiveEffect(name: "Mood Lift", description: "A gentle improvement in mood and outlook, often described as feeling slightly more optimistic or content."),
                SubjectiveEffect(name: "Time Compression", description: "A subtle sense that time is passing more quickly, making tasks feel shorter than they actually are."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 7, buildRate: "rapid"),
            halfLifeMinutes: 300,
            sources: ["Drugs.com", "FDA DailyMed", "Examine.com", "PubMed"]
        ),

        // MARK: - Amphetamine

        Substance(
            name: "Amphetamine",
            aliases: ["Speed", "Adderall", "Amph", "Pep"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...15, common: 15...30, strong: 30...60, heavy: 60, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 180, max: 360),
                    total: TimeRange(min: 480, max: 720)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 3...10, common: 10...25, strong: 25...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 2, max: 5),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 240),
                    total: TimeRange(min: 180, max: 360)
                )),
                SubstanceRoute(route: .rectal, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 4...12, common: 12...25, strong: 25...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 90, max: 120),
                    afterglow: TimeRange(min: 120, max: 240),
                    total: TimeRange(min: 300, max: 480)
                )),
                SubstanceRoute(route: .intravenous, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 3...8, common: 8...20, strong: 20...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.5, max: 1),
                    comeup: TimeRange(min: 1, max: 5),
                    peak: TimeRange(min: 30, max: 90),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 240),
                    total: TimeRange(min: 120, max: 300)
                )),
            ],
            effects: ["Euphoria", "Increased focus", "Motivation", "Appetite suppression", "Wakefulness", "Jaw clenching", "Elevated heart rate", "Anxiety", "Irritability", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Euphoria", description: "A powerful wave of well-being and pleasure that can feel like everything in life is going perfectly, often accompanied by a warm, glowing sensation."),
                SubjectiveEffect(name: "Focus Enhancement", description: "An intense sharpening of concentration where distractions fade away and a single task can absorb complete attention for hours."),
                SubjectiveEffect(name: "Motivation Enhancement", description: "A strong drive to accomplish tasks and goals, making even mundane activities feel purposeful and rewarding."),
                SubjectiveEffect(name: "Stimulation", description: "A powerful surge of physical and mental energy, often described as feeling 'wired' with an intense desire to move and be active."),
                SubjectiveEffect(name: "Confidence Enhancement", description: "An amplified sense of self-assurance and social boldness, making conversations and interactions feel effortless."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A near-complete elimination of hunger, often persisting for the entire duration of the experience and into the comedown."),
                SubjectiveEffect(name: "Jaw Clenching", description: "An involuntary tightening of the jaw muscles and tendency to grind or clench teeth, often unnoticed until soreness develops."),
                SubjectiveEffect(name: "Thought Acceleration", description: "A rapid flow of ideas and mental connections, where thinking feels faster and more fluid than baseline."),
                SubjectiveEffect(name: "Comedown", description: "A period of irritability, fatigue, low mood, and difficulty concentrating as the effects wear off, often lasting several hours."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 660,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PsychonautWiki"]
        ),

        // MARK: - Dextroamphetamine

        Substance(
            name: "Dextroamphetamine",
            aliases: ["Dexedrine", "Dexamfetamine", "d-Amphetamine", "Zenzedi"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 2.5...10, common: 10...20, strong: 20...40, heavy: 40, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 360, max: 540)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 2...7, common: 7...15, strong: 15...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 2, max: 5),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 120, max: 240),
                    total: TimeRange(min: 180, max: 360)
                )),
                SubstanceRoute(route: .rectal, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 2...7, common: 7...15, strong: 15...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 240),
                    total: TimeRange(min: 240, max: 420)
                )),
            ],
            effects: ["Euphoria", "Increased focus", "Motivation", "Confidence", "Appetite suppression", "Wakefulness", "Elevated heart rate", "Jaw clenching", "Anxiety", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Euphoria", description: "A clean, pronounced sense of pleasure and well-being that feels slightly more cerebral and less body-heavy compared to racemic amphetamine."),
                SubjectiveEffect(name: "Focus Enhancement", description: "A laser-like concentration that makes complex or tedious tasks feel absorbing, often described as the 'cleanest' focus of the amphetamine class."),
                SubjectiveEffect(name: "Motivation Enhancement", description: "A powerful internal drive to be productive and accomplish goals, with sustained willpower to push through challenging tasks."),
                SubjectiveEffect(name: "Confidence Enhancement", description: "A strong sense of self-assurance and social ease, making it feel natural to take initiative and speak assertively."),
                SubjectiveEffect(name: "Stimulation", description: "A smooth, energizing wakefulness with less peripheral body stimulation compared to racemic amphetamine, feeling more 'mental' in character."),
                SubjectiveEffect(name: "Thought Acceleration", description: "A noticeable increase in the speed and clarity of thinking, with ideas flowing more rapidly and connections forming easily."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A strong and persistent suppression of hunger that can make eating feel unappealing for the full duration of effects."),
                SubjectiveEffect(name: "Talkativeness", description: "An increased desire and ease in verbal communication, with conversations feeling more engaging and words coming effortlessly."),
                SubjectiveEffect(name: "Comedown", description: "A rebound period of low mood, fatigue, and mental fogginess as dopamine and norepinephrine activity returns to baseline."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 660,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        // MARK: - Lisdexamfetamine

        Substance(
            name: "Lisdexamfetamine",
            aliases: ["Vyvanse", "Elvanse", "Lisdex", "LDX"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 10...30, common: 30...50, strong: 50...70, heavy: 70, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 120, max: 300),
                    total: TimeRange(min: 600, max: 840)
                )),
            ],
            effects: ["Increased focus", "Motivation", "Euphoria", "Appetite suppression", "Wakefulness", "Elevated heart rate", "Dry mouth", "Anxiety", "Irritability", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Focus Enhancement", description: "A gradual, smooth onset of deep concentration that builds over 1-2 hours, providing sustained and even attention without the abrupt peaks of immediate-release formulations."),
                SubjectiveEffect(name: "Motivation Enhancement", description: "A steady sense of purpose and drive that feels more natural and less forced than immediate-release amphetamines, making productivity feel effortless."),
                SubjectiveEffect(name: "Euphoria", description: "A mild-to-moderate sense of well-being that is typically less intense than other amphetamines due to the gradual enzymatic conversion to active dextroamphetamine."),
                SubjectiveEffect(name: "Stimulation", description: "A gentle, sustained wakefulness without the sharp 'kick' of other stimulants, often described as feeling naturally energized rather than chemically stimulated."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A prolonged and consistent reduction in hunger that can last 10-14 hours, often one of the most noticeable effects."),
                SubjectiveEffect(name: "Thought Organization", description: "An improved ability to structure and organize thoughts, making it easier to plan, prioritize, and follow through on multi-step tasks."),
                SubjectiveEffect(name: "Emotional Blunting", description: "A dampening of emotional intensity where both positive and negative feelings feel muted, sometimes described as feeling 'robotic' or flat."),
                SubjectiveEffect(name: "Comedown", description: "A gradual return to baseline that is typically milder than other amphetamines, though irritability and fatigue can still occur in the evening hours."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 660,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        // MARK: - Methamphetamine

        Substance(
            name: "Methamphetamine",
            aliases: ["Crystal", "Tina", "Ice", "Meth", "Glass", "Crank", "Desoxyn"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...15, common: 15...30, strong: 30...60, heavy: 60, fatal: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 150, max: 300),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: TimeRange(min: 240, max: 720),
                    total: TimeRange(min: 600, max: 960)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 5...10, common: 10...25, strong: 25...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 3, max: 5),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 180, max: 360),
                    total: TimeRange(min: 240, max: 480)
                )),
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...10, common: 10...20, strong: 20...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 0.5),
                    comeup: TimeRange(min: 1, max: 5),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 180, max: 360),
                    total: TimeRange(min: 240, max: 480)
                )),
                SubstanceRoute(route: .intravenous, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 3...8, common: 8...20, strong: 20...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 0.5),
                    comeup: TimeRange(min: 1, max: 5),
                    peak: TimeRange(min: 30, max: 120),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 180, max: 360),
                    total: TimeRange(min: 240, max: 420)
                )),
                SubstanceRoute(route: .rectal, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...10, common: 10...25, strong: 25...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 180, max: 360),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Intense euphoria", "Increased energy", "Wakefulness", "Hyperfocus", "Appetite suppression", "Jaw clenching", "Elevated heart rate", "Sweating", "Paranoia", "Compulsive redosing"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Intense Euphoria", description: "An overwhelming rush of pleasure and bliss that is significantly more powerful than other amphetamines, often described as the most intense euphoria possible from a stimulant."),
                SubjectiveEffect(name: "Stimulation", description: "An extreme surge of physical and mental energy that can last for many hours, with a powerful urge to move, talk, and engage in activity."),
                SubjectiveEffect(name: "Hyperfocus", description: "An all-consuming fixation on a single activity or task that can persist for hours, often on repetitive or unproductive tasks like disassembling electronics or cleaning."),
                SubjectiveEffect(name: "Compulsive Redosing", description: "An intense psychological urge to take more once the peak begins to fade, often overriding rational judgment about dosage and timing."),
                SubjectiveEffect(name: "Confidence Enhancement", description: "A grandiose sense of invincibility and supreme self-assurance that can lead to overestimating abilities and underestimating risks."),
                SubjectiveEffect(name: "Thought Acceleration", description: "An extremely rapid flow of thoughts and ideas that can feel creative and insightful but may become disorganized or scattered at higher doses."),
                SubjectiveEffect(name: "Paranoia", description: "An irrational suspicion and mistrust of others that intensifies with higher doses and prolonged use, sometimes reaching delusional intensity during binges."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A complete loss of appetite that can persist for the entire duration and well into the comedown, sometimes lasting over 24 hours."),
                SubjectiveEffect(name: "Severe Comedown", description: "A prolonged crash characterized by deep depression, extreme fatigue, intense hunger, hypersomnia, and anhedonia that can last days after heavy use."),
                SubjectiveEffect(name: "Tactile Hallucinations", description: "At high doses or after prolonged use, a crawling or itching sensation under the skin known as 'meth bugs' or formication."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 660,
            sources: ["PsychonautWiki", "Erowid", "DEA", "StatPearls"]
        ),

        // MARK: - Methylphenidate

        Substance(
            name: "Methylphenidate",
            aliases: ["Ritalin", "Concerta", "Methylin", "Daytrana", "MPH"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 5...20, common: 20...40, strong: 40...60, heavy: 60, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 240, max: 360)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 3...10, common: 10...20, strong: 20...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 30, max: 90),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 120, max: 240)
                )),
                SubstanceRoute(route: .rectal, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...15, common: 15...30, strong: 30...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 180, max: 300)
                )),
                SubstanceRoute(route: .intravenous, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 3...8, common: 8...15, strong: 15...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.5, max: 1),
                    comeup: TimeRange(min: 1, max: 5),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 90, max: 180)
                )),
            ],
            effects: ["Increased focus", "Alertness", "Motivation", "Appetite suppression", "Elevated heart rate", "Anxiety", "Insomnia", "Irritability", "Dry mouth", "Headache"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Focus Enhancement", description: "A crisp, task-oriented concentration that narrows attention to the activity at hand, often described as more 'mechanical' or 'clinical' than amphetamine-type focus."),
                SubjectiveEffect(name: "Stimulation", description: "A moderate physical and mental activation that feels more jittery and peripheral compared to amphetamines, with a noticeable increase in heart rate and alertness."),
                SubjectiveEffect(name: "Motivation Enhancement", description: "A functional increase in willingness to engage with tasks, though typically described as less euphoric and more 'neutral' drive compared to amphetamines."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A moderate reduction in hunger, generally less intense than with amphetamines, that may diminish as the dose wears off."),
                SubjectiveEffect(name: "Anxiety", description: "A restless, edgy feeling that can manifest as nervousness or physical tension, particularly noticeable due to methylphenidate's norepinephrine activity."),
                SubjectiveEffect(name: "Emotional Blunting", description: "A flattening of emotional responses where feelings feel dulled or distant, sometimes described as feeling 'zombie-like' at therapeutic doses."),
                SubjectiveEffect(name: "Rebound Effect", description: "A noticeable crash as the drug wears off, characterized by irritability, emotional sensitivity, fatigue, and difficulty concentrating, often more abrupt than amphetamine comedowns."),
                SubjectiveEffect(name: "Thought Organization", description: "An improved ability to sequence thoughts and follow through on plans, making executive function tasks like organizing and planning feel more manageable."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 10, buildRate: "moderate"),
            halfLifeMinutes: 150,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        // MARK: - Dexmethylphenidate

        Substance(
            name: "Dexmethylphenidate",
            aliases: ["Focalin", "d-MPH", "d-Methylphenidate"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2.5...5, common: 5...15, strong: 15...30, heavy: 30, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 150),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 210, max: 330)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...10, strong: 10...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 30, max: 75),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 120, max: 210)
                )),
            ],
            effects: ["Increased focus", "Alertness", "Motivation", "Appetite suppression", "Elevated heart rate", "Anxiety", "Insomnia", "Dry mouth", "Irritability", "Nausea"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Focus Enhancement", description: "A refined, precise concentration that is often described as cleaner than racemic methylphenidate, with less peripheral jitteriness and smoother task engagement."),
                SubjectiveEffect(name: "Stimulation", description: "A moderate, even-keeled mental and physical activation that feels more balanced than racemic MPH, with less of the 'wired' body sensation."),
                SubjectiveEffect(name: "Motivation Enhancement", description: "A practical sense of drive and task engagement that feels functional rather than euphoric, helping to initiate and sustain effort on work."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A moderate reduction in appetite, typically proportional to dose, that fades as the medication clears the system."),
                SubjectiveEffect(name: "Thought Clarity", description: "A quieting of mental noise and racing thoughts, making it easier to think sequentially and stay on track with a single train of thought."),
                SubjectiveEffect(name: "Emotional Blunting", description: "A subtle dampening of emotional range at higher doses, where reactions to events feel somewhat muted and flat."),
                SubjectiveEffect(name: "Rebound Effect", description: "An abrupt return of inattention and emotional sensitivity as the drug clears, sometimes more pronounced than with the racemic formulation."),
                SubjectiveEffect(name: "Wakefulness", description: "A reliable resistance to drowsiness and mental fog, providing sustained alertness without the intense stimulation of amphetamine-class drugs."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 10, buildRate: "moderate"),
            halfLifeMinutes: 180,
            sources: ["Drugs.com", "FDA DailyMed", "PsychonautWiki", "StatPearls"]
        ),

        // MARK: - Cocaine

        Substance(
            name: "Cocaine",
            aliases: ["Coke", "Blow", "Snow", "Yayo", "Charlie", "Powder"],
            category: .stimulant,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...30, common: 30...60, strong: 60...90, heavy: 90, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: nil,
                    total: TimeRange(min: 45, max: 90)
                )),
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 20, light: 30...60, common: 60...120, strong: 120...200, heavy: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: nil,
                    total: TimeRange(min: 60, max: 120)
                )),
                SubstanceRoute(route: .intravenous, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 8...15, common: 15...30, strong: 30...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 0.5),
                    comeup: TimeRange(min: 0.5, max: 2),
                    peak: TimeRange(min: 5, max: 15),
                    offset: TimeRange(min: 15, max: 30),
                    afterglow: nil,
                    total: TimeRange(min: 15, max: 45)
                )),
                SubstanceRoute(route: .rectal, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 20...40, common: 40...80, strong: 80...150, heavy: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 3, max: 10),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 30, max: 45),
                    afterglow: nil,
                    total: TimeRange(min: 45, max: 90)
                )),
            ],
            effects: ["Euphoria", "Confidence", "Talkativeness", "Numbness", "Increased energy", "Elevated heart rate", "Appetite suppression", "Anxiety", "Compulsive redosing", "Nasal congestion"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Euphoria", description: "A sudden, intense burst of pleasure and confidence that arrives within minutes of insufflation, often described as feeling on top of the world."),
                SubjectiveEffect(name: "Confidence Enhancement", description: "A dramatic increase in self-assurance and social boldness, making interactions feel effortless and fueling a desire to be the center of attention."),
                SubjectiveEffect(name: "Talkativeness", description: "An irresistible urge to talk rapidly and at length, with conversations feeling deeply engaging and important in the moment."),
                SubjectiveEffect(name: "Local Anesthesia", description: "A characteristic numbing of the gums, nasal passages, and throat when insufflated, which produces a distinctive tingling-to-numb sensation."),
                SubjectiveEffect(name: "Stimulation", description: "A sharp, short-lived burst of physical and mental energy that peaks quickly and fades within 30-60 minutes, creating a restless urge to move."),
                SubjectiveEffect(name: "Compulsive Redosing", description: "A strong psychological pull to take more as the short-lived peak fades, often leading to far higher total consumption than originally intended."),
                SubjectiveEffect(name: "Thought Acceleration", description: "A rapid, often scattered flow of ideas and grandiose plans that feel brilliant in the moment but may lack coherence in retrospect."),
                SubjectiveEffect(name: "Anxiety", description: "A mounting tension and paranoia that often emerges during the comedown or after repeated doses, sometimes manifesting as hypervigilance."),
                SubjectiveEffect(name: "Comedown", description: "A sharp crash involving depressed mood, fatigue, restlessness, and intense craving that arrives as the short-acting effects wear off."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 60,
            sources: ["PsychonautWiki", "Erowid", "DEA", "StatPearls"]
        ),

        // MARK: - Crack Cocaine

        Substance(
            name: "Crack Cocaine",
            aliases: ["Crack", "Rock", "Freebase Cocaine", "Base"],
            category: .stimulant,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...25, common: 25...50, strong: 50...80, heavy: 80, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 0.25),
                    comeup: TimeRange(min: 0.5, max: 1),
                    peak: TimeRange(min: 5, max: 10),
                    offset: TimeRange(min: 15, max: 30),
                    afterglow: nil,
                    total: TimeRange(min: 15, max: 30)
                )),
            ],
            effects: ["Intense euphoria", "Rush", "Confidence", "Increased energy", "Elevated heart rate", "Appetite suppression", "Paranoia", "Anxiety", "Compulsive redosing", "Chest tightness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Intense Rush", description: "An immediate, overwhelming wave of euphoria and stimulation that hits within seconds of inhalation, far more intense and abrupt than insufflated cocaine."),
                SubjectiveEffect(name: "Euphoria", description: "An extreme but very short-lived peak of pleasure lasting only 5-15 minutes, often described as a 'bell ringer' — an all-consuming wave of bliss."),
                SubjectiveEffect(name: "Compulsive Redosing", description: "An extremely powerful urge to smoke another hit almost immediately as the intense peak fades, making it very difficult to limit consumption."),
                SubjectiveEffect(name: "Confidence Enhancement", description: "A grandiose sense of power and invincibility during the peak that vanishes rapidly, leaving an intense desire to recapture the feeling."),
                SubjectiveEffect(name: "Stimulation", description: "An explosive burst of physical energy and mental alertness that is far more intense but shorter-lasting than powdered cocaine."),
                SubjectiveEffect(name: "Paranoia", description: "An acute suspiciousness and hypervigilance that can onset rapidly after repeated hits, sometimes leading to irrational fear of being watched or followed."),
                SubjectiveEffect(name: "Chest Tightness", description: "A constricting sensation in the chest and shortness of breath from the smoke and intense cardiovascular stimulation."),
                SubjectiveEffect(name: "Severe Comedown", description: "An intense crash characterized by deep depression, agitation, exhaustion, and overwhelming craving that begins minutes after the last dose."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 60,
            sources: ["Drugs.com", "Merck Manual", "PsychonautWiki", "StatPearls"]
        ),

        // MARK: - Nicotine

        Substance(
            name: "Nicotine",
            aliases: ["Nic", "Tobacco", "Vape"],
            category: .stimulant,
            defaultRoute: .inhalation,
            routes: [
                SubstanceRoute(route: .inhalation, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 0.5...1, common: 1...3, strong: 3...5, heavy: 5, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.1, max: 0.5),
                    comeup: TimeRange(min: 0.5, max: 2),
                    peak: TimeRange(min: 1, max: 5),
                    offset: TimeRange(min: 15, max: 30),
                    afterglow: nil,
                    total: TimeRange(min: 30, max: 60)
                )),
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 1...2, common: 2...4, strong: 4...8, heavy: 8, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: nil,
                    total: TimeRange(min: 60, max: 120)
                )),
                SubstanceRoute(route: .transdermal, unit: "mg", doses: DoseRange(
                    threshold: 3.5, light: 7...14, common: 14...21, strong: 21...35, heavy: 35
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 120),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 360, max: 720),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
                SubstanceRoute(route: .sublingual, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 1...2, common: 2...4, strong: 4...6, heavy: 6
                ), duration: DurationProfile(
                    onset: TimeRange(min: 2, max: 5),
                    comeup: TimeRange(min: 3, max: 8),
                    peak: TimeRange(min: 10, max: 20),
                    offset: TimeRange(min: 20, max: 45),
                    afterglow: nil,
                    total: TimeRange(min: 30, max: 60)
                )),
            ],
            effects: ["Relaxation", "Alertness", "Buzz", "Appetite suppression", "Nausea", "Dizziness", "Elevated heart rate", "Headache", "Craving", "Lightheadedness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Nicotine Buzz", description: "A brief, pleasant head rush and mild euphoria lasting seconds to minutes, most pronounced in non-tolerant users and often accompanied by slight dizziness."),
                SubjectiveEffect(name: "Relaxation", description: "A paradoxical calming effect despite being a stimulant, reducing subjective stress and tension, particularly for habitual users."),
                SubjectiveEffect(name: "Alertness", description: "A subtle sharpening of attention and mental clarity that is brief and mild, often only noticeable when transitioning from a state of craving."),
                SubjectiveEffect(name: "Craving", description: "A persistent, nagging urge to use again that develops rapidly with regular use, felt as restlessness, irritability, and difficulty concentrating."),
                SubjectiveEffect(name: "Nausea", description: "A queasy, motion-sickness-like sensation that occurs with higher doses or in non-tolerant users, sometimes accompanied by salivation."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A mild reduction in hunger that is subtle at typical doses but can contribute to reduced food intake over time."),
                SubjectiveEffect(name: "Lightheadedness", description: "A brief floaty or dizzy sensation, especially when standing, that occurs primarily with the first use of the day or after a period of abstinence."),
                SubjectiveEffect(name: "Cognitive Habituation", description: "A rapid development of tolerance where the pleasurable effects diminish within days of regular use, leaving primarily craving relief as the subjective experience."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 2, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls", "PubMed"]
        ),

        // MARK: - Modafinil

        Substance(
            name: "Modafinil",
            aliases: ["Provigil", "Modalert", "Modvigil"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...400, heavy: 400, fatal: 5000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 300),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1080)
                )),
            ],
            effects: ["Wakefulness", "Increased focus", "Alertness", "Motivation", "Appetite suppression", "Insomnia", "Headache", "Anxiety", "Dry mouth", "Nausea"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Wakefulness", description: "A profound resistance to sleep and fatigue that does not feel like traditional stimulation — more like the sensation of simply not being tired rather than being energized."),
                SubjectiveEffect(name: "Focus Enhancement", description: "A subtle but sustained improvement in concentration and task engagement that feels natural and non-forced, without the tunnel vision of amphetamines."),
                SubjectiveEffect(name: "Motivation Enhancement", description: "A mild increase in willingness to engage with work, often described as 'removing the barrier to starting' tasks rather than actively driving productivity."),
                SubjectiveEffect(name: "Emotional Dampening", description: "A subtle flattening of emotional reactivity where stressors feel less impactful and emotional responses feel slightly muted."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A moderate reduction in hunger signals that can persist throughout the long duration of action, sometimes leading to accidentally skipping meals."),
                SubjectiveEffect(name: "Headache", description: "A dull, persistent pressure headache that is one of the most commonly reported side effects, sometimes mitigated by staying well-hydrated."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty falling asleep even many hours after dosing due to the long half-life, particularly when taken later in the day."),
                SubjectiveEffect(name: "Absence of Euphoria", description: "A notably non-euphoric experience compared to traditional stimulants, which makes it feel functional rather than recreational."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 900,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        // MARK: - Armodafinil

        Substance(
            name: "Armodafinil",
            aliases: ["Nuvigil", "Waklert", "Artvigil"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 25...75, common: 75...150, strong: 150...250, heavy: 250
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 180, max: 300),
                    offset: TimeRange(min: 300, max: 600),
                    afterglow: nil,
                    total: TimeRange(min: 840, max: 1200)
                )),
            ],
            effects: ["Wakefulness", "Increased focus", "Alertness", "Motivation", "Appetite suppression", "Insomnia", "Headache", "Anxiety", "Dry mouth", "Nausea"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Wakefulness", description: "A sustained, clean alertness that may feel even more persistent than modafinil due to the longer-acting R-enantiomer, with effects lasting well into the evening."),
                SubjectiveEffect(name: "Focus Enhancement", description: "A steady, low-key improvement in sustained attention that feels very similar to modafinil but with a more even tail-end, maintaining concentration late in the day."),
                SubjectiveEffect(name: "Motivation Enhancement", description: "A functional nudge toward task engagement that is subtle and non-euphoric, helping reduce procrastination without producing a stimulant 'high.'"),
                SubjectiveEffect(name: "Appetite Suppression", description: "A reliable reduction in hunger that can persist for the full 12-15 hour duration of action, often more pronounced than with modafinil."),
                SubjectiveEffect(name: "Headache", description: "A common tension-type headache, particularly during the first few days of use, that may be related to histamine activity."),
                SubjectiveEffect(name: "Insomnia", description: "A pronounced difficulty falling asleep that can be more problematic than modafinil due to the longer effective duration, requiring early morning dosing."),
                SubjectiveEffect(name: "Emotional Dampening", description: "A mild reduction in emotional variability, making the day feel even-keeled but potentially less vibrant."),
                SubjectiveEffect(name: "Absence of Euphoria", description: "A characteristically non-recreational experience with no discernible high, making the effects feel like simply being awake and functional."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 900,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        // MARK: - Ephedrine

        Substance(
            name: "Ephedrine",
            aliases: ["Ephed", "Ma Huang"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 8, light: 12.5...25, common: 25...50, strong: 50...75, heavy: 75, fatal: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Increased energy", "Appetite suppression", "Bronchodilation", "Elevated heart rate", "Sweating", "Anxiety", "Tremor", "Insomnia", "Elevated blood pressure", "Nausea"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Physical Stimulation", description: "A noticeable increase in physical energy and body warmth that feels more peripheral and body-focused than cerebral, with a distinct 'amped up' physical sensation."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A strong reduction in hunger that was historically one of its primary uses, often more pronounced than the energy-boosting effects."),
                SubjectiveEffect(name: "Bronchodilation", description: "A noticeable opening of the airways that makes breathing feel easier and deeper, particularly helpful for those with respiratory congestion."),
                SubjectiveEffect(name: "Cardiovascular Stimulation", description: "A prominent increase in heart rate and blood pressure that is often felt as a pounding or racing heart, particularly at higher doses."),
                SubjectiveEffect(name: "Sweating", description: "An increased tendency to perspire, especially during physical activity, due to sympathetic nervous system activation."),
                SubjectiveEffect(name: "Tremor", description: "A fine shaking of the hands and fingers that becomes more pronounced at higher doses, making fine motor tasks more difficult."),
                SubjectiveEffect(name: "Anxiety", description: "A jittery, nervous energy that can escalate to feelings of panic at higher doses, driven by strong adrenergic stimulation."),
                SubjectiveEffect(name: "Mild Mood Lift", description: "A subtle improvement in mood and sense of well-being, though much less pronounced than with amphetamines."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 360,
            sources: ["Drugs.com", "FDA DailyMed", "PsychonautWiki", "StatPearls"]
        ),

        // MARK: - Pseudoephedrine

        Substance(
            name: "Pseudoephedrine",
            aliases: ["Sudafed", "PSE"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 15, light: 30...60, common: 60...120, strong: 120...240, heavy: 240, fatal: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 480)
                )),
            ],
            effects: ["Nasal decongestion", "Wakefulness", "Mild stimulation", "Elevated heart rate", "Restlessness", "Insomnia", "Dry mouth", "Anxiety", "Elevated blood pressure", "Appetite suppression"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Nasal Decongestion", description: "A clearing of blocked nasal passages that is the primary intended effect, providing easier breathing within 30 minutes of oral dosing."),
                SubjectiveEffect(name: "Mild Stimulation", description: "A very subtle increase in alertness and wakefulness that is noticeable mainly when taking higher decongestant doses, feeling like a very mild caffeine-like effect."),
                SubjectiveEffect(name: "Restlessness", description: "A fidgety, unable-to-sit-still feeling that can interfere with relaxation and sleep, particularly at doses above 60mg."),
                SubjectiveEffect(name: "Dry Mouth", description: "A noticeable reduction in saliva production that can make the mouth feel parched and uncomfortable."),
                SubjectiveEffect(name: "Cardiovascular Awareness", description: "A subtle awareness of increased heart rate and blood pressure, sometimes felt as a slight tightness or pounding in the chest."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty falling asleep when taken later in the day, owing to its mild stimulant properties and relatively long duration of action."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 360,
            sources: ["Drugs.com", "FDA DailyMed", "PsychonautWiki", "StatPearls"]
        ),

        // MARK: - Propylhexedrine

        Substance(
            name: "Propylhexedrine",
            aliases: ["Benzedrex", "Hexahydromethamphetamine"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 62.5...125, common: 125...250, strong: 250...375, heavy: 375, fatal: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 120, max: 240),
                    total: TimeRange(min: 240, max: 480)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 15, light: 25...62.5, common: 62.5...125, strong: 125...187.5, heavy: 187.5
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 30, max: 90),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 120, max: 240)
                )),
            ],
            effects: ["Euphoria", "Increased energy", "Appetite suppression", "Elevated heart rate", "Sweating", "Jaw clenching", "Anxiety", "Nausea", "Vasoconstriction", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Euphoria", description: "A pronounced sense of pleasure and well-being often compared to a moderate amphetamine experience, with a distinctly 'dirty' or rough quality to the stimulation."),
                SubjectiveEffect(name: "Stimulation", description: "A strong physical and mental activation with a heavy body load, often described as feeling intensely wired with significant peripheral nervous system effects."),
                SubjectiveEffect(name: "Jaw Clenching", description: "A marked involuntary clenching and grinding of the teeth, often more severe than with pharmaceutical amphetamines."),
                SubjectiveEffect(name: "Vasoconstriction", description: "A noticeable tightening and constriction of blood vessels that can cause cold extremities, pale skin, and uncomfortable physical tension."),
                SubjectiveEffect(name: "Nausea", description: "A strong stomach discomfort often reported due to the unpleasant taste and chemical properties of the substance, sometimes leading to vomiting."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A significant loss of appetite that persists through the experience and into the aftermath."),
                SubjectiveEffect(name: "Sweating", description: "Profuse perspiration that is disproportionate to activity level, often accompanied by an unpleasant chemical body odor."),
                SubjectiveEffect(name: "Comedown", description: "A harsh crash involving headache, fatigue, irritability, and body aches, often described as more physically uncomfortable than typical amphetamine comedowns."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 360,
            sources: ["Drugs.com", "FDA DailyMed", "PsychonautWiki", "StatPearls"]
        ),

        // MARK: - DMAA

        Substance(
            name: "DMAA",
            aliases: ["1,3-Dimethylamylamine", "Methylhexanamine", "Geranamine", "Forthane"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 10...25, common: 25...50, strong: 50...75, heavy: 75, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 300)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 5...15, common: 15...30, strong: 30...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 2, max: 5),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: nil,
                    total: TimeRange(min: 60, max: 150)
                )),
            ],
            effects: ["Increased energy", "Euphoria", "Increased focus", "Elevated heart rate", "Elevated blood pressure", "Appetite suppression", "Sweating", "Anxiety", "Shortness of breath", "Headache"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Stimulation", description: "An intense, almost aggressive burst of physical energy and alertness that feels distinctly sympathomimetic, with a heavy body load and pronounced cardiovascular effects."),
                SubjectiveEffect(name: "Euphoria", description: "A moderate sense of well-being and energy that resembles amphetamine-like stimulation, often used in pre-workout supplements for its motivating quality."),
                SubjectiveEffect(name: "Focus Enhancement", description: "A noticeable narrowing of attention toward physical or mental tasks, particularly useful during exercise or demanding workouts."),
                SubjectiveEffect(name: "Cardiovascular Stimulation", description: "A strong increase in heart rate and blood pressure that is one of the most prominent effects, often felt as a racing or pounding heart."),
                SubjectiveEffect(name: "Shortness of Breath", description: "A feeling of difficulty catching a full breath, particularly during physical exertion, that can be alarming at higher doses."),
                SubjectiveEffect(name: "Sweating", description: "An excessive perspiration response that begins quickly after ingestion, significantly more pronounced during physical activity."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A strong reduction in hunger that lasts for several hours, historically one of the reasons it was included in weight-loss supplements."),
                SubjectiveEffect(name: "Headache", description: "A throbbing headache that often develops during or after the experience, likely related to vasoconstriction and blood pressure elevation."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 504,
            sources: ["PubMed", "Examine.com", "WHO"]
        ),

        // MARK: - Phenylethylamine

        Substance(
            name: "Phenylethylamine",
            aliases: ["PEA", "beta-Phenylethylamine", "Phenethylamine"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 200...500, common: 500...1000, strong: 1000...1500, heavy: 1500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 5, max: 15),
                    offset: TimeRange(min: 15, max: 30),
                    afterglow: nil,
                    total: TimeRange(min: 15, max: 45)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 20, light: 30...60, common: 60...100, strong: 100...200, heavy: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 3),
                    comeup: TimeRange(min: 2, max: 5),
                    peak: TimeRange(min: 3, max: 10),
                    offset: TimeRange(min: 10, max: 20),
                    afterglow: nil,
                    total: TimeRange(min: 10, max: 30)
                )),
            ],
            effects: ["Mood lift", "Increased energy", "Alertness", "Elevated heart rate", "Headache", "Nausea", "Anxiety", "Rapid onset", "Short duration", "Appetite suppression"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Rapid Onset Rush", description: "An extremely fast-acting burst of stimulation and mood lift that peaks within minutes and fades just as quickly, especially via insufflation."),
                SubjectiveEffect(name: "Mood Lift", description: "A brief but noticeable elevation in mood and sense of well-being, often described as a fleeting moment of clarity and happiness."),
                SubjectiveEffect(name: "Stimulation", description: "A short-lived surge of energy and alertness lasting only 15-30 minutes orally, making it one of the shortest-acting stimulants available."),
                SubjectiveEffect(name: "Cardiovascular Stimulation", description: "A rapid increase in heart rate and blood pressure that can feel alarming due to how quickly it develops and its intensity relative to the brief experience."),
                SubjectiveEffect(name: "Headache", description: "A common side effect that can persist well beyond the short-lived stimulant effects, likely due to rapid MAO-B metabolism and vasoactive properties."),
                SubjectiveEffect(name: "Nausea", description: "A queasy stomach feeling that is frequently reported, particularly at higher doses or when combined with food."),
                SubjectiveEffect(name: "Fleeting Duration", description: "A remarkably short window of effects that is often over before it feels like it has fully begun, leading some users to compulsively redose."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 10,
            sources: ["Drugs.com", "PubMed", "PsychonautWiki", "StatPearls"]
        ),

        // MARK: - Adrafinil

        Substance(
            name: "Adrafinil",
            aliases: ["Olmifon", "CRL-40028"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 150...300, common: 300...600, strong: 600...900, heavy: 900
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 90),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 180, max: 300),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 600, max: 900)
                )),
            ],
            effects: ["Wakefulness", "Increased focus", "Alertness", "Motivation", "Insomnia", "Headache", "Nausea", "Anxiety", "Stomach discomfort", "Dry mouth"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Wakefulness", description: "A gradual-onset wakefulness that takes 60-90 minutes to develop as the prodrug is metabolized to modafinil, feeling less immediate but equally sustained."),
                SubjectiveEffect(name: "Focus Enhancement", description: "A mild improvement in concentration that mirrors modafinil in character but develops more slowly and may feel less potent due to incomplete conversion."),
                SubjectiveEffect(name: "Motivation Enhancement", description: "A subtle functional drive similar to modafinil, helping to initiate tasks without the euphoric push of traditional stimulants."),
                SubjectiveEffect(name: "Stomach Discomfort", description: "A notable gastrointestinal discomfort and nausea that is more common with adrafinil than modafinil, due to the additional hepatic metabolism required."),
                SubjectiveEffect(name: "Headache", description: "A dull pressure headache similar to modafinil's but sometimes more pronounced, potentially due to the hepatic processing and metabolite effects."),
                SubjectiveEffect(name: "Delayed Onset", description: "A noticeably slower onset compared to modafinil, typically requiring 1-2 hours before effects are fully perceived, as the liver must first convert it."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty falling asleep that can extend well into the night due to the delayed onset adding to modafinil's already long duration of action."),
                SubjectiveEffect(name: "Absence of Euphoria", description: "A characteristically non-recreational profile identical to modafinil, with effects limited to wakefulness and mild cognitive enhancement."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 900,
            sources: ["PsychonautWiki", "PubMed", "DrugBank", "Examine.com"]
        ),

        // MARK: - Atomoxetine

        Substance(
            name: "Atomoxetine",
            aliases: ["Strattera", "ATX"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 10...25, common: 25...60, strong: 60...100, heavy: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Increased focus", "Improved attention", "Reduced impulsivity", "Appetite suppression", "Dry mouth", "Nausea", "Insomnia", "Elevated heart rate", "Dizziness", "Mood changes"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Focus Enhancement", description: "A gradual, subtle improvement in sustained attention that develops over weeks of consistent use rather than producing an immediate noticeable effect."),
                SubjectiveEffect(name: "Reduced Impulsivity", description: "A growing ability to pause before acting on impulses, with improved capacity to consider consequences before making decisions."),
                SubjectiveEffect(name: "Emotional Lability", description: "A tendency toward mood swings and increased emotional sensitivity, particularly during the initial weeks of treatment as the body adjusts."),
                SubjectiveEffect(name: "Nausea", description: "A persistent queasiness and stomach upset that is one of the most common side effects, often improving after the first few weeks of use."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A moderate reduction in appetite that is a common side effect rather than a primary therapeutic effect, as atomoxetine is a selective norepinephrine reuptake inhibitor."),
                SubjectiveEffect(name: "Dizziness", description: "A lightheaded, unsteady feeling particularly when standing up quickly, related to norepinephrine-mediated blood pressure changes."),
                SubjectiveEffect(name: "Absence of Euphoria", description: "A notably non-euphoric experience with no recreational potential, as the drug selectively targets norepinephrine without significant dopamine release."),
                SubjectiveEffect(name: "Gradual Onset", description: "A therapeutic effect that builds incrementally over 4-6 weeks of daily use, with no immediate cognitive boost felt on the first dose."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 21, buildRate: "slow"),
            halfLifeMinutes: 300,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        // MARK: - Phentermine

        Substance(
            name: "Phentermine",
            aliases: ["Adipex", "Adipex-P", "Ionamin", "Lomaira"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 4, light: 8...15, common: 15...30, strong: 30...45, heavy: 45, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 180, max: 300),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 720)
                )),
            ],
            effects: ["Appetite suppression", "Increased energy", "Elevated heart rate", "Insomnia", "Dry mouth", "Restlessness", "Anxiety", "Euphoria", "Elevated blood pressure", "Constipation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Appetite Suppression", description: "A powerful and sustained elimination of hunger that is the primary therapeutic effect, making it very easy to maintain caloric restriction."),
                SubjectiveEffect(name: "Stimulation", description: "A moderate boost of physical and mental energy that feels similar to a low dose of amphetamine, providing increased alertness and drive."),
                SubjectiveEffect(name: "Euphoria", description: "A mild-to-moderate mood elevation that can occur especially at higher doses, giving a sense of well-being and contentment."),
                SubjectiveEffect(name: "Restlessness", description: "A fidgety, keyed-up feeling that makes it difficult to sit still or relax, particularly in the first few hours after dosing."),
                SubjectiveEffect(name: "Dry Mouth", description: "A pronounced dryness in the mouth and throat that persists throughout the duration, often requiring frequent water intake."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty falling and staying asleep, especially when taken later in the day, due to its moderate duration of stimulant action."),
                SubjectiveEffect(name: "Cardiovascular Awareness", description: "A noticeable awareness of elevated heart rate and blood pressure, sometimes felt as heart pounding or a sensation of pressure in the head."),
                SubjectiveEffect(name: "Tolerance Development", description: "A rapid diminishing of appetite-suppressant and euphoric effects with continued use, typically within weeks of regular administration."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 1200,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        // MARK: - Phenmetrazine

        Substance(
            name: "Phenmetrazine",
            aliases: ["Preludin"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...25, common: 25...50, strong: 50...75, heavy: 75, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 60, max: 180),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 360)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...15, common: 15...30, strong: 30...50, heavy: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 2, max: 5),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 30, max: 90),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: nil,
                    total: TimeRange(min: 90, max: 180)
                )),
                SubstanceRoute(route: .intravenous, unit: "mg", doses: DoseRange(
                    threshold: 3, light: 5...10, common: 10...25, strong: 25...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 0.5, max: 1),
                    comeup: TimeRange(min: 1, max: 5),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: nil,
                    total: TimeRange(min: 60, max: 150)
                )),
            ],
            effects: ["Euphoria", "Increased energy", "Appetite suppression", "Increased focus", "Confidence", "Elevated heart rate", "Jaw clenching", "Anxiety", "Insomnia", "Sweating"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Euphoria", description: "A strong, clean sense of pleasure and well-being that was historically considered highly reinforcing and comparable to amphetamine in quality."),
                SubjectiveEffect(name: "Stimulation", description: "A potent energizing effect with both physical and mental activation, described as smooth and focused with less jitteriness than amphetamine."),
                SubjectiveEffect(name: "Focus Enhancement", description: "A clear, task-oriented concentration that made phenmetrazine popular among professionals seeking enhanced productivity."),
                SubjectiveEffect(name: "Confidence Enhancement", description: "An amplified sense of self-assurance and social ease that contributes to its historically reported recreational appeal."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A pronounced suppression of hunger that was the original medical indication, effectively eliminating the desire to eat for hours."),
                SubjectiveEffect(name: "Jaw Clenching", description: "A noticeable involuntary tightening and grinding of the jaw muscles, similar in character to amphetamine-induced bruxism."),
                SubjectiveEffect(name: "Sweating", description: "An increased perspiration response, particularly during physical activity or in warm environments."),
                SubjectiveEffect(name: "Comedown", description: "A moderate period of fatigue, low mood, and irritability as effects subside, though generally reported as less harsh than amphetamine."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 480,
            sources: ["Drugs.com", "Merck Manual", "PsychonautWiki", "StatPearls"]
        ),

        // MARK: - Pemoline

        Substance(
            name: "Pemoline",
            aliases: ["Cylert", "PEM"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 18.75...37.5, common: 37.5...75, strong: 75...112.5, heavy: 112.5
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 720)
                )),
            ],
            effects: ["Increased focus", "Wakefulness", "Alertness", "Appetite suppression", "Insomnia", "Irritability", "Nausea", "Headache", "Dizziness", "Stomach discomfort"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Focus Enhancement", description: "A mild but sustained improvement in concentration and attention span that develops over days of consistent use, feeling subtle and functional."),
                SubjectiveEffect(name: "Wakefulness", description: "A low-grade alertness that helps combat fatigue and drowsiness without the intensity of amphetamine-type stimulation."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A moderate reduction in hunger that is a consistent effect of the mild dopaminergic stimulation."),
                SubjectiveEffect(name: "Irritability", description: "A tendency toward short-temperedness and impatience, particularly noticeable during the afternoon as effects begin to wane."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty falling asleep that can be problematic given pemoline's long half-life, requiring morning-only dosing."),
                SubjectiveEffect(name: "Headache", description: "A dull headache that is a commonly reported side effect, sometimes occurring consistently with regular use."),
                SubjectiveEffect(name: "Stomach Discomfort", description: "A mild gastrointestinal unease including nausea and abdominal discomfort that may accompany each dose."),
                SubjectiveEffect(name: "Absence of Euphoria", description: "A characteristically non-euphoric stimulant profile that provides functional benefits without a discernible high or rewarding sensation."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 720,
            sources: ["Drugs.com", "FDA DailyMed", "PsychonautWiki", "StatPearls"]
        ),

        // MARK: - Amineptine

        Substance(
            name: "Amineptine",
            aliases: ["Survector", "Maneon"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...300, heavy: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 480)
                )),
            ],
            effects: ["Mood lift", "Increased motivation", "Increased energy", "Improved concentration", "Appetite suppression", "Anxiety", "Insomnia", "Headache", "Dry mouth", "Nausea"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mood Lift", description: "A gentle, sustained antidepressant-like improvement in mood that develops over days of use, described as a lifting of emotional heaviness rather than euphoria."),
                SubjectiveEffect(name: "Motivation Enhancement", description: "A restored sense of drive and interest in activities that were previously unappealing, reflecting its dopamine reuptake inhibition."),
                SubjectiveEffect(name: "Stimulation", description: "A mild energizing effect that is more subtle than traditional stimulants, providing increased wakefulness without intense physical activation."),
                SubjectiveEffect(name: "Focus Enhancement", description: "An improved ability to sustain attention on tasks, related to its dopaminergic mechanism rather than norepinephrine-driven alertness."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A moderate reduction in appetite that is secondary to its antidepressant-stimulant effects."),
                SubjectiveEffect(name: "Anxiety", description: "A potential for increased nervousness and restlessness, particularly during the initial adjustment period."),
                SubjectiveEffect(name: "Compulsive Redosing", description: "A reported tendency toward dose escalation and compulsive use patterns, which contributed to its withdrawal from the market due to abuse potential."),
                SubjectiveEffect(name: "Nausea", description: "A mild stomach queasiness that can occur with each dose, generally improving with food."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 60,
            sources: ["Drugs.com", "WHO", "PsychonautWiki", "StatPearls"]
        ),

        // MARK: - Prolintane

        Substance(
            name: "Prolintane",
            aliases: ["Catovit", "Promotil", "Villescon"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 5...10, common: 10...20, strong: 20...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Increased energy", "Alertness", "Wakefulness", "Appetite suppression", "Elevated heart rate", "Anxiety", "Insomnia", "Restlessness", "Nausea", "Dry mouth"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Stimulation", description: "A moderate, straightforward physical and mental energy boost that is sometimes compared to a combination of caffeine and a mild amphetamine."),
                SubjectiveEffect(name: "Wakefulness", description: "A strong anti-fatigue effect that keeps users alert and attentive for several hours."),
                SubjectiveEffect(name: "Alertness", description: "A heightened state of vigilance and sensory awareness, making it easier to notice and respond to environmental stimuli."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A noticeable reduction in hunger that accompanies the stimulant effects."),
                SubjectiveEffect(name: "Cardiovascular Stimulation", description: "A prominent increase in heart rate that can be felt as a racing heart, especially at higher doses."),
                SubjectiveEffect(name: "Restlessness", description: "A jittery, agitated feeling with difficulty remaining calm or seated, more pronounced at higher doses."),
                SubjectiveEffect(name: "Dry Mouth", description: "A consistent dryness in the mouth that persists through the duration of effects."),
                SubjectiveEffect(name: "Anxiety", description: "A nervous tension that escalates with dose, potentially leading to uncomfortable feelings of unease and worry."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120,
            sources: ["PsychonautWiki", "PubMed", "DrugBank"]
        ),

        // MARK: - Theacrine

        Substance(
            name: "Theacrine",
            aliases: ["TeaCrine", "1,3,7,9-Tetramethyluric acid"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...300, heavy: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 480)
                )),
            ],
            effects: ["Wakefulness", "Increased energy", "Mood lift", "Increased focus", "Reduced fatigue", "Mild euphoria", "Nausea", "Restlessness", "Headache", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Wakefulness", description: "A caffeine-like alertness that is often described as smoother and longer-lasting, without the jitteriness typically associated with high-dose caffeine."),
                SubjectiveEffect(name: "Mood Lift", description: "A gentle enhancement of mood and sense of well-being, slightly more noticeable than caffeine and sometimes described as mildly euphoric."),
                SubjectiveEffect(name: "Focus Enhancement", description: "A subtle improvement in sustained attention and task engagement, comparable to caffeine but reportedly with less tolerance development."),
                SubjectiveEffect(name: "Reduced Fatigue", description: "A notable decrease in feelings of tiredness and mental fog, with users reporting sustained performance during extended tasks."),
                SubjectiveEffect(name: "Stimulation", description: "A moderate increase in physical and mental energy that builds gradually and persists without the sharp peak-and-crash cycle of caffeine."),
                SubjectiveEffect(name: "Tolerance Resistance", description: "A reported lack of rapid tolerance development compared to caffeine, allowing for more consistent effects with regular use."),
                SubjectiveEffect(name: "Nausea", description: "A mild stomach discomfort that can occur particularly at higher doses, sometimes mitigated by taking with food."),
                SubjectiveEffect(name: "Insomnia", description: "Potential difficulty falling asleep if taken too late in the day, though typically less disruptive than equivalent caffeine doses."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 150,
            sources: ["Examine.com", "PubMed"]
        ),

        // MARK: - Dynamine

        Substance(
            name: "Dynamine",
            aliases: ["Methylliberine", "2-Methylliberine"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...300, heavy: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: nil,
                    total: TimeRange(min: 60, max: 120)
                )),
            ],
            effects: ["Increased energy", "Alertness", "Mood lift", "Increased focus", "Rapid onset", "Short duration", "Elevated heart rate", "Jitteriness", "Headache", "Nausea"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Rapid Onset Stimulation", description: "A quick-hitting burst of energy and alertness that develops faster than caffeine, often felt within 15-30 minutes of ingestion."),
                SubjectiveEffect(name: "Mood Lift", description: "A brief enhancement of mood and sense of well-being that is subtle but noticeable, adding a pleasant tone to the stimulation."),
                SubjectiveEffect(name: "Focus Enhancement", description: "A short-lived sharpening of concentration that pairs well with its rapid onset, useful for short bursts of productivity."),
                SubjectiveEffect(name: "Short Duration", description: "A notably brief window of effects lasting roughly 1-2 hours, making it useful for targeted energy boosts without long-lasting effects."),
                SubjectiveEffect(name: "Alertness", description: "A heightened state of mental clarity and awareness that comes on quickly but fades relatively fast."),
                SubjectiveEffect(name: "Jitteriness", description: "A shaky, tremulous energy that can feel uncomfortable at higher doses, similar to overcaffeination."),
                SubjectiveEffect(name: "Cardiovascular Stimulation", description: "A noticeable increase in heart rate that develops quickly with the rapid onset, particularly pronounced during physical activity."),
                SubjectiveEffect(name: "Headache", description: "A tension headache that may develop as the short-lived effects wear off, potentially related to the rapid metabolic clearance."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 60,
            sources: ["Examine.com", "PubMed"]
        ),

        // MARK: - Yohimbine

        Substance(
            name: "Yohimbine",
            aliases: ["Yohimbe", "Pausinystalia yohimbe", "Quebrachine"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 2.5...5, common: 5...10, strong: 10...15, heavy: 15, fatal: 100
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Increased energy", "Appetite suppression", "Anxiety", "Elevated heart rate", "Elevated blood pressure", "Sweating", "Nausea", "Panic attacks", "Tremor", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Stimulation", description: "A distinctly anxiogenic stimulation driven by alpha-2 adrenergic antagonism, often felt as a restless, 'fight-or-flight' activation rather than pleasant energy."),
                SubjectiveEffect(name: "Anxiety", description: "A pronounced anxious feeling that is one of the most characteristic effects, ranging from mild nervousness to full panic attacks at higher doses."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A noticeable reduction in hunger related to its adrenergic and lipolytic activity, historically used as a fat-loss supplement."),
                SubjectiveEffect(name: "Cardiovascular Stimulation", description: "A strong increase in heart rate and blood pressure that can feel overwhelming and is often the most immediately noticeable physical effect."),
                SubjectiveEffect(name: "Sweating", description: "An increased perspiration response that can be profuse, driven by sympathetic nervous system activation."),
                SubjectiveEffect(name: "Panic Attacks", description: "A potential for sudden, intense episodes of fear and physical distress, particularly in those predisposed to anxiety or at higher doses."),
                SubjectiveEffect(name: "Tremor", description: "A visible shaking of hands and limbs that can be quite pronounced, reflecting the intensity of the adrenergic activation."),
                SubjectiveEffect(name: "Body Awareness", description: "An amplified awareness of physical sensations and bodily functions, sometimes causing benign sensations to feel concerning or alarming."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 36,
            sources: ["Drugs.com", "FDA DailyMed", "PsychonautWiki", "StatPearls"]
        ),

        // MARK: - Hordenine

        Substance(
            name: "Hordenine",
            aliases: ["N,N-Dimethyltyramine", "Anhaline", "Peyocactin"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 20...50, common: 50...100, strong: 100...150, heavy: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 15),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: nil,
                    total: TimeRange(min: 60, max: 180)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...25, common: 25...50, strong: 50...75, heavy: 75
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 10),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 20, max: 40),
                    afterglow: nil,
                    total: TimeRange(min: 30, max: 90)
                )),
            ],
            effects: ["Mild stimulation", "Increased energy", "Mood lift", "Appetite suppression", "Elevated heart rate", "Nausea", "Headache", "Anxiety", "Sweating", "Elevated blood pressure"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mild Stimulation", description: "A gentle, subtle increase in energy and alertness that is barely noticeable on its own, often used to potentiate other stimulants like caffeine."),
                SubjectiveEffect(name: "Mood Lift", description: "A very mild improvement in mood and sense of well-being, often described as barely perceptible without the context of a combined supplement stack."),
                SubjectiveEffect(name: "MAO-B Inhibition", description: "A potentiation of other phenylethylamine-type compounds through monoamine oxidase inhibition, which extends the effects of co-administered stimulants."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A mild reduction in hunger, contributing subtly to its use in weight-loss supplement formulations."),
                SubjectiveEffect(name: "Cardiovascular Stimulation", description: "A slight increase in heart rate and blood pressure that is usually only noticeable when combined with other stimulants."),
                SubjectiveEffect(name: "Nausea", description: "A stomach discomfort that can occur particularly at higher doses or when combined with other supplements."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 60,
            sources: ["Drugs.com", "PubMed", "PsychonautWiki", "StatPearls"]
        ),

        // MARK: - Synephrine

        Substance(
            name: "Synephrine",
            aliases: ["p-Synephrine", "Oxedrine", "Bitter Orange Extract"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Increased energy", "Appetite suppression", "Mild stimulation", "Elevated heart rate", "Elevated blood pressure", "Sweating", "Nausea", "Headache", "Anxiety", "Restlessness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mild Stimulation", description: "A gentle increase in energy and alertness similar to a mild dose of ephedrine, sometimes used in fat-loss supplement stacks."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A moderate reduction in hunger driven by its adrenergic receptor activity, one of the primary reasons it is used in weight management."),
                SubjectiveEffect(name: "Cardiovascular Stimulation", description: "A noticeable increase in heart rate and blood pressure, particularly when combined with caffeine or other stimulants."),
                SubjectiveEffect(name: "Thermogenesis", description: "A subtle increase in body temperature and metabolic rate, sometimes felt as mild warmth or increased sweating during physical activity."),
                SubjectiveEffect(name: "Sweating", description: "An increase in perspiration, especially during exercise, related to the metabolic and sympathomimetic effects."),
                SubjectiveEffect(name: "Headache", description: "A tension-type headache that can develop with regular use, potentially related to blood pressure elevation."),
                SubjectiveEffect(name: "Nausea", description: "A stomach discomfort that can occur at higher doses, particularly when consumed on an empty stomach."),
                SubjectiveEffect(name: "Restlessness", description: "A mild fidgety energy that can make relaxation difficult, especially at higher doses or when combined with caffeine."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 150,
            sources: ["Drugs.com", "FDA DailyMed", "PsychonautWiki", "StatPearls"]
        ),

        // MARK: - Clenbuterol

        Substance(
            name: "Clenbuterol",
            aliases: ["Clen", "Spiropent", "Ventipulmin"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mcg", doses: DoseRange(
                    threshold: 10, light: 20...40, common: 40...80, strong: 80...120, heavy: 120, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Increased metabolic rate", "Bronchodilation", "Tremor", "Elevated heart rate", "Sweating", "Appetite suppression", "Insomnia", "Muscle cramps", "Anxiety", "Elevated blood pressure"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Thermogenesis", description: "A sustained increase in body temperature and metabolic rate that is felt as persistent internal warmth, with the body burning more calories at rest."),
                SubjectiveEffect(name: "Tremor", description: "A pronounced shaking of the hands and body that is one of the most prominent and consistent effects, particularly noticeable during fine motor tasks."),
                SubjectiveEffect(name: "Cardiovascular Stimulation", description: "A significant increase in heart rate that can be felt as a pounding or racing heart, often the most immediately concerning physical effect."),
                SubjectiveEffect(name: "Muscle Cramps", description: "Painful, involuntary muscle contractions that commonly affect the calves and hands, caused by taurine depletion and electrolyte shifts."),
                SubjectiveEffect(name: "Sweating", description: "A profuse perspiration response that occurs even at rest, becoming extreme during physical activity due to elevated metabolic rate."),
                SubjectiveEffect(name: "Stimulation", description: "A jittery, restless energy that feels more peripheral and physical than cerebral, making it difficult to sit still or relax."),
                SubjectiveEffect(name: "Insomnia", description: "A significant difficulty falling and staying asleep related to sustained beta-adrenergic stimulation, especially problematic at higher doses."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A notable reduction in hunger that is one of the primary reasons for its off-label use in body composition optimization."),
                SubjectiveEffect(name: "Bronchodilation", description: "A noticeable opening of the airways that makes breathing feel deeper and easier, reflecting its original medical purpose for treating asthma."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 2100,
            sources: ["Drugs.com", "Merck Manual", "PsychonautWiki", "StatPearls"]
        ),

        // MARK: - Herbal & Ethnobotanical Stimulants

        // MARK: - Khat

        Substance(
            name: "Khat",
            aliases: ["Catha edulis", "Qat", "Chat", "Miraa"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "g", doses: DoseRange(
                    threshold: 20, light: 50...100, common: 100...200, strong: 200...400, heavy: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Euphoria", "Stimulation", "Appetite suppression", "Alertness", "Talkativeness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Stimulating Euphoria", description: "A pleasant sense of well-being and alertness that develops gradually over 30-60 minutes of chewing fresh leaves, driven by the cathinone and cathine alkaloids."),
                SubjectiveEffect(name: "Talkativeness", description: "A pronounced increase in sociability and verbal fluency, making conversations feel engaging and effortless during traditional chewing sessions."),
                SubjectiveEffect(name: "Mental Alertness", description: "A clear, focused wakefulness with improved concentration and mental sharpness, traditionally valued for long work sessions and social gatherings."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A significant reduction in hunger signals that persists throughout the chewing session and for several hours afterward."),
                SubjectiveEffect(name: "Physical Energy", description: "An increase in physical vitality and restless energy that encourages activity and discourages sedentary behavior."),
                SubjectiveEffect(name: "Mood Elevation", description: "A consistent lift in mood with increased optimism and a sense that things are going well, similar in quality to a mild amphetamine effect."),
                SubjectiveEffect(name: "Comedown Irritability", description: "A period of low mood, irritability, and restless fatigue as the effects wear off, sometimes accompanied by mild depressive feelings."),
                SubjectiveEffect(name: "Insomnia", description: "Difficulty falling asleep for several hours after a chewing session, particularly when consumed later in the day."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "PubMed", "WHO"]
        ),

        // MARK: - Betel Nut

        Substance(
            name: "Betel Nut",
            aliases: ["Areca catechu", "Areca Nut", "Paan", "Supari"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "g", doses: DoseRange(
                    threshold: 0.5, light: 1...2, common: 2...4, strong: 4...8, heavy: 8
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: nil,
                    total: TimeRange(min: 60, max: 120)
                )),
            ],
            effects: ["Mild stimulation", "Euphoria", "Salivation", "Warm sensation", "Alertness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Warm Stimulation", description: "A mild, warm energizing sensation that spreads through the body within minutes of chewing, accompanied by a feeling of alertness and readiness."),
                SubjectiveEffect(name: "Mild Euphoria", description: "A gentle sense of well-being and contentment driven by arecoline acting on muscarinic and nicotinic acetylcholine receptors."),
                SubjectiveEffect(name: "Increased Salivation", description: "A pronounced increase in saliva production that is one of the most immediate and noticeable effects, often staining the mouth red when chewed with lime."),
                SubjectiveEffect(name: "Alertness Enhancement", description: "A subtle sharpening of mental focus and wakefulness, similar in quality to a mild dose of nicotine."),
                SubjectiveEffect(name: "Digestive Stimulation", description: "An increase in gastrointestinal activity and a warming sensation in the stomach that is traditionally believed to aid digestion."),
                SubjectiveEffect(name: "Facial Flushing", description: "A warm reddening of the face and a sense of heat in the cheeks that accompanies the stimulant onset."),
                SubjectiveEffect(name: "Nausea", description: "Stomach discomfort and nausea that can occur in non-habitual users or at higher doses, sometimes progressing to vomiting."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 2, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 45,
            sources: ["PsychonautWiki", "Erowid", "PubMed", "WHO"]
        ),

        // MARK: - Guarana

        Substance(
            name: "Guarana",
            aliases: ["Paullinia cupana"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...500, strong: 500...1000, heavy: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Sustained energy", "Improved focus", "Appetite suppression", "Alertness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Sustained Energy", description: "A slow-release caffeine effect that provides steady, long-lasting energy without the sharp peak and crash of coffee, due to tannins slowing absorption."),
                SubjectiveEffect(name: "Mental Focus", description: "A clear, sustained improvement in concentration and cognitive performance that feels smoother and more even than pure caffeine."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A moderate reduction in hunger that complements the stimulant effects, historically used by Amazonian peoples during long hunts."),
                SubjectiveEffect(name: "Mood Lift", description: "A mild improvement in mood and motivation attributed to the combination of caffeine with theobromine and theophylline found in the seed."),
                SubjectiveEffect(name: "Physical Alertness", description: "An increased sense of wakefulness and readiness for physical activity without the jittery quality of high-dose caffeine."),
                SubjectiveEffect(name: "Gradual Onset", description: "A notably slower onset than coffee, with effects building over 30-60 minutes and sustaining for several hours due to the natural matrix of the seed."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 300,
            sources: ["Drugs.com", "FDA DailyMed", "PsychonautWiki", "StatPearls"]
        ),

        // MARK: - Yerba Mate

        Substance(
            name: "Yerba Mate",
            aliases: ["Ilex paraguariensis", "Mate", "Chimarrão"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "g", doses: DoseRange(
                    threshold: 2, light: 5...10, common: 10...20, strong: 20...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Sustained energy", "Focus", "Mood lift", "Appetite suppression", "Smooth stimulation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Smooth Stimulation", description: "A clean, sustained energy that feels distinctly different from coffee, often described as alert yet relaxed, attributed to the synergy of caffeine, theobromine, and chlorogenic acids."),
                SubjectiveEffect(name: "Mental Clarity", description: "An improved ability to focus and think clearly without the anxiety or jitteriness that often accompanies equivalent caffeine doses."),
                SubjectiveEffect(name: "Mood Enhancement", description: "A reliable lift in mood and sense of well-being that adds a positive, social quality to the stimulant effects."),
                SubjectiveEffect(name: "Physical Endurance", description: "Improved stamina and reduced perception of fatigue during physical activity, traditionally valued by South American laborers and athletes."),
                SubjectiveEffect(name: "Appetite Regulation", description: "A mild suppression of hunger that is less aggressive than pure caffeine, helping to naturally moderate food intake."),
                SubjectiveEffect(name: "Social Bonding", description: "A sense of warmth and communal connection when shared traditionally from a gourd, with the ritual itself enhancing the social effects."),
                SubjectiveEffect(name: "Digestive Stimulation", description: "A mild stimulation of digestive processes and bowel motility, more gentle than coffee but still noticeable with regular consumption."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 300,
            sources: ["Drugs.com", "FDA DailyMed", "PsychonautWiki", "StatPearls"]
        ),

        // MARK: - Coca Leaf

        Substance(
            name: "Coca Leaf",
            aliases: ["Erythroxylum coca", "Coca Tea", "Mate de Coca"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "g", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...10, strong: 10...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: nil,
                    total: TimeRange(min: 60, max: 180)
                )),
            ],
            effects: ["Mild stimulation", "Appetite suppression", "Altitude sickness relief", "Numbness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Gentle Stimulation", description: "A mild, clean energy and wakefulness that is far subtler than refined cocaine, comparable to strong coffee but with a smoother, more grounded quality."),
                SubjectiveEffect(name: "Appetite Suppression", description: "A noticeable reduction in hunger that has been used for centuries by Andean peoples to sustain energy during long periods of physical labor without food."),
                SubjectiveEffect(name: "Altitude Sickness Relief", description: "A traditional remedy for soroche (altitude sickness) that reduces headache, nausea, and fatigue when consumed as tea at high elevations."),
                SubjectiveEffect(name: "Oral Numbness", description: "A mild tingling and numbing of the mouth, tongue, and gums when leaves are chewed, caused by trace amounts of cocaine alkaloid in the natural leaf."),
                SubjectiveEffect(name: "Mood Elevation", description: "A gentle improvement in mood and sense of well-being that is mild and functional, lacking the intense euphoria of concentrated cocaine."),
                SubjectiveEffect(name: "Physical Endurance", description: "An improved ability to sustain physical exertion, traditionally valued by indigenous peoples for long treks through mountainous terrain."),
                SubjectiveEffect(name: "Digestive Aid", description: "A soothing effect on the stomach when consumed as tea, traditionally used to ease digestive discomfort and nausea."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 60,
            sources: ["PsychonautWiki", "Erowid", "PubMed", "WHO"]
        ),
    ]
}
