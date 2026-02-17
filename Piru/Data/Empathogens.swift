import Foundation

extension SubstanceLibrary {
    static let empathogens: [Substance] = [

        // MARK: - MDMA

        Substance(
            name: "MDMA",
            aliases: ["Ecstasy", "Molly", "XTC", "X", "E", "Mandy", "3,4-Methylenedioxymethamphetamine"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 40...75, common: 75...125, strong: 125...175, heavy: 175, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 45),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 720, max: 2880),
                    total: TimeRange(min: 180, max: 360)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 20, light: 30...60, common: 60...100, strong: 100...150, heavy: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 45, max: 90),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 720, max: 2880),
                    total: TimeRange(min: 120, max: 240)
                )),
                SubstanceRoute(route: .rectal, unit: "mg", doses: DoseRange(
                    threshold: 20, light: 35...65, common: 65...110, strong: 110...150, heavy: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 10, max: 30),
                    comeup: TimeRange(min: 10, max: 30),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 720, max: 2880),
                    total: TimeRange(min: 180, max: 330)
                )),
            ],
            effects: ["Empathy enhancement", "Euphoria", "Sociability", "Tactile enhancement", "Increased emotional closeness", "Jaw clenching", "Stimulation", "Hyperthermia", "Anxiety suppression", "Music appreciation enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Empathogenic euphoria", description: "An overwhelming sense of love, connection, and emotional warmth toward others that feels profoundly meaningful and authentic."),
                SubjectiveEffect(name: "Tactile enhancement", description: "Physical touch becomes extraordinarily pleasurable, with textures and skin contact producing intense waves of pleasure."),
                SubjectiveEffect(name: "Emotional openness", description: "Emotional barriers dissolve, making it feel safe and natural to share deep feelings and personal experiences."),
                SubjectiveEffect(name: "Music appreciation enhancement", description: "Music sounds richer, more beautiful, and deeply emotionally moving, with enhanced perception of melody, rhythm, and lyrics."),
                SubjectiveEffect(name: "Jaw clenching", description: "Involuntary tightening and grinding of the jaw muscles that can be persistent and uncomfortable throughout the experience."),
                SubjectiveEffect(name: "Body high", description: "A warm, electric tingling sensation that radiates through the body, often described as rolling waves of pleasure."),
                SubjectiveEffect(name: "Sociability enhancement", description: "A powerful desire to connect, communicate, and share experiences with others, making social interaction deeply rewarding."),
                SubjectiveEffect(name: "Anxiety suppression", description: "Fear and social anxiety dissolve completely, replaced by a sense of safety and unconditional acceptance."),
                SubjectiveEffect(name: "Stimulation", description: "Increased energy and wakefulness, with a desire to move, dance, and engage physically with the environment."),
                SubjectiveEffect(name: "Comedown", description: "A period of low mood, fatigue, and emotional sensitivity in the days following use due to serotonin depletion."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 30, fullResetDays: 90, buildRate: "slow"),
            halfLifeMinutes: 480
        ),

        // MARK: - MDA

        Substance(
            name: "MDA",
            aliases: ["Sally", "Sass", "Sassafras", "3,4-Methylenedioxyamphetamine"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 20, light: 30...60, common: 60...100, strong: 100...145, heavy: 145, fatal: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 720, max: 2880),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Empathy enhancement", "Euphoria", "Stimulation", "Psychedelic visual effects", "Increased emotional closeness", "Jaw clenching", "Tactile enhancement", "Hyperthermia", "Sociability", "Appetite suppression"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Psychedelic visuals", description: "More pronounced visual effects than MDMA, including geometric patterns, color enhancement, and flowing surfaces."),
                SubjectiveEffect(name: "Empathogenic warmth", description: "Deep feelings of emotional connection and love, similar to MDMA but with a more introspective and psychedelic character."),
                SubjectiveEffect(name: "Stimulation", description: "More stimulating than MDMA, with greater physical energy and a desire for movement and activity."),
                SubjectiveEffect(name: "Tactile enhancement", description: "Touch becomes amplified and pleasurable, though sometimes less prominent than with MDMA due to the psychedelic component."),
                SubjectiveEffect(name: "Jaw clenching", description: "Persistent involuntary clenching of the jaw and grinding of teeth, often more intense than with MDMA."),
                SubjectiveEffect(name: "Body temperature increase", description: "Core body temperature rises noticeably, with sweating and feelings of heat that require attention to hydration."),
                SubjectiveEffect(name: "Introspection", description: "A tendency toward deeper self-reflection and examination of personal feelings and relationships."),
                SubjectiveEffect(name: "Extended duration", description: "Effects last longer than MDMA, with a more gradual onset and extended plateau phase."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 30, fullResetDays: 90, buildRate: "slow"),
            halfLifeMinutes: 600
        ),

        // MARK: - MDEA

        Substance(
            name: "MDEA",
            aliases: ["Eve", "MDE", "3,4-Methylenedioxy-N-ethylamphetamine"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 40, light: 80...120, common: 120...180, strong: 180...250, heavy: 250, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 90, max: 150),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 360, max: 1440),
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Empathy enhancement", "Euphoria", "Sociability", "Relaxation", "Increased emotional closeness", "Tactile enhancement", "Jaw clenching", "Mild stimulation", "Anxiety suppression", "Music appreciation enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Gentle empathy", description: "A softer, more relaxed empathogenic experience than MDMA, with emotional warmth that feels less forced and more natural."),
                SubjectiveEffect(name: "Relaxation", description: "A calm, easygoing quality that distinguishes MDEA from the more stimulating MDMA experience."),
                SubjectiveEffect(name: "Emotional openness", description: "Willingness to share feelings and connect emotionally, though typically less intense than MDMA."),
                SubjectiveEffect(name: "Tactile enhancement", description: "Touch feels pleasantly enhanced, with physical contact producing warm, comforting sensations."),
                SubjectiveEffect(name: "Music appreciation", description: "Music sounds more beautiful and emotionally meaningful, with enhanced sensitivity to melodies and harmonies."),
                SubjectiveEffect(name: "Mild stimulation", description: "A gentle increase in energy, less pushy than MDMA, allowing for comfortable socializing without restlessness."),
                SubjectiveEffect(name: "Anxiety suppression", description: "Social fears and anxieties diminish, making communication and self-expression feel easy and natural."),
                SubjectiveEffect(name: "Jaw tension", description: "Mild to moderate jaw clenching and teeth grinding, typically less severe than with MDMA."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 30, fullResetDays: 90, buildRate: "slow"),
            halfLifeMinutes: 360
        ),

        // MARK: - 6-APB

        Substance(
            name: "6-APB",
            aliases: ["Benzo fury", "6-(2-Aminopropyl)benzofuran"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 30, light: 50...80, common: 80...120, strong: 120...150, heavy: 150, fatal: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 90),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 360, max: 1440),
                    total: TimeRange(min: 360, max: 540)
                )),
            ],
            effects: ["Empathy enhancement", "Euphoria", "Stimulation", "Visual enhancement", "Sociability", "Tactile enhancement", "Increased emotional closeness", "Jaw clenching", "Music appreciation enhancement", "Hyperthermia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Empathogenic euphoria", description: "A deep emotional warmth and sense of connection similar to MDMA, with added psychedelic depth and visual richness."),
                SubjectiveEffect(name: "Visual enhancement", description: "Colors appear more vivid and saturated, with subtle visual distortions and enhanced pattern recognition."),
                SubjectiveEffect(name: "Extended duration", description: "Effects last significantly longer than MDMA, often 6-8 hours, with a slow build and extended plateau."),
                SubjectiveEffect(name: "Tactile enhancement", description: "Physical sensations are heightened, with touch producing warm, pleasurable waves throughout the body."),
                SubjectiveEffect(name: "Music appreciation", description: "Music becomes immersive and deeply emotional, often described as more psychedelic than MDMA's music enhancement."),
                SubjectiveEffect(name: "Stimulation", description: "Physical and mental energy increase, with a desire to move, explore, and engage with surroundings."),
                SubjectiveEffect(name: "Jaw clenching", description: "Involuntary jaw tension and teeth grinding similar to MDMA, which can persist throughout the experience."),
                SubjectiveEffect(name: "Slow onset", description: "Effects take 1-2 hours to fully manifest, which can lead to premature redosing if one is not patient."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 30, fullResetDays: 90, buildRate: "slow"),
            halfLifeMinutes: 420
        ),

        // MARK: - 5-APB

        Substance(
            name: "5-APB",
            aliases: ["5-(2-Aminopropyl)benzofuran"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 20, light: 40...60, common: 60...90, strong: 90...120, heavy: 120, fatal: 350
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 120, max: 180),
                    offset: TimeRange(min: 90, max: 150),
                    afterglow: TimeRange(min: 360, max: 1440),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Empathy enhancement", "Euphoria", "Sociability", "Stimulation", "Tactile enhancement", "Increased emotional closeness", "Jaw clenching", "Music appreciation enhancement", "Hyperthermia", "Anxiety suppression"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Empathogenic warmth", description: "A strong sense of emotional openness and love toward others, similar in quality to MDMA but with more psychedelic undertones."),
                SubjectiveEffect(name: "Euphoria", description: "A buoyant, joyful mood elevation that builds gradually and sustains for several hours."),
                SubjectiveEffect(name: "Stimulation", description: "Physical energy increases noticeably, with a desire to be active and engage with the environment."),
                SubjectiveEffect(name: "Tactile enhancement", description: "Touch and physical contact feel amplified and deeply pleasurable."),
                SubjectiveEffect(name: "Music appreciation", description: "Music becomes particularly moving and immersive, with enhanced emotional resonance."),
                SubjectiveEffect(name: "Anxiety suppression", description: "Social anxiety and self-doubt dissolve, making communication and vulnerability feel comfortable."),
                SubjectiveEffect(name: "Jaw clenching", description: "Bruxism and jaw tension are common, sometimes requiring a mouthguard or magnesium supplementation."),
                SubjectiveEffect(name: "Extended duration", description: "Effects persist longer than MDMA, with a 5-7 hour experience from a single dose."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 30, fullResetDays: 90, buildRate: "slow"),
            halfLifeMinutes: 360
        ),

        // MARK: - 5-MAPB

        Substance(
            name: "5-MAPB",
            aliases: ["5-(2-Methylaminopropyl)benzofuran"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 15, light: 30...50, common: 50...75, strong: 75...100, heavy: 100, fatal: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 120, max: 180),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 360, max: 1440),
                    total: TimeRange(min: 240, max: 420)
                )),
            ],
            effects: ["Empathy enhancement", "Euphoria", "Sociability", "Increased emotional closeness", "Tactile enhancement", "Stimulation", "Jaw clenching", "Music appreciation enhancement", "Anxiety suppression", "Hyperthermia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "MDMA-like euphoria", description: "Often described as the closest analogue to the MDMA experience among benzofurans, with strong empathy and euphoria."),
                SubjectiveEffect(name: "Emotional closeness", description: "A profound sense of connection and intimacy with others that feels genuine and deeply meaningful."),
                SubjectiveEffect(name: "Tactile enhancement", description: "Physical touch produces intense pleasure, with enhanced sensitivity to textures and skin contact."),
                SubjectiveEffect(name: "Music appreciation", description: "Musical experiences become profoundly enhanced, with deep emotional responses to melody and rhythm."),
                SubjectiveEffect(name: "Anxiety suppression", description: "Fears and anxieties melt away, creating a state of emotional safety and openness."),
                SubjectiveEffect(name: "Stimulation", description: "A balanced increase in energy that supports socializing and dancing without excessive restlessness."),
                SubjectiveEffect(name: "Serotonergic comedown", description: "A period of reduced mood and emotional sensitivity following the experience, similar to MDMA's aftermath."),
                SubjectiveEffect(name: "Jaw tension", description: "Involuntary clenching and grinding of the jaw that persists throughout the peak effects."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 30, fullResetDays: 90, buildRate: "slow"),
            halfLifeMinutes: 360
        ),

        // MARK: - 6-MAPB

        Substance(
            name: "6-MAPB",
            aliases: ["6-(2-Methylaminopropyl)benzofuran"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 20, light: 30...50, common: 50...80, strong: 80...110, heavy: 110
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 75),
                    comeup: TimeRange(min: 25, max: 50),
                    peak: TimeRange(min: 120, max: 210),
                    offset: TimeRange(min: 90, max: 150),
                    afterglow: TimeRange(min: 360, max: 1440),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Empathy enhancement", "Euphoria", "Sociability", "Increased emotional closeness", "Tactile enhancement", "Visual enhancement", "Stimulation", "Jaw clenching", "Music appreciation enhancement", "Hyperthermia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Empathogenic euphoria", description: "Strong empathy and emotional warmth comparable to 5-MAPB but with added visual and psychedelic depth."),
                SubjectiveEffect(name: "Visual enhancement", description: "Colors become more vivid and saturated, with subtle visual distortions adding a psychedelic quality."),
                SubjectiveEffect(name: "Emotional closeness", description: "Deep feelings of connection and intimacy, with enhanced ability to empathize and communicate."),
                SubjectiveEffect(name: "Tactile enhancement", description: "Physical touch is profoundly pleasurable, with heightened awareness of texture and body sensations."),
                SubjectiveEffect(name: "Music appreciation", description: "Music takes on extraordinary depth and beauty, with enhanced emotional impact from melodies and lyrics."),
                SubjectiveEffect(name: "Stimulation", description: "Moderate physical and mental energy that supports dancing and social engagement."),
                SubjectiveEffect(name: "Jaw clenching", description: "Persistent jaw tension and bruxism, which can be managed with magnesium or a mouthguard."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 30, fullResetDays: 90, buildRate: "slow"),
            halfLifeMinutes: 480
        ),

        // MARK: - 4-FA

        Substance(
            name: "4-FA",
            aliases: ["4-Fluoroamphetamine", "4-FMP", "Flux"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 20, light: 50...80, common: 80...120, strong: 120...160, heavy: 160, fatal: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 180, max: 360),
                    total: TimeRange(min: 360, max: 540)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 15, light: 30...60, common: 60...100, strong: 100...140, heavy: 140
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 10),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 150),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Stimulation", "Euphoria", "Empathy enhancement", "Sociability", "Focus enhancement", "Increased motivation", "Jaw clenching", "Appetite suppression", "Increased heart rate", "Hyperthermia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Stimulant-empathogen hybrid", description: "A unique blend of amphetamine stimulation and MDMA-like empathy, leaning more stimulant at lower doses and more empathogenic at higher doses."),
                SubjectiveEffect(name: "Euphoria", description: "A strong, rush-like euphoria that combines physical energy with emotional warmth and sociability."),
                SubjectiveEffect(name: "Focus enhancement", description: "Mental clarity and concentration improve, making tasks feel engaging and manageable."),
                SubjectiveEffect(name: "Sociability", description: "Interactions feel rewarding and natural, with increased desire to talk and connect with others."),
                SubjectiveEffect(name: "Appetite suppression", description: "Hunger signals are significantly dulled, making eating feel unappealing or unnecessary."),
                SubjectiveEffect(name: "Jaw clenching", description: "Involuntary jaw tension and teeth grinding that can be uncomfortable and persistent."),
                SubjectiveEffect(name: "Cardiovascular stimulation", description: "Heart rate increases noticeably, with awareness of heartbeat and potential chest tightness."),
                SubjectiveEffect(name: "Hyperthermia", description: "Body temperature rises, producing sweating and a feeling of warmth that requires attention to cooling."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 30, fullResetDays: 90, buildRate: "slow"),
            halfLifeMinutes: 300
        ),

        // MARK: - Methylone

        Substance(
            name: "Methylone",
            aliases: ["bk-MDMA", "M1", "MDMC", "3,4-Methylenedioxy-N-methylcathinone"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 60, light: 100...150, common: 150...250, strong: 250...350, heavy: 350, fatal: 600
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 180, max: 300)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 40, light: 60...100, common: 100...175, strong: 175...250, heavy: 250
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 5, max: 15),
                    peak: TimeRange(min: 30, max: 90),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 240),
                    total: TimeRange(min: 120, max: 210)
                )),
            ],
            effects: ["Empathy enhancement", "Euphoria", "Stimulation", "Sociability", "Increased emotional closeness", "Jaw clenching", "Tactile enhancement", "Appetite suppression", "Increased heart rate", "Hyperthermia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "MDMA-like empathy", description: "Empathogenic effects reminiscent of MDMA but generally regarded as less intense and more fleeting."),
                SubjectiveEffect(name: "Euphoria", description: "A pleasant mood elevation with feelings of warmth and positivity, though often described as less profound than MDMA."),
                SubjectiveEffect(name: "Stimulation", description: "Noticeable physical energy and mental alertness, with a desire to move and socialize."),
                SubjectiveEffect(name: "Shorter duration", description: "Effects wear off more quickly than MDMA, often leading to a desire to redose within a few hours."),
                SubjectiveEffect(name: "Tactile enhancement", description: "Touch feels more pleasurable and engaging, though typically less intense than with MDMA."),
                SubjectiveEffect(name: "Jaw clenching", description: "Bruxism and jaw tension are common, sometimes persisting after other effects have subsided."),
                SubjectiveEffect(name: "Appetite suppression", description: "Hunger is suppressed during the active effects, with eating feeling unappealing."),
                SubjectiveEffect(name: "Cardiovascular stimulation", description: "Elevated heart rate and blood pressure that can feel uncomfortable, especially during physical activity."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 90
        ),

        // MARK: - Butylone

        Substance(
            name: "Butylone",
            aliases: ["bk-MBDB", "B1"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 75...125, common: 125...200, strong: 200...300, heavy: 300
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 120, max: 240),
                    total: TimeRange(min: 180, max: 270)
                )),
            ],
            effects: ["Empathy enhancement", "Euphoria", "Stimulation", "Sociability", "Increased emotional closeness", "Jaw clenching", "Appetite suppression", "Tactile enhancement", "Increased heart rate"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Empathogenic effects", description: "Moderate feelings of emotional openness and empathy, generally regarded as less potent than MDMA or methylone."),
                SubjectiveEffect(name: "Euphoria", description: "A pleasant, uplifting mood that provides a general sense of well-being and positivity."),
                SubjectiveEffect(name: "Stimulation", description: "Physical and mental energy increase, promoting activity and engagement with surroundings."),
                SubjectiveEffect(name: "Sociability", description: "Social interactions feel easier and more rewarding, with increased desire to communicate."),
                SubjectiveEffect(name: "Jaw clenching", description: "Involuntary jaw tension and bruxism that is common across cathinone-type empathogens."),
                SubjectiveEffect(name: "Appetite suppression", description: "Food becomes unappealing during active effects, with hunger returning as the substance wears off."),
                SubjectiveEffect(name: "Short duration", description: "Effects are relatively brief, often lasting only 2-3 hours, which can encourage compulsive redosing."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 120
        ),

        // MARK: - Ethylone

        Substance(
            name: "Ethylone",
            aliases: ["bk-MDEA", "MDEC", "3,4-Methylenedioxy-N-ethylcathinone"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 60, light: 100...150, common: 150...225, strong: 225...325, heavy: 325
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 90),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Empathy enhancement", "Euphoria", "Stimulation", "Sociability", "Increased emotional closeness", "Jaw clenching", "Relaxation", "Tactile enhancement", "Music appreciation enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Relaxed empathy", description: "A calmer, more relaxed version of empathogenic effects compared to methylone, with less stimulating push."),
                SubjectiveEffect(name: "Euphoria", description: "A moderate sense of pleasure and well-being that feels easygoing and comfortable."),
                SubjectiveEffect(name: "Sociability", description: "Social barriers lower and conversations flow easily, though with less intensity than MDMA."),
                SubjectiveEffect(name: "Relaxation", description: "A notable sedating quality that distinguishes ethylone from more stimulating cathinone empathogens."),
                SubjectiveEffect(name: "Tactile enhancement", description: "Physical touch and textures feel enhanced and more pleasurable than usual."),
                SubjectiveEffect(name: "Music appreciation", description: "Music sounds more emotionally engaging, with enhanced sensitivity to rhythm and melody."),
                SubjectiveEffect(name: "Jaw tension", description: "Mild to moderate jaw clenching and teeth grinding during the peak effects."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 180
        ),

        // MARK: - Pentylone

        Substance(
            name: "Pentylone",
            aliases: ["bk-MBDP", "bk-Methyl-K"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 2, light: 5...10, common: 10...20, strong: 20...35, heavy: 35
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 60, max: 120),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 180, max: 300)
                )),
            ],
            effects: ["Stimulation", "Euphoria", "Empathy enhancement", "Sociability", "Jaw clenching", "Appetite suppression", "Increased heart rate", "Restlessness", "Insomnia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Intense stimulation", description: "A strong stimulant push that is more pronounced than the empathogenic component, with significant physical energy."),
                SubjectiveEffect(name: "Restlessness", description: "Difficulty sitting still or relaxing, with a persistent need to move and engage in activity."),
                SubjectiveEffect(name: "Insomnia", description: "Sleep becomes impossible for many hours after dosing, with persistent wakefulness even after other effects fade."),
                SubjectiveEffect(name: "Mild empathy", description: "Some empathogenic warmth is present but secondary to the stimulant effects."),
                SubjectiveEffect(name: "Jaw clenching", description: "Significant jaw tension and teeth grinding, often more uncomfortable than with MDMA."),
                SubjectiveEffect(name: "Appetite suppression", description: "Complete loss of appetite during the experience and for hours afterward."),
                SubjectiveEffect(name: "Cardiovascular strain", description: "Noticeable heart rate elevation and sometimes uncomfortable chest awareness."),
                SubjectiveEffect(name: "Compulsive redosing urge", description: "The short duration creates a strong desire to take more, which can lead to excessive consumption."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 180
        ),

        // MARK: - Mephedrone

        Substance(
            name: "Mephedrone",
            aliases: ["4-MMC", "Meow Meow", "M-Cat", "Drone", "4-Methylmethcathinone"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 75...150, common: 150...250, strong: 250...350, heavy: 350, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 120, max: 180)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 45...80, common: 80...125, strong: 125...175, heavy: 175, fatal: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 30, max: 45),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 60, max: 120)
                )),
            ],
            effects: ["Euphoria", "Stimulation", "Empathy enhancement", "Sociability", "Tactile enhancement", "Jaw clenching", "Compulsive redosing", "Increased heart rate", "Hyperthermia", "Appetite suppression"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Rush euphoria", description: "An intense initial rush of pleasure, particularly when insufflated, that is often compared to a combination of MDMA and cocaine."),
                SubjectiveEffect(name: "Empathogenic warmth", description: "Strong feelings of emotional openness and love toward others, especially at moderate to high doses."),
                SubjectiveEffect(name: "Tactile enhancement", description: "Touch and physical contact become extraordinarily pleasurable, rivaling or exceeding MDMA in intensity."),
                SubjectiveEffect(name: "Stimulation", description: "A powerful boost of physical energy and mental alertness that drives activity and engagement."),
                SubjectiveEffect(name: "Compulsive redosing", description: "The short duration and intense euphoria create a strong urge to redose repeatedly, which is a significant risk."),
                SubjectiveEffect(name: "Sociability", description: "Social interactions become deeply rewarding, with a strong desire to talk and connect with others."),
                SubjectiveEffect(name: "Jaw clenching", description: "Pronounced jaw tension and bruxism that can cause soreness lasting into the following day."),
                SubjectiveEffect(name: "Hyperthermia", description: "Body temperature rises noticeably, with sweating and flushing that require attention to hydration and cooling."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 120
        ),

        // MARK: - 3-MMC

        Substance(
            name: "3-MMC",
            aliases: ["3-Methylmethcathinone", "Metaphedrone"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 75...150, common: 150...250, strong: 250...350, heavy: 350, fatal: 500
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 25),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 120, max: 210)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 30...75, common: 75...125, strong: 125...175, heavy: 175, fatal: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 30, max: 45),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 60, max: 120)
                )),
            ],
            effects: ["Euphoria", "Stimulation", "Empathy enhancement", "Sociability", "Tactile enhancement", "Jaw clenching", "Compulsive redosing", "Increased heart rate", "Appetite suppression", "Music appreciation enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Balanced euphoria", description: "A mix of stimulant and empathogenic euphoria that feels similar to mephedrone but somewhat softer."),
                SubjectiveEffect(name: "Sociability", description: "Strong desire to communicate and connect with others, with conversations feeling easy and enjoyable."),
                SubjectiveEffect(name: "Tactile enhancement", description: "Physical sensations are enhanced, with touch and textures feeling more vivid and pleasurable."),
                SubjectiveEffect(name: "Music appreciation", description: "Music sounds richer and more emotionally engaging, enhancing the enjoyment of listening and dancing."),
                SubjectiveEffect(name: "Compulsive redosing", description: "Short duration of effects creates a strong pull to redose, which can lead to excessive consumption."),
                SubjectiveEffect(name: "Stimulation", description: "Moderate physical and mental energy that supports activity and socializing."),
                SubjectiveEffect(name: "Jaw clenching", description: "Involuntary jaw tension and teeth grinding that is characteristic of serotonergic cathinones."),
                SubjectiveEffect(name: "Appetite suppression", description: "Hunger is effectively suppressed for the duration of effects and some time afterward."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 120
        ),

        // MARK: - 4-CMC

        Substance(
            name: "4-CMC",
            aliases: ["Clephedrone", "4-Chloromethcathinone"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...150, common: 150...250, strong: 250...350, heavy: 350
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 25),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 120, max: 180)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 30, light: 50...100, common: 100...175, strong: 175...250, heavy: 250
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 30, max: 45),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 60, max: 120)
                )),
            ],
            effects: ["Stimulation", "Mild euphoria", "Sociability", "Empathy enhancement", "Jaw clenching", "Appetite suppression", "Increased heart rate", "Restlessness"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mild stimulation", description: "A moderate increase in energy and alertness, less intense than mephedrone or 3-MMC."),
                SubjectiveEffect(name: "Mild euphoria", description: "A subtle sense of well-being and positivity, without the overwhelming rush of stronger cathinones."),
                SubjectiveEffect(name: "Subtle empathy", description: "Some empathogenic warmth may be present but is mild and secondary to the stimulant effects."),
                SubjectiveEffect(name: "Sociability", description: "Social interactions feel easier, with mild disinhibition and increased desire to communicate."),
                SubjectiveEffect(name: "Jaw clenching", description: "Mild jaw tension that is present but generally less severe than with more serotonergic compounds."),
                SubjectiveEffect(name: "Restlessness", description: "Difficulty relaxing or sitting still, with a persistent need for movement or activity."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 180
        ),

        // MARK: - 3-CMC

        Substance(
            name: "3-CMC",
            aliases: ["3-Chloromethcathinone"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 75...150, common: 150...250, strong: 250...350, heavy: 350
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 25),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 120, max: 180)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...150, strong: 150...225, heavy: 225
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 30, max: 45),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 60, max: 120)
                )),
            ],
            effects: ["Stimulation", "Mild euphoria", "Sociability", "Empathy enhancement", "Jaw clenching", "Appetite suppression", "Increased heart rate", "Restlessness", "Compulsive redosing"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Stimulant-dominant effects", description: "Predominantly stimulating with only subtle empathogenic undertones, leaning more toward a functional stimulant experience."),
                SubjectiveEffect(name: "Mild euphoria", description: "A moderate mood elevation that is noticeable but not overwhelming or particularly distinctive."),
                SubjectiveEffect(name: "Sociability", description: "Social interactions feel slightly easier and more engaging, with mild disinhibition."),
                SubjectiveEffect(name: "Compulsive redosing", description: "The mild and short-lived effects can drive a pattern of frequent redosing in pursuit of stronger effects."),
                SubjectiveEffect(name: "Restlessness", description: "Physical and mental restlessness that makes it difficult to relax or stay still."),
                SubjectiveEffect(name: "Appetite suppression", description: "Hunger is reduced during and shortly after the active effects."),
                SubjectiveEffect(name: "Jaw tension", description: "Some jaw clenching and teeth grinding, typically milder than with more serotonergic compounds."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 180
        ),

        // MARK: - 4-EMC

        Substance(
            name: "4-EMC",
            aliases: ["4-Ethylmethcathinone"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...150, common: 150...250, strong: 250...350, heavy: 350
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 25),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 120, max: 210)
                )),
            ],
            effects: ["Stimulation", "Euphoria", "Empathy enhancement", "Sociability", "Jaw clenching", "Appetite suppression", "Increased heart rate", "Tactile enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Moderate euphoria", description: "A pleasant mood elevation with empathogenic qualities, similar to mephedrone but milder overall."),
                SubjectiveEffect(name: "Stimulation", description: "Moderate physical energy and alertness that supports socializing and physical activity."),
                SubjectiveEffect(name: "Empathogenic warmth", description: "Some emotional openness and warmth toward others, adding an entactogenic dimension to the stimulant effects."),
                SubjectiveEffect(name: "Sociability", description: "Conversations and social interactions feel more rewarding and easier to navigate."),
                SubjectiveEffect(name: "Tactile enhancement", description: "Touch and physical sensations are mildly enhanced, with greater appreciation for textures."),
                SubjectiveEffect(name: "Jaw clenching", description: "Moderate jaw tension and teeth grinding characteristic of serotonin-releasing cathinones."),
                SubjectiveEffect(name: "Appetite suppression", description: "Food becomes unappealing during the active effects, with normal appetite returning gradually."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 180
        ),

        // MARK: - MDAI

        Substance(
            name: "MDAI",
            aliases: ["5,6-Methylenedioxy-2-aminoindane"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 75...100, common: 100...175, strong: 175...250, heavy: 250
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 90, max: 150),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Empathy enhancement", "Increased emotional closeness", "Sociability", "Mood lift", "Relaxation", "Anxiety suppression", "Mild euphoria", "Tactile enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Pure empathy", description: "A clean empathogenic effect with minimal stimulation, producing emotional openness and warmth without restlessness."),
                SubjectiveEffect(name: "Emotional closeness", description: "Deep feelings of connection and intimacy with others, with enhanced ability to communicate feelings."),
                SubjectiveEffect(name: "Relaxation", description: "A calm, sedating quality that distinguishes MDAI from stimulating empathogens like MDMA."),
                SubjectiveEffect(name: "Anxiety suppression", description: "Social anxiety and nervousness dissolve, making vulnerability and emotional expression feel safe."),
                SubjectiveEffect(name: "Mild euphoria", description: "A gentle, understated sense of well-being that is pleasant but not overwhelming or euphoric."),
                SubjectiveEffect(name: "Tactile enhancement", description: "Touch feels warmer and more pleasurable, though the enhancement is subtler than with MDMA."),
                SubjectiveEffect(name: "Mood lift", description: "A gentle elevation of baseline mood that makes interactions and activities feel more pleasant."),
                SubjectiveEffect(name: "Minimal comedown", description: "The aftermath is typically gentler than MDMA, with less pronounced serotonergic depletion effects."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 30, fullResetDays: 90, buildRate: "slow"),
            halfLifeMinutes: 360
        ),

        // MARK: - 5-EAPB

        Substance(
            name: "5-EAPB",
            aliases: ["5-(2-Ethylaminopropyl)benzofuran"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 30, light: 50...80, common: 80...120, strong: 120...150, heavy: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 120, max: 180),
                    offset: TimeRange(min: 90, max: 150),
                    afterglow: TimeRange(min: 360, max: 1440),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Empathy enhancement", "Euphoria", "Stimulation", "Sociability", "Tactile enhancement", "Increased emotional closeness", "Jaw clenching", "Music appreciation enhancement", "Hyperthermia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Empathogenic euphoria", description: "Strong feelings of emotional warmth and connection, combining empathogenic and benzofuran characteristics."),
                SubjectiveEffect(name: "Stimulation", description: "Moderate physical and mental energy that promotes activity and social engagement."),
                SubjectiveEffect(name: "Tactile enhancement", description: "Physical touch and textures feel more pleasurable and engaging, similar to other benzofuran empathogens."),
                SubjectiveEffect(name: "Music appreciation", description: "Music sounds richer and more emotionally impactful, enhancing the experience of listening and dancing."),
                SubjectiveEffect(name: "Emotional openness", description: "Barriers to emotional expression lower, making it feel natural to share feelings and connect deeply."),
                SubjectiveEffect(name: "Jaw clenching", description: "Involuntary jaw tension that is characteristic of serotonin-releasing empathogens."),
                SubjectiveEffect(name: "Hyperthermia", description: "Body temperature rises, with sweating and warmth that require attention to cooling and hydration."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 30, fullResetDays: 90, buildRate: "slow"),
            halfLifeMinutes: 360
        ),

        // MARK: - 5-IT

        Substance(
            name: "5-IT",
            aliases: ["5-(2-Aminopropyl)indole", "5-API"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 5, light: 10...20, common: 20...35, strong: 35...50, heavy: 50, fatal: 50
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 90),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 180, max: 360),
                    offset: TimeRange(min: 120, max: 240),
                    afterglow: TimeRange(min: 360, max: 1440),
                    total: TimeRange(min: 480, max: 720)
                )),
            ],
            effects: ["Stimulation", "Euphoria", "Empathy enhancement", "Sociability", "Increased heart rate", "Hyperthermia", "Jaw clenching", "Insomnia", "Serotonergic effects"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Intense stimulation", description: "A powerful stimulant push with strong serotonergic activity that can feel overwhelming and difficult to manage."),
                SubjectiveEffect(name: "Euphoria", description: "An intense euphoria when present, though the experience can be unpredictable and sometimes dysphoric."),
                SubjectiveEffect(name: "Dangerous hyperthermia", description: "Body temperature can rise to dangerous levels, making this compound particularly risky in warm environments."),
                SubjectiveEffect(name: "Cardiovascular stress", description: "Significant heart rate and blood pressure elevation that can be medically dangerous."),
                SubjectiveEffect(name: "Insomnia", description: "Extremely prolonged wakefulness that can persist for 12-24 hours or longer after dosing."),
                SubjectiveEffect(name: "Jaw clenching", description: "Severe bruxism and jaw tension due to heavy serotonin release."),
                SubjectiveEffect(name: "Serotonin syndrome risk", description: "The potent serotonergic activity creates significant risk of serotonin toxicity, especially in combination with other serotonergic substances."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 30, fullResetDays: 90, buildRate: "slow"),
            halfLifeMinutes: 540
        ),

        // MARK: - 4-MEC

        Substance(
            name: "4-MEC",
            aliases: ["4-Methylethcathinone"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 100...150, common: 150...250, strong: 250...350, heavy: 350
                ), duration: DurationProfile(
                    onset: TimeRange(min: 15, max: 30),
                    comeup: TimeRange(min: 10, max: 25),
                    peak: TimeRange(min: 30, max: 60),
                    offset: TimeRange(min: 30, max: 60),
                    afterglow: TimeRange(min: 60, max: 180),
                    total: TimeRange(min: 120, max: 210)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 30, light: 50...100, common: 100...175, strong: 175...250, heavy: 250
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 5),
                    comeup: TimeRange(min: 5, max: 10),
                    peak: TimeRange(min: 15, max: 30),
                    offset: TimeRange(min: 30, max: 45),
                    afterglow: TimeRange(min: 60, max: 120),
                    total: TimeRange(min: 60, max: 120)
                )),
            ],
            effects: ["Stimulation", "Euphoria", "Empathy enhancement", "Sociability", "Jaw clenching", "Appetite suppression", "Increased heart rate", "Tactile enhancement", "Compulsive redosing"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Stimulant euphoria", description: "A predominantly stimulating euphoria with some empathogenic character, similar to mephedrone but milder."),
                SubjectiveEffect(name: "Sociability", description: "Social interactions feel easier and more enjoyable, with reduced inhibition and increased talkativeness."),
                SubjectiveEffect(name: "Tactile enhancement", description: "Physical sensations are mildly enhanced, with touch feeling slightly more pleasurable."),
                SubjectiveEffect(name: "Compulsive redosing", description: "The relatively short and mild effects can drive repeated dosing in pursuit of a stronger experience."),
                SubjectiveEffect(name: "Jaw clenching", description: "Moderate jaw tension and bruxism, typical of serotonin-releasing cathinones."),
                SubjectiveEffect(name: "Appetite suppression", description: "Hunger is reduced during the active effects, returning as the substance wears off."),
                SubjectiveEffect(name: "Cardiovascular stimulation", description: "Elevated heart rate and blood pressure that can be uncomfortable during physical activity."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 14, fullResetDays: 45, buildRate: "moderate"),
            halfLifeMinutes: 120
        ),

        // MARK: - BDB

        Substance(
            name: "BDB",
            aliases: ["Benzodioxolylbutanamine", "3,4-Methylenedioxy-alpha-ethylphenethylamine", "J"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 50, light: 75...125, common: 125...200, strong: 200...275, heavy: 275
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 90, max: 180),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 480),
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Empathy enhancement", "Euphoria", "Increased emotional closeness", "Sociability", "Relaxation", "Tactile enhancement", "Anxiety suppression", "Mild stimulation"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Gentle empathy", description: "A warm, relaxed empathogenic effect that is similar to MDMA but with less stimulation and a calmer quality."),
                SubjectiveEffect(name: "Emotional closeness", description: "Deep feelings of intimacy and connection with others, making personal conversations feel natural and meaningful."),
                SubjectiveEffect(name: "Relaxation", description: "A calm, comfortable quality that makes the experience feel less intense and more manageable than MDMA."),
                SubjectiveEffect(name: "Anxiety suppression", description: "Social anxiety and self-consciousness dissolve, making emotional vulnerability feel safe."),
                SubjectiveEffect(name: "Tactile enhancement", description: "Touch feels warmer and more pleasurable, with enhanced appreciation for physical contact."),
                SubjectiveEffect(name: "Mild stimulation", description: "A gentle increase in energy that supports socializing without producing restlessness or agitation."),
                SubjectiveEffect(name: "Euphoria", description: "A moderate, pleasant sense of well-being and happiness that accompanies the empathogenic effects."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 30, fullResetDays: 90, buildRate: "slow"),
            halfLifeMinutes: 420
        ),

        // MARK: - MBDB

        Substance(
            name: "MBDB",
            aliases: ["Methylbenzodioxolylbutanamine", "Eden", "Methyl-J"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 60, light: 100...150, common: 150...250, strong: 250...350, heavy: 350
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 20, max: 40),
                    peak: TimeRange(min: 90, max: 150),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 480),
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Empathy enhancement", "Increased emotional closeness", "Sociability", "Relaxation", "Anxiety suppression", "Mild euphoria", "Tactile enhancement", "Introspection"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Entactogenic warmth", description: "A deep, introspective empathy that favors intimate conversation and emotional bonding over stimulation."),
                SubjectiveEffect(name: "Relaxation", description: "A notably calm and sedating quality compared to MDMA, making the experience feel gentle and unhurried."),
                SubjectiveEffect(name: "Introspection", description: "A tendency toward self-reflection and examination of personal feelings and relationships."),
                SubjectiveEffect(name: "Emotional openness", description: "Barriers to emotional expression dissolve, making it feel natural to share thoughts and feelings."),
                SubjectiveEffect(name: "Anxiety suppression", description: "Social anxieties and inhibitions are reduced, creating a space for genuine emotional exchange."),
                SubjectiveEffect(name: "Tactile enhancement", description: "Physical touch feels enhanced and comforting, promoting physical closeness with others."),
                SubjectiveEffect(name: "Mild euphoria", description: "A gentle, understated pleasure that is more contemplative than the euphoria of MDMA."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 30, fullResetDays: 90, buildRate: "slow"),
            halfLifeMinutes: 420
        ),

        // MARK: - IAP

        Substance(
            name: "IAP",
            aliases: ["5-Iodo-2-aminoindane", "5-IAI"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...100, common: 100...150, strong: 150...200, heavy: 200
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 90, max: 150),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 240, max: 360)
                )),
            ],
            effects: ["Empathy enhancement", "Sociability", "Stimulation", "Mood lift", "Increased emotional closeness", "Mild euphoria", "Appetite suppression", "Jaw clenching"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Mild empathy", description: "A moderate sense of emotional openness and warmth toward others, less intense than MDMA."),
                SubjectiveEffect(name: "Stimulation", description: "A functional increase in energy and alertness that supports activity and socializing."),
                SubjectiveEffect(name: "Mood lift", description: "A noticeable improvement in mood and outlook, making interactions and activities feel more positive."),
                SubjectiveEffect(name: "Sociability", description: "Social barriers lower, making conversation and connection feel easier and more natural."),
                SubjectiveEffect(name: "Mild euphoria", description: "A gentle sense of well-being that is present but not overwhelming or intensely pleasurable."),
                SubjectiveEffect(name: "Appetite suppression", description: "Hunger is mildly reduced during the experience, returning to normal as effects subside."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 30, fullResetDays: 90, buildRate: "slow"),
            halfLifeMinutes: 300
        ),

        // MARK: - 5-Methyl-MDA

        Substance(
            name: "5-Methyl-MDA",
            aliases: ["5-Me-MDA", "2-Amino-1-(6-methyl-3,4-methylenedioxyphenyl)propane"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 20, light: 40...80, common: 80...120, strong: 120...170, heavy: 170
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 60),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 720, max: 2880),
                    total: TimeRange(min: 300, max: 480)
                )),
            ],
            effects: ["Empathy enhancement", "Euphoria", "Stimulation", "Psychedelic visual effects", "Sociability", "Increased emotional closeness", "Jaw clenching", "Tactile enhancement", "Hyperthermia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "MDA-like experience", description: "A strong psychedelic-empathogenic combination similar to MDA, with more visual effects than MDMA."),
                SubjectiveEffect(name: "Visual effects", description: "Pronounced visual distortions and enhancements including patterns, color shifts, and breathing surfaces."),
                SubjectiveEffect(name: "Empathogenic warmth", description: "Deep emotional connection and love for others, combined with psychedelic depth and introspection."),
                SubjectiveEffect(name: "Stimulation", description: "Significant physical energy and mental arousal that drives activity and engagement."),
                SubjectiveEffect(name: "Tactile enhancement", description: "Touch and physical sensations are heightened, with textures feeling vivid and detailed."),
                SubjectiveEffect(name: "Jaw clenching", description: "Strong jaw tension and bruxism due to serotonergic activity, often requiring management strategies."),
                SubjectiveEffect(name: "Hyperthermia", description: "Body temperature elevation that requires attention to hydration, cooling, and rest."),
                SubjectiveEffect(name: "Extended duration", description: "Effects last longer than MDMA, with a slow build and sustained plateau."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 30, fullResetDays: 90, buildRate: "slow"),
            halfLifeMinutes: 540
        ),

        // MARK: - 6-APB-FURANYL

        Substance(
            name: "6-APB-FURANYL",
            aliases: ["6-FURANYL-APB"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 30, light: 50...80, common: 80...120, strong: 120...160, heavy: 160
                ), duration: DurationProfile(
                    onset: TimeRange(min: 30, max: 90),
                    comeup: TimeRange(min: 30, max: 60),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 360, max: 1440),
                    total: TimeRange(min: 360, max: 540)
                )),
            ],
            effects: ["Empathy enhancement", "Euphoria", "Stimulation", "Sociability", "Tactile enhancement", "Increased emotional closeness", "Jaw clenching", "Music appreciation enhancement", "Hyperthermia"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Benzofuran empathy", description: "Empathogenic effects characteristic of the benzofuran class, with emotional warmth and openness."),
                SubjectiveEffect(name: "Stimulation", description: "Moderate physical and mental energy that supports social activity and engagement."),
                SubjectiveEffect(name: "Tactile enhancement", description: "Touch feels heightened and pleasurable, contributing to the overall empathogenic experience."),
                SubjectiveEffect(name: "Music appreciation", description: "Music sounds richer and more emotionally impactful, with enhanced enjoyment of rhythm and melody."),
                SubjectiveEffect(name: "Emotional openness", description: "Emotional barriers lower, facilitating honest and meaningful communication with others."),
                SubjectiveEffect(name: "Jaw clenching", description: "Involuntary jaw tension common across serotonin-releasing empathogens."),
                SubjectiveEffect(name: "Hyperthermia", description: "Elevated body temperature requiring awareness of hydration and environmental cooling."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 30, fullResetDays: 90, buildRate: "slow"),
            halfLifeMinutes: 420
        ),

        // MARK: - 4-FMA

        Substance(
            name: "4-FMA",
            aliases: ["4-Fluoromethamphetamine"],
            category: .empathogen,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange(
                    threshold: 25, light: 50...75, common: 75...125, strong: 125...175, heavy: 175, fatal: 400
                ), duration: DurationProfile(
                    onset: TimeRange(min: 20, max: 45),
                    comeup: TimeRange(min: 15, max: 30),
                    peak: TimeRange(min: 120, max: 240),
                    offset: TimeRange(min: 120, max: 180),
                    afterglow: TimeRange(min: 180, max: 360),
                    total: TimeRange(min: 360, max: 540)
                )),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange(
                    threshold: 15, light: 30...60, common: 60...100, strong: 100...150, heavy: 150
                ), duration: DurationProfile(
                    onset: TimeRange(min: 1, max: 10),
                    comeup: TimeRange(min: 10, max: 20),
                    peak: TimeRange(min: 60, max: 150),
                    offset: TimeRange(min: 60, max: 120),
                    afterglow: TimeRange(min: 120, max: 360),
                    total: TimeRange(min: 180, max: 360)
                )),
            ],
            effects: ["Stimulation", "Euphoria", "Empathy enhancement", "Sociability", "Focus enhancement", "Jaw clenching", "Appetite suppression", "Increased heart rate", "Hyperthermia", "Tactile enhancement"],
            subjectiveEffects: [
                SubjectiveEffect(name: "Stimulant-empathogen blend", description: "A combination of amphetamine-like stimulation and moderate empathogenic warmth, with the balance depending on dose."),
                SubjectiveEffect(name: "Euphoria", description: "A strong, energetic euphoria that combines stimulant rush with emotional warmth and sociability."),
                SubjectiveEffect(name: "Focus enhancement", description: "Mental clarity and concentration improve, lending a functional quality to the experience at lower doses."),
                SubjectiveEffect(name: "Sociability", description: "Social interactions feel rewarding and effortless, with enhanced desire to communicate and connect."),
                SubjectiveEffect(name: "Tactile enhancement", description: "Physical sensations are heightened, with touch feeling more pleasurable than usual."),
                SubjectiveEffect(name: "Jaw clenching", description: "Pronounced bruxism and jaw tension from the combined dopaminergic and serotonergic activity."),
                SubjectiveEffect(name: "Appetite suppression", description: "Hunger is significantly reduced during and after the active effects."),
                SubjectiveEffect(name: "Cardiovascular stimulation", description: "Noticeable heart rate and blood pressure elevation that warrants caution during physical activity."),
            ],
            toleranceInfo: ToleranceInfo(halfLife: 30, fullResetDays: 90, buildRate: "slow"),
            halfLifeMinutes: 360
        ),
    ]
}
