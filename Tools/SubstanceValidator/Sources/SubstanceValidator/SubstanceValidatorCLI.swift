import ArgumentParser
import Foundation

@main
struct SubstanceValidator: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "SubstanceValidator",
        abstract: "Validate and enrich Piru's substance library against TripSit and PsychonautWiki APIs.",
        subcommands: [Validate.self, Generate.self]
    )
}

// MARK: - Validate Subcommand

struct Validate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Fetch API data, compare against local library, and output a validation report."
    )

    @Option(name: .long, help: "Path to the Piru Data/ directory containing Swift substance files.")
    var dataDir: String = "../../Piru/Data"

    @Option(name: .long, help: "Directory to write the report to.")
    var outputDir: String = "."

    @Option(name: .long, help: "Report format: text or json.")
    var reportFormat: String = "text"

    @Flag(name: .long, help: "Skip PsychonautWiki queries (TripSit only).")
    var skipPw: Bool = false

    @Flag(name: .long, help: "Verbose output.")
    var verbose: Bool = false

    func run() async throws {
        print("Piru Substance Validator")
        print("========================\n")

        // Step 1: Parse local data
        print("[1/4] Parsing local substance files...")
        let localSubstances = try SubstanceParser.parseDirectory(at: dataDir, verbose: verbose)
        print("  Found \(localSubstances.count) local substances\n")

        // Step 2: Fetch TripSit data
        print("[2/4] Fetching TripSit drug database...")
        let tripSitClient = TripSitClient()
        let tripSitDrugs: TripSitDrugDatabase
        do {
            tripSitDrugs = try await tripSitClient.fetchAllDrugs(verbose: verbose)
            print("  Loaded \(tripSitDrugs.count) TripSit drugs\n")
        } catch {
            print("  ERROR: Failed to fetch TripSit data: \(error.localizedDescription)")
            print("  Continuing with PsychonautWiki only...\n")
            tripSitDrugs = [:]
        }

        // Step 3: Convert TripSit to unified format
        print("[3/4] Processing API data...")
        let normalizer = NameNormalizer()

        var apiSubstances: [String: UnifiedSubstance] = [:]
        for (name, drug) in tripSitDrugs {
            let unified = UnifiedSubstance.from(tripSit: drug, name: name)
            apiSubstances[unified.normalizedName] = unified
        }
        if verbose { print("  Converted \(apiSubstances.count) TripSit substances to unified format") }

        // Step 4: Fetch PsychonautWiki data (optional)
        var pwCount = 0
        if !skipPw {
            print("  Fetching PsychonautWiki data (this may take a while)...")
            let pwClient = PsychonautWikiClient()

            // Query for all local substance names + all TripSit names
            var namesToQuery = Set(localSubstances.map(\.name))
            for (name, _) in tripSitDrugs {
                namesToQuery.insert(name)
            }

            let pwResults = try await pwClient.fetchSubstances(names: Array(namesToQuery), verbose: verbose)
            pwCount = pwResults.count

            // Merge PW data with TripSit data
            for (normalizedName, pwSubstance) in pwResults {
                let pwUnified = UnifiedSubstance.from(psychonautWiki: pwSubstance)
                if let existing = apiSubstances[normalizedName] {
                    apiSubstances[normalizedName] = UnifiedSubstance.merge(existing, pwUnified)
                } else {
                    apiSubstances[pwUnified.normalizedName] = pwUnified
                }
            }
        }
        print("  Total unified API substances: \(apiSubstances.count)\n")

        // Step 5: Match and compare
        print("[4/4] Matching and comparing...")
        let matchIndex = normalizer.buildIndex(from: localSubstances)
        var matches: [MatchResult] = []
        var newSubstances: [UnifiedSubstance] = []
        var matchedLocalNames = Set<String>()
        var fuzzyMatches: [MatchResult] = []
        var allDiscrepancies: [SubstanceDiscrepancy] = []

        for (_, apiSubstance) in apiSubstances {
            if let (localMatch, matchType) = normalizer.findMatch(for: apiSubstance, in: matchIndex) {
                matchedLocalNames.insert(normalizer.normalize(localMatch.name))

                // Compare doses for each matched route
                var discrepancies: [SubstanceDiscrepancy] = []

                for apiRoute in apiSubstance.routes {
                    // Find corresponding local route
                    if let localRoute = localMatch.routes.first(where: { $0.route == apiRoute.routeName }) {
                        let routeDiscrepancies = DoseComparator.compare(
                            localRoute: localRoute,
                            apiRoute: apiRoute,
                            substanceName: localMatch.name
                        )
                        discrepancies.append(contentsOf: routeDiscrepancies)
                    } else {
                        discrepancies.append(SubstanceDiscrepancy(
                            substanceName: localMatch.name,
                            kind: .missingRoute(route: apiRoute.routeName, presentIn: "API"),
                            severity: .info,
                            recommendation: "Route '\(apiRoute.routeName)' found in API but not in local data."
                        ))
                    }
                }

                // Check for alias differences
                let localAliasSet = Set(localMatch.aliases.map { normalizer.normalize($0) })
                let apiAliasSet = Set(apiSubstance.normalizedAliases)
                let localOnly = localMatch.aliases.filter { !apiAliasSet.contains(normalizer.normalize($0)) }
                let apiOnly = apiSubstance.aliases.filter { !localAliasSet.contains(normalizer.normalize($0)) }
                if !apiOnly.isEmpty {
                    discrepancies.append(SubstanceDiscrepancy(
                        substanceName: localMatch.name,
                        kind: .aliasDifference(localOnly: localOnly, apiOnly: apiOnly),
                        severity: .info,
                        recommendation: "Consider adding aliases: \(apiOnly.joined(separator: ", "))"
                    ))
                }

                let result = MatchResult(
                    localSubstance: localMatch,
                    apiSubstance: apiSubstance,
                    matchType: matchType,
                    discrepancies: discrepancies
                )
                matches.append(result)
                allDiscrepancies.append(contentsOf: discrepancies)

                if matchType == .fuzzy {
                    fuzzyMatches.append(result)
                }
            } else {
                // New substance not in local library
                if !apiSubstance.routes.isEmpty { // Only include substances with dose data
                    newSubstances.append(apiSubstance)
                }
            }
        }

        // Find local-only substances
        let localOnly = localSubstances.filter { !matchedLocalNames.contains(normalizer.normalize($0.name)) }

        // Build report
        let report = ValidationReport(
            timestamp: Date(),
            totalLocalSubstances: localSubstances.count,
            totalTripSitSubstances: tripSitDrugs.count,
            totalPWSubstances: pwCount,
            matchedCount: matches.count,
            matches: matches,
            discrepancies: allDiscrepancies.sorted { $0.severity < $1.severity },
            newSubstancesFromAPI: newSubstances,
            localOnlySubstances: localOnly,
            fuzzyMatchesForReview: fuzzyMatches
        )

        // Generate report
        let reportContent: String
        let fileExtension: String
        if reportFormat == "json" {
            reportContent = ReportGenerator.generateJSONReport(report)
            fileExtension = "json"
        } else {
            reportContent = ReportGenerator.generateTextReport(report)
            fileExtension = "txt"
        }

        // Print summary to stdout
        print(ReportGenerator.generateTextReport(report).components(separatedBy: "\n").prefix(25).joined(separator: "\n"))

        // Write full report to file
        let outputURL = URL(fileURLWithPath: outputDir)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        let reportFile = outputURL.appendingPathComponent("validation-report.\(fileExtension)")
        try reportContent.write(to: reportFile, atomically: true, encoding: .utf8)
        print("\n  Full report written to: \(reportFile.path)")
    }
}

