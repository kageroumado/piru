import Foundation

// MARK: - SPARQL response shapes

private struct SPARQLResponse: Codable {
    let results: Results
    struct Results: Codable { let bindings: [[String: Binding]] }
    struct Binding: Codable {
        let type: String?
        let value: String
        let xmlLang: String?
        enum CodingKeys: String, CodingKey { case type, value, xmlLang = "xml:lang" }
    }
}

/// One canonical chemical entity sourced from Wikidata.
struct WikidataCompound {
    let item: String // QID, e.g. "Q409"
    let name: String // English label (rdfs:label)
    let aliases: [String] // skos:altLabel set
    let cas: String? // P231
    let inchiKey: String? // P235
    let smiles: String? // P233
    let pubchemCID: Int? // P662
    let drugClass: [String] // P5642 + drug-class labels via P31/P279
    /// The seed category (e.g. "Designer drugs") this came from. Used for
    /// `category` mapping when nothing more specific is found.
    let seedCategory: WikidataSource.Seed
}

/// Pulls compounds from Wikidata via SPARQL. We run one query per seed
/// category and union the results.
struct WikidataSource {
    let cache: HTTPCache

    /// Seed categories. Each maps to a Wikidata SPARQL "is-instance-of or
    /// subclass-of" filter against the corresponding meta-item.
    /// Each maps to a Wikidata class hub used as the `wdt:P279*` filter
    /// (transitive `subclass-of`). On Wikidata, individual chemical compounds
    /// are typically modeled as *subclasses* of their class concept, not as
    /// instances — so P279* finds the actual compound list. QIDs verified
    /// 2026-05; counts in comments are approximate.
    enum Seed: String, CaseIterable {
        case phenethylamine = "Q422693" // ~1500 compounds
        case tryptamine = "Q10705510" // ~3600 compounds
        case substitutedAmphetamine = "Q2445303" // ~90 compounds
        case cathinone = "Q7632116" // ~30 compounds
        case syntheticCannabinoid = "Q19904200" // ~5 compounds
        case opioid = "Q427523" // ~10 compounds
        case designerDrug = "Q1200715" // ~5 compounds
        case hallucinogen = "Q189553" // ~10 compounds

        var label: String {
            switch self {
            case .phenethylamine: "phenethylamine"
            case .tryptamine: "tryptamine"
            case .substitutedAmphetamine: "substituted amphetamine"
            case .cathinone: "cathinone"
            case .syntheticCannabinoid: "synthetic cannabinoid"
            case .opioid: "opioid"
            case .designerDrug: "designer drug"
            case .hallucinogen: "hallucinogen"
            }
        }

        var defaultCategory: String {
            switch self {
            // For broad structural classes we default to "Other" — many
            // members (e.g. tryptophan metabolites, melatonin) aren't
            // recreational drugs. Specific drug-class P5642 labels override
            // this in CategoryMapper.
            case .phenethylamine: "Other"
            case .tryptamine: "Other"
            case .substitutedAmphetamine: "Stimulant"
            case .cathinone: "Stimulant"
            case .syntheticCannabinoid: "Cannabinoid"
            case .opioid: "Opioid"
            case .designerDrug: "Other"
            case .hallucinogen: "Psychedelic"
            }
        }
    }

    func fetchAll() async -> [WikidataCompound] {
        var seen: [String: WikidataCompound] = [:] // by InChIKey or QID
        for seed in Seed.allCases {
            do {
                let compounds = try await fetch(seed: seed)
                Log.info("Wikidata[\(seed.label)]: \(compounds.count) compounds")
                for c in compounds {
                    let key = c.inchiKey ?? c.item
                    // Keep first occurrence — earlier seeds tend to be more specific.
                    if seen[key] == nil { seen[key] = c }
                }
            } catch {
                Log.warn("Wikidata[\(seed.label)] failed: \(error.localizedDescription)")
            }
        }
        Log.info("Wikidata: \(seen.count) deduplicated compounds")
        // Sort by item QID for deterministic output.
        return seen.keys.sorted().map { seen[$0]! }
    }

