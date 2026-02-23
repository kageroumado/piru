import Foundation

extension SubstanceLibrary {
    static let commonMedications: [Substance] = [

        // MARK: - Analgesics

        Substance(
            name: "Acetaminophen",
            aliases: ["Tylenol", "Paracetamol", "APAP"],
            category: .analgesic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 250...500, common: 500...1000, strong: 1000...1500, heavy: 1500, fatal: 10000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Pain relief", "Reduced fever", "Headache relief", "Mild relaxation", "Liver strain at high doses"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Pain Relief", description: "A gradual dulling of mild to moderate pain that typically becomes noticeable within 30-60 minutes of dosing."),
                SubjectiveEffect(name: "Fever Reduction", description: "A cooling sensation and reduced malaise as body temperature normalizes over 1-2 hours."),
                SubjectiveEffect(name: "Headache Relief", description: "A loosening of headache tension and throbbing that develops within 30-45 minutes."),
                SubjectiveEffect(name: "Mild Relaxation", description: "A subtle easing of tension and discomfort that can feel like a general settling of the body."),
                SubjectiveEffect(name: "Stomach Comfort", description: "Generally well-tolerated on the stomach compared to NSAIDs, though high doses can cause nausea."),
            ],
            halfLifeMinutes: 180,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Ibuprofen",
            aliases: ["Advil", "Motrin"],
            category: .analgesic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...400, strong: 400...800, heavy: 800, fatal: 20000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 480)
                )),
            ],
            effects: ["Pain relief", "Anti-inflammatory", "Reduced fever", "Stomach upset", "Reduced swelling", "Headache relief"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Pain Relief", description: "A noticeable reduction in pain intensity that develops within 30-60 minutes and lasts 4-6 hours."),
                SubjectiveEffect(name: "Anti-Inflammatory Effect", description: "A reduction in swelling, redness, and warmth in inflamed areas that builds over hours of dosing."),
                SubjectiveEffect(name: "Fever Reduction", description: "A cooling and normalization of body temperature accompanied by reduced achiness and malaise."),
                SubjectiveEffect(name: "Stomach Irritation", description: "A burning or gnawing discomfort in the stomach, particularly when taken on an empty stomach."),
                SubjectiveEffect(name: "Headache Relief", description: "A effective loosening of headache pain, often considered first-line for tension and migraine headaches."),
                SubjectiveEffect(name: "Reduced Swelling", description: "A visible decrease in inflammatory swelling in joints and soft tissues over hours to days."),
            ],
            halfLifeMinutes: 120,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Aspirin",
            aliases: ["ASA", "Bayer"],
            category: .analgesic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 40, light: 81...325, common: 325...650, strong: 650...1000, heavy: 1000, fatal: 20000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 480)
                )),
            ],
            effects: ["Pain relief", "Anti-inflammatory", "Reduced fever", "Blood thinning", "Stomach irritation", "Headache relief"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Pain Relief", description: "A reduction in mild to moderate pain that develops within 30 minutes and lasts several hours."),
                SubjectiveEffect(name: "Anti-Inflammatory Effect", description: "A decrease in swelling and inflammatory pain that builds with consistent dosing."),
                SubjectiveEffect(name: "Fever Reduction", description: "A cooling of elevated body temperature with accompanying relief from fever-related achiness."),
                SubjectiveEffect(name: "Stomach Irritation", description: "A burning or uncomfortable feeling in the stomach, especially on an empty stomach or with chronic use."),
                SubjectiveEffect(name: "Blood Thinning", description: "Irreversible platelet inhibition that leads to easier bruising and prolonged bleeding from cuts."),
                SubjectiveEffect(name: "Headache Relief", description: "Effective reduction of headache pain, particularly tension-type headaches."),
            ],
            halfLifeMinutes: 180,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Naproxen",
            aliases: ["Aleve", "Naprosyn"],
            category: .analgesic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 55, light: 110...220, common: 220...440, strong: 440...660, heavy: 660, fatal: 15000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1080)
                )),
            ],
            effects: ["Pain relief", "Anti-inflammatory", "Reduced swelling", "Reduced fever", "Stomach upset", "Menstrual cramp relief"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Pain Relief", description: "A sustained reduction in pain that develops within 1-2 hours and lasts longer than ibuprofen, up to 12 hours."),
                SubjectiveEffect(name: "Anti-Inflammatory Effect", description: "A reduction in joint and muscle inflammation that builds with regular dosing."),
                SubjectiveEffect(name: "Menstrual Cramp Relief", description: "An easing of uterine cramping and pelvic discomfort during menstruation."),
                SubjectiveEffect(name: "Stomach Upset", description: "Mild GI discomfort that may develop with chronic use, though generally less than with shorter-acting NSAIDs."),
                SubjectiveEffect(name: "Reduced Swelling", description: "A decrease in inflammatory swelling that improves joint mobility and comfort."),
                SubjectiveEffect(name: "Fever Reduction", description: "A normalization of elevated body temperature with relief from fever symptoms."),
            ],
            halfLifeMinutes: 870,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Celecoxib",
            aliases: ["Celebrex"],
            category: .analgesic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...400, strong: 400...600, heavy: 600, fatal: 10000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 360, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 720)
                )),
            ],
            effects: ["Pain relief", "Anti-inflammatory", "Joint stiffness relief", "Reduced swelling", "Less GI irritation than other NSAIDs"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Pain Relief", description: "A smooth reduction in arthritis and inflammatory pain with less stomach discomfort than traditional NSAIDs."),
                SubjectiveEffect(name: "Joint Stiffness Relief", description: "A loosening of stiff, painful joints that improves mobility and comfort over days of consistent use."),
                SubjectiveEffect(name: "Anti-Inflammatory Effect", description: "A targeted reduction in inflammation with COX-2 selectivity providing a more focused anti-inflammatory action."),
                SubjectiveEffect(name: "Reduced Swelling", description: "A decrease in inflammatory swelling around joints and soft tissues."),
                SubjectiveEffect(name: "GI Tolerability", description: "Notably less stomach irritation and ulcer risk compared to traditional NSAIDs, often reported as gentler on the stomach."),
            ],
            halfLifeMinutes: 660,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Meloxicam",
            aliases: ["Mobic"],
            category: .analgesic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 3.75, light: 7.5...15, common: 7.5...15, strong: 15...22.5, heavy: 22.5
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 300, max: 420),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 960, max: 1440)
                )),
            ],
            effects: ["Pain relief", "Anti-inflammatory", "Reduced joint stiffness", "Reduced swelling", "Improved mobility"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Pain Relief", description: "A steady reduction in joint and inflammatory pain with once-daily dosing that builds over days."),
                SubjectiveEffect(name: "Reduced Joint Stiffness", description: "A loosening of morning stiffness and joint rigidity that improves mobility throughout the day."),
                SubjectiveEffect(name: "Anti-Inflammatory Effect", description: "A reduction in inflammatory swelling and heat that develops over hours to days."),
                SubjectiveEffect(name: "Improved Mobility", description: "An increased ability to move joints and engage in physical activity as pain and stiffness diminish."),
                SubjectiveEffect(name: "GI Tolerability", description: "Generally better stomach tolerance than older NSAIDs, though some GI effects can still occur."),
            ],
            halfLifeMinutes: 1200,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Diclofenac",
            aliases: ["Voltaren"],
            category: .analgesic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 12.5, light: 25...50, common: 50...100, strong: 100...150, heavy: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 240, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 540)
                )),
            ],
            effects: ["Pain relief", "Anti-inflammatory", "Reduced swelling", "Joint pain relief", "Muscle pain relief", "Stomach upset"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Pain Relief", description: "A potent reduction in pain from both topical and oral formulations, with the gel providing localized relief."),
                SubjectiveEffect(name: "Anti-Inflammatory Effect", description: "A strong anti-inflammatory action that reduces swelling and heat in affected areas."),
                SubjectiveEffect(name: "Joint Pain Relief", description: "A targeted easing of joint pain that improves with consistent use over days."),
                SubjectiveEffect(name: "Muscle Pain Relief", description: "A reduction in muscle soreness and stiffness, particularly effective for acute musculoskeletal injuries."),
                SubjectiveEffect(name: "Stomach Upset", description: "GI discomfort that can include nausea, indigestion, and abdominal pain, particularly with oral use."),
            ],
            halfLifeMinutes: 90,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Ketorolac",
            aliases: ["Toradol"],
            category: .analgesic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...30, strong: 30...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 420)
                )),
                SubstanceRoute(route: .intramuscular, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 15...30, common: 15...30, strong: 30...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 20),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Strong pain relief", "Anti-inflammatory", "Reduced swelling", "Stomach upset", "Post-surgical pain relief"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Strong Pain Relief", description: "A powerful analgesic effect often compared to opioids in intensity, noticeable within 30 minutes of dosing."),
                SubjectiveEffect(name: "Anti-Inflammatory Effect", description: "A robust reduction in inflammation and swelling, particularly effective for post-surgical and acute pain."),
                SubjectiveEffect(name: "Post-Surgical Relief", description: "Rapid and effective pain control following surgical procedures without the sedation of opioid alternatives."),
                SubjectiveEffect(name: "Stomach Upset", description: "Significant GI discomfort including nausea and stomach pain, particularly with repeated dosing."),
                SubjectiveEffect(name: "Short Duration", description: "Pain relief that is intense but time-limited, requiring awareness that this medication is meant for short-term use only."),
            ],
            halfLifeMinutes: 330,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Indomethacin",
            aliases: ["Indocin"],
            category: .analgesic,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 12.5, light: 25...50, common: 50...100, strong: 100...150, heavy: 150, fatal: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 240, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 540)
                )),
            ],
            effects: ["Pain relief", "Anti-inflammatory", "Reduced swelling", "Gout pain relief", "Headache", "Stomach upset", "Dizziness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Pain Relief", description: "A powerful analgesic effect particularly effective for acute inflammatory conditions like gout."),
                SubjectiveEffect(name: "Gout Relief", description: "A dramatic reduction in the searing, burning pain of gout attacks that develops within hours."),
                SubjectiveEffect(name: "Anti-Inflammatory Effect", description: "One of the strongest NSAID anti-inflammatory effects, noticeable as a rapid reduction in swelling and heat."),
                SubjectiveEffect(name: "Headache", description: "A paradoxical headache that can develop as a side effect, sometimes described as a frontal pressure."),
                SubjectiveEffect(name: "Stomach Upset", description: "Significant GI distress including nausea, indigestion, and stomach pain that limits long-term use."),
                SubjectiveEffect(name: "Dizziness", description: "Lightheadedness and occasional vertigo that can occur during treatment."),
            ],
            halfLifeMinutes: 270,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        // MARK: - Antihistamines

        Substance(
            name: "Diphenhydramine",
            aliases: ["Benadryl", "DPH"],
            category: .antihistamine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 6.25, light: 12.5...25, common: 25...50, strong: 50...100, heavy: 100, fatal: 1500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 480)
                )),
            ],
            effects: ["Allergy relief", "Drowsiness", "Dry mouth", "Reduced itching", "Sleep aid", "Sedation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Sedation", description: "A pronounced drowsiness that develops within 30-60 minutes and can feel heavy and impairing."),
                SubjectiveEffect(name: "Allergy Relief", description: "A reduction in sneezing, runny nose, and itchy eyes that develops within an hour."),
                SubjectiveEffect(name: "Dry Mouth", description: "A noticeable oral dryness and thirst that accompanies the antihistamine effects."),
                SubjectiveEffect(name: "Reduced Itching", description: "A calming of skin itching and hives that provides significant relief for allergic reactions."),
                SubjectiveEffect(name: "Sleep Induction", description: "A powerful urge to sleep that makes this commonly used as an over-the-counter sleep aid."),
                SubjectiveEffect(name: "Morning Grogginess", description: "A lingering fogginess and sluggishness upon waking that can persist for hours."),
                SubjectiveEffect(name: "Cognitive Impairment", description: "A noticeable slowing of reaction time and mental processing that accompanies the sedation."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 7, buildRate: "rapid"),
            halfLifeMinutes: 360,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Cetirizine",
            aliases: ["Zyrtec"],
            category: .antihistamine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...20, strong: 20...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Allergy relief", "Reduced sneezing", "Reduced itching", "Mild drowsiness", "Reduced runny nose"],
            halfLifeMinutes: 540,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Loratadine",
            aliases: ["Claritin"],
            category: .antihistamine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...20, strong: 20...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 480, max: 720),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 1080, max: 1440)
                )),
            ],
            effects: ["Allergy relief", "Reduced sneezing", "Reduced itching", "Non-drowsy", "Reduced runny nose", "Hive relief"],
            halfLifeMinutes: 480,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Fexofenadine",
            aliases: ["Allegra"],
            category: .antihistamine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 15, light: 30...60, common: 60...180, strong: 180...360, heavy: 360
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 360, max: 600),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 1080, max: 1440)
                )),
            ],
            effects: ["Allergy relief", "Reduced sneezing", "Non-drowsy", "Reduced itching", "Reduced watery eyes"],
            halfLifeMinutes: 840,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Hydroxyzine",
            aliases: ["Vistaril", "Atarax"],
            category: .antihistamine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 6.25, light: 12.5...25, common: 25...50, strong: 50...100, heavy: 100, fatal: 3000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 600)
                )),
            ],
            effects: ["Anxiety relief", "Sedation", "Reduced itching", "Drowsiness", "Dry mouth", "Allergy relief"],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 1200,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Promethazine",
            aliases: ["Phenergan"],
            category: .antihistamine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 6.25, light: 12.5...25, common: 25...50, strong: 50...75, heavy: 75, fatal: 1500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 240, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 720)
                )),
            ],
            effects: ["Anti-nausea", "Sedation", "Allergy relief", "Drowsiness", "Dry mouth", "Dizziness"],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 14, buildRate: "moderate"),
            halfLifeMinutes: 960,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Chlorpheniramine",
            aliases: ["Chlor-Trimeton"],
            category: .antihistamine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...4, common: 4...8, strong: 8...16, heavy: 16, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 240, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 480)
                )),
            ],
            effects: ["Allergy relief", "Drowsiness", "Reduced sneezing", "Dry mouth", "Reduced runny nose"],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 7, buildRate: "rapid"),
            halfLifeMinutes: 1260,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Doxylamine",
            aliases: ["Unisom"],
            category: .antihistamine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 6.25, light: 12.5...25, common: 25...50, strong: 50...75, heavy: 75, fatal: 1500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 180),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 540)
                )),
            ],
            effects: ["Drowsiness", "Sleep aid", "Allergy relief", "Dry mouth", "Sedation", "Grogginess"],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 7, buildRate: "rapid"),
            halfLifeMinutes: 600,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Meclizine",
            aliases: ["Antivert", "Bonine"],
            category: .antihistamine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 6.25, light: 12.5...25, common: 25...50, strong: 50...75, heavy: 75
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Motion sickness relief", "Anti-nausea", "Reduced dizziness", "Drowsiness", "Dry mouth"],
            toleranceInfo: ToleranceInfo(halfLife: 5, fullResetDays: 10, buildRate: "moderate"),
            halfLifeMinutes: 360,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Dimenhydrinate",
            aliases: ["Dramamine", "Gravol"],
            category: .antihistamine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 12.5, light: 25...50, common: 50...100, strong: 100...150, heavy: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 480)
                )),
            ],
            effects: ["Motion sickness relief", "Anti-nausea", "Drowsiness", "Sedation", "Dry mouth", "Dizziness"],
            toleranceInfo: ToleranceInfo(halfLife: 3, fullResetDays: 7, buildRate: "rapid"),
            halfLifeMinutes: 480,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Levocetirizine",
            aliases: ["Xyzal"],
            category: .antihistamine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1.25, light: 2.5...5, common: 5...10, strong: 10...15, heavy: 15
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Allergy relief", "Reduced sneezing", "Reduced itching", "Mild drowsiness", "Reduced runny nose"],
            halfLifeMinutes: 480,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Desloratadine",
            aliases: ["Clarinex"],
            category: .antihistamine,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1.25, light: 2.5...5, common: 5...10, strong: 10...15, heavy: 15
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 480, max: 720),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 1080, max: 1440)
                )),
            ],
            effects: ["Allergy relief", "Reduced sneezing", "Non-drowsy", "Reduced itching", "Hive relief"],
            halfLifeMinutes: 1620,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        // MARK: - Proton Pump Inhibitors & Antacids

        Substance(
            name: "Omeprazole",
            aliases: ["Prilosec"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: ["Heartburn relief", "Reduced stomach acid", "GERD relief", "Ulcer healing", "Nausea reduction"],
            halfLifeMinutes: 60,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Pantoprazole",
            aliases: ["Protonix"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 20...40, common: 40...80, strong: 80...120, heavy: 120
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: ["Heartburn relief", "Reduced stomach acid", "GERD relief", "Ulcer healing", "Stomach pain relief"],
            halfLifeMinutes: 60,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Famotidine",
            aliases: ["Pepcid"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...80, heavy: 80
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 360, max: 600),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 720)
                )),
            ],
            effects: ["Heartburn relief", "Reduced stomach acid", "Indigestion relief", "Ulcer prevention", "Acid reflux relief"],
            halfLifeMinutes: 180,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        // MARK: - Metabolic

        Substance(
            name: "Metformin",
            aliases: ["Glucophage"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 125, light: 250...500, common: 500...1000, strong: 1000...2000, heavy: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 360, max: 600),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 720)
                )),
            ],
            effects: ["Blood sugar reduction", "Improved insulin sensitivity", "Appetite suppression", "GI discomfort", "Nausea", "Weight management"],
            halfLifeMinutes: 390,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Levothyroxine",
            aliases: ["Synthroid"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "\u{00B5}g", doses: DoseRange(
                    threshold: 12.5, light: 25...50, common: 50...100, strong: 100...200, heavy: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 120, max: 360),
                    comeup: TimeRange(min: 360, max: 720),
                    peak: TimeRange(min: 1440, max: 4320),
                    offset: TimeRange(min: 4320, max: 10080),
                    afterglow: nil,
                    total: TimeRange(min: 7200, max: 10080)
                )),
            ],
            effects: ["Increased energy", "Improved metabolism", "Reduced fatigue", "Mood stabilization", "Weight normalization", "Reduced cold sensitivity"],
            halfLifeMinutes: 10080,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        // MARK: - Cardiovascular

        Substance(
            name: "Lisinopril",
            aliases: ["Prinivil", "Zestril"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1.25, light: 2.5...5, common: 5...20, strong: 20...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 360, max: 480),
                    offset: TimeRange(min: 720, max: 1080),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2160)
                )),
            ],
            effects: ["Blood pressure reduction", "Heart protection", "Dry cough", "Dizziness", "Kidney protection"],
            halfLifeMinutes: 720,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Amlodipine",
            aliases: ["Norvasc"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1.25, light: 2.5...5, common: 5...10, strong: 10...15, heavy: 15
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 360, max: 720),
                    offset: TimeRange(min: 1440, max: 2880),
                    afterglow: nil,
                    total: TimeRange(min: 2160, max: 4320)
                )),
            ],
            effects: ["Blood pressure reduction", "Reduced chest pain", "Ankle swelling", "Dizziness", "Flushing"],
            halfLifeMinutes: 2100,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Losartan",
            aliases: ["Cozaar"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 12.5, light: 25...50, common: 50...100, strong: 100...150, heavy: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 720, max: 1080),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2160)
                )),
            ],
            effects: ["Blood pressure reduction", "Kidney protection", "Dizziness", "Fatigue", "Heart protection"],
            halfLifeMinutes: 420,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Atenolol",
            aliases: ["Tenormin"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 6.25, light: 12.5...25, common: 25...50, strong: 50...100, heavy: 100, fatal: 5000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 360, max: 600),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Reduced heart rate", "Blood pressure reduction", "Reduced anxiety tremor", "Fatigue", "Cold extremities", "Dizziness"],
            halfLifeMinutes: 420,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Metoprolol",
            aliases: ["Lopressor"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 6.25, light: 12.5...25, common: 25...100, strong: 100...200, heavy: 200, fatal: 5000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 240, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 720)
                )),
            ],
            effects: ["Reduced heart rate", "Blood pressure reduction", "Reduced chest pain", "Fatigue", "Dizziness", "Cold extremities"],
            halfLifeMinutes: 240,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Propranolol",
            aliases: ["Inderal"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...40, strong: 40...80, heavy: 80, fatal: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 480)
                )),
            ],
            effects: ["Reduced heart rate", "Anxiety relief", "Reduced tremor", "Blood pressure reduction", "Performance anxiety relief", "Fatigue"],
            halfLifeMinutes: 270,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Clonidine",
            aliases: ["Catapres"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.025, light: 0.05...0.1, common: 0.1...0.2, strong: 0.2...0.4, heavy: 0.4, fatal: 5
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1080)
                )),
            ],
            effects: ["Blood pressure reduction", "Sedation", "Dry mouth", "Anxiety relief", "Drowsiness", "ADHD symptom relief"],
            halfLifeMinutes: 780,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        // MARK: - PDE5 Inhibitors

        Substance(
            name: "Sildenafil",
            aliases: ["Viagra"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 10, light: 25...50, common: 50...100, strong: 100...150, heavy: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Increased blood flow", "Headache", "Flushing", "Nasal congestion", "Dizziness", "Visual changes"],
            halfLifeMinutes: 240,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Tadalafil",
            aliases: ["Cialis"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...20, strong: 20...40, heavy: 40
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 1440, max: 2160),
                    afterglow: nil,
                    total: TimeRange(min: 1800, max: 2880)
                )),
            ],
            effects: ["Increased blood flow", "Headache", "Back pain", "Flushing", "Nasal congestion", "Muscle aches"],
            halfLifeMinutes: 1050,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        // MARK: - Respiratory

        Substance(
            name: "Montelukast",
            aliases: ["Singulair"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 4...5, common: 5...10, strong: 10...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Reduced asthma symptoms", "Allergy relief", "Improved breathing", "Headache", "Mood changes", "Reduced nasal congestion"],
            halfLifeMinutes: 330,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        // MARK: - Corticosteroids

        Substance(
            name: "Prednisone",
            aliases: [],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2.5...5, common: 5...20, strong: 20...60, heavy: 60
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 120, max: 360),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Anti-inflammatory", "Increased appetite", "Insomnia", "Mood changes", "Fluid retention", "Immune suppression", "Elevated energy"],
            halfLifeMinutes: 210,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Dexamethasone",
            aliases: ["Decadron"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 0.25, light: 0.5...2, common: 2...4, strong: 4...10, heavy: 10, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 2160, max: 4320)
                )),
            ],
            effects: ["Anti-inflammatory", "Anti-nausea", "Increased appetite", "Insomnia", "Mood changes", "Immune suppression"],
            halfLifeMinutes: 2160,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        // MARK: - Mood Stabilizers & Anticonvulsants

        Substance(
            name: "Lithium",
            aliases: ["Lithobid", "Eskalith"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 75, light: 150...300, common: 300...600, strong: 600...1200, heavy: 1200, fatal: 3000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 60, max: 120),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2880)
                )),
            ],
            effects: ["Mood stabilization", "Reduced mania", "Increased thirst", "Tremor", "Weight gain", "Cognitive dulling", "Nausea"],
            halfLifeMinutes: 1440,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Lamotrigine",
            aliases: ["Lamictal"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 12.5, light: 25...50, common: 50...200, strong: 200...400, heavy: 400, fatal: 5000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2160)
                )),
            ],
            effects: ["Mood stabilization", "Seizure prevention", "Reduced depression", "Headache", "Dizziness", "Rash risk"],
            halfLifeMinutes: 1500,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Valproic Acid",
            aliases: ["Depakote", "Depakene"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 62.5, light: 125...250, common: 250...750, strong: 750...1500, heavy: 1500, fatal: 10000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 60, max: 240),
                    offset: TimeRange(min: 480, max: 960),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Mood stabilization", "Seizure prevention", "Weight gain", "Drowsiness", "Nausea", "Tremor", "Hair thinning"],
            halfLifeMinutes: 660,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Carbamazepine",
            aliases: ["Tegretol"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...600, strong: 600...1200, heavy: 1200, fatal: 10000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 480, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 720, max: 1440)
                )),
            ],
            effects: ["Mood stabilization", "Seizure prevention", "Nerve pain relief", "Drowsiness", "Dizziness", "Nausea"],
            halfLifeMinutes: 1080,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Topiramate",
            aliases: ["Topamax"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 12.5, light: 25...50, common: 50...200, strong: 200...400, heavy: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1080, max: 1800)
                )),
            ],
            effects: ["Seizure prevention", "Migraine prevention", "Appetite suppression", "Weight loss", "Cognitive dulling", "Tingling sensation"],
            halfLifeMinutes: 1260,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        // MARK: - Migraine & Anti-emetic

        Substance(
            name: "Sumatriptan",
            aliases: ["Imitrex"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 12.5, light: 25...50, common: 50...100, strong: 100...200, heavy: 200, fatal: 800
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 120, max: 240)
                )),
                SubstanceRoute(route: .subcutaneous, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 3...6, common: 6...12, strong: 12...18, heavy: 18
                ), duration: DurationProfile(
                    onset: TimeRange(min: 5, max: 10),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 120, max: 180)
                )),
            ],
            effects: ["Migraine relief", "Reduced nausea", "Chest tightness", "Tingling sensation", "Dizziness", "Fatigue"],
            halfLifeMinutes: 120,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Ondansetron",
            aliases: ["Zofran"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 1, light: 2...4, common: 4...8, strong: 8...16, heavy: 16
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 480)
                )),
            ],
            effects: ["Anti-nausea", "Anti-vomiting", "Headache", "Constipation", "Fatigue"],
            halfLifeMinutes: 210,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        // MARK: - Anxiolytics (Non-Benzodiazepine)

        Substance(
            name: "Buspirone",
            aliases: ["Buspar", "BuSpar"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...20, strong: 20...30, heavy: 30
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Anxiety relief", "Dizziness", "Headache", "Nausea", "Delayed onset (weeks)"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Gradual Anxiolysis", description: "Unlike benzodiazepines, anxiety relief develops slowly over 2-4 weeks of consistent dosing, with no immediate noticeable effect."),
                SubjectiveEffect(name: "Non-Sedating Calm", description: "A subtle reduction in anxious thought patterns that does not produce drowsiness or cognitive impairment."),
                SubjectiveEffect(name: "Dizziness on Initiation", description: "A lightheaded or unsteady feeling that is common during the first few days of treatment but typically resolves."),
                SubjectiveEffect(name: "Headache", description: "A mild tension-type headache that may occur during the initial adjustment period and usually diminishes with continued use."),
                SubjectiveEffect(name: "Nausea", description: "Mild stomach discomfort that occasionally accompanies the early phase of treatment, usually transient."),
                SubjectiveEffect(name: "No Recreational Potential", description: "The absence of euphoria, disinhibition, or immediate anxiolysis means this substance has virtually no abuse potential."),
                SubjectiveEffect(name: "Improved Baseline Anxiety", description: "After weeks of consistent use, a general lowering of baseline anxiety becomes apparent, making daily stressors feel more manageable."),
            ],
            halfLifeMinutes: 150,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        // MARK: - Anticonvulsants

        Substance(
            name: "Phenytoin",
            aliases: ["Dilantin", "Phenytek"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...300, strong: 300...400, heavy: 400, fatal: 2000
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 60, max: 120),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 720, max: 1440),
                    afterglow: nil,
                    total: TimeRange(min: 1440, max: 2160)
                )),
            ],
            effects: ["Seizure control", "Dizziness", "Gingival hyperplasia", "Ataxia", "Drowsiness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Seizure Suppression", description: "A stabilization of neuronal activity that prevents the electrical storms underlying seizures, noticed as an absence of seizure episodes."),
                SubjectiveEffect(name: "Dizziness", description: "A persistent sense of lightheadedness and unsteadiness, particularly at higher serum levels or during dose adjustments."),
                SubjectiveEffect(name: "Gingival Overgrowth", description: "Gums may become swollen, tender, and overgrown with chronic use, a distinctive and well-known side effect requiring dental hygiene vigilance."),
                SubjectiveEffect(name: "Ataxia", description: "Coordination and balance deteriorate at supratherapeutic levels, with unsteady gait and difficulty with fine motor tasks."),
                SubjectiveEffect(name: "Cognitive Slowing", description: "Mental processing may feel slightly dulled, with reduced sharpness in concentration and slower reaction times."),
                SubjectiveEffect(name: "Drowsiness", description: "A mild to moderate sedation that can interfere with alertness, especially during initial dosing or after dose increases."),
            ],
            halfLifeMinutes: 1320,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Levetiracetam",
            aliases: ["Keppra"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 125, light: 250...500, common: 500...1000, strong: 1000...1500, heavy: 1500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 360, max: 480),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 720)
                )),
            ],
            effects: ["Seizure control", "Drowsiness", "Irritability", "Mood changes", "Fatigue"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Seizure Suppression", description: "Effective broad-spectrum seizure control that is typically well-tolerated, noticed as a reduction or elimination of seizure episodes."),
                SubjectiveEffect(name: "Irritability", description: "A notable increase in irritability and short-temperedness that is commonly reported, sometimes called 'Keppra rage' by patients."),
                SubjectiveEffect(name: "Mood Changes", description: "Emotional lability or depressive feelings may develop, requiring monitoring for behavioral changes during treatment."),
                SubjectiveEffect(name: "Drowsiness", description: "A mild to moderate sleepiness that is most prominent during the initial weeks of treatment and tends to improve."),
                SubjectiveEffect(name: "Fatigue", description: "A pervasive tiredness and low energy that can accompany treatment, particularly at higher doses."),
                SubjectiveEffect(name: "Cognitive Effects", description: "Some patients report difficulty with concentration or word-finding, though generally milder than with older anticonvulsants."),
            ],
            halfLifeMinutes: 420,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Oxcarbazepine",
            aliases: ["Trileptal"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 75, light: 150...300, common: 300...600, strong: 600...1200, heavy: 1200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 300),
                    offset: TimeRange(min: 360, max: 600),
                    afterglow: nil,
                    total: TimeRange(min: 540, max: 960)
                )),
            ],
            effects: ["Seizure control", "Dizziness", "Drowsiness", "Hyponatremia", "Double vision"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Seizure Suppression", description: "Effective control of partial seizures through sodium channel blockade, noticed as a reduction in seizure frequency and severity."),
                SubjectiveEffect(name: "Dizziness", description: "A spinning or lightheaded sensation that is common during dose titration and may persist at higher doses."),
                SubjectiveEffect(name: "Drowsiness", description: "A sedating effect that is most pronounced during dose increases and gradually improves with tolerance."),
                SubjectiveEffect(name: "Hyponatremia Symptoms", description: "Low sodium levels can develop insidiously, presenting as headache, confusion, nausea, and fatigue that may be mistaken for other causes."),
                SubjectiveEffect(name: "Double Vision", description: "Diplopia or blurred vision may occur, particularly at higher doses, making reading and driving difficult."),
                SubjectiveEffect(name: "Mood Stabilization", description: "A subtle evening-out of mood fluctuations that contributes to its off-label use as a mood stabilizer."),
            ],
            halfLifeMinutes: 540,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        // MARK: - Local Anesthetics & Analgesics

        Substance(
            name: "Lidocaine",
            aliases: ["Xylocaine", "Lignocaine"],
            category: .analgesic,
            defaultRoute: .transdermal,
            routes: [
                SubstanceRoute(route: .transdermal, unit: "mg (patch)", doses: DoseRange(
                    threshold: 100, light: 200...350, common: 350...700, strong: 700...1050, heavy: 1050
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 240, max: 480),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 720)
                )),
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...200, common: 200...400, strong: 400...600, heavy: 600
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: nil,
                    total: TimeRange(min: 120, max: 240)
                )),
                SubstanceRoute(route: .intravenous, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...200, strong: 200...300, heavy: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 3),
                    comeup: TimeRange(min: 1, max: 2),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: nil,
                    total: TimeRange(min: 60, max: 120)
                )),
            ],
            effects: ["Local numbing", "Pain relief", "Antiarrhythmic", "Tingling", "Metallic taste"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Local Numbing", description: "A progressive loss of sensation in the treated area that develops within minutes, creating a complete absence of pain and touch."),
                SubjectiveEffect(name: "Tingling Onset", description: "A prickling or buzzing sensation at the application site that precedes full numbness, signaling the onset of anesthetic action."),
                SubjectiveEffect(name: "Pain Relief", description: "A profound silencing of neuropathic and localized pain that provides significant functional improvement."),
                SubjectiveEffect(name: "Metallic Taste", description: "A distinctive metallic or chemical taste in the mouth that can occur with systemic absorption, serving as an early warning of toxicity."),
                SubjectiveEffect(name: "Lightheadedness", description: "A feeling of dizziness or floating that may occur with higher systemic levels, indicating significant absorption."),
                SubjectiveEffect(name: "Perioral Numbness", description: "Numbness around the lips and tongue that can develop with systemic exposure, distinct from the intended local effect."),
                SubjectiveEffect(name: "Antiarrhythmic Effect", description: "When administered intravenously, a stabilization of cardiac rhythm that is not subjectively felt but is clinically significant."),
            ],
            halfLifeMinutes: 90,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        // MARK: - Orexin Receptor Antagonists

        Substance(
            name: "Suvorexant",
            aliases: ["Belsomra"],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 5...10, common: 10...15, strong: 15...20, heavy: 20
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 360, max: 600),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 720)
                )),
            ],
            effects: ["Sleep induction", "Next-day drowsiness", "Vivid dreams", "Sleep paralysis risk"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Natural-Feeling Sleepiness", description: "A gradual onset of drowsiness that mimics natural tiredness rather than the forceful sedation of traditional hypnotics."),
                SubjectiveEffect(name: "Vivid Dreams", description: "Dreams become notably more vivid, detailed, and memorable, sometimes with unusual or fantastical content."),
                SubjectiveEffect(name: "Sleep Paralysis Risk", description: "Some users experience brief episodes of sleep paralysis upon waking, where the body remains temporarily immobile while consciousness returns."),
                SubjectiveEffect(name: "Next-Day Drowsiness", description: "Residual sleepiness may persist into the morning, particularly at higher doses, affecting alertness and productivity."),
                SubjectiveEffect(name: "Improved Sleep Maintenance", description: "A reduction in nighttime awakenings and an ability to return to sleep more easily if awakened during the night."),
                SubjectiveEffect(name: "Minimal Cognitive Impairment", description: "Unlike benzodiazepines and Z-drugs, there is relatively little amnesia or confusion associated with this mechanism of action."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 14, buildRate: "slow"),
            halfLifeMinutes: 720,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Lemborexant",
            aliases: ["Dayvigo"],
            category: .depressant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 2.5...5, common: 5...7.5, strong: 7.5...10, heavy: 10
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 360, max: 720),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 840)
                )),
            ],
            effects: ["Sleep induction", "Next-day drowsiness", "Vivid dreams"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Gentle Sleep Onset", description: "A smooth transition toward sleep that feels natural and unforced, without the heaviness of traditional sedatives."),
                SubjectiveEffect(name: "Vivid Dreams", description: "Dreams become more detailed and immersive, with enhanced narrative complexity and emotional intensity."),
                SubjectiveEffect(name: "Next-Day Drowsiness", description: "Some residual sleepiness may carry into the following morning, though generally milder than with longer-acting hypnotics."),
                SubjectiveEffect(name: "Improved Sleep Architecture", description: "Sleep feels more restorative with better maintenance of natural sleep stages compared to GABAergic sleep aids."),
                SubjectiveEffect(name: "Low Dependence Risk", description: "Discontinuation does not typically produce the rebound insomnia seen with benzodiazepines or Z-drugs."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 7, fullResetDays: 14, buildRate: "slow"),
            halfLifeMinutes: 1020,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        // MARK: - Expectorants & Antitussives

        Substance(
            name: "Guaifenesin",
            aliases: ["Mucinex", "Robitussin"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 100, light: 200...400, common: 400...600, strong: 600...1200, heavy: 1200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Mucus thinning", "Improved cough productiveness", "Mild nausea", "Stomach discomfort"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mucus Thinning", description: "Chest and sinus congestion loosens noticeably within 30-60 minutes as mucus becomes thinner and easier to expel."),
                SubjectiveEffect(name: "Productive Cough", description: "Coughing becomes more effective at clearing secretions, transitioning from a dry, irritating cough to a productive one."),
                SubjectiveEffect(name: "Mild Nausea", description: "A queasy sensation in the stomach that is common at higher doses, particularly when taken without adequate water."),
                SubjectiveEffect(name: "Stomach Discomfort", description: "Abdominal cramping or discomfort may occur, especially with extended-release formulations on an empty stomach."),
                SubjectiveEffect(name: "Increased Urination", description: "Some users notice increased urinary frequency, possibly due to the high fluid intake recommended with this medication."),
            ],
            halfLifeMinutes: 60,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Benzonatate",
            aliases: ["Tessalon", "Tessalon Perles"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...150, common: 100...200, strong: 200...300, heavy: 300, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 20),
                    comeup: TimeRange(min: 10, max: 15),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 120, max: 300),
                    afterglow: nil,
                    total: TimeRange(min: 180, max: 480)
                )),
            ],
            effects: ["Cough suppression", "Throat numbness", "Dizziness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Cough Suppression", description: "A significant reduction in the cough reflex that develops within 15-20 minutes and lasts several hours, providing relief from persistent coughing."),
                SubjectiveEffect(name: "Throat Numbness", description: "A local anesthetic numbness in the throat and airways if the capsule is chewed or dissolved, which should be avoided as it can impair swallowing."),
                SubjectiveEffect(name: "Dizziness", description: "A mild lightheadedness that may occur during the active period, usually not severe at therapeutic doses."),
                SubjectiveEffect(name: "Sedation", description: "A mild drowsiness that can accompany cough suppression, contributing to restful sleep when coughing has been disrupting it."),
                SubjectiveEffect(name: "Overdose Danger", description: "The fatal dose is exceptionally low compared to therapeutic doses; even a small number of extra capsules can cause seizures, cardiac arrest, and death."),
            ],
            halfLifeMinutes: 120,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        // MARK: - Anti-Nausea & GI

        Substance(
            name: "Prochlorperazine",
            aliases: ["Compazine", "Compro"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...15, strong: 15...25, heavy: 25
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 720)
                )),
                SubstanceRoute(route: .rectal, unit: "mg", doses: DoseRange(
                    threshold: 2.5, light: 5...10, common: 10...15, strong: 15...25, heavy: 25
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 20),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 180, max: 360),
                    afterglow: nil,
                    total: TimeRange(min: 360, max: 720)
                )),
            ],
            effects: ["Anti-nausea", "Anti-vertigo", "Drowsiness", "Restlessness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Anti-Nausea", description: "A powerful suppression of nausea and the urge to vomit that develops within 30-60 minutes, providing substantial relief."),
                SubjectiveEffect(name: "Anti-Vertigo", description: "A stabilization of the spinning sensation associated with vestibular disorders, making movement and position changes tolerable."),
                SubjectiveEffect(name: "Drowsiness", description: "A pronounced sedation that can make maintaining alertness difficult, especially during the first few doses."),
                SubjectiveEffect(name: "Akathisia", description: "An intensely uncomfortable inner restlessness and compulsive need to move that can paradoxically accompany the sedation."),
                SubjectiveEffect(name: "Dystonic Reactions", description: "Involuntary muscle contractions, particularly in the neck, jaw, or eyes, that can occur as an acute and distressing side effect."),
                SubjectiveEffect(name: "Dry Mouth", description: "A noticeable reduction in saliva production creating persistent oral dryness and thirst."),
            ],
            halfLifeMinutes: 420,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        Substance(
            name: "Ranitidine",
            aliases: ["Zantac"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 37.5, light: 75...150, common: 150...300, strong: 300...450, heavy: 450
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 180),
                    offset: TimeRange(min: 360, max: 600),
                    afterglow: nil,
                    total: TimeRange(min: 480, max: 720)
                )),
            ],
            effects: ["Acid reduction", "Heartburn relief", "Headache", "Constipation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Heartburn Relief", description: "A noticeable reduction in the burning chest sensation of acid reflux that develops within 30-60 minutes of dosing."),
                SubjectiveEffect(name: "Acid Reduction", description: "A decrease in stomach acid production that provides relief from indigestion and allows irritated tissue to heal."),
                SubjectiveEffect(name: "Headache", description: "A mild headache that occasionally accompanies treatment, usually transient and manageable."),
                SubjectiveEffect(name: "Constipation", description: "Reduced bowel frequency and harder stools that may develop with regular use."),
                SubjectiveEffect(name: "Well Tolerated", description: "Generally produces minimal noticeable side effects at therapeutic doses, though the product has been withdrawn from many markets due to NDMA contamination concerns."),
            ],
            halfLifeMinutes: 180,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),

        // MARK: - Melatonin Agonists

        Substance(
            name: "Ramelteon",
            aliases: ["Rozerem"],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 4...8, common: 8...12, strong: 12...16, heavy: 16
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 120, max: 300),
                    afterglow: nil,
                    total: TimeRange(min: 240, max: 480)
                )),
            ],
            effects: ["Sleep induction (melatonin agonist)", "No dependence", "Mild dizziness", "Vivid dreams"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Gentle Sleep Onset", description: "A subtle shift toward sleepiness that mimics the natural melatonin signal, easing the transition into sleep without forceful sedation."),
                SubjectiveEffect(name: "No Dependence Potential", description: "Discontinuation does not produce withdrawal symptoms or rebound insomnia, making it suitable for patients with substance use histories."),
                SubjectiveEffect(name: "Vivid Dreams", description: "Dreams may become slightly more vivid and memorable, consistent with the melatonergic mechanism of action."),
                SubjectiveEffect(name: "Mild Dizziness", description: "A faint lightheadedness that some users experience, usually mild and transient."),
                SubjectiveEffect(name: "Circadian Rhythm Reset", description: "With consistent nightly use, the body's internal clock gradually realigns, improving sleep-wake regularity over days to weeks."),
            ],
            halfLifeMinutes: 90,
            sources: ["Drugs.com", "FDA DailyMed", "StatPearls"]
        ),
    ]
}
