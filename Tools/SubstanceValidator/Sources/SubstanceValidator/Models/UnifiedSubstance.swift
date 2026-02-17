import Foundation

// MARK: - Unified Intermediate Representation

/// A normalized substance representation that both TripSit and PsychonautWiki
/// data can be mapped into for comparison against the local library.
struct UnifiedSubstance {
    let name: String
    let normalizedName: String
    let aliases: [String]
    let normalizedAliases: [String]
    let categories: [String]
    let routes: [UnifiedRoute]
    let effects: [String]
    let summary: String?
    let source: DataSource

    enum DataSource: String {
        case tripSit = "TripSit"
        case psychonautWiki = "PsychonautWiki"
        case merged = "Merged"
    }
}

struct UnifiedRoute {
    let routeName: String
    let unit: String
    let threshold: Double?
    let light: ClosedRange<Double>?
    let common: ClosedRange<Double>?
    let strong: ClosedRange<Double>?
    let heavy: Double?
}

// MARK: - Parsed Local Substance (from Swift source files)

struct ParsedLocalSubstance {
    let name: String
    let aliases: [String]
    let category: String
    let defaultRoute: String
    let routes: [ParsedLocalRoute]
    let effects: [String]
    let sourceFile: String
    let lineNumber: Int
}

struct ParsedLocalRoute {
    let route: String
    let unit: String
    let threshold: Double?
    let light: ClosedRange<Double>?
    let common: ClosedRange<Double>?
    let strong: ClosedRange<Double>?
    let heavy: Double?
    let fatal: Double?
}

// MARK: - Conversion from API models

extension UnifiedSubstance {
    static func from(tripSit drug: TripSitDrug, name: String) -> UnifiedSubstance {
        let normalizer = NameNormalizer()
        var routes: [UnifiedRoute] = []

        if let formattedDose = drug.formattedDose {
            for (routeName, levels) in formattedDose {
                let mappedRoute = RouteMapper.mapRoute(routeName)
                var threshold: Double?
                var light: ClosedRange<Double>?
                var common: ClosedRange<Double>?
                var strong: ClosedRange<Double>?
                var heavy: Double?
                var unit = "mg"

                for (level, doseString) in levels {
                    guard let parsed = TripSitDoseParser.parse(doseString) else { continue }
                    unit = parsed.unit

                    switch level.lowercased() {
                    case "threshold":
                        threshold = parsed.min
                    case "light":
                        if let range = parsed.range {
                            light = range
                        } else {
                            light = parsed.min...parsed.min
                        }
                    case "common":
                        if let range = parsed.range {
                            common = range
                        } else {
                            common = parsed.min...parsed.min
                        }
                    case "strong":
                        if let range = parsed.range {
                            strong = range
                        } else {
                            // "1.5ml+" style means this is a minimum for strong/heavy
                            heavy = parsed.min
                        }
                    case "heavy":
                        heavy = parsed.min
                    default:
                        break
                    }
                }

                routes.append(UnifiedRoute(
                    routeName: mappedRoute,
                    unit: unit,
                    threshold: threshold,
                    light: light,
                    common: common,
                    strong: strong,
                    heavy: heavy
                ))
            }
        }

        // TripSit pweffects keys are URLs like "https://psychonautwiki.org/wiki/Euphoria"
        // Extract the effect name from the URL path, or use the key as-is if not a URL.
        // Also check formatted_effects if available.
        var effects: [String] = []
        if let pweffects = drug.pweffects {
            for key in pweffects.keys {
                let effectName: String
                if key.contains("/wiki/") {
                    // Extract from URL: ".../wiki/Euphoria" → "Euphoria"
                    effectName = key.components(separatedBy: "/wiki/").last?
                        .replacingOccurrences(of: "_", with: " ")
                        .removingPercentEncoding ?? String(key)
                } else {
                    effectName = String(key)
                }
                if !effectName.isEmpty {
                    effects.append(effectName)
                }
            }
        }
        let prettyName = ChemicalNameFormatter.format(name)

        return UnifiedSubstance(
            name: prettyName,
            normalizedName: normalizer.normalize(name),
            aliases: drug.aliases ?? [],
            normalizedAliases: (drug.aliases ?? []).map { normalizer.normalize($0) },
            categories: drug.categories ?? [],
            routes: routes,
            effects: effects,
            summary: drug.properties?.summary,
            source: .tripSit
        )
    }

