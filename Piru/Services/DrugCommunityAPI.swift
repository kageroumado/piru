import Foundation
import os

private let logger = Logger(subsystem: "dev.yumeji.piru", category: "DrugCommunityAPI")

/// [drug.community](https://drug.community) API client — a 4th data source
/// alongside TripSit, PsychonautWiki, and DailyMed.
///
/// Why it's here: TripSit covers the common recreational substances and
/// DailyMed covers FDA-approved drugs, but the long tail of research
/// chemicals and recently-scheduled analogs (DMXE, 3-MMC, novel
/// arylcyclohexylamines, fluorinated amphetamines, etc.) was a gap that
/// hurt search and harm-reduction value. drug.community fills it with
/// ~420 substances, mostly research chemicals and analogs not present in
/// the other sources.
///
/// ## Endpoint
///
/// `GET /api/info?name=<canonical-name-or-alias>` — returns a single
/// substance record. No bulk endpoint exists; the site is a SPA that
/// ships its substance data inline in the JS bundle. We bundle a static
/// name list (`drug-community-names.json`) extracted from that bundle and
/// query each name individually. The list is refreshable via the
/// `Tools/SubstanceValidator` CLI if drug.community adds substances.
///
/// ## Pipeline placement
///
/// Runs as a *background* enrichment stage after the TripSit-only UI has
/// already rendered, similar to ``PsychonautWikiAPI``. New substances are
/// added; existing ones are merged via ``SubstanceDeduplicator``.
struct DrugCommunityAPI {

    // MARK: - Endpoint

    nonisolated private static let endpoint = "https://drug.community/api/info"

    // MARK: - Name list

    /// All substance names known to drug.community at the time the bundled
    /// name list was extracted. Loaded once from the app bundle.
    static let allNames: [String] = {
        guard let url = Bundle.main.url(forResource: "drug-community-names", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let names = try? JSONDecoder().decode([String].self, from: data) else {
            logger.error("Failed to load drug-community-names.json from bundle")
            return []
        }
        return names
    }()

    // MARK: - JSON shapes

    nonisolated struct Response: Decodable, Sendable {
        let drug_name: String
        let alternative_names: [String]?
        let chemical_class: String?
        let psychoactive_class: String?
        let dosages: Dosages?
        let duration: Duration?
        let duration_curves: [DurationCurveEntry]?
        let half_life: String?
        let subjective_effects: [String]?
        let categories: [String]?

        struct Dosages: Decodable, Sendable {
            let routes_of_administration: [RouteEntry]?
        }

        struct RouteEntry: Decodable, Sendable {
            let route: String
            let units: String?
            let notes: String?
            let dose_ranges: DoseRanges?
        }

        struct DoseRanges: Decodable, Sendable {
            let threshold: String?
            let light: String?
            let common: String?
            let strong: String?
            let heavy: String?
        }

        struct Duration: Decodable, Sendable {
            let total_duration: String?
            let onset: String?
            let peak: String?
            let offset: String?
            let after_effects: String?
        }

        struct DurationCurveEntry: Decodable, Sendable {
            let method: String
            let duration_curve: DurationCurve?
        }

        struct DurationCurve: Decodable, Sendable {
            let total_duration: Phase?
            let onset: Phase?
            let peak: Phase?
            let offset: Phase?
            let after_effects: Phase?
        }

        struct Phase: Decodable, Sendable {
            let min: Double?
            let max: Double?
            let start: Double?
            let end: Double?
        }
    }

    // MARK: - Errors

    enum APIError: Error {
        case badResponse
        case notFound
    }

    // MARK: - Fetch

    /// Fetch a single substance by name. Returns nil if drug.community
    /// doesn't have a record for that name. The raw response is Sendable —
    /// the MainActor-isolated `toSubstance(_:)` conversion happens at the
    /// caller's site so SwiftData / model objects don't have to cross the
    /// actor boundary.
    nonisolated static func fetchResponse(name: String) async -> Response? {
        guard var components = URLComponents(string: endpoint) else { return nil }
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Piru/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            // 404s come back as a JSON `{"error":"Drug not found"}` blob the
            // decoder can't handle; treat as no result rather than a crash.
            return nil
        }
    }

