import Foundation

extension SubstanceLibrary {

    // MARK: - RC Dissociatives

    static let researchChemicalsDissociatives: [Substance] = [

        // MARK: 3-Me-PCP

        Substance(
            name: "3-Me-PCP",
            aliases: ["3-Methylphencyclidine"],
            category: .dissociative,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 3...6, common: 6...10, strong: 10...15, heavy: 15, fatal: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 240, max: 480),
                    total: TimeRange(min: 300, max: 480)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...8, strong: 8...12, heavy: 12
                ), duration: DurationProfile(
                    onset: TimeRange(min: 2, max: 10),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Dissociation", "Mania", "Stimulation", "Euphoria", "Delusions of sobriety", "Conceptual thinking", "Motor control loss", "Compulsive redosing"],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 720,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA"]
        ),

        // MARK: 3-Me-PCPy

        Substance(
            name: "3-Me-PCPy",
            aliases: ["3-Methyl-PCPy", "3-Methylrolicyclidine"],
            category: .dissociative,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 4...8, common: 8...15, strong: 15...22, heavy: 22
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 180, max: 480),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Dissociation", "Stimulation", "Mania", "Euphoria", "Conceptual thinking", "Motor control loss", "Delusions of sobriety"],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 480,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA"]
        ),

        // MARK: 3-Cl-PCP

        Substance(
            name: "3-Cl-PCP",
            aliases: ["3-Chlorophencyclidine"],
            category: .dissociative,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...10, strong: 10...15, heavy: 15, fatal: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 40),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 240, max: 480),
                    total: TimeRange(min: 300, max: 480)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...4, common: 4...8, strong: 8...12, heavy: 12
                ), duration: DurationProfile(
                    onset: TimeRange(min: 2, max: 10),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Dissociation", "Mania", "Stimulation", "Euphoria", "Delusions of sobriety", "Motor control loss", "Conceptual thinking", "Compulsive redosing"],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 720,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA"]
        ),

        // MARK: PCE

        Substance(
            name: "PCE",
            aliases: ["Eticyclidine", "N-Ethyl-1-phenylcyclohexylamine"],
            category: .dissociative,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...10, strong: 10...15, heavy: 15, fatal: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 300),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 240, max: 480),
                    total: TimeRange(min: 360, max: 540)
                )),
            ],
            effects: ["Dissociation", "Mania", "Stimulation", "Euphoria", "Delusions of sobriety", "Motor control loss", "Spatial disorientation", "Compulsive redosing"],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 21, buildRate: "moderate"),
            halfLifeMinutes: 360,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA"]
        ),

        // MARK: 2-BDCK

        Substance(
            name: "2-BDCK",
            aliases: ["2-Bromodeschloroketamine", "2-Bromoketamine"],
            category: .dissociative,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 20...40, common: 40...80, strong: 80...150, heavy: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 15),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 30, max: 90),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 120, max: 300)
                )),
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 20, light: 40...80, common: 80...150, strong: 150...250, heavy: 250
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 180, max: 420)
                )),
            ],
            effects: ["Dissociation", "Ketamine-like effects", "Longer duration", "Hole potential", "Nausea", "Motor control loss", "Euphoria"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Ketamine-like dissociation", description: "A dissociative state closely resembling ketamine but with a notably longer duration, providing extended periods of detachment from physical reality and bodily awareness."),
                SubjectiveEffect(name: "Hole potential", description: "At sufficient doses, a deep immersive dissociative experience analogous to the ketamine hole, where awareness of the external world is completely replaced by an internal experiential landscape."),
                SubjectiveEffect(name: "Extended duration", description: "Effects persist significantly longer than ketamine, often lasting 3-5 hours compared to ketamine's 1-2 hours, which can be either desirable or uncomfortably prolonged."),
                SubjectiveEffect(name: "Euphoria", description: "A warm, floating sense of well-being and contentment that accompanies the dissociative state, comparable in quality to ketamine but more sustained."),
                SubjectiveEffect(name: "Nausea", description: "A common gastrointestinal discomfort that may be more pronounced than with ketamine, particularly during the onset phase or at higher doses."),
                SubjectiveEffect(name: "Motor control loss", description: "A progressive impairment of physical coordination and balance that makes walking hazardous, requiring a safe seated or lying position before effects intensify."),
                SubjectiveEffect(name: "Cognitive disconnection", description: "A detachment from normal thought patterns where linear thinking dissolves into abstract, dreamlike ideation and the boundaries between self and environment blur."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA"]
        ),
    ]

    // MARK: - RC Opioids

    static let researchChemicalsOpioids: [Substance] = [

        // MARK: AP-238

        Substance(
            name: "AP-238",
            aliases: ["AP238"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 15...30, common: 30...50, strong: 50...80, heavy: 80, fatal: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Euphoria", "Analgesia", "Sedation", "Anxiolysis", "Respiratory depression", "Nausea", "Warmth", "Itching"],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA"]
        ),

        // MARK: Metonitazene

        Substance(
            name: "Metonitazene",
            aliases: ["Metonitazine"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.5, light: 1...2, common: 2...5, strong: 5...10, heavy: 10, fatal: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 30),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Euphoria", "Analgesia", "Sedation", "Respiratory depression", "Nausea", "Itching", "Warmth", "Cognitive suppression"],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA"]
        ),

        // MARK: Protonitazene

        Substance(
            name: "Protonitazene",
            aliases: ["Protonitazine"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "\u{00B5}g", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...15, strong: 15...30, heavy: 30, fatal: 250
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 30),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Euphoria", "Analgesia", "Sedation", "Respiratory depression", "Nausea", "Warmth", "Itching", "Cognitive suppression"],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 120,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA"]
        ),

        // MARK: Dipyanone

        Substance(
            name: "Dipyanone",
            aliases: ["Pipadone analog"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60, fatal: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 45),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 480)
                )),
            ],
            effects: ["Euphoria", "Analgesia", "Sedation", "Anxiolysis", "Respiratory depression", "Nausea", "Warmth"],
            toleranceInfo: ToleranceInfo(halfLife: 4, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 240,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA"]
        ),

        // MARK: 2F-Viminol

        Substance(
            name: "2F-Viminol",
            aliases: ["2-Fluoroviminol"],
            category: .opioid,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...5, common: 5...10, strong: 10...15, heavy: 15, fatal: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Euphoria", "Analgesia", "Sedation", "Anxiolysis", "Respiratory depression", "Nausea", "Warmth"],
            toleranceInfo: ToleranceInfo(halfLife: 4, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 240,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA"]
        ),

        // MARK: N-Desethyl Isotonitazene

        Substance(
            name: "N-Desethyl Isotonitazene",
            aliases: ["N-Desethyl Iso"],
            category: .opioid,
            defaultRoute: .insufflation,
            routes: [
                SubstanceRoute(route: .insufflation, unit: "\u{00B5}g", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...500, heavy: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 2, max: 5),
                    peak: TimeRange(min: 15, max: 60),
                    offset: TimeRange(min: 15, max: 30),
                    afterglow: nil,
                    total: TimeRange(min: 60, max: 150)
                )),
                SubstanceRoute(route: .oral, unit: "\u{00B5}g", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...400, strong: 400...1000, heavy: 1000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 25),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 30, max: 90),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: nil,
                    total: TimeRange(min: 120, max: 240)
                )),
            ],
            effects: ["Extreme opioid potency", "Respiratory depression", "Overdose risk", "Euphoria", "Sedation", "Nausea", "Nodding"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Extreme opioid potency", description: "A benzimidazole opioid with potency comparable to isotonitazene, active at microgram doses with an extraordinarily dangerous margin of error that makes accidental overdose almost inevitable without precise measurement."),
                SubjectiveEffect(name: "Respiratory depression", description: "A severe and life-threatening suppression of the breathing reflex that can progress to respiratory arrest within minutes, often resistant to standard naloxone reversal doses."),
                SubjectiveEffect(name: "Intense euphoria", description: "A powerful opioid euphoria characterized by overwhelming warmth and bliss that contributes to the compound's extreme addiction potential."),
                SubjectiveEffect(name: "Heavy sedation and nodding", description: "A profound drowsiness and characteristic opioid nodding where consciousness drifts in and out, easily progressing to dangerous unconsciousness."),
                SubjectiveEffect(name: "Nausea and vomiting", description: "Severe opioid-induced nausea that poses a critical aspiration risk in users who are deeply sedated or unconscious."),
                SubjectiveEffect(name: "Fatal overdose risk", description: "Among the most dangerous opioids in existence, with numerous confirmed fatalities and a potency that makes standard harm reduction measures extremely difficult to apply."),
                SubjectiveEffect(name: "Naloxone resistance", description: "Multiple doses of naloxone may be required to reverse overdose effects due to the compound's extreme receptor binding affinity, complicating emergency medical response."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid"),
            halfLifeMinutes: 180,
            sources: ["PsychonautWiki", "Erowid", "EMCDDA"]
        ),
    ]

    // MARK: - RC Benzodiazepines

    static let researchChemicalsBenzodiazepines: [Substance] = [
    ]

    // MARK: - RC Empathogens

    static let researchChemicalsEmpathogens: [Substance] = [
    ]
}