    func fetch(seed: Seed) async throws -> [WikidataCompound] {
        let query = sparql(seed: seed)
        let endpoint = URL(string: "https://query.wikidata.org/sparql")!
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url else {
            throw NSError(domain: "Wikidata", code: 1, userInfo: [NSLocalizedDescriptionKey: "URL build failed"])
        }
        let data = try await cache.fetch(
            url: url,
            headers: ["Accept": "application/sparql-results+json"],
            scope: "wikidata",
        )
        return try parseResponse(data, seed: seed)
    }

    /// SPARQL: items that are transitive subclasses of `seed`. Wikidata
    /// models individual compounds as `wdt:P279*` (subclass-of) of their
    /// chemical-class hub, so this pattern enumerates them. Optional
    /// CAS/InChIKey/SMILES/PubChem CID, plus drug-class labels via P5642.
    private func sparql(seed: Seed) -> String {
        """
        SELECT ?item ?itemLabel ?cas ?inchikey ?smiles ?pubchem (GROUP_CONCAT(DISTINCT ?classLabel; separator="|") AS ?classes) (GROUP_CONCAT(DISTINCT ?alias; separator="|") AS ?aliases)
        WHERE {
          ?item wdt:P279* wd:\(seed.rawValue).
          OPTIONAL { ?item wdt:P231 ?cas. }
          OPTIONAL { ?item wdt:P235 ?inchikey. }
          OPTIONAL { ?item wdt:P233 ?smiles. }
          OPTIONAL { ?item wdt:P662 ?pubchem. }
          OPTIONAL { ?item wdt:P5642 ?class.
                     ?class rdfs:label ?classLabel.
                     FILTER (LANG(?classLabel) = "en") }
          OPTIONAL { ?item skos:altLabel ?alias.
                     FILTER (LANG(?alias) = "en") }
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        }
        GROUP BY ?item ?itemLabel ?cas ?inchikey ?smiles ?pubchem
        LIMIT 4000
        """
    }

    private func parseResponse(_ data: Data, seed: Seed) throws -> [WikidataCompound] {
        let resp = try JSONDecoder().decode(SPARQLResponse.self, from: data)
        var out: [WikidataCompound] = []
        out.reserveCapacity(resp.results.bindings.count)
        for row in resp.results.bindings {
            guard let item = row["item"]?.value,
                  let qid = item.components(separatedBy: "/").last,
                  let name = row["itemLabel"]?.value,
                  !name.isEmpty,
                  !name.hasPrefix("Q") // unlabeled items echo back their QID
            else { continue }

            let aliases = (row["aliases"]?.value ?? "")
                .components(separatedBy: "|")
                .filter { !$0.isEmpty }
            let classes = (row["classes"]?.value ?? "")
                .components(separatedBy: "|")
                .filter { !$0.isEmpty }
            let pubchemCID: Int? = (row["pubchem"]?.value).flatMap(Int.init)

            let cas = row["cas"]?.value
            let inchi = row["inchikey"]?.value
            // Skip purely-structural entries with no identifier of any kind:
            // these are abstract concepts (e.g. "aromatic amine"), not
            // discrete compounds users would log.
            guard cas != nil || inchi != nil || pubchemCID != nil else { continue }

            let decodedName = Self.decodeHTMLEntities(name)

            // Unconditional peptide skip — tripeptides containing Trp leak
            // into the tryptamine SPARQL but aren't drugs users would log.
            if Self.isPeptide(decodedName) { continue }

            // Skip IUPAC-style structural names — they're real compounds but
            // browsing a list of them is useless and they push out the
            // recognizable drug names. Heuristic: very long names (>40 chars)
            // or names with multiple parentheses / brackets are IUPAC.
            if decodedName.count > 60 { continue }
            let openParens = decodedName.count(where: { $0 == "(" })
            let openBrackets = decodedName.count(where: { $0 == "[" })
            if openParens + openBrackets >= 2 { continue }

            // Skip natural-product noise: stereochemistry-prefixed obscure
            // alkaloid metabolites have no recreational relevance. Heuristic:
            // require either a known drug-class tag, OR a drug-shaped name
            // (one of our recognized prefixes/suffixes), OR aliases.
            if classes.isEmpty,
               !Self.looksLikeRecreationalDrug(decodedName),
               aliases.isEmpty {
                continue
            }

            out.append(WikidataCompound(
                item: qid,
                name: decodedName,
                aliases: aliases.map(Self.decodeHTMLEntities),
                cas: cas,
                inchiKey: inchi,
                smiles: row["smiles"]?.value,
                pubchemCID: pubchemCID,
                drugClass: classes,
                seedCategory: seed,
            ))
        }
        return out
    }

