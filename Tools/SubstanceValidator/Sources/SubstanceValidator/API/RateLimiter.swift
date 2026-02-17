import Foundation

/// Simple token-bucket rate limiter for API requests.
actor RateLimiter {
    private let interval: Duration
    private var lastRequest: ContinuousClock.Instant?

    /// - Parameter interval: Minimum time between requests.
    init(interval: Duration) {
        self.interval = interval
    }

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
