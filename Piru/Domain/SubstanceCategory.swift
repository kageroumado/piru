import SwiftUI

enum SubstanceCategory: String, Codable, CaseIterable, Identifiable {
    case stimulant = "Stimulant"
    case psychedelic = "Psychedelic"
    case dissociative = "Dissociative"
    case dysdelic = "Dysdelic"
    case deliriant = "Deliriant"
    case opioid = "Opioid"
    case benzodiazepine = "Benzodiazepine"
    case gabapentinoid = "GABAergic"
    case empathogen = "Empathogen"
    case cannabinoid = "Cannabinoid"
    case nootropic = "Nootropic"
    case ampakine = "AMPAkine"
    case eugeroic = "Eugeroic"
    case depressant = "Depressant"
    case orexinAntagonist = "OrexinAntagonist"
    case antidepressant = "Antidepressant"
    case antipsychotic = "Antipsychotic"
    case analgesic = "Analgesic"
    case antihistamine = "Antihistamine"
    case cardiovascular = "Cardiovascular"
    case antimicrobial = "Antimicrobial"
    case gastrointestinal = "Gastrointestinal"
    case respiratory = "Respiratory"
    case endocrine = "Endocrine"
    case immunological = "Immunological"
    case supplement = "Supplement"
    case peptide = "Peptide"
    case anticonvulsant = "Anticonvulsant"
    case other = "Other"

    /// Modifier categories that are flags, not substantive classifications
    static let modifierCategories: Set<String> = [
        "common", "habit-forming", "research-chemical", "tentative", "inactive",
    ]

    /// Map TripSit lowercase categories to our enum
    nonisolated static func from(tripSitCategory: String) -> SubstanceCategory {
        switch tripSitCategory.lowercased() {
        case "stimulant": .stimulant
        case "psychedelic", "hallucinogen": .psychedelic
        case "dissociative": .dissociative
        case "dysdelic", "kappa-agonist", "kappa-opioid-agonist", "salvinorin": .dysdelic
        case "deliriant", "anticholinergic", "muscarinic-antagonist": .deliriant
        case "opioid", "opiate": .opioid
        case "benzodiazepine": .benzodiazepine
        case "depressant", "barbiturate", "sedative": .depressant
        case "empathogen", "entactogen": .empathogen
        case "cannabinoid": .cannabinoid
        case "nootropic": .nootropic
        case "ampakine", "ampa-pam", "ampa-positive-modulator": .ampakine
        case "eugeroic", "afinil", "wake-promoting": .eugeroic
        case "ssri", "snri", "maoi", "antidepressant": .antidepressant
        case "antipsychotic": .antipsychotic
        case "antihistamine": .antihistamine
        case "analgesic": .analgesic
        case "supplement", "vitamin", "steroid": .supplement
        case "peptide", "peptide-mimetic": .peptide
        case "gabapentinoid", "gabaergic": .gabapentinoid
        case "orexinantagonist", "orexin antagonist", "orexin-antagonist", "dora": .orexinAntagonist
        case "anxiolytic", "hypnotic": .depressant
        case "anticonvulsant", "mood-stabilizer", "mood stabilizer", "antiepileptic": .anticonvulsant
        case "sympathomimetic": .stimulant
        case "cardiovascular": .cardiovascular
        case "antimicrobial", "antibiotic", "antifungal", "antiviral": .antimicrobial
        case "gastrointestinal": .gastrointestinal
        case "respiratory": .respiratory
        case "endocrine": .endocrine
        case "immunological": .immunological
        default: .other
        }
    }

    var id: String {
        rawValue
    }

    /// Acute-tolerance (tachyphylaxis) strength, `0...1`. Drives the timeline's
    /// descending-limb gate: how much faster subjective effect fades than the
    /// drug's plasma curve once past peak. Catecholamine/serotonin releasers
    /// crash hard while blood levels are still high (the classic stimulant
    /// comedown), so they score high; most depressants/psychedelics track
    /// concentration far more closely and score 0 (no reshaping — the pure
    /// Bateman offset is kept). See `TimelineGraphView.intensity(at:…)`.
    var acuteToleranceFactor: Double {
        switch self {
        case .stimulant: 0.75
        case .empathogen: 0.70
        case .eugeroic: 0.20
        case .dissociative: 0.25
        default: 0
        }
    }

