import Foundation

/// A URLProtocol that answers from a closure and records every request, so a test can run
/// the real request code against canned responses. Routes are keyed by host: give each test
/// its own host (`t1.stub.test`) and nothing leaks between tests.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Reply {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
        /// Held back this long, so two callers can overlap.
        var delay: TimeInterval = 0

        init(status: Int = 200, headers: [String: String] = [:], body: String = "", delay: TimeInterval = 0) {
            self.status = status
            self.headers = headers
            self.body = Data(body.utf8)
            self.delay = delay
        }
    }

    struct Seen: Equatable {
        let path: String
        let query: String?
        let authorization: String?
    }

    typealias Route = @Sendable (Seen) -> Reply

    private static let lock = NSLock()
    nonisolated(unsafe) private static var routes: [String: Route] = [:]
    nonisolated(unsafe) private static var seen: [String: [Seen]] = [:]

    static func register(host: String, route: @escaping Route) {
        self.lock.withLock {
            self.routes[host] = route
            self.seen[host] = []
        }
    }

    static func requests(host: String) -> [Seen] {
        self.lock.withLock { self.seen[host] ?? [] }
    }

    /// A session that sends everything to the stub.
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = self.request.url, let host = url.host else { return }
        let seen = Seen(path: url.path, query: url.query, authorization: self.request.value(forHTTPHeaderField: "Authorization"))
        let route = Self.lock.withLock { () -> Route? in
            Self.seen[host, default: []].append(seen)
            return Self.routes[host]
        }
        let reply = route?(seen) ?? Reply(status: 404)
        let deliver: @Sendable () -> Void = { [self] in
            let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: reply.body)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        if reply.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay, execute: deliver)
        } else {
            deliver()
        }
    }

    override func stopLoading() {}
}
