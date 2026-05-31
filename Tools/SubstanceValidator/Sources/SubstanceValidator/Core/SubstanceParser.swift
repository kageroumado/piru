import Foundation

/// Parses existing Swift source files to extract substance definitions using regex.
enum SubstanceParser {
    /// Parse all .swift files in a directory to extract Substance definitions.
    static func parseDirectory(at path: String, verbose: Bool = false) throws -> [ParsedLocalSubstance] {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)

        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil) else {
            throw ParserError.directoryNotFound(path)
        }

        var allSubstances: [ParsedLocalSubstance] = []

        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            let filename = fileURL.lastPathComponent

            // Skip SubstanceLibrary.swift (it's the aggregator, not data)
            if filename == "SubstanceLibrary.swift" { continue }

            if verbose { print("  Parsing \(filename)...") }
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let substances = parseFile(content: content, filename: filename)
            if verbose { print("    Found \(substances.count) substances") }
            allSubstances.append(contentsOf: substances)
        }

        return allSubstances
    }

    /// Parse a single Swift file's contents to extract Substance definitions.
    static func parseFile(content: String, filename: String) -> [ParsedLocalSubstance] {
        var substances: [ParsedLocalSubstance] = []
        let lines = content.components(separatedBy: .newlines)

        var i = 0
        while i < lines.count {
            let line = lines[i]

            // Look for Substance( opening
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("Substance(") {
                let startLine = i + 1 // 1-based
                if let (substance, endIndex) = parseSubstanceBlock(lines: lines, startIndex: i, filename: filename, startLine: startLine) {
                    substances.append(substance)
                    i = endIndex
                    continue
                }
            }
            i += 1
        }

        return substances
    }

    /// Parse a single Substance(...) block from lines starting at startIndex.
    private static func parseSubstanceBlock(lines: [String], startIndex: Int, filename: String, startLine: Int) -> (ParsedLocalSubstance, Int)? {
        // Collect all lines until we find the closing ),
        var blockLines: [String] = []
        var depth = 0
        var endIndex = startIndex

        for i in startIndex ..< lines.count {
            let line = lines[i]
            blockLines.append(line)

            for char in line {
                if char == "(" { depth += 1 }
                if char == ")" { depth -= 1 }
            }

            if depth <= 0 {
                endIndex = i + 1
                break
            }
        }

        let block = blockLines.joined(separator: "\n")

        // Extract name
        guard let name = extractString(from: block, key: "name") else { return nil }

        // Extract aliases
        let aliases = extractStringArray(from: block, key: "aliases")

        // Extract category
        let category = extractEnumCase(from: block, key: "category") ?? "other"

        // Extract defaultRoute
        let defaultRoute = extractEnumCase(from: block, key: "defaultRoute") ?? "oral"

        // Extract effects
        let effects = extractStringArray(from: block, key: "effects")

        // Extract routes
        let routes = parseRoutes(from: block)

        let substance = ParsedLocalSubstance(
            name: name,
            aliases: aliases,
            category: category,
            defaultRoute: defaultRoute,
            routes: routes,
            effects: effects,
            sourceFile: filename,
            lineNumber: startLine,
        )

        return (substance, endIndex)
    }

    // MARK: - Field Extractors

    private static func extractString(from block: String, key: String) -> String? {
        let pattern = key + #":\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)),
              let range = Range(match.range(at: 1), in: block) else {
            return nil
        }
        return String(block[range])
    }

    private static func extractStringArray(from block: String, key: String) -> [String] {
        // Find the array for this key — handle multi-line arrays
        let pattern = key + #":\s*\["#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)),
              let startRange = Range(match.range, in: block) else {
            return []
        }

        // Find the matching ]
        let afterBracket = block[startRange.upperBound...]
        var depth = 1
        var endIdx = afterBracket.startIndex
        for idx in afterBracket.indices {
            if afterBracket[idx] == "[" { depth += 1 }
            if afterBracket[idx] == "]" { depth -= 1 }
            if depth == 0 {
                endIdx = idx
                break
            }
        }

        let arrayContent = String(afterBracket[afterBracket.startIndex ..< endIdx])

        // Extract all quoted strings
        var results: [String] = []
        let stringPattern = #""([^"]+)""#
        if let stringRegex = try? NSRegularExpression(pattern: stringPattern) {
            let matches = stringRegex.matches(in: arrayContent, range: NSRange(arrayContent.startIndex..., in: arrayContent))
            for m in matches {
                if let range = Range(m.range(at: 1), in: arrayContent) {
                    results.append(String(arrayContent[range]))
                }
            }
        }

        return results
    }

    private static func extractEnumCase(from block: String, key: String) -> String? {
        let pattern = key + #":\s*\.(\w+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)),
              let range = Range(match.range(at: 1), in: block) else {
            return nil
        }
        return String(block[range])
    }

    // MARK: - Route Parsing

    private static func parseRoutes(from block: String) -> [ParsedLocalRoute] {
        var routes: [ParsedLocalRoute] = []

        // Find all SubstanceRoute blocks
        let pattern = #"SubstanceRoute\(route:\s*\.(\w+),\s*unit:\s*"([^"]+)",\s*doses:\s*DoseRange\("#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let matches = regex.matches(in: block, range: NSRange(block.startIndex..., in: block))

        for match in matches {
            guard let routeRange = Range(match.range(at: 1), in: block),
                  let unitRange = Range(match.range(at: 2), in: block) else { continue }

            let route = String(block[routeRange])
            let unit = String(block[unitRange])

            // Find the DoseRange parameters after this match
            let afterMatch = block[block.index(block.startIndex, offsetBy: match.range.upperBound)...]
            let doseParams = extractDoseRangeParams(from: String(afterMatch))

            routes.append(ParsedLocalRoute(
                route: route,
                unit: unit,
                threshold: doseParams.threshold,
                light: doseParams.light,
                common: doseParams.common,
                strong: doseParams.strong,
                heavy: doseParams.heavy,
                fatal: doseParams.fatal,
            ))
        }

        return routes
    }

    private static func extractDoseRangeParams(from text: String) -> (threshold: Double?, light: ClosedRange<Double>?, common: ClosedRange<Double>?, strong: ClosedRange<Double>?, heavy: Double?, fatal: Double?) {
        // Find content up to the closing ))
        var depth = 1
        var endIdx = text.startIndex
        for idx in text.indices {
            if text[idx] == "(" { depth += 1 }
            if text[idx] == ")" { depth -= 1 }
            if depth <= 0 {
                endIdx = idx
                break
            }
        }

        let params = String(text[text.startIndex ..< endIdx])

        let threshold = extractDoubleParam(from: params, key: "threshold")
        let light = extractRangeParam(from: params, key: "light")
        let common = extractRangeParam(from: params, key: "common")
        let strong = extractRangeParam(from: params, key: "strong")
        let heavy = extractDoubleParam(from: params, key: "heavy")
        let fatal = extractDoubleParam(from: params, key: "fatal")

        return (threshold, light, common, strong, heavy, fatal)
    }

    private static func extractDoubleParam(from params: String, key: String) -> Double? {
        let pattern = key + #":\s*([\d.]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: params, range: NSRange(params.startIndex..., in: params)),
              let range = Range(match.range(at: 1), in: params) else {
            return nil
        }
        return Double(params[range])
    }

    private static func extractRangeParam(from params: String, key: String) -> ClosedRange<Double>? {
        let pattern = key + #":\s*([\d.]+)\.\.\.([\d.]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: params, range: NSRange(params.startIndex..., in: params)),
              let lowerRange = Range(match.range(at: 1), in: params),
              let upperRange = Range(match.range(at: 2), in: params),
              let lower = Double(params[lowerRange]),
              let upper = Double(params[upperRange]) else {
            return nil
        }
        return lower ... upper
    }

    enum ParserError: Error, LocalizedError {
        case directoryNotFound(String)

        var errorDescription: String? {
            switch self {
            case let .directoryNotFound(path): "Directory not found: \(path)"
            }
        }
    }
}