    /// Proportions for synthesizing a renderable effect curve from
    /// endpoint-only duration data (a `total` but no come-up/peak/offset — the
    /// LSD-oral class, where one source supplied only onset+total). `onset` is a
    /// fraction of `total`, used only when no onset phase exists; `comeup` /
    /// `peak` / `offset` are *relative weights* that split the remaining active
    /// span into the rising / plateau / falling shoulders of the bell. Shaped by
    /// class pharmacology: psychedelics build slowly into a broad peak, stimulants
    /// spike then taper (the descending limb is further crashed by
    /// ``acuteToleranceFactor``), opioids peak fast. See
    /// ``DurationProfile/fillingMissingPhases(for:)``.
    var synthesizedPhaseShape: (onset: Double, comeup: Double, peak: Double, offset: Double) {
        switch self {
        case .psychedelic, .dysdelic, .deliriant:
            (0.08, 0.20, 0.30, 0.50)
        case .stimulant:
            (0.06, 0.15, 0.20, 0.65)
        case .empathogen:
            (0.07, 0.18, 0.27, 0.55)
        case .eugeroic:
            (0.08, 0.15, 0.35, 0.50)
        case .opioid, .analgesic:
            (0.06, 0.16, 0.24, 0.60)
        case .dissociative:
            (0.06, 0.17, 0.27, 0.56)
        case .benzodiazepine, .depressant, .gabapentinoid, .orexinAntagonist:
            (0.07, 0.18, 0.30, 0.52)
        case .cannabinoid:
            (0.06, 0.18, 0.26, 0.56)
        default:
            (0.08, 0.20, 0.25, 0.55)
        }
    }

    var displayName: LocalizedStringResource {
        switch self {
        case .stimulant: "Stimulant"
        case .psychedelic: "Psychedelic"
        case .dissociative: "Dissociative"
        case .dysdelic: "Dysdelic"
        case .deliriant: "Deliriant"
        case .opioid: "Opioid"
        case .benzodiazepine: "Benzodiazepine"
        case .gabapentinoid: "GABAergic"
        case .empathogen: "Empathogen"
        case .cannabinoid: "Cannabinoid"
        case .nootropic: "Nootropic"
        case .ampakine: "AMPAkine"
        case .eugeroic: "Eugeroic"
        case .depressant: "Depressant"
        case .orexinAntagonist: "Orexin Antagonist"
        case .antidepressant: "Antidepressant"
        case .antipsychotic: "Antipsychotic"
        case .analgesic: "Analgesic"
        case .antihistamine: "Antihistamine"
        case .cardiovascular: "Cardiovascular"
        case .antimicrobial: "Antimicrobial"
        case .gastrointestinal: "Gastrointestinal"
        case .respiratory: "Respiratory"
        case .endocrine: "Endocrine"
        case .immunological: "Immunological"
        case .supplement: "Supplement"
        case .peptide: "Peptide"
        case .anticonvulsant: "Anticonvulsant"
        case .other: "Other"
        }
    }

    /// Categories whose whole point is wakefulness — the gate on whether the app
    /// may say a dose will still be working at bedtime, and on the wind-down
    /// reminder that follows a long session.
    ///
    /// Deliberately narrow: a med that merely *can* disturb sleep is not a claim
    /// either surface should make. Eugeroics are in because wake promotion is
    /// their indication rather than a side effect.
    ///
    /// **One declaration, read by both consumers** (`MedTimeConsequence` for the
    /// sentence, `RampDownScheduler` for the reminder).
    static let wakePromoting: Set<SubstanceCategory> = [.stimulant, .empathogen, .eugeroic]

    // MARK: - Display Metadata

    var icon: String {
        switch self {
        case .stimulant: "bolt.fill"
        case .psychedelic: "eye.fill"
        case .dissociative: "waveform.path"
        case .dysdelic: "tornado"
        case .deliriant: "cloud.fog.fill"
        case .opioid: "cross.fill"
        case .benzodiazepine: "moon.fill"
        case .gabapentinoid: "waveform"
        case .empathogen: "heart.fill"
        case .cannabinoid: "leaf.fill"
        case .nootropic: "brain.fill"
        case .ampakine: "sparkles"
        case .eugeroic: "sunrise.fill"
        case .depressant: "arrow.down.circle.fill"
        case .orexinAntagonist: "moon.zzz.fill"
        case .antidepressant: "sun.max.fill"
        case .antipsychotic: "shield.fill"
        case .analgesic: "bandage.fill"
        case .antihistamine: "allergens.fill"
        case .cardiovascular: "heart.text.square.fill"
        case .antimicrobial: "microbe.fill"
        case .gastrointestinal: "fork.knife"
        case .respiratory: "lungs.fill"
        case .endocrine: "atom"
        case .immunological: "shield.lefthalf.filled"
        case .supplement: "pill.fill"
        case .peptide: "link.circle.fill"
        case .anticonvulsant: "waveform.path.ecg"
        case .other: "pills.fill"
        }
    }

