import Foundation

/// A published reference snapshot. These records never enter DoseRange or any
/// dose-prefill, classification or session-model calculation.
nonisolated struct WikiDoseReferenceRecord: Identifiable {
    let id: String
    let sourceName: String
    let profileSHA256: String
    let snapshotSHA256: String
    let releaseID: String?
    let model: WikiDoseReferenceModel

    init(
        id: String, sourceName: String, profileSHA256: String, snapshotSHA256: String,
        releaseID: String?, modelJSON: String,
    ) throws {
        self.id = id
        self.sourceName = sourceName
        self.profileSHA256 = profileSHA256
        self.snapshotSHA256 = snapshotSHA256
        self.releaseID = releaseID
        self.model = try JSONDecoder().decode(WikiDoseReferenceModel.self, from: Data(modelJSON.utf8))
    }

    var sourceURL: URL? {
        let slug = sourceName.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return URL(string: "https://substance.wiki/drug/\(slug)")
    }
}

nonisolated struct WikiDoseReferenceModel: Decodable {
    let schemaVersion: String
    let status: String
    let groups: [WikiDoseReferenceGroup]
    let notes: [String]
    let warnings: [String]
    let reportedAmountDistributions: [WikiDoseReferenceJSON]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case status
        case groups
        case notes
        case warnings
        case reportedAmountDistributions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        status = try container.decode(String.self, forKey: .status)
        guard schemaVersion == "drug-community-dose-bands/1",
              ["available", "unavailable", "withdrawn"].contains(status)
        else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: container, debugDescription: "Unsupported dose reference contract")
        }
        notes = try container.decode([String].self, forKey: .notes)
        warnings = try container.decode([String].self, forKey: .warnings)
        // A withdrawal must not expose stale groups even if an inconsistent
        // old bundle left content beside that state.
        guard status != "withdrawn" else {
            groups = []
            reportedAmountDistributions = []
            return
        }
        groups = try container.decode([WikiDoseReferenceGroup].self, forKey: .groups)
        reportedAmountDistributions = try container.decode([WikiDoseReferenceJSON].self, forKey: .reportedAmountDistributions)
        guard (status == "available") == groups.contains(where: { !$0.bands.isEmpty }),
              Set(groups.map(\.id)).count == groups.count
        else {
            throw DecodingError.dataCorruptedError(forKey: .groups, in: container, debugDescription: "Missing or duplicate dose reference groups")
        }
    }
}

nonisolated struct WikiDoseReferenceGroup: Decodable, Identifiable {
    let id: String
    let kind: String
    let sourcePath: String
    let route: String
    let units: String
    let formulation: String?
    let materialBasis: String?
    let populationLimits: String?
    let notes: [String]
    let warnings: [String]
    let calculationEligible: Bool?
    let sources: [WikiDoseReferenceSource]
    let observations: [WikiDoseReferenceJSON]
    let bands: [WikiDoseReferenceBand]

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case sourcePath
        case route
        case units
        case formulation
        case materialBasis
        case populationLimits
        case notes
        case warnings
        case calculationEligible
        case sources
        case observations
        case bands
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(String.self, forKey: .kind)
        sourcePath = try container.decode(String.self, forKey: .sourcePath)
        route = try container.decode(String.self, forKey: .route)
        units = try container.decode(String.self, forKey: .units)
        formulation = try container.decodeIfPresent(String.self, forKey: .formulation)
        materialBasis = try container.decodeIfPresent(String.self, forKey: .materialBasis)
        populationLimits = try container.decodeIfPresent(String.self, forKey: .populationLimits)
        notes = try container.decode([String].self, forKey: .notes)
        warnings = try container.decode([String].self, forKey: .warnings)
        calculationEligible = try container.decodeIfPresent(Bool.self, forKey: .calculationEligible)
        sources = try container.decode([WikiDoseReferenceSource].self, forKey: .sources)
        observations = try container.decode([WikiDoseReferenceJSON].self, forKey: .observations)
        bands = try container.decode([WikiDoseReferenceBand].self, forKey: .bands)
        let sourceIDs = Set(sources.map(\.id))
        let observationIDs = Set(observations.compactMap { $0["id"]?.stringValue })
        guard ["published_route", "provisional_human"].contains(kind),
              kind != "provisional_human" || calculationEligible == false,
              sourceIDs.count == sources.count,
              sources.allSatisfy({ $0.details.objectValue != nil }),
              observations.allSatisfy({ $0.objectValue != nil }),
              Set(bands.map(\.id)).count == bands.count,
              bands.allSatisfy({ band in
                  band.sourceIds.allSatisfy(sourceIDs.contains)
                      && band.sourceObservationIds.allSatisfy(observationIDs.contains)
                      && (band.amount.kind == "text" || band.amount.units == units)
                      && (kind != "provisional_human" || band.calculationEligible == false)
                      && (band.band != "fatal" || band.calculationEligible == false)
                      && (band.provenance == nil || band.provenance?.objectValue != nil)
                      && (band.confidence == nil || band.confidence?.stringValue != nil || band.confidence?.numberValue != nil)
              })
        else {
            throw DecodingError.dataCorruptedError(forKey: .bands, in: container, debugDescription: "Invalid dose reference identity, context or evidence binding")
        }
    }
}