    /// Convert one Wikidata compound to a `SourcedSubstance`. Wikidata never
    /// has dose data — these are identifier-only stubs whose value is the
    /// reference URLs and accurate identifier metadata for dedup.
    static func toSourced(_ c: WikidataCompound) -> SourcedSubstance {
        var tags = Tagger.tags(for: c.name, sourceClasses: c.drugClass + [c.seedCategory.label])
        tags.append("no-human-data")
        tags = Tagger.merge(tags)

        // Category cascade:
        //   1. Explicit name override (modafinil → Eugeroic, salvinorin → Dysdelic).
        //   2. Tag-implied category (NBOMe/2C-x/DOx → Psychedelic, nitazene → Opioid).
        //   3. Wikidata P5642 drug-class labels.
        //   4. Seed category default.
        let mapped = CategoryMapper.map(labels: c.drugClass, name: c.name)
        let category: String = if mapped != "Other" {
            mapped
        } else if let tagCat = categoryFromTags(tags) {
            tagCat
        } else {
            c.seedCategory.defaultCategory
        }

        var sources = ["Wikidata: https://www.wikidata.org/wiki/\(c.item)"]
        if let cid = c.pubchemCID {
            sources.append("PubChem CID \(cid): https://pubchem.ncbi.nlm.nih.gov/compound/\(cid)")
        }
        if let cas = c.cas {
            sources.append("CAS \(cas)")
        }

        let warnings = SafetyWarnings.warnings(for: c.name, tags: tags)

        return SourcedSubstance(
            substance: BundledSubstance(
                name: c.name,
                aliases: c.aliases,
                category: category,
                defaultRoute: "oral",
                routes: [],
                effects: warnings,
                halfLifeMinutes: nil,
                sources: sources,
                tags: tags,
            ),
            provenance: .wikidataPubchem,
            inchiKey: c.inchiKey,
            pubchemCID: c.pubchemCID,
            cas: c.cas,
        )
    }

    /// Wikidata labels occasionally come back with numeric character refs
    /// (e.g. `&#177;` for ±). Strip the common ones.
    private static func decodeHTMLEntities(_ s: String) -> String {
        var out = s
        let pairs: [(String, String)] = [
            ("&#177;", "±"), ("&plusmn;", "±"),
            ("&#945;", "α"), ("&alpha;", "α"),
            ("&#946;", "β"), ("&beta;", "β"),
            ("&#947;", "γ"), ("&gamma;", "γ"),
            ("&#956;", "µ"), ("&micro;", "µ"),
            ("&#8211;", "–"), ("&ndash;", "–"),
            ("&#8212;", "—"), ("&mdash;", "—"),
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"),
        ]
        for (k, v) in pairs {
            out = out.replacingOccurrences(of: k, with: v)
        }
        return out
    }

    /// 3-letter amino-acid codes used to filter out tripeptides/dipeptides
    /// that bleed into the tryptamine SPARQL because they contain Trp.
    private static let aminoAcidCodes: Set<String> = [
        "ala", "arg", "asn", "asp", "cys", "gln", "glu", "gly", "his",
        "ile", "leu", "lys", "met", "phe", "pro", "ser", "thr", "trp",
        "tyr", "val",
    ]

