import Foundation
@testable import HarborCore
import Testing

struct LoopbackServerTests {
    @Test
    func parseExtractsCodeAndState() {
        let request = "GET /callback?code=abc&state=xyz HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        let parsed = LoopbackServer.parse(request: request)
        #expect(parsed?.code == "abc")
        #expect(parsed?.state == "xyz")
    }

    @Test
    @MainActor
    func waitForCallbackReturnsResult() async throws {
        let (server, redirectURL) = try await Self.startServer()
        defer { server.stop() }

        let expectedCode = "code-1"
        let expectedState = "state-1"

        var components = URLComponents(url: redirectURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: expectedCode),
            URLQueryItem(name: "state", value: expectedState)
        ]
        let callbackURL = components.url!

        let sendTask = Task.detached {
            while !Task.isCancelled {
                do {
                    var request = URLRequest(url: callbackURL)
                    request.timeoutInterval = 0.5
                    _ = try await URLSession.shared.data(for: request)
                    return
                } catch {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
            }
        }
        defer { sendTask.cancel() }

        let result = try await server.waitForCallback(timeout: 10)
        #expect(result.code == expectedCode)
        #expect(result.state == expectedState)
    }

    @Test
    @MainActor
    func waitForCallbackTimesOut() async throws {
        let (server, _) = try await Self.startServer()
        defer { server.stop() }

        do {
            _ = try await server.waitForCallback(timeout: 0.05)
            Issue.record("Expected timeout")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
        }
    }
}

private extension LoopbackServerTests {
    @MainActor
    static func startServer() async throws -> (LoopbackServer, URL) {
        var lastError: Error?
        for _ in 0 ..< 40 {
            let port = Int.random(in: 49152 ... 65000)
            let server = LoopbackServer(port: port)
            do {
                let redirectURL = try server.start()
                return (server, redirectURL)
            } catch {
                lastError = error
                server.stop()
            }
        }
        throw lastError ?? URLError(.cannotConnectToHost)
    }
}