// MARK: - Generate Subcommand

struct Generate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate Swift data files for new substances discovered from APIs."
    )

    @Option(name: .long, help: "Path to the Piru Data/ directory.")
    var dataDir: String = "../../Piru/Data"

    @Option(name: .long, help: "Directory to write generated Swift files.")
    var outputDir: String = "../../Piru/Data"

    @Flag(name: .long, help: "Skip PsychonautWiki queries.")
    var skipPw: Bool = false

    @Flag(name: .long, help: "Preview what would be generated without writing files.")
    var dryRun: Bool = false

    @Flag(name: .long, help: "Verbose output.")
    var verbose: Bool = false

    func run() async throws {
        print("Piru Substance Generator")
        print("========================\n")

        // Parse local data
        print("[1/3] Parsing local substance files...")
        let localSubstances = try SubstanceParser.parseDirectory(at: dataDir, verbose: verbose)
        print("  Found \(localSubstances.count) local substances\n")

        // Fetch API data
        print("[2/3] Fetching API data...")
        let tripSitClient = TripSitClient()
        let tripSitDrugs = try await tripSitClient.fetchAllDrugs(verbose: verbose)
        print("  Loaded \(tripSitDrugs.count) TripSit drugs")

        let normalizer = NameNormalizer()
        var apiSubstances: [String: UnifiedSubstance] = [:]

        for (name, drug) in tripSitDrugs {
            let unified = UnifiedSubstance.from(tripSit: drug, name: name)
            apiSubstances[unified.normalizedName] = unified
        }

        if !skipPw {
            print("  Fetching PsychonautWiki data...")
            let pwClient = PsychonautWikiClient()
            let namesToQuery = Set(tripSitDrugs.keys)
            let pwResults = try await pwClient.fetchSubstances(names: Array(namesToQuery), verbose: verbose)

            for (normalizedName, pwSubstance) in pwResults {
                let pwUnified = UnifiedSubstance.from(psychonautWiki: pwSubstance)
                if let existing = apiSubstances[normalizedName] {
                    apiSubstances[normalizedName] = UnifiedSubstance.merge(existing, pwUnified)
                } else {
                    apiSubstances[pwUnified.normalizedName] = pwUnified
                }
            }
        }

        // Find new substances
        print("\n[3/3] Identifying new substances...")
        let matchIndex = normalizer.buildIndex(from: localSubstances)
        var newSubstances: [UnifiedSubstance] = []

        for (_, apiSubstance) in apiSubstances {
            if normalizer.findMatch(for: apiSubstance, in: matchIndex) == nil {
                if !apiSubstance.routes.isEmpty {
                    newSubstances.append(apiSubstance)
                }
            }
        }

        print("  Found \(newSubstances.count) new substances with dose data\n")

        if newSubstances.isEmpty {
            print("No new substances to generate.")
            return
        }

        // Generate files
        let files = SwiftCodeGenerator.generateFiles(for: newSubstances)

        if dryRun {
            print("DRY RUN — would generate \(files.count) files:")
            for (filename, content) in files {
                let substanceCount = content.components(separatedBy: "// MARK: -").count - 1
                print("  \(filename) (\(substanceCount) substances)")
            }
        } else {
            let outputURL = URL(fileURLWithPath: outputDir)
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

            for (filename, content) in files {
                let fileURL = outputURL.appendingPathComponent(filename)
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                let substanceCount = content.components(separatedBy: "// MARK: -").count - 1
                print("  Generated: \(filename) (\(substanceCount) substances)")
            }

            print("\nDone! Don't forget to add the new arrays to SubstanceLibrary.swift:")
            print("  In SubstanceLibrary.all, add:")
            for (filename, _) in files {
                let property = filename.replacingOccurrences(of: ".swift", with: "")
                let camelCase = "apiDiscovered" + property.replacingOccurrences(of: "APIDiscovered", with: "")
                print("    + \(camelCase)")
            }
        }
    }
}
