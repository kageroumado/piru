import Foundation

/// A contraindication from a clinical label, normalized to a closed vocabulary.
///
/// Label prose is written for prescribers — "Those who have experienced asthma,
/// urticaria, or allergic reactions after takings NSAIDs". The pipeline matches
/// each sentence to one of these cases and stores the case; the wording below
/// is Piru's, which is what makes it short, localizable, and consistent across
/// the substances that share a contraindication.
///
/// The vocabulary is authored in `pipeline/build/contraindication_flags.py` and
/// the two are kept in step by `ContraindicationFlagTests`, which fails if the
/// database carries a flag with no case here.
enum ContraindicationFlag: String, Codable, Hashable, CaseIterable {
    case hypersensitivity
    case maoi
    case cnsDepressants = "cns_depressants"
    case cyp3a4
    case qtProlonging = "qt_prolonging"
    case liveVaccine = "live_vaccine"
    case guanylateCyclase = "guanylate_cyclase"
    case alcohol
    case anticoagulant
    case respiratoryDepression = "respiratory_depression"
    case acuteAsthma = "acute_asthma"
    case giObstruction = "gi_obstruction"
    case activeBleeding = "active_bleeding"
    case hepaticImpairment = "hepatic_impairment"
    case renalImpairment = "renal_impairment"
    case anuria
    case cardiacIschemia = "cardiac_ischemia"
    case uncontrolledHypertension = "uncontrolled_hypertension"
    case arrhythmia
    case heartFailure = "heart_failure"
    case seizureDisorder = "seizure_disorder"
    case glaucoma
    case urinaryRetention = "urinary_retention"
    case adrenalInsufficiency = "adrenal_insufficiency"
    case fungalInfection = "fungal_infection"
    case porphyria
    case phaeochromocytoma
    case thyroid
    case pregnancy
    case breastfeeding
    case children
    case eatingDisorder = "eating_disorder"
    case myastheniaGravis = "myasthenia_gravis"
    case sleepApnea = "sleep_apnea"
    case smokingOver35 = "smoking_over_35"
    case hypoglycemia
    case hypokalemia
    case hyperkalemia
    case thyroidCancerHistory = "thyroid_cancer_history"
    case anxietyAgitation = "anxiety_agitation"
    case recentSurgery = "recent_surgery"

    /// Piru's own wording. A noun phrase stating what the contraindication IS —
    /// never an instruction about what to do, which is the label's register and
    /// not this app's.
    var label: LocalizedStringResource {
        switch self {
        case .hypersensitivity: "Known allergy to it"
        case .maoi: "With an MAOI, or within 14 days of one"
        case .cnsDepressants: "With other CNS depressants"
        case .cyp3a4: "With a strong CYP3A4 inhibitor"
        case .qtProlonging: "With a QT-prolonging drug"
        case .liveVaccine: "With a live vaccine"
        case .guanylateCyclase: "With a nitrate or a guanylate cyclase stimulator"
        case .alcohol: "With alcohol"
        case .anticoagulant: "With an anticoagulant"
        case .respiratoryDepression: "Existing respiratory depression"
        case .acuteAsthma: "During an acute asthma attack"
        case .giObstruction: "Bowel obstruction"
        case .activeBleeding: "Active bleeding"
        case .hepaticImpairment: "Liver disease"
        case .renalImpairment: "Kidney disease"
        case .anuria: "Anuria"
        case .cardiacIschemia: "Recent heart attack or heart surgery"
        case .uncontrolledHypertension: "Uncontrolled high blood pressure"
        case .arrhythmia: "Heart rhythm disorder"
        case .heartFailure: "Heart failure"
        case .seizureDisorder: "Seizure disorder"
        case .glaucoma: "Narrow-angle glaucoma"
        case .urinaryRetention: "Urinary retention"
        case .adrenalInsufficiency: "Adrenal insufficiency"
        case .fungalInfection: "Systemic fungal infection"
        case .porphyria: "Porphyria"
        case .phaeochromocytoma: "Pheochromocytoma"
        case .thyroid: "Untreated thyroid disease"
        case .pregnancy: "Pregnancy"
        case .breastfeeding: "Breastfeeding"
        case .children: "Children"
        case .eatingDisorder: "Eating disorder"
        case .myastheniaGravis: "Myasthenia gravis"
        case .sleepApnea: "Sleep apnea"
        case .smokingOver35: "Smoking over the age of 35"
        case .hypoglycemia: "During low blood sugar"
        case .hypokalemia: "Low potassium"
        case .hyperkalemia: "High potassium"
        case .thyroidCancerHistory: "Personal or family history of thyroid cancer"
        case .anxietyAgitation: "Marked anxiety or agitation"
        case .recentSurgery: "Around surgery"
        }
    }
}
