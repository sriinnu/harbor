import Foundation
import Network

/// Minimal one-shot HTTP loopback listener to capture OAuth redirects.
@MainActor
public final class LoopbackServer {
    private let port: UInt16
    private var listener: NWListener?
    private var continuation: CheckedContinuation<(code: String, state: String), Error>?
    private var pendingResult: (code: String, state: String)?

    public init(port: Int) {
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
                guard let self, let data, let request = String(data: data, encoding: .utf8) else { return }
                guard let parsed = Self.parse(request: request) else { return }
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 7\r\n\r\nSuccess"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { [weak self] _ in
                    connection.cancel()
                    Task { @MainActor in self?.listener?.cancel() }
                })
                if let continuation {
                    continuation.resume(returning: parsed)
                    self.continuation = nil
                } else {
                    self.pendingResult = parsed
                }
            }
        }
    }

    /// Pure parser to ease testing.
    public nonisolated static func parse(request: String) -> (code: String, state: String)? {
        guard let firstLine = request.components(separatedBy: "\r\n").first,
              let range = firstLine.range(of: "GET ") else { return nil }
        let pathPart = firstLine[range.upperBound...].split(separator: " ").first ?? "" as Substring
        let components = URLComponents(string: "http://localhost\(pathPart)")
        let code = components?.queryItems?.first(where: { $0.name == "code" })?.value ?? ""
        let state = components?.queryItems?.first(where: { $0.name == "state" })?.value ?? ""
        return (code, state)
    }
}
