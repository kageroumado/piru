import Foundation

/// Compares dose ranges between local data and API data, producing discrepancy reports.
enum DoseComparator {
    /// Convert a dose value between compatible units. Returns nil if units are incomparable.
    static func convertToCommonUnit(value: Double, from fromUnit: String, to toUnit: String) -> Double? {
        let from = TripSitDoseParser.normalizeUnit(fromUnit)
        let to = TripSitDoseParser.normalizeUnit(toUnit)

        if from == to { return value }

        // Weight conversions
        let toMg: [String: Double] = [
            "µg": 0.001,
            "mg": 1.0,
            "g": 1000.0,
        ]

        guard let fromFactor = toMg[from], let toFactor = toMg[to] else {
            return nil // Incomparable units (IU, ml, etc.)
        }

        return value * fromFactor / toFactor
    }

    /// Compare dose ranges for a matched route between local and API data.
    static func compare(
        localRoute: ParsedLocalRoute,
        apiRoute: UnifiedRoute,
        substanceName: String
    ) -> [SubstanceDiscrepancy] {
        var discrepancies: [SubstanceDiscrepancy] = []
        let routeName = apiRoute.routeName

        // Check unit compatibility
        let localUnit = TripSitDoseParser.normalizeUnit(localRoute.unit)
        let apiUnit = TripSitDoseParser.normalizeUnit(apiRoute.unit)

        if localUnit != apiUnit {
            // Try conversion
            if convertToCommonUnit(value: 1, from: localUnit, to: apiUnit) == nil {
                discrepancies.append(SubstanceDiscrepancy(
                    substanceName: substanceName,
                    kind: .unitMismatch(route: routeName, localUnit: localUnit, apiUnit: apiUnit),
                    severity: .warning,
                    recommendation: "Units differ and cannot be automatically compared. Manual review needed."
                ))
                return discrepancies
            }
        }

        // Compare threshold
        if let localThreshold = localRoute.threshold, let apiThreshold = apiRoute.threshold {
            let apiConverted = convertToCommonUnit(value: apiThreshold, from: apiUnit, to: localUnit) ?? apiThreshold
            let diff = percentDifference(localThreshold, apiConverted)
            if diff > 10 {
                discrepancies.append(SubstanceDiscrepancy(
                    substanceName: substanceName,
                    kind: .doseMismatch(route: routeName, level: "threshold",
                                        localValue: formatDose(localThreshold, localUnit),
                                        apiValue: formatDose(apiConverted, localUnit),
                                        percentDiff: diff),
                    severity: severityFor(diff, substanceName: substanceName, localValue: localThreshold, apiValue: apiConverted),
                    recommendation: recommendationFor(diff, level: "threshold", substanceName: substanceName, localValue: localThreshold, apiValue: apiConverted)
                ))
            }
        } else if localRoute.threshold == nil && apiRoute.threshold != nil {
            discrepancies.append(SubstanceDiscrepancy(
                substanceName: substanceName,
                kind: .missingDoseLevel(route: routeName, level: "threshold", presentIn: "API"),
                severity: .info,
                recommendation: "Consider adding threshold dose from API data."
            ))
        }

        // Compare ranges (light, common, strong)
        compareRange(local: localRoute.light, api: apiRoute.light, level: "light",
                      localUnit: localUnit, apiUnit: apiUnit, routeName: routeName,
                      substanceName: substanceName, discrepancies: &discrepancies)
        compareRange(local: localRoute.common, api: apiRoute.common, level: "common",
                      localUnit: localUnit, apiUnit: apiUnit, routeName: routeName,
                      substanceName: substanceName, discrepancies: &discrepancies)
        compareRange(local: localRoute.strong, api: apiRoute.strong, level: "strong",
                      localUnit: localUnit, apiUnit: apiUnit, routeName: routeName,
                      substanceName: substanceName, discrepancies: &discrepancies)

        // Compare heavy
        if let localHeavy = localRoute.heavy, let apiHeavy = apiRoute.heavy {
            let apiConverted = convertToCommonUnit(value: apiHeavy, from: apiUnit, to: localUnit) ?? apiHeavy
            let diff = percentDifference(localHeavy, apiConverted)
            if diff > 10 {
                discrepancies.append(SubstanceDiscrepancy(
                    substanceName: substanceName,
                    kind: .doseMismatch(route: routeName, level: "heavy",
                                        localValue: formatDose(localHeavy, localUnit),
                                        apiValue: formatDose(apiConverted, localUnit),
                                        percentDiff: diff),
                    severity: severityFor(diff, substanceName: substanceName, localValue: localHeavy, apiValue: apiConverted),
                    recommendation: recommendationFor(diff, level: "heavy", substanceName: substanceName, localValue: localHeavy, apiValue: apiConverted)
                ))
            }
        }

        return discrepancies
    }

