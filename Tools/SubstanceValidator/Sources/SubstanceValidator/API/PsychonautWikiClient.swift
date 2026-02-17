import Foundation

/// GraphQL client for the PsychonautWiki API.
struct PsychonautWikiClient {
    private let endpoint = URL(string: "https://api.psychonautwiki.org/graphql")!
    private let rateLimiter = RateLimiter(interval: .seconds(2))
    private let maxConcurrent = 3
    private let cacheDir: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        cacheDir = home.appendingPathComponent(".piru-cache")
    }

    /// Fetch substance data for a list of names, with local caching.
    func fetchSubstances(names: [String], verbose: Bool = false) async throws -> [String: PWSubstance] {
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let cacheFile = cacheDir.appendingPathComponent("pw-cache.json")

        // Load existing cache
        var cache: [String: PWSubstance] = loadCache(from: cacheFile)
        if verbose && !cache.isEmpty {
            print("  Loaded \(cache.count) cached PsychonautWiki entries")
        }

        // Filter out already-cached names
        let uncached = names.filter { cache[NameNormalizer().normalize($0)] == nil }
        if verbose {
            print("  Need to fetch \(uncached.count) substances from PsychonautWiki (\(names.count - uncached.count) cached)")
        }

        if uncached.isEmpty { return cache }

        // Fetch in batches with concurrency limit
        var results: [String: PWSubstance] = [:]
        let normalizer = NameNormalizer()

        for batch in uncached.chunked(into: maxConcurrent) {
            await withTaskGroup(of: (String, PWSubstance?).self) { group in
                for name in batch {
                    group.addTask {
                        await rateLimiter.wait()
                        do {
                            let substance = try await fetchSingle(name: name)
                            return (name, substance)
                        } catch {
                            if verbose {
                                print("    Warning: Failed to fetch '\(name)': \(error.localizedDescription)")
                            }
                            return (name, nil)
                        }
                    }
                }

                for await (name, substance) in group {
                    if let substance {
                        let key = normalizer.normalize(name)
                        results[key] = substance
                    }
                }
            }

            if verbose {
                let total = results.count
                print("  PW progress: \(total)/\(uncached.count) fetched")
            }
        }

        // Merge with cache and save
        for (key, value) in results {
            cache[key] = value
        }
        saveCache(cache, to: cacheFile)

        return cache
    }

    private func fetchSingle(name: String) async throws -> PWSubstance? {
        let query = """
        {
            substances(query: "\(name.replacingOccurrences(of: "\"", with: "\\\""))") {
                name
                summary
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
                        total { min max units }
                    }
                }
                effects {
                    name
                    url
                }
                classes {
                    chemical
                    psychoactive
                }
                toxicity
                addictionPotential
                crossTolerances
                tolerance {
                    full
                    half
                    zero
                }
            }
        }
        """

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body = ["query": query]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PWError.invalidResponse
        }

        if http.statusCode == 429 {
            // Rate limited — wait and retry once
            try await Task.sleep(for: .seconds(5))
            return try await fetchSingle(name: name)
        }

        guard http.statusCode == 200 else {
            throw PWError.httpError(statusCode: http.statusCode)
        }

        let graphQLResponse = try JSONDecoder().decode(PWGraphQLResponse.self, from: data)
        return graphQLResponse.data?.substances?.first
    }

    // MARK: - Cache

    private func loadCache(from url: URL) -> [String: PWSubstance] {
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode([String: PWSubstance].self, from: data) else {
            return [:]
        }
        return cache
    }

    private func saveCache(_ cache: [String: PWSubstance], to url: URL) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url)
    }

    enum PWError: Error, LocalizedError {
        case httpError(statusCode: Int)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .httpError(let code): return "PW HTTP error \(code)"
            case .invalidResponse: return "Invalid response from PsychonautWiki"
            }
        }
    }
}

// MARK: - Array chunking helper

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