    /// Fetch a batch of responses in parallel. Names that aren't in
    /// drug.community's index return nothing and don't appear in the result.
    /// Conversion to ``Substance`` happens on the caller's actor.
    nonisolated static func fetchResponses(names: [String], maxConcurrent: Int = 10) async -> [Response] {
        guard !names.isEmpty else { return [] }
        return await withTaskGroup(of: Response?.self) { group in
            var iter = names.makeIterator()
            var results: [Response] = []

            func enqueueNext() {
                guard let name = iter.next() else { return }
                group.addTask {
                    await fetchResponse(name: name)
                }
            }

            for _ in 0..<min(maxConcurrent, names.count) { enqueueNext() }
            while let result = await group.next() {
                if let result { results.append(result) }
                enqueueNext()
            }
            return results
        }
    }

    // MARK: - Conversion

    /// Map a drug.community response to our canonical ``Substance``.
    static func toSubstance(_ response: Response) -> Substance {
        let (name, parentheticalAliases) = splitNameAndParentheticals(response.drug_name)
        var aliases = parentheticalAliases
        if let alts = response.alternative_names {
            for alias in alts where alias.lowercased() != name.lowercased() {
                if !aliases.contains(where: { $0.lowercased() == alias.lowercased() }) {
                    aliases.append(alias)
                }
            }
        }

        let category = SubstanceCategory.from(
            tripSitCategory: response.psychoactive_class ?? response.categories?.first ?? ""
        )

        // Build a per-route duration profile lookup from the structured
        // duration_curves payload — it carries explicit min/max numbers per
        // phase in hours and is way cleaner than parsing the prose
        // `duration` block.
        var durationByRoute: [RouteOfAdministration: DurationProfile] = [:]
        if let curves = response.duration_curves {
            for entry in curves {
                guard let curve = entry.duration_curve else { continue }
                let route = RouteOfAdministration.from(string: entry.method)
                if let profile = makeDurationProfile(from: curve) {
                    durationByRoute[route] = profile
                }
            }
        }

        var routes: [SubstanceRoute] = []
        if let routeEntries = response.dosages?.routes_of_administration {
            for entry in routeEntries {
                let route = RouteOfAdministration.from(string: entry.route)
                let unit = entry.units ?? "mg"
                let doses = parseDoseRange(entry.dose_ranges)
                let duration = durationByRoute[route]
                routes.append(SubstanceRoute(
                    route: route,
                    unit: unit,
                    doses: doses,
                    duration: duration
                ))
            }
        }

        // Some substances ship duration curves for routes that aren't in the
        // dosages block (e.g. a "vaporized" curve without dosage data). Add
        // them with empty dose ranges so timing data is still surfaced.
        let coveredRoutes = Set(routes.map(\.route))
        for (route, profile) in durationByRoute where !coveredRoutes.contains(route) {
            routes.append(SubstanceRoute(route: route, unit: "mg", doses: DoseRange(), duration: profile))
        }

        let halfLife = parseHalfLifeMinutes(response.half_life)
        let defaultRoute = routes.first?.route ?? .oral
        let subjectiveEffects = (response.subjective_effects ?? [])
            .map { SubjectiveEffect(name: $0, description: "") }

        return Substance(
            name: name,
            aliases: aliases,
            category: category,
            defaultRoute: defaultRoute,
            routes: routes,
            effects: [],
            subjectiveEffects: subjectiveEffects,
            toleranceInfo: nil,
            halfLifeMinutes: halfLife,
            sources: ["drug.community"]
        )
    }

    // MARK: - Parsing helpers

