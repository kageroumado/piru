import Foundation

struct SourceInfo {
    let name: String
    let url: String
    let detail: String
    let description: String
}

enum AppSources {
    static let all: [SourceInfo] = [
        SourceInfo(
            name: "Drugs.com",
            url: "https://www.drugs.com",
            detail: "drugs.com",
            description: "Comprehensive consumer drug information database providing FDA-approved prescribing information, dosing guidelines, side effects, and drug interactions."
        ),
        SourceInfo(
            name: "FDA DailyMed",
            url: "https://dailymed.nlm.nih.gov",
            detail: "dailymed.nlm.nih.gov",
            description: "Official FDA drug labeling database maintained by the National Library of Medicine, containing approved product labeling (package inserts) for prescription and OTC drugs."
        ),
        SourceInfo(
            name: "StatPearls",
            url: "https://www.statpearls.com",
            detail: "statpearls.com — NCBI Bookshelf",
            description: "Peer-reviewed medical reference covering pharmacology, mechanisms of action, pharmacokinetics, and clinical guidance. Available free through NCBI Bookshelf."
        ),
        SourceInfo(
            name: "PubMed",
            url: "https://pubmed.ncbi.nlm.nih.gov",
            detail: "pubmed.ncbi.nlm.nih.gov",
            description: "Biomedical literature database maintained by the National Library of Medicine, providing access to peer-reviewed research articles and clinical studies."
        ),
        SourceInfo(
            name: "DrugBank",
            url: "https://go.drugbank.com",
            detail: "go.drugbank.com",
            description: "Comprehensive pharmaceutical knowledge base combining detailed drug data with drug target information. Used for pharmacokinetic parameters and drug properties."
        ),
        SourceInfo(
            name: "PsychonautWiki",
            url: "https://psychonautwiki.org",
            detail: "psychonautwiki.org",
            description: "Community-driven encyclopedia documenting the encyclopedic cataloging of psychoactive substances, including dosage ranges, duration profiles, and subjective effects based on user reports and available research."
        ),
        SourceInfo(
            name: "Erowid",
            url: "https://www.erowid.org",
            detail: "erowid.org",
            description: "Non-profit educational organization providing information about psychoactive substances, including dosage, duration, and experience reports collected since 1995."
        ),
        SourceInfo(
            name: "TiHKAL",
            url: "https://isomerdesign.com/PiHKAL/TiHKAL/",
            detail: "Tryptamines I Have Known and Loved — Shulgin & Shulgin (1997)",
            description: "Pharmacological reference text by Alexander and Ann Shulgin documenting the synthesis, dosage, duration, and qualitative effects of tryptamine compounds."
        ),
        SourceInfo(
            name: "PiHKAL",
            url: "https://isomerdesign.com/PiHKAL/PiHKAL/",
            detail: "Phenethylamines I Have Known and Loved — Shulgin & Shulgin (1991)",
            description: "Pharmacological reference text by Alexander and Ann Shulgin documenting the synthesis, dosage, duration, and qualitative effects of phenethylamine compounds."
        ),
        SourceInfo(
            name: "Examine.com",
            url: "https://examine.com",
            detail: "examine.com",
            description: "Independent, evidence-based nutrition and supplement research database analyzing scientific studies on supplements, nutrients, and bioactive compounds."
        ),
        SourceInfo(
            name: "NIH ODS",
            url: "https://ods.od.nih.gov",
            detail: "Office of Dietary Supplements — ods.od.nih.gov",
            description: "National Institutes of Health Office of Dietary Supplements, providing evidence-based fact sheets on vitamins, minerals, and dietary supplements."
        ),
        SourceInfo(
            name: "WHO",
            url: "https://www.who.int/teams/health-product-and-policy-standards/medicines-selection-and-ip",
            detail: "WHO Expert Committee on Drug Dependence",
            description: "World Health Organization critical reviews and assessments of psychoactive substances, including pharmacological evaluations and scheduling recommendations."
        ),
        SourceInfo(
            name: "DEA",
            url: "https://www.deadiversion.usdoj.gov/drug_chem_info/",
            detail: "Drug Enforcement Administration",
            description: "U.S. Drug Enforcement Administration drug and chemical information profiles, providing scheduling status and pharmacological summaries."
        ),
        SourceInfo(
            name: "EMCDDA",
            url: "https://www.emcdda.europa.eu",
            detail: "European Monitoring Centre for Drugs and Drug Addiction",
            description: "EU agency providing risk assessments and pharmacological profiles of new psychoactive substances (NPS) and novel research chemicals."
        ),
        SourceInfo(
            name: "Merck Manual",
            url: "https://www.merckmanuals.com/professional",
            detail: "merckmanuals.com/professional",
            description: "Medical reference providing clinical pharmacology, dosing, and adverse effect information for healthcare professionals."
        ),
        SourceInfo(
            name: "UpToDate",
            url: "https://www.uptodate.com",
            detail: "uptodate.com",
            description: "Evidence-based clinical decision support resource used by healthcare providers for drug dosing, pharmacokinetics, and clinical guidance."
        ),
        SourceInfo(
            name: "INCB",
            url: "https://www.incb.org",
            detail: "International Narcotics Control Board",
            description: "United Nations body monitoring international drug control treaty compliance, providing substance classification and pharmacological data."
        ),
        SourceInfo(
            name: "Goodman & Gilman's",
            url: "",
            detail: "The Pharmacological Basis of Therapeutics (14th ed.)",
            description: "Authoritative pharmacology textbook covering mechanisms of action, pharmacokinetics, therapeutic uses, and toxicology of drugs."
        ),
        SourceInfo(
            name: "Stahl's Prescriber's Guide",
            url: "",
            detail: "Stahl's Essential Psychopharmacology — Prescriber's Guide (7th ed.)",
            description: "Clinical psychopharmacology reference covering dosing, pharmacokinetics, mechanisms of action, and side effects of psychiatric medications."
        ),
        SourceInfo(
            name: "Lexicomp",
            url: "https://online.lexi.com",
            detail: "Lexicomp Drug Information — online.lexi.com",
            description: "Clinical drug reference database used in hospitals and pharmacies, providing comprehensive prescribing information and pharmacokinetic data."
        ),
        SourceInfo(
            name: "LiverTox",
            url: "https://www.ncbi.nlm.nih.gov/books/NBK547852/",
            detail: "NIDDK LiverTox — ncbi.nlm.nih.gov",
            description: "National Institute of Diabetes and Digestive and Kidney Diseases database on drug-induced liver injury, hepatotoxicity, and safe dosing limits."
        ),
        SourceInfo(
            name: "Martindale",
            url: "",
            detail: "Martindale: The Complete Drug Reference (40th ed.)",
            description: "Comprehensive international drug reference covering prescription drugs, OTC medicines, and herbal and supplementary preparations worldwide."
        ),
    ]

    static func info(for name: String) -> SourceInfo? {
        all.first { $0.name == name }
    }
}
