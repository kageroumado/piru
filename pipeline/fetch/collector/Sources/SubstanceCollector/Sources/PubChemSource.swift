import Foundation

// MARK: - PubChem REST shapes

private struct PCNameToCID: Codable {
    let identifierList: IdentifierList?
    struct IdentifierList: Codable { let cid: [Int] }
    enum CodingKeys: String, CodingKey { case identifierList = "IdentifierList" }
}

private struct PCProperties: Codable {
    let propertyTable: PropertyTable?
    struct PropertyTable: Codable {
        let properties: [Row]
        enum CodingKeys: String, CodingKey { case properties = "Properties" }
    }
    enum CodingKeys: String, CodingKey { case propertyTable = "PropertyTable" }
    struct Row: Codable {
        let CID: Int
        let CanonicalSMILES: String?
        let InChIKey: String?
        let IUPACName: String?
        let MolecularFormula: String?
    }
}

private struct PCSynonyms: Codable {
    let informationList: InformationList?
    struct InformationList: Codable {
        let information: [Info]
        enum CodingKeys: String, CodingKey { case information = "Information" }
    }
    enum CodingKeys: String, CodingKey { case informationList = "InformationList" }
    struct Info: Codable {
        let CID: Int
        let Synonym: [String]?
    }
}

/// Looks up InChIKey/CID/synonyms for Wikidata compounds that lack a
/// structural identifier. Rate-limited to 5 req/sec per PubChem's policy
/// (we use 250 ms = 4 req/sec to leave headroom).
struct PubChemSource {
    let cache: HTTPCache

    init(cache: HTTPCache) {
        self.cache = cache
        Task { await cache.configureLimiter(host: "pubchem.ncbi.nlm.nih.gov", interval: .milliseconds(250)) }
    }

    /// Enrich a list of Wikidata compounds in place by querying PubChem
    /// for any that lack an InChIKey. Returns the modified array.
    func enrich(_ compounds: [WikidataCompound]) async -> [WikidataCompound] {
        var result: [WikidataCompound] = []
        result.reserveCapacity(compounds.count)
        var enrichedCount = 0
        var failedCount = 0

        for (i, c) in compounds.enumerated() {
            if c.inchiKey != nil {
                result.append(c)
                continue
            }
            // Try name search → CID → properties.
            do {
                let cid: Int? = if let existing = c.pubchemCID {
                    existing
                } else {
                    try await lookupCID(name: c.name)
                }
                guard let cid else { result.append(c); failedCount += 1; continue }
                let (inchiKey, smiles, synonyms) = try await fetchProperties(cid: cid)
                let merged = WikidataCompound(
                    item: c.item, name: c.name,
                    aliases: dedupAliases(existing: c.aliases, additions: synonyms),
                    cas: c.cas,
                    inchiKey: inchiKey ?? c.inchiKey,
                    smiles: smiles ?? c.smiles,
                    pubchemCID: cid,
                    drugClass: c.drugClass,
                    seedCategory: c.seedCategory,
                )
                result.append(merged)
                enrichedCount += 1
            } catch {
                result.append(c)
                failedCount += 1
            }
            if (i + 1) % 25 == 0 {
                Log.info("PubChem: \(i + 1)/\(compounds.count) processed (\(enrichedCount) enriched, \(failedCount) skipped)")
            }
        }
        Log.info("PubChem: \(enrichedCount) compounds enriched, \(failedCount) lookups returned no usable data")
        return result
    }

    private func lookupCID(name: String) async throws -> Int? {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        guard let url = URL(string: "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/name/\(encoded)/cids/JSON") else {
            return nil
        }
        guard let data = try await cache.fetchOptional(url: url, scope: "pubchem-cid") else { return nil }
        let decoded = try? JSONDecoder().decode(PCNameToCID.self, from: data)
        return decoded?.identifierList?.cid.first
    }

    private func fetchProperties(cid: Int) async throws -> (inchiKey: String?, smiles: String?, synonyms: [String]) {
        let propsURL = URL(string: "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid/\(cid)/property/InChIKey,CanonicalSMILES,IUPACName,MolecularFormula/JSON")!
        var inchiKey: String?
        var smiles: String?
        if let data = try await cache.fetchOptional(url: propsURL, scope: "pubchem-props"),
           let decoded = try? JSONDecoder().decode(PCProperties.self, from: data),
           let row = decoded.propertyTable?.properties.first {
            inchiKey = row.InChIKey
            smiles = row.CanonicalSMILES
        }
        let synonyms: [String]
        let synURL = URL(string: "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid/\(cid)/synonyms/JSON")!
        if let data = try await cache.fetchOptional(url: synURL, scope: "pubchem-syn"),
           let decoded = try? JSONDecoder().decode(PCSynonyms.self, from: data),
           let info = decoded.informationList?.information.first,
           let syn = info.Synonym {
            // Take only the first ~10 synonyms; the rest are usually
            // catalog numbers and translations.
            synonyms = Array(syn.prefix(10))
        } else {
            synonyms = []
        }
        return (inchiKey, smiles, synonyms)
    }

    private func dedupAliases(existing: [String], additions: [String]) -> [String] {
        var seen = Set(existing.map(NameNormalizer.normalize))
        var out = existing
        for a in additions {
            let n = NameNormalizer.normalize(a)
            if !seen.contains(n), !a.isEmpty {
                seen.insert(n)
                out.append(a)
            }
        }
        return out
    }
}
