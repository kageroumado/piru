import Foundation

/// Fetches the TripSit drug database from their GitHub repository.
struct TripSitClient {
    private let rateLimiter = RateLimiter(interval: .seconds(1))

    /// Primary: raw GitHub JSON. Fallback: API endpoint.
    private let primaryURL = URL(string: "https://raw.githubusercontent.com/TripSit/drugs/main/drugs.json")!
    private let fallbackURL = URL(string: "https://tripbot.tripsit.me/api/tripsit/getAllDrugs")!

    func fetchAllDrugs(verbose: Bool = false) async throws -> TripSitDrugDatabase {
        await rateLimiter.wait()

        if verbose { print("  Fetching TripSit drugs.json from GitHub...") }

        do {
            let (data, response) = try await URLSession.shared.data(from: primaryURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw TripSitError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            if verbose { print("  Downloaded \(data.count / 1024) KB from GitHub") }
            return try decodeDrugs(data)
        } catch let error as TripSitError {
            throw error
        } catch {
            if verbose { print("  GitHub fetch failed (\(error.localizedDescription)), trying API fallback...") }
            return try await fetchFromAPI(verbose: verbose)
        }
    }

    private func fetchFromAPI(verbose: Bool) async throws -> TripSitDrugDatabase {
        await rateLimiter.wait()
        let (data, response) = try await URLSession.shared.data(from: fallbackURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TripSitError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        if verbose { print("  Downloaded \(data.count / 1024) KB from API") }

        // The API wraps in {"err": false, "data": [{...drugs...}]}
        // Try direct decode first, then wrapped format
        if let direct = try? decodeDrugs(data) {
            return direct
        }

        let wrapper = try JSONDecoder().decode(TripSitAPIWrapper.self, from: data)
        return wrapper.data
    }

    private func decodeDrugs(_ data: Data) throws -> TripSitDrugDatabase {
        let decoder = JSONDecoder()
        return try decoder.decode(TripSitDrugDatabase.self, from: data)
    }

    enum TripSitError: Error, LocalizedError {
        case httpError(statusCode: Int)
        case decodingFailed(String)

        var errorDescription: String? {
            switch self {
            case .httpError(let code): return "HTTP error \(code)"
            case .decodingFailed(let msg): return "Decoding failed: \(msg)"
            }
        }
    }
}

private struct TripSitAPIWrapper: Codable {
    let err: Bool?
    let data: TripSitDrugDatabase
}
