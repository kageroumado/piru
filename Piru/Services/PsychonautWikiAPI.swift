import Foundation
import os

private let logger = Logger(subsystem: "dev.yumeji.piru", category: "PsychonautWikiAPI")

/// PsychonautWiki GraphQL API client — fetches psychoactive substance data
/// with per-route dose ranges, full duration profiles, subjective effects, and tolerance info.
///
/// Adapted from the proven CLI tool implementation (`Tools/SubstanceValidator`).
enum PsychonautWikiAPI {
    private static let endpoint = URL(string: "https://api.psychonautwiki.org/graphql")!

    // MARK: - Public API

    /// Fetch substance data for a list of names, returning successfully converted `Substance` values.
    /// Queries are batched (max 3 concurrent) with a 2-second rate limit to avoid 429s.
    static func fetchSubstances(names: [String]) async -> [Substance] {
        let limiter = PWRateLimiter()
        var rawResults: [PWSubstance] = []

        for batch in names.chunked(into: 3) {
            await withTaskGroup(of: PWSubstance?.self) { group in
                for name in batch {
                    group.addTask {
                        await limiter.wait()
                        return await fetchSingle(name: name)
                    }
                }

                for await result in group {
                    if let result { rawResults.append(result) }
                }
            }
        }

        // Convert outside the task group (avoids @Sendable isolation issues)
        let substances = rawResults.map { toSubstance($0) }
        logger.info("Fetched \(substances.count)/\(names.count) substances")
        return substances
    }

    // MARK: - GraphQL Query

