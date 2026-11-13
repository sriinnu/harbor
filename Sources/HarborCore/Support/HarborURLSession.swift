import Foundation

/// The one way Harbor talks to the network. No `URLCache`, and every request ignores local
/// cache data, so a response is never served from, or written to, disk or memory by Foundation.
/// Speed comes from fewer, batched, concurrent requests, not from reusing an old answer.
public enum HarborURLSession {
    /// Configuration every Harbor session starts from.
    public static func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 8
        return config
    }

    public static let shared = URLSession(configuration: configuration())
}
