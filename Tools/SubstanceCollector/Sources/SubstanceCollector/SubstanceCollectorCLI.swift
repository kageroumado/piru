import ArgumentParser
import Foundation

@main
struct SubstanceCollector: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "SubstanceCollector",
        abstract: "Assemble a comprehensive substance JSON database for the Piru app's bundled resource.",
        subcommands: [Build.self]
    )
}

struct Build: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run the full collector pipeline (TripSit + Wikidata + PubChem + Erowid + DEA + curated overlay) and write the result to substances-bundled.json."
    )

    @Option(name: .long, help: "Output JSON path for the merged dataset (kept for compatibility with the JSON-fed app path until iOS migrates to SQLite).")
    var output: String = "../../Piru/Data/substances-bundled.json"

    @Option(name: .long, help: "Output JSON path for the per-record sourced dataset. Each entry retains its provenance + dedup identifiers so the SQLite builder can attribute every fact to the right source. Pre-merge.")
    var sourcedOutput: String = "../../Piru/Data/sourced-substances.json"

    @Option(name: .long, help: "HTTP cache directory.")
    var cacheDir: String = ".cache"

    @Option(name: .long, help: "Curated overlay JSON.")
    var curatedOverlay: String = "curated-overlay.json"

    @Flag(name: .long, help: "Don't make any network requests; rely solely on the cache.")
    var noNetwork: Bool = false

    @Flag(name: .long, help: "Skip the Erowid scraper (helpful when iterating on other sources).")
    var skipErowid: Bool = false

    @Flag(name: .long, help: "Skip the Wikidata + PubChem pass.")
    var skipWikidata: Bool = false

    @Flag(name: .long, help: "Skip TripSit (only useful for testing other sources in isolation).")
    var skipTripsit: Bool = false

    func run() async throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let outputURL = URL(fileURLWithPath: output, isDirectory: false, relativeTo: cwd).standardizedFileURL
        let sourcedOutputURL = URL(fileURLWithPath: sourcedOutput, isDirectory: false, relativeTo: cwd).standardizedFileURL
        let cacheURL = URL(fileURLWithPath: cacheDir, isDirectory: true, relativeTo: cwd).standardizedFileURL
        let overlayURL = URL(fileURLWithPath: curatedOverlay, isDirectory: false, relativeTo: cwd).standardizedFileURL

        Log.info("SubstanceCollector — build pipeline")
        Log.info("Merged output:    \(outputURL.path)")
        Log.info("Sourced output:   \(sourcedOutputURL.path)")
        Log.info("Cache:            \(cacheURL.path)")
        Log.info("Curated overlay:  \(overlayURL.path)")
        Log.info("Mode:             \(noNetwork ? "OFFLINE (cache only)" : "online")")

        let cache = HTTPCache(cacheDir: cacheURL, offline: noNetwork)

        var allSourced: [SourcedSubstance] = []
        var warnings: [String] = []

        // ── TripSit ────────────────────────────────────────────────────────
        if !skipTripsit {
            Log.step("Step 1/5: TripSit drugs.json")
            do {
                let ts = TripSitSource(cache: cache)
                let entries = try await ts.fetch()
                allSourced.append(contentsOf: entries)
            } catch {
                warnings.append("TripSit fetch failed: \(error.localizedDescription)")
                Log.error("TripSit: \(error.localizedDescription)")
            }
        }

        // ── Wikidata + PubChem ─────────────────────────────────────────────
        if !skipWikidata {
            Log.step("Step 2/5: Wikidata SPARQL")
            let wd = WikidataSource(cache: cache)
            let wdCompounds = await wd.fetchAll()
            if wdCompounds.isEmpty {
                warnings.append("Wikidata returned 0 compounds; SPARQL endpoint may have rejected all queries.")
            }

            Log.step("Step 3/5: PubChem enrichment")
            let pubchem = PubChemSource(cache: cache)
            let enriched = await pubchem.enrich(wdCompounds)

            let wdSourced = enriched.map(WikidataSource.toSourced)
            allSourced.append(contentsOf: wdSourced)
        }

        // ── Erowid ─────────────────────────────────────────────────────────
        if !skipErowid {
            Log.step("Step 4/5: Erowid PIHKAL/TIHKAL")
            let erowid = ErowidSource(cache: cache)
            let entries = await erowid.fetchAll()
            if entries.isEmpty {
                warnings.append("Erowid scraper produced 0 entries.")
            }
            allSourced.append(contentsOf: entries)
        }

        // ── Curated overlay ────────────────────────────────────────────────
        Log.step("Step 5/5: Curated overlay")
        let overlay = CuratedOverlayLoader.load(path: overlayURL)
        if let w = overlay.warning {
            warnings.append(w)
            Log.warn(w)
        }
        if !overlay.entries.isEmpty {
            Log.info("Curated overlay: \(overlay.entries.count) entries")
            allSourced.append(contentsOf: overlay.entries)
        }

        // ── Write per-source dataset (pre-merge) ───────────────────────────
        // Each record retains its provenance + dedup identifiers so the SQLite
        // builder can attribute every fact to the right `sources.slug`. Sort
        // deterministically for byte-stable output across runs.
        Log.step("Writing sourced (pre-merge) dataset")
        let sortedSourced = allSourced.sorted { a, b in
            if a.provenance.rawValue != b.provenance.rawValue {
                return a.provenance.rawValue < b.provenance.rawValue
            }
            return a.substance.name.lowercased() < b.substance.name.lowercased()
        }
        try JSONWriter.writeSourced(sortedSourced, to: sourcedOutputURL)
        Log.info("Wrote \(sortedSourced.count) sourced records to \(sourcedOutputURL.path)")

        // ── Merge & write merged dataset ───────────────────────────────────
        Log.step("Merging")
        Log.info("Total source records before merge: \(allSourced.count)")
        let result = Merger.merge(allSourced)
        Log.info("After dedup/merge: \(result.substances.count) compounds (\(result.mergedCount) duplicates collapsed)")

        try JSONWriter.write(result.substances, to: outputURL)
        Log.info("Wrote \(result.substances.count) substances to \(outputURL.path)")

        let hits = await cache.hits
        let misses = await cache.misses
        let summary = StatsReporter.summarize(
            result.substances,
            countsByProvenance: result.countsByProvenance,
            mergedCount: result.mergedCount,
            warnings: warnings,
            cacheHits: hits,
            cacheMisses: misses
        )
        FileHandle.standardError.write(Data(StatsReporter.render(summary).utf8))
    }
}