    /// drug.community formats names as "Primary (alias1, alias2, ...)" — split
    /// the parenthetical portion off and emit each as an alias.
    private static func splitNameAndParentheticals(_ raw: String) -> (name: String, aliases: [String]) {
        guard let openIdx = raw.firstIndex(of: "("),
              let closeIdx = raw.lastIndex(of: ")"),
              openIdx < closeIdx else {
            return (raw.trimmingCharacters(in: .whitespaces), [])
        }
        let name = String(raw[..<openIdx]).trimmingCharacters(in: .whitespaces)
        let inner = String(raw[raw.index(after: openIdx)..<closeIdx])
        let aliases = inner
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return (name, aliases)
    }

    /// Parse a drug.community dose-range block, where each level is a string
    /// like "15–25 mg", "100+ mg", or "5 mg" with an en-dash or hyphen.
    static func parseDoseRange(_ block: Response.DoseRanges?) -> DoseRange {
        guard let block else { return DoseRange() }

        func parse(_ s: String?) -> (lo: Double?, hi: Double?) {
            guard let s else { return (nil, nil) }
            // Strip everything that isn't a digit or decimal point — hyphens,
            // en-dashes, em-dashes, plus signs, and units all become spaces.
            // The dash that separates a range becomes whitespace too, which
            // is what lets a single-pass split-by-whitespace return both
            // numbers for "15–25 mg".
            let numbers = s
                .replacingOccurrences(of: "[^0-9.]", with: " ", options: .regularExpression)
                .split(separator: " ")
                .compactMap { Double($0) }
            if numbers.isEmpty { return (nil, nil) }
            if numbers.count == 1 { return (numbers[0], numbers[0]) }
            return (numbers[0], numbers[1])
        }

        let t = parse(block.threshold)
        let l = parse(block.light)
        let c = parse(block.common)
        let s = parse(block.strong)
        let h = parse(block.heavy)

        let lightRange: ClosedRange<Double>? = {
            guard let lo = l.lo, let hi = l.hi, lo <= hi else { return nil }
            return lo...hi
        }()
        let commonRange: ClosedRange<Double>? = {
            guard let lo = c.lo, let hi = c.hi, lo <= hi else { return nil }
            return lo...hi
        }()
        let strongRange: ClosedRange<Double>? = {
            guard let lo = s.lo, let hi = s.hi, lo <= hi else { return nil }
            return lo...hi
        }()

        return DoseRange(
            threshold: t.lo,
            light: lightRange,
            common: commonRange,
            strong: strongRange,
            heavy: h.lo
        )
    }

    /// Build a ``DurationProfile`` from a drug.community ``DurationCurve``.
    /// Phases come in hours; we store everything in minutes.
    static func makeDurationProfile(from curve: Response.DurationCurve) -> DurationProfile? {
        guard curve.total_duration != nil
                || curve.onset != nil
                || curve.peak != nil
                || curve.offset != nil
                || curve.after_effects != nil
        else { return nil }

        func toRange(_ phase: Response.Phase?) -> DurationRange? {
            guard let phase else { return nil }
            let lo = phase.start ?? phase.min
            let hi = phase.end ?? phase.max
            guard let lo, let hi, lo <= hi, hi > 0 else { return nil }
            // drug.community always emits durations in hours.
            return DurationRange(min: lo * 60, max: hi * 60)
        }

        return DurationProfile(
            onset: toRange(curve.onset),
            comeup: nil,
            peak: toRange(curve.peak),
            offset: toRange(curve.offset),
            afterglow: toRange(curve.after_effects),
            total: toRange(curve.total_duration)
        )
    }

    /// Parse a free-form half-life string like "3-6 h" or "30 minutes" into
    /// minutes. Returns nil for unknown/unparseable values.
    static func parseHalfLifeMinutes(_ str: String?) -> Double? {
        guard let str, !str.isEmpty else { return nil }
        let lower = str.lowercased()
        let numbers = lower
            .replacingOccurrences(of: "[^0-9.]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .compactMap { Double($0) }
        guard let first = numbers.first else { return nil }
        if lower.contains("day") { return first * 24 * 60 }
        if lower.contains("hour") || lower.contains(" h") || lower.hasSuffix("h") { return first * 60 }
        if lower.contains("min") { return first }
        // Default: assume hours, which is the common case for drug.community.
        return first * 60
    }
}