    /// True for names like "Ala-Trp-Asp" or "Gly-Trp" — these are peptides
    /// that contain a Trp residue and aren't recreational drugs.
    private static func isPeptide(_ name: String) -> Bool {
        let parts = name.split(separator: "-").map { $0.lowercased() }
        guard parts.count >= 2 else { return false }
        let aaCount = parts.count(where: { aminoAcidCodes.contains($0) })
        return aaCount >= 2
    }

    /// Heuristic: does this name look like a recreational drug compound vs an
    /// arbitrary natural product? We accept names containing recognized
    /// suffixes/prefixes from the controlled vocabulary, or names that are
    /// short uppercase acronyms (e.g. "4-AcO-DMT").
    private static func looksLikeRecreationalDrug(_ name: String) -> Bool {
        if isPeptide(name) { return false }
        let lower = name.lowercased()
        // Bypass for compound names that match known drug substring patterns.
        let drugLike = [
            "amphetamine", "cathinone", "tryptamine", "dipt", "dmt", "dmt-",
            "5-meo-", "4-aco-", "4-ho-", "4-meo-", "phenidine",
            "nbome", "nboh", "2c-", "dox", "doi", "dob", "doc", "dom",
            "ketamine", "methoxetamine", "mxe", "pcp", "diphenidine",
            "fentanyl", "fentanil", "nitazene", "etonitazene",
            "modafinil", "adrafinil", "ampakine",
            "racetam", "salvinorin",
            "azepam", "azolam", "azenil",
            "methcathinone", "methylone", "ephedrone", "buphedrone",
            "pyrovalerone", "pvp", "mdpv", "mdma", "mda", "mde",
            "lsd", "lsa",
            "jwh-", "ab-", "adb-", "5f-", "mdmb-",
            "u-47", "u-48", "u-50",
        ]
        if drugLike.contains(where: lower.contains) { return true }
        // Short alphanumeric pseudo-acronyms (e.g. "AH-7921", "AM-2201").
        let acronymPattern = #"^[a-z0-9]{1,5}-[0-9]+[a-z]?$"#
        if lower.range(of: acronymPattern, options: .regularExpression) != nil { return true }
        // ChEMBL/LY/CX/Org/PRE/IDRA series identifiers.
        let seriesPattern = #"^(cx|ly|org|pre|idra|sb|wb|abt|gw|ru|mk|ro|cgs|wd|ya)\s*-?\s*\d+"#
        if lower.range(of: seriesPattern, options: .regularExpression) != nil { return true }
        return false
    }

    /// Infer a category from the tag set when the source category was "Other".
    /// Returns nil if no tag suggests a clear category.
    private static func categoryFromTags(_ tags: [String]) -> String? {
        let set = Set(tags)
        // Order matters — first match wins.
        if set.contains("nitazene") || set.contains("mu-opioid-agonist") { return "Opioid" }
        if set.contains("kappa-opioid-agonist") { return "Dysdelic" }
        if set.contains("synthetic-cannabinoid") { return "Cannabinoid" }
        if set.contains("GABAA-PAM") && set.contains("benzodiazepine") { return "Benzodiazepine" }
        if set.contains("NMDA-antagonist") { return "Dissociative" }
        if set.contains("NBOMe") || set.contains("DOx") || set.contains("2C-x") || set.contains("5-HT2A-agonist") {
            return "Psychedelic"
        }
        if set.contains("AMPA-PAM") || set.contains("ampakine") { return "AMPAkine" }
        if set.contains("eugeroic") { return "Eugeroic" }
        if set.contains("racetam") || set.contains("nootropic") { return "Nootropic" }
        if set.contains("cathinone") { return "Stimulant" }
        if set.contains("DRI") || set.contains("NDRI") || set.contains("TAAR1") { return "Stimulant" }
        if set.contains("SRI") || set.contains("SNRI") || set.contains("SNDRI") { return "Antidepressant" }
        if set.contains("MAOI-A") || set.contains("MAOI-B") || set.contains("RIMA") { return "Antidepressant" }
        return nil
    }
}