    static func from(psychonautWiki sub: PWSubstance) -> UnifiedSubstance {
        let normalizer = NameNormalizer()
        var routes: [UnifiedRoute] = []

        if let roas = sub.roas {
            for roa in roas {
                guard let roaName = roa.name else { continue }
                let mappedRoute = RouteMapper.mapRoute(roaName)
                let dose = roa.dose
                let unit = TripSitDoseParser.normalizeUnit(dose?.units ?? "mg")

                routes.append(UnifiedRoute(
                    routeName: mappedRoute,
                    unit: unit,
                    threshold: dose?.threshold,
                    light: dose?.light?.closedRange,
                    common: dose?.common?.closedRange,
                    strong: dose?.strong?.closedRange,
                    heavy: dose?.heavy
                ))
            }
        }

        let effects = (sub.effects ?? []).compactMap { $0.name }

        return UnifiedSubstance(
            name: sub.name,
            normalizedName: normalizer.normalize(sub.name),
            aliases: [],
            normalizedAliases: [],
            categories: (sub.classes?.psychoactive ?? []) + (sub.classes?.chemical ?? []),
            routes: routes,
            effects: effects,
            summary: sub.summary,
            source: .psychonautWiki
        )
    }

    /// Merge TripSit and PsychonautWiki data for the same substance.
    /// PW dose data is preferred when available; TripSit fills gaps at the route
    /// and individual dose-level granularity.
    static func merge(_ ts: UnifiedSubstance, _ pw: UnifiedSubstance) -> UnifiedSubstance {
        var mergedRoutes: [UnifiedRoute] = []
        let tsRoutesByName = Dictionary(grouping: ts.routes, by: \.routeName)
            .mapValues { $0.first! }

        // For each PW route, fill in any missing dose levels from TripSit
        for pwRoute in pw.routes {
            if let tsRoute = tsRoutesByName[pwRoute.routeName] {
                mergedRoutes.append(UnifiedRoute(
                    routeName: pwRoute.routeName,
                    unit: pwRoute.unit,
                    threshold: pwRoute.threshold ?? tsRoute.threshold,
                    light: pwRoute.light ?? tsRoute.light,
                    common: pwRoute.common ?? tsRoute.common,
                    strong: pwRoute.strong ?? tsRoute.strong,
                    heavy: pwRoute.heavy ?? tsRoute.heavy
                ))
            } else {
                mergedRoutes.append(pwRoute)
            }
        }

        // Add TripSit-only routes not present in PW
        let pwRouteNames = Set(pw.routes.map { $0.routeName })
        for tsRoute in ts.routes where !pwRouteNames.contains(tsRoute.routeName) {
            mergedRoutes.append(tsRoute)
        }

        // Union effects from both sources, deduplicate case-insensitively
        var seenEffects = Set<String>()
        var allEffects: [String] = []
        for effect in pw.effects + ts.effects {
            let key = effect.lowercased()
            if !seenEffects.contains(key) {
                seenEffects.insert(key)
                allEffects.append(effect)
            }
        }
        allEffects.sort()

        // Union aliases from both sources
        var seenAliases = Set<String>()
        var allAliases: [String] = []
        var allNormalizedAliases: [String] = []
        for (alias, normalized) in zip(ts.aliases + pw.aliases, ts.normalizedAliases + pw.normalizedAliases) {
            if !seenAliases.contains(normalized) {
                seenAliases.insert(normalized)
                allAliases.append(alias)
                allNormalizedAliases.append(normalized)
            }
        }

        // Prefer PW name (usually more formal)
        return UnifiedSubstance(
            name: pw.name,
            normalizedName: pw.normalizedName,
            aliases: allAliases,
            normalizedAliases: allNormalizedAliases,
            categories: pw.categories.isEmpty ? ts.categories : pw.categories,
            routes: mergedRoutes,
            effects: allEffects,
            summary: pw.summary ?? ts.summary,
            source: .merged
        )
    }
}
