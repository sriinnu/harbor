import Foundation

/// Simple in-memory ETag cache keyed by URL string.
actor ETagCache {
    private var store: [String: (etag: String, data: Data)] = [:]
    private var rateLimitedUntil: Date?

    func cached(for url: URL) -> (etag: String, data: Data)? {
        self.store[url.absoluteString]
    }

    func save(url: URL, etag: String?, data: Data) {
        guard let etag else { return }
        self.store[url.absoluteString] = (etag, data)
    }

    func setRateLimitReset(date: Date) {
        self.rateLimitedUntil = date
    }

    func rateLimitUntil(now: Date = Date()) -> Date? {
        guard let until = self.rateLimitedUntil else { return nil }
        if until <= now {
            self.rateLimitedUntil = nil
            return nil
        }
        return until
    }

    func isRateLimited(now: Date = Date()) -> Bool {
        guard let until = self.rateLimitUntil(now: now) else { return false }
        return until > now
    }

    func clear() {
        self.store.removeAll()
        self.rateLimitedUntil = nil
    }

    func count() -> Int {
        self.store.count
    }
}