    /// Mark colour for the category badge. Text uses ``labelColor``.
    ///
    /// Nine of these were hand-mixed `Color(red:green:blue:)` literals with **no
    /// dark variant**, so they rendered the same pixel in both appearances.
    /// All 29 now come from the `category` scale in the catalog.
    @MainActor var color: Color {
        switch self {
        case .stimulant: .Category.Stimulant.accent
        case .psychedelic: .Category.Psychedelic.accent
        case .dissociative: .Category.Dissociative.accent
        case .dysdelic: .Category.Dysdelic.accent
        case .deliriant: .Category.Deliriant.accent
        case .opioid: .Category.Opioid.accent
        case .benzodiazepine: .Category.Benzodiazepine.accent
        case .gabapentinoid: .Category.Gabapentinoid.accent
        case .empathogen: .Category.Empathogen.accent
        case .cannabinoid: .Category.Cannabinoid.accent
        case .nootropic: .Category.Nootropic.accent
        case .ampakine: .Category.Ampakine.accent
        case .eugeroic: .Category.Eugeroic.accent
        case .depressant: .Category.Depressant.accent
        case .orexinAntagonist: .Category.OrexinAntagonist.accent
        case .antidepressant: .Category.Antidepressant.accent
        case .antipsychotic: .Category.Antipsychotic.accent
        case .analgesic: .Category.Analgesic.accent
        case .antihistamine: .Category.Antihistamine.accent
        case .cardiovascular: .Category.Cardiovascular.accent
        case .antimicrobial: .Category.Antimicrobial.accent
        case .gastrointestinal: .Category.Gastrointestinal.accent
        case .respiratory: .Category.Respiratory.accent
        case .endocrine: .Category.Endocrine.accent
        case .immunological: .Category.Immunological.accent
        case .supplement: .Category.Supplement.accent
        case .peptide: .Category.Peptide.accent
        case .anticonvulsant: .Category.Anticonvulsant.accent
        case .other: .Category.Other.accent
        }
    }

    /// Legible text variant, gated at WCAG AA against the card *and* against
    /// this category's own tinted fill. The Library badge draws the name in this
    /// colour on a 12% fill of ``color`` — the self-tint pattern, which measured
    /// 2.06:1 for stimulant orange before the scale existed.
    @MainActor var labelColor: Color {
        switch self {
        case .stimulant: .Category.Stimulant.text
        case .psychedelic: .Category.Psychedelic.text
        case .dissociative: .Category.Dissociative.text
        case .dysdelic: .Category.Dysdelic.text
        case .deliriant: .Category.Deliriant.text
        case .opioid: .Category.Opioid.text
        case .benzodiazepine: .Category.Benzodiazepine.text
        case .gabapentinoid: .Category.Gabapentinoid.text
        case .empathogen: .Category.Empathogen.text
        case .cannabinoid: .Category.Cannabinoid.text
        case .nootropic: .Category.Nootropic.text
        case .ampakine: .Category.Ampakine.text
        case .eugeroic: .Category.Eugeroic.text
        case .depressant: .Category.Depressant.text
        case .orexinAntagonist: .Category.OrexinAntagonist.text
        case .antidepressant: .Category.Antidepressant.text
        case .antipsychotic: .Category.Antipsychotic.text
        case .analgesic: .Category.Analgesic.text
        case .antihistamine: .Category.Antihistamine.text
        case .cardiovascular: .Category.Cardiovascular.text
        case .antimicrobial: .Category.Antimicrobial.text
        case .gastrointestinal: .Category.Gastrointestinal.text
        case .respiratory: .Category.Respiratory.text
        case .endocrine: .Category.Endocrine.text
        case .immunological: .Category.Immunological.text
        case .supplement: .Category.Supplement.text
        case .peptide: .Category.Peptide.text
        case .anticonvulsant: .Category.Anticonvulsant.text
        case .other: .Category.Other.text
        }
    }
}
