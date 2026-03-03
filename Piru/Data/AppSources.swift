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
            name: "TripSit",
            url: "https://tripsit.me",
            detail: "tripsit.me",
            description: "Harm reduction community providing factsheets on psychoactive substances, including dosage ranges, duration, interactions, and safety information."
        ),
        SourceInfo(
            name: "OpenFDA",
            url: "https://open.fda.gov",
            detail: "open.fda.gov — FDA Drug Labels API",
            description: "U.S. Food and Drug Administration open data API providing drug labeling information, pharmacologic classes, routes of administration, and brand/generic names."
        ),
        SourceInfo(
            name: "PsychonautWiki",
            url: "https://psychonautwiki.org",
            detail: "psychonautwiki.org",
            description: "Community-driven encyclopedia of psychoactive substances providing dosage, duration, pharmacology, subjective effects, and harm reduction information."
        ),
        SourceInfo(
            name: "DrugBank",
            url: "https://go.drugbank.com",
            detail: "go.drugbank.com",
            description: "Comprehensive pharmaceutical knowledge base combining detailed drug data with drug target information. Used for pharmacokinetic parameters and drug properties."
        ),
        SourceInfo(
            name: "PubMed",
            url: "https://pubmed.ncbi.nlm.nih.gov",
            detail: "pubmed.ncbi.nlm.nih.gov",
            description: "Biomedical literature database maintained by the National Library of Medicine, providing access to peer-reviewed research articles and clinical studies."
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
            name: "PiHKAL",
            url: "https://isomerdesign.com/PiHKAL/PiHKAL/",
            detail: "Phenethylamines I Have Known and Loved — Shulgin & Shulgin (1991)",
            description: "Pharmacological reference text by Alexander and Ann Shulgin documenting the synthesis, dosage, duration, and qualitative effects of phenethylamine compounds."
        ),
        SourceInfo(
            name: "TiHKAL",
            url: "https://isomerdesign.com/PiHKAL/TiHKAL/",
            detail: "Tryptamines I Have Known and Loved — Shulgin & Shulgin (1997)",
            description: "Pharmacological reference text by Alexander and Ann Shulgin documenting the synthesis, dosage, duration, and qualitative effects of tryptamine compounds."
        ),
        SourceInfo(
            name: "FDA DailyMed",
            url: "https://dailymed.nlm.nih.gov",
            detail: "dailymed.nlm.nih.gov",
            description: "Official FDA drug labeling database maintained by the National Library of Medicine, containing approved product labeling (package inserts) for prescription and OTC drugs."
        ),
        SourceInfo(
            name: "EMCDDA",
            url: "https://www.emcdda.europa.eu",
            detail: "European Monitoring Centre for Drugs and Drug Addiction",
            description: "EU agency providing risk assessments and pharmacological profiles of new psychoactive substances (NPS) and novel research chemicals."
        ),
        SourceInfo(
            name: "WHO",
            url: "https://www.who.int/teams/health-product-and-policy-standards/medicines-selection-and-ip",
            detail: "WHO Expert Committee on Drug Dependence",
            description: "World Health Organization critical reviews and assessments of psychoactive substances, including pharmacological evaluations and scheduling recommendations."
        ),
    ]

    static func info(for name: String) -> SourceInfo? {
        all.first { $0.name == name }
    }
}