    private static func fetchSingle(name: String) async -> PWSubstance? {
        let escapedName = name.replacingOccurrences(of: "\"", with: "\\\"")
        let query = """
        {
            substances(query: "\(escapedName)") {
                name
                roas {
                    name
                    dose {
                        units
                        threshold
                        heavy
                        common { min max }
                        light { min max }
                        strong { min max }
                    }
                    duration {
                        onset { min max units }
                        comeup { min max units }
                        peak { min max units }
                        offset { min max units }
                        afterglow { min max units }
                        total { min max units }
                    }
                }
                effects {
                    name
                    url
                }
                classes {
                    psychoactive
                }
                tolerance {
                    full
                    half
                    zero
                }
                addictionPotential
            }
        }
        """

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Piru/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        do {
            let body = ["query": query]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }

            if http.statusCode == 429 {
                // Rate limited — wait 5s and retry once
                try await Task.sleep(for: .seconds(5))
                let (retryData, retryResponse) = try await URLSession.shared.data(for: request)
                guard let retryHttp = retryResponse as? HTTPURLResponse,
                      retryHttp.statusCode == 200 else { return nil }
                let retryResult = try JSONDecoder().decode(PWGraphQLResponse.self, from: retryData)
                return retryResult.data?.substances?.first
            }

            guard http.statusCode == 200 else { return nil }
            let result = try JSONDecoder().decode(PWGraphQLResponse.self, from: data)
            return result.data?.substances?.first
        } catch {
            logger.error("fetchSingle(\(name)) failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Conversion

    /// Convert a PW substance to our unified Substance model.
    private static func toSubstance(_ pw: PWSubstance) -> Substance {
        let category = mapCategory(pw.classes?.psychoactive?.first)
        let routes = (pw.roas ?? []).compactMap { buildRoute($0) }
        let defaultRoute = routes.first?.route ?? .oral

        // Effects: both flat list and structured subjective effects
        let effectNames = (pw.effects ?? []).compactMap(\.name).filter { !$0.isEmpty }
        let subjectiveEffects = effectNames.map {
            SubjectiveEffect(name: $0, description: "")
        }

        let toleranceInfo = buildToleranceInfo(from: pw)

        return Substance(
            name: pw.name,
            aliases: [],
            category: category,
            defaultRoute: defaultRoute,
            routes: routes,
            effects: effectNames,
            subjectiveEffects: subjectiveEffects,
            toleranceInfo: toleranceInfo,
            halfLifeMinutes: nil, // Enriched later from HalfLifeDatabase
            sources: ["PsychonautWiki"]
        )
    }

    /// Build a SubstanceRoute from a PW ROA entry.
    private static func buildRoute(_ roa: PWROA) -> SubstanceRoute? {
        guard let routeName = roa.name else { return nil }
        let route = RouteOfAdministration.from(string: routeName)
        let unit = roa.dose?.units ?? "mg"

        let doses = DoseRange(
            threshold: roa.dose?.threshold,
            light: roa.dose?.light?.closedRange,
            common: roa.dose?.common?.closedRange,
            strong: roa.dose?.strong?.closedRange,
            heavy: roa.dose?.heavy
        )

        let duration = buildDurationProfile(from: roa.duration)

        return SubstanceRoute(route: route, unit: unit, doses: doses, duration: duration)
    }

    /// Convert PW duration fields to a DurationProfile, normalizing time units to minutes.
    private static func buildDurationProfile(from dur: PWDuration?) -> DurationProfile? {
        guard let dur else { return nil }

        // At least one phase should have data
        guard dur.onset != nil || dur.comeup != nil || dur.peak != nil
            || dur.offset != nil || dur.total != nil else { return nil }

        return DurationProfile(
            onset: normalizeDurationRange(dur.onset),
            comeup: normalizeDurationRange(dur.comeup),
            peak: normalizeDurationRange(dur.peak),
            offset: normalizeDurationRange(dur.offset),
            afterglow: normalizeDurationRange(dur.afterglow),
            total: normalizeDurationRange(dur.total)
        )
    }

    /// Normalize a PW time range to minutes.
    private static func normalizeDurationRange(_ tr: PWTimeRange?) -> DurationRange? {
        guard let tr, let min = tr.min, let max = tr.max, min > 0, max > 0 else { return nil }
        let multiplier = timeMultiplier(for: tr.units)
        return DurationRange(min: min * multiplier, max: max * multiplier)
    }

    /// Multiplier to convert PW time units to minutes.
    private static func timeMultiplier(for units: String?) -> Double {
        switch units?.lowercased() {
        case "hours": return 60
        case "seconds": return 1.0 / 60.0
        default: return 1 // minutes
        }
    }

    /// Build ToleranceInfo from PW tolerance data.
    private static func buildToleranceInfo(from pw: PWSubstance) -> ToleranceInfo? {
        guard let tol = pw.tolerance else { return nil }
        let halfDays = parseDays(tol.half)
        let fullDays = parseDays(tol.full) ?? parseDays(tol.zero)
        guard halfDays != nil || fullDays != nil else { return nil }

        let buildRate: String
        if let addiction = pw.addictionPotential?.lowercased() {
            if addiction.contains("high") || addiction.contains("extreme") {
                buildRate = "rapid"
            } else if addiction.contains("moderate") || addiction.contains("medium") {
                buildRate = "moderate"
            } else {
                buildRate = "slow"
            }
        } else {
            buildRate = "moderate"
        }

        return ToleranceInfo(
            halfLife: halfDays ?? (fullDays.map { $0 / 2 } ?? 7),
            fullResetDays: fullDays ?? (halfDays.map { $0 * 3 } ?? 14),
            buildRate: buildRate
        )
    }

    /// Parse a PW tolerance string like "3 - 7 days" into a midpoint in days.
    private static func parseDays(_ str: String?) -> Double? {
        guard let str else { return nil }
        let nums = str.replacingOccurrences(of: "[^0-9.]", with: " ", options: .regularExpression)
            .split(separator: " ").compactMap { Double($0) }
        guard !nums.isEmpty else { return nil }
        let value = nums.count > 1 ? (nums[0] + nums[1]) / 2 : nums[0]

        let lower = str.lowercased()
        if lower.contains("month") { return value * 30 }
        if lower.contains("week") { return value * 7 }
        if lower.contains("hour") { return value / 24 }
        return value // default: days
    }

    /// Map PW psychoactive class string to our SubstanceCategory.
    private static func mapCategory(_ pwClass: String?) -> SubstanceCategory {
        guard let cls = pwClass?.lowercased() else { return .other }
        switch cls {
        case "psychedelics": return .psychedelic
        case "dissociatives": return .dissociative
        case "stimulants": return .stimulant
        case "opioids": return .opioid
        case "depressants", "sedatives": return .depressant
        case "entactogens": return .empathogen
        case "cannabinoids": return .cannabinoid
        case "nootropics": return .nootropic
        case "antipsychotics": return .antipsychotic
        case "deliriants": return .antihistamine
        case "benzodiazepines": return .benzodiazepine
        case "gabapentinoids": return .gabapentinoid
        default: return .other
        }
    }
}

// MARK: - Rate Limiter

/// Token-bucket rate limiter — enforces minimum interval between API requests.
private actor PWRateLimiter {
    private let interval: Duration = .seconds(2)
    private var lastRequest: ContinuousClock.Instant?

    func wait() async {
        if let last = lastRequest {
            let elapsed = ContinuousClock.now - last
            if elapsed < interval {
                try? await Task.sleep(for: interval - elapsed)
            }
        }
        lastRequest = .now
    }
}

// MARK: - PsychonautWiki GraphQL Models

private struct PWGraphQLResponse: Codable {
    let data: PWData?
}

private struct PWData: Codable {
    let substances: [PWSubstance]?
}

private struct PWSubstance: Codable {
    let name: String
    let roas: [PWROA]?
    let effects: [PWEffect]?
    let classes: PWClasses?
    let tolerance: PWTolerance?
    let addictionPotential: String?
}

private struct PWROA: Codable {
    let name: String?
    let dose: PWDose?
    let duration: PWDuration?
}

private struct PWDose: Codable {
    let units: String?
    let threshold: Double?
    let light: PWRange?
    let common: PWRange?
    let strong: PWRange?
    let heavy: Double?
}

private struct PWRange: Codable {
    let min: Double?
    let max: Double?

    var closedRange: ClosedRange<Double>? {
        guard let min, let max, min <= max else { return nil }
        return min...max
    }
}

private struct PWDuration: Codable {
    let onset: PWTimeRange?
    let comeup: PWTimeRange?
    let peak: PWTimeRange?
    let offset: PWTimeRange?
    let afterglow: PWTimeRange?
    let total: PWTimeRange?
}

private struct PWTimeRange: Codable {
    let min: Double?
    let max: Double?
    let units: String?
}

private struct PWEffect: Codable {
    let name: String?
    let url: String?
}

private struct PWClasses: Codable {
    let psychoactive: [String]?
}

private struct PWTolerance: Codable {
    let full: String?
    let half: String?
    let zero: String?
}

// MARK: - Array Chunking

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