    private static func compareRange(
        local: ClosedRange<Double>?, api: ClosedRange<Double>?,
        level: String, localUnit: String, apiUnit: String,
        routeName: String, substanceName: String,
        discrepancies: inout [SubstanceDiscrepancy]
    ) {
        if let local, let api {
            let apiLower = convertToCommonUnit(value: api.lowerBound, from: apiUnit, to: localUnit) ?? api.lowerBound
            let apiUpper = convertToCommonUnit(value: api.upperBound, from: apiUnit, to: localUnit) ?? api.upperBound

            let lowerDiff = percentDifference(local.lowerBound, apiLower)
            let upperDiff = percentDifference(local.upperBound, apiUpper)
            let maxDiff = max(lowerDiff, upperDiff)

            if maxDiff > 10 {
                // Use midpoints for context check
                let localMid = (local.lowerBound + local.upperBound) / 2
                let apiMid = (apiLower + apiUpper) / 2
                discrepancies.append(SubstanceDiscrepancy(
                    substanceName: substanceName,
                    kind: .doseMismatch(route: routeName, level: level,
                                        localValue: formatRange(local, localUnit),
                                        apiValue: formatRange(apiLower...apiUpper, localUnit),
                                        percentDiff: maxDiff),
                    severity: severityFor(maxDiff, substanceName: substanceName, localValue: localMid, apiValue: apiMid),
                    recommendation: recommendationFor(maxDiff, level: level, substanceName: substanceName, localValue: localMid, apiValue: apiMid)
                ))
            }
        } else if local == nil && api != nil {
            discrepancies.append(SubstanceDiscrepancy(
                substanceName: substanceName,
                kind: .missingDoseLevel(route: routeName, level: level, presentIn: "API"),
                severity: .info,
                recommendation: "Consider adding \(level) dose range from API data."
            ))
        }
    }

    static func percentDifference(_ a: Double, _ b: Double) -> Double {
        let maxVal = max(abs(a), abs(b))
        guard maxVal > 0 else { return 0 }
        return abs(a - b) / maxVal * 100
    }

    /// Determine severity, with context-aware downgrading for substances
    /// that have known therapeutic vs recreational dosing differences.
    static func severityFor(_ percentDiff: Double, substanceName: String? = nil, localValue: Double? = nil, apiValue: Double? = nil) -> ValidationSeverity {
        // Check if this is a contextual discrepancy that should be downgraded
        if let name = substanceName, let local = localValue, let api = apiValue {
            let (isContextual, _) = DosingContext.isContextualDiscrepancy(
                substanceName: name, localValue: local, apiValue: api
            )
            if isContextual {
                // Downgrade: critical → warning, warning → info
                if percentDiff > 50 { return .warning }
                return .info
            }
        }

        if percentDiff > 50 { return .critical }
        if percentDiff > 20 { return .warning }
        return .info
    }

    static func recommendationFor(_ percentDiff: Double, level: String, substanceName: String? = nil, localValue: Double? = nil, apiValue: Double? = nil) -> String {
        // Check for contextual discrepancy
        if let name = substanceName, let local = localValue, let api = apiValue {
            let (isContextual, note) = DosingContext.isContextualDiscrepancy(
                substanceName: name, localValue: local, apiValue: api
            )
            if isContextual {
                let ctx = note ?? "Different dosing contexts"
                return "CONTEXT: \(level) dose differs by ~\(Int(percentDiff))% — likely due to therapeutic vs recreational context. \(ctx)"
            }
        }

        if percentDiff > 50 {
            return "CRITICAL: \(level) dose differs by >\(Int(percentDiff))%. Review immediately — use most conservative value for safety."
        } else if percentDiff > 20 {
            return "\(level) dose differs by ~\(Int(percentDiff))%. Consider updating to match API consensus."
        } else {
            return "Minor \(level) dose difference (~\(Int(percentDiff))%). Likely acceptable."
        }
    }

    static func formatDose(_ value: Double, _ unit: String) -> String {
        if value == value.rounded() {
            return "\(Int(value)) \(unit)"
        }
        return "\(value) \(unit)"
    }

    static func formatRange(_ range: ClosedRange<Double>, _ unit: String) -> String {
        "\(formatDose(range.lowerBound, ""))...\(formatDose(range.upperBound, unit))"
    }
}
