import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Hashes URL+method+body to a deterministic cache key. We use a manually-
/// folded FNV-1a so cache files persist across process invocations —
/// Swift's `Hasher` is per-process-seeded and would generate fresh names
/// every run.
private func cacheKey(method: String, url: URL, body: Data?) -> String {
    var fnv: UInt64 = 0xCBF2_9CE4_8422_2325
    func absorb(_ bytes: some Sequence<UInt8>) {
        for byte in bytes {
            fnv ^= UInt64(byte)
            fnv &*= 0x100_0000_01B3
        }
    }
    absorb(method.utf8)
    absorb([0x1F] as [UInt8])
    absorb(url.absoluteString.utf8)
    if let body {
        absorb([0x1F] as [UInt8])
        absorb(body)
    }
    return String(fnv, radix: 16)
}

/// Token-bucket rate limiter compatible with structured concurrency.
actor RateLimiter {
    private let interval: Duration
    private var nextAllowed: ContinuousClock.Instant = .now

    init(interval: Duration) {
        self.interval = interval
    }

    func wait() async {
        let now = ContinuousClock.now
        let target = nextAllowed
        if target > now {
            try? await Task.sleep(for: target - now)
        }
        nextAllowed = max(now, target) + interval
    }
}

/// HTTP client with disk caching and per-host rate limiting.
///
/// Cached entries live under `cacheDir/<scope>/<hex>.bin` and have no TTL —
/// the dataset is meant to be reproducible. Delete the cache directory to
/// force a refresh.
actor HTTPCache {
    private let cacheDir: URL
    private let session: URLSession
    private var limiters: [String: RateLimiter] = [:]
    private let defaultLimiter: RateLimiter
    private let offline: Bool
    private(set) var hits = 0
    private(set) var misses = 0

    init(cacheDir: URL, offline: Bool) {
        self.cacheDir = cacheDir
        self.offline = offline
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 180
        cfg.httpMaximumConnectionsPerHost = 4
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpAdditionalHeaders = [
            // Many hosts (Wikidata, Erowid) require a real UA.
            "User-Agent": "SubstanceCollector/1.0 (https://github.com/kageroumado/piru; piru-substance-collector)",
            "Accept-Encoding": "gzip, deflate",
        ]
        self.session = URLSession(configuration: cfg)
        self.defaultLimiter = RateLimiter(interval: .milliseconds(250))
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Configure a per-host rate limit (e.g. PubChem requires ≤5 req/sec).
    func configureLimiter(host: String, interval: Duration) {
        limiters[host] = RateLimiter(interval: interval)
    }

    /// GET or POST that returns the response body. Always cached on success.
    func fetch(
        url: URL,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:],
        scope: String,
    ) async throws -> Data {
        let scopeDir = cacheDir.appendingPathComponent(scope, isDirectory: true)
        try? FileManager.default.createDirectory(at: scopeDir, withIntermediateDirectories: true)
        let key = cacheKey(method: method, url: url, body: body)
        let cacheFile = scopeDir.appendingPathComponent("\(key).bin")

        if FileManager.default.fileExists(atPath: cacheFile.path) {
            hits += 1
            return try Data(contentsOf: cacheFile)
        }

        if offline {
            throw HTTPError.offlineMiss(url: url)
        }

        misses += 1
        let host = url.host ?? "default"
        let limiter = limiters[host] ?? defaultLimiter
        await limiter.wait()

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        for (k, v) in headers {
            req.setValue(v, forHTTPHeaderField: k)
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.badResponse(url: url)
        }
        // Retry once on transient errors.
        if http.statusCode == 429 || (500 ..< 600).contains(http.statusCode) {
            try? await Task.sleep(for: .seconds(2))
            await limiter.wait()
            let (retryData, retryResp) = try await session.data(for: req)
            guard let rhttp = retryResp as? HTTPURLResponse, (200 ..< 300).contains(rhttp.statusCode) else {
                throw HTTPError.httpStatus(url: url, status: (retryResp as? HTTPURLResponse)?.statusCode ?? -1)
            }
            try retryData.write(to: cacheFile)
            return retryData
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw HTTPError.httpStatus(url: url, status: http.statusCode)
        }
        try data.write(to: cacheFile)
        return data
    }

    /// Same as `fetch` but tolerates 404 by returning nil and recording an
    /// empty cache entry so we don't re-request known-missing pages.
    func fetchOptional(
        url: URL,
        scope: String,
        headers: [String: String] = [:],
    ) async throws -> Data? {
        let scopeDir = cacheDir.appendingPathComponent(scope, isDirectory: true)
        try? FileManager.default.createDirectory(at: scopeDir, withIntermediateDirectories: true)
        let key = cacheKey(method: "GET", url: url, body: nil)
        let cacheFile = scopeDir.appendingPathComponent("\(key).bin")
        let missMarker = scopeDir.appendingPathComponent("\(key).miss")

        if FileManager.default.fileExists(atPath: missMarker.path) {
            hits += 1
            return nil
        }
        if FileManager.default.fileExists(atPath: cacheFile.path) {
            hits += 1
            return try Data(contentsOf: cacheFile)
        }
        if offline { return nil }

        do {
            return try await fetch(url: url, headers: headers, scope: scope)
        } catch let HTTPError.httpStatus(_, status) where status == 404 {
            // Record miss.
            try? Data().write(to: missMarker)
            return nil
        }
    }

    enum HTTPError: Error, LocalizedError {
        case badResponse(url: URL)
        case httpStatus(url: URL, status: Int)
        case offlineMiss(url: URL)

        var errorDescription: String? {
            switch self {
            case let .badResponse(u): "Bad response from \(u)"
            case let .httpStatus(u, s): "HTTP \(s) from \(u)"
            case let .offlineMiss(u): "Offline mode and cache miss for \(u)"
            }
        }
    }
}