nonisolated struct WikiDoseReferenceBand: Decodable, Identifiable {
    let id: String
    let band: String
    let label: String
    let text: String
    let amount: WikiDoseReferenceAmount
    let status: String
    let confidence: WikiDoseReferenceJSON?
    let sourceIds: [String]
    let sourceObservationIds: [String]
    let notes: [String]
    let calculationEligible: Bool?
    let provenance: WikiDoseReferenceJSON?
}

nonisolated struct WikiDoseReferenceAmount: Decodable {
    let kind: String
    let lower: Double?
    let upper: Double?
    let lowerInclusive: Bool?
    let upperInclusive: Bool?
    let units: String?
    let basis: String

    private enum CodingKeys: String, CodingKey {
        case kind
        case lower
        case upper
        case lowerInclusive
        case upperInclusive
        case units
        case basis
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        lower = try container.decodeIfPresent(Double.self, forKey: .lower)
        upper = try container.decodeIfPresent(Double.self, forKey: .upper)
        lowerInclusive = try container.decodeIfPresent(Bool.self, forKey: .lowerInclusive)
        upperInclusive = try container.decodeIfPresent(Bool.self, forKey: .upperInclusive)
        units = try container.decodeIfPresent(String.self, forKey: .units)
        basis = try container.decode(String.self, forKey: .basis)
        let validBounds = [lower, upper].compactMap(\.self).allSatisfy { $0.isFinite && $0 >= 0 }
        let valid: Bool = switch kind {
        case "text":
            lower == nil && upper == nil && lowerInclusive == nil && upperInclusive == nil && units == nil && basis == "unparsed"
        case "lower_bound":
            lower != nil && upper == nil && upperInclusive == nil
        case "upper_bound":
            upper != nil && lower == nil && lowerInclusive == nil
        case "range", "exact":
            if let lower, let upper { lower <= upper && (kind != "exact" || lower == upper) } else { false }
        default:
            false
        }
        let validBasis = kind == "text" || (["source_numeric", "parsed_text"].contains(basis) && units?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        guard validBounds, valid, validBasis else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Invalid dose reference amount")
        }
    }
}

nonisolated struct WikiDoseReferenceSource: Decodable, Identifiable {
    let id: String
    let title: String?
    let url: String?
    let details: WikiDoseReferenceJSON

    var safeURL: URL? {
        guard let url, let result = URL(string: url),
              let scheme = result.scheme?.lowercased(), scheme == "http" || scheme == "https",
              result.host?.isEmpty == false, result.user == nil, result.password == nil
        else { return nil }
        return result
    }
}
