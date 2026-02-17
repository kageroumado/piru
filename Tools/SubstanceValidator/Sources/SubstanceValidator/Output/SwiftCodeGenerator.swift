import Foundation

/// Generates Swift source files matching the existing Piru data file format.
enum SwiftCodeGenerator {
    /// Generate a complete Swift data file for a category of substances.
    static func generateFile(
        substances: [UnifiedSubstance],
        propertyName: String
    ) -> String {
        var out = "import Foundation\n\n"
        out += "extension SubstanceLibrary {\n"
        out += "    static let \(propertyName): [Substance] = [\n"

        for substance in substances {
            out += "\n"
            out += "        // MARK: - \(substance.name)\n"
            out += "\n"
            out += "        Substance(\n"
            out += "            name: \"\(escapeString(substance.name))\",\n"
            out += "            aliases: [\(substance.aliases.map { "\"\(escapeString($0))\"" }.joined(separator: ", "))],\n"

            let category = CategoryMapper.mapCategories(substance.categories)
            out += "            category: .\(category),\n"

            let defaultRoute = substance.routes.first?.routeName ?? "oral"
            out += "            defaultRoute: .\(defaultRoute),\n"

            out += "            routes: [\n"
            for route in substance.routes {
                out += "                SubstanceRoute(route: .\(route.routeName), unit: \"\(route.unit)\", doses: DoseRange(\n"
                out += "                    threshold: \(formatOptionalDouble(route.threshold))"
                out += ", light: \(formatOptionalRange(route.light))"
                out += ", common: \(formatOptionalRange(route.common))"
                out += ", strong: \(formatOptionalRange(route.strong))"
                out += ", heavy: \(formatOptionalDouble(route.heavy))"
                out += "\n                )),\n"
            }
            out += "            ],\n"

            out += "            effects: [\(substance.effects.map { "\"\(escapeString($0))\"" }.joined(separator: ", "))]\n"
            out += "        ),\n"
        }

        out += "    ]\n"
        out += "}\n"

        return out
    }

    /// Generate files grouped by category, returning [(filename, content)].
    static func generateFiles(for substances: [UnifiedSubstance]) -> [(String, String)] {
        // Group by mapped category
        var byCat: [String: [UnifiedSubstance]] = [:]
        for sub in substances {
            let cat = CategoryMapper.mapCategories(sub.categories)
            byCat[cat, default: []].append(sub)
        }

        return byCat.map { (category, subs) in
            let sortedSubs = subs.sorted { $0.name < $1.name }
            let propertyName = "apiDiscovered\(category.prefix(1).uppercased())\(category.dropFirst())"
            let filename = "APIDiscovered\(category.prefix(1).uppercased())\(category.dropFirst()).swift"
            let content = generateFile(substances: sortedSubs, propertyName: propertyName)
            return (filename, content)
        }.sorted { $0.0 < $1.0 }
    }

    // MARK: - Formatting Helpers

    private static func formatOptionalDouble(_ value: Double?) -> String {
        guard let value else { return "nil" }
        if value == value.rounded() && value < 1_000_000 {
            return "\(Int(value))"
        }
        // Use minimal decimal places
        let formatted = String(format: "%g", value)
        return formatted
    }

    private static func formatOptionalRange(_ range: ClosedRange<Double>?) -> String {
        guard let range else { return "nil" }
        return "\(formatOptionalDouble(range.lowerBound))...\(formatOptionalDouble(range.upperBound))"
    }

    private static func escapeString(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
    }
}
