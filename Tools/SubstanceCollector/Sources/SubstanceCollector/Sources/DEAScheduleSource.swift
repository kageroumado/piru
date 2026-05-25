import Foundation

/// US Drug Enforcement Administration controlled-substance schedules.
///
/// We attempted to parse the Orange Book PDF
/// (https://www.deadiversion.usdoj.gov/schedules/orangebook/c_cs_alpha.pdf)
/// but the layout-driven text extraction produces too many false positives
/// without a real PDF library. Instead we ship a curated table of ~50
/// well-known substances and rely on the per-substance overrides for
/// research chemicals (most of which are Schedule I anyway).
///
/// Source: 21 CFR §1308, current as of 2024. Re-check before relying on this
/// for any safety-critical application.
enum DEAScheduleSource {
    /// Normalized name → "US-Schedule-{I,II,III,IV,V}" tag.
    static let table: [String: String] = {
        var t: [String: String] = [:]

        let schedI = [
            "heroin", "lsd", "lysergic acid diethylamide", "marijuana", "cannabis",
            "thc", "mescaline", "peyote", "psilocybin", "psilocin",
            "mdma", "mdma", "methamphetamine", // (note: only certain meth salts are II)
            "mda", "mdea", "dmt", "ibogaine", "ghb",
            "ketamine analogs", "2c-b", "2c-i", "2c-e", "dom", "doi", "dob",
            "5-meo-dmt", "5-meo-dipt", "amt", "5-meo-amt",
            "synthetic cannabinoids", "jwh-018", "jwh-073", "jwh-200",
            "cp-47497", "am-2201", "ab-fubinaca", "adb-fubinaca",
            "mdpv", "mephedrone", "4-mmc", "methylone", "alpha-pvp",
            "etizolam", "fentanyl analogues", "u-47700", "acetylfentanyl",
            "furanylfentanyl", "carfentanil",
            "ah-7921", "amb-fubinaca", "5f-amb", "5f-pb-22",
            "nbome", "25i-nbome", "25c-nbome", "25b-nbome",
            "ethylone", "butylone", "pentylone",
        ]
        for n in schedI { t[NameNormalizer.normalize(n)] = "US-Schedule-I" }

        let schedII = [
            "amphetamine", "methamphetamine", "cocaine", "methylphenidate",
            "ritalin", "adderall", "vyvanse", "lisdexamfetamine",
            "morphine", "oxycodone", "oxymorphone", "hydromorphone",
            "fentanyl", "hydrocodone", "methadone", "meperidine",
            "remifentanil", "sufentanil", "alfentanil",
            "tapentadol", "pentobarbital", "secobarbital",
            "amobarbital", "nabilone", "dronabinol oral solution",
            "phencyclidine", "pcp", "opium",
        ]
        for n in schedII { t[NameNormalizer.normalize(n)] = "US-Schedule-II" }

        let schedIII = [
            "buprenorphine", "ketamine", "anabolic steroids",
            "testosterone", "nandrolone", "stanozolol", "oxandrolone",
            "marinol", "dronabinol", "codeine combinations",
            "benzphetamine", "phendimetrazine",
            "tylenol with codeine",
        ]
        for n in schedIII { t[NameNormalizer.normalize(n)] = "US-Schedule-III" }

        let schedIV = [
            "alprazolam", "diazepam", "lorazepam", "clonazepam", "midazolam",
            "temazepam", "triazolam", "oxazepam", "chlordiazepoxide",
            "clorazepate", "flurazepam", "estazolam", "halazepam",
            "phenobarbital", "carisoprodol", "modafinil", "armodafinil",
            "zolpidem", "zopiclone", "zaleplon", "eszopiclone",
            "tramadol", "soma",
        ]
        for n in schedIV { t[NameNormalizer.normalize(n)] = "US-Schedule-IV" }

        let schedV = [
            "pregabalin", "lyrica", "ezogabine", "lacosamide",
            "ezogabine", "brivaracetam", "cenobamate",
            "cough syrups with codeine",
        ]
        for n in schedV { t[NameNormalizer.normalize(n)] = "US-Schedule-V" }

        return t
    }()

    static func scheduleTag(for name: String) -> String? {
        let n = NameNormalizer.normalize(name)
        return table[n]
    }
}
