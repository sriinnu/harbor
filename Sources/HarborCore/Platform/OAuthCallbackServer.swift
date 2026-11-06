import Foundation

/// Platform-agnostic protocol for OAuth callback HTTP server
///
/// Implementations:
/// - macOS: Uses Network framework (NWListener)
/// - Windows: Uses WinSock via Rust
/// - Web: Uses server-side route handler
/// - Linux: Uses socket2 or tokio
@preconcurrency public protocol OAuthCallbackServer: Sendable {
    /// Start the HTTP server and return the callback URL
    /// - Returns: The URL that OAuth providers should redirect to
    /// - Throws: If the server fails to start
    func start() throws -> URL

    /// Wait for the OAuth callback with code and state
    /// - Parameter timeout: Maximum time to wait in seconds
    /// - Returns: A tuple containing the authorization code and state
    /// - Throws: If timeout occurs or callback fails
    func waitForCallback(timeout: TimeInterval) async throws -> (code: String, state: String)

    /// Stop the server and clean up resources
    func stop()
}

// MARK: - Platform Implementations

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Network

/// macOS/iOS implementation using Network framework
@MainActor
public final class NetworkFrameworkCallbackServer: @preconcurrency OAuthCallbackServer {
    private let port: UInt16
    private var listener: NWListener?
    private var continuation: CheckedContinuation<(code: String, state: String), Error>?
    private var pendingResult: (code: String, state: String)?

    public nonisolated init(port: Int = 53682) {
        self.port = UInt16(port)
    }

    public func start() throws -> URL {
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: self.port)!)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor [weak self] in
                self?.handle(connection: connection)
            }
        }
        listener.start(queue: .main)
        return URL(string: "http://127.0.0.1:\(self.port)/callback")!
    }

    public func waitForCallback(timeout: TimeInterval = 180) async throws -> (code: String, state: String) {
        if let pendingResult {
            self.pendingResult = nil
            self.stop()
            return pendingResult
        }

        let timeoutTask = Task { @MainActor in
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if let continuation {
                continuation.resume(throwing: URLError(.timedOut))
                self.continuation = nil
            }
        }
        let result = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<
            (code: String, state: String),
            Error
        >) in
            self.continuation = cont
        }
        timeoutTask.cancel()
        self.stop()
        return result
    }

    public func stop() {
        self.listener?.cancel()
        self.listener = nil
        self.continuation = nil
        self.pendingResult = nil
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                // Check if we received data
                guard let data, let request = String(data: data, encoding: .utf8) else {
                    self.sendError(connection: connection, message: "No data received")
                    return
                }

                // Parse the request
                guard let parsed = Self.parse(request: request), !parsed.code.isEmpty else {
                    self.sendError(connection: connection, message: "Failed to parse OAuth callback")
                    return
                }

                // Send success response
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 7\r\n\r\nSuccess"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { [weak self] _ in
                    connection.cancel()
                    Task { @MainActor in self?.listener?.cancel() }
                })

                // Resume with the parsed values
                if let continuation {
                    continuation.resume(returning: parsed)
                    self.continuation = nil
                } else {
                    self.pendingResult = parsed
                }
            }
        }
    }

    private func sendError(connection: NWConnection, message: String) {
        let response = "HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nContent-Length: \(message.count)\r\n\r\n\(message)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// Pure parser to ease testing.
    public nonisolated static func parse(request: String) -> (code: String, state: String)? {
        guard let firstLine = request.components(separatedBy: "\r\n").first,
              let range = firstLine.range(of: "GET ") else { return nil }
        let pathPart = firstLine[range.upperBound...].split(separator: " ").first ?? "" as Substring
        // Use 127.0.0.1 to match what the server actually receives
        let components = URLComponents(string: "http://127.0.0.1\(pathPart)")
        let code = components?.queryItems?.first(where: { $0.name == "code" })?.value ?? ""
        let state = components?.queryItems?.first(where: { $0.name == "state" })?.value ?? ""
        return (code, state)
    }
}
#endif

// MARK: - Mock Implementation (Testing)

/// Mock implementation for testing OAuth flows
/// A class with a lock, not an actor: the protocol is synchronous, and an actor
/// conforming through `@preconcurrency` traps at runtime (SIGABRT) whenever it is
/// called from outside its own executor.
public final class MockCallbackServer: OAuthCallbackServer, @unchecked Sendable {
    private let lock = NSLock()
    private var mockResponse: (code: String, state: String)?
    private var shouldFail: Bool = false

    public init() {}

    public func configureMock(code: String, state: String) {
        lock.withLock { self.mockResponse = (code, state) }
    }

    public func configureFailure() {
        lock.withLock { self.shouldFail = true }
    }

    public func start() throws -> URL {
        if lock.withLock({ shouldFail }) {
            throw URLError(.cannotConnectToHost)
        }
        return URL(string: "http://127.0.0.1:53682/callback")!
    }

    public func waitForCallback(timeout: TimeInterval = 180) async throws -> (code: String, state: String) {
        let (shouldFail, mockResponse) = lock.withLock { (self.shouldFail, self.mockResponse) }
        if shouldFail {
            throw URLError(.timedOut)
        }
        guard let response = mockResponse else {
            throw URLError(.badServerResponse)
        }
        return response
    }

    public func stop() {
        lock.withLock { mockResponse = nil }
    }
}

// MARK: - Usage Example

/*
 Platform-specific instantiation:

 macOS/iOS:
 let server: OAuthCallbackServer = NetworkFrameworkCallbackServer(port: 53682)

 Windows (Rust implementation via FFI):
 let server: OAuthCallbackServer = WinSockCallbackServer(port: 53682)

 Web (Server-side):
 let server: OAuthCallbackServer = NextJSCallbackHandler()

 Testing:
 let server: OAuthCallbackServer = MockCallbackServer()

 Then use the protocol:
 let callbackURL = try server.start()
 // Open browser to OAuth URL with callbackURL
 let (code, state) = try await server.waitForCallback(timeout: 180)
 server.stop()
 */
