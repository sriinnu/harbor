import Foundation

// DEPRECATED: Use OAuthCallbackServer protocol instead
@MainActor
protocol LoopbackServing: AnyObject {
    func start() throws -> URL
    func waitForCallback(timeout: TimeInterval) async throws -> (code: String, state: String)
    func stop()
}

extension LoopbackServer: LoopbackServing {}

@MainActor
public struct OAuthLoginFlow {
    private let tokenStorage: SecureTokenStorage
    private let openURL: @Sendable (URL) throws -> Void
    private let dataProvider: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let makeLoopbackServer: (Int) -> LoopbackServing
    private let stateProvider: @Sendable () -> String

    // MARK: - New Platform-Agnostic Initializer

    /// Create an OAuth flow with platform services
    /// - Parameters:
    ///   - platform: Platform services providing token storage and callback server
    ///   - openURL: Platform-specific URL opening function
    ///   - dataProvider: Network data provider (defaults to URLSession)
    public init(
        platform: PlatformServices,
        openURL: @escaping @Sendable (URL) throws -> Void,
        dataProvider: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.tokenStorage = platform.tokenStorage
        self.openURL = openURL
        self.dataProvider = dataProvider
        // Bridge to the new OAuthCallbackServer protocol
        self.makeLoopbackServer = { port in
            CallbackServerBridge(server: platform.callbackServer)
        }
        self.stateProvider = { UUID().uuidString }
    }

    // MARK: - Legacy Initializers (Deprecated)

    @available(*, deprecated, message: "Use init(platform:openURL:dataProvider:) instead")
    public init(
        tokenStore: TokenStore = .shared,
        openURL: @escaping @Sendable (URL) throws -> Void,
        dataProvider: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        #if os(macOS) || os(iOS)
        let storage = KeychainTokenStorage(service: "com.sriinnu.athena.harbor.auth")
        #else
        let storage = InMemoryTokenStorage()
        #endif

        self.init(
            tokenStorage: storage,
            openURL: openURL,
            dataProvider: dataProvider,
            makeLoopbackServer: { port in LoopbackServer(port: port) },
            stateProvider: { UUID().uuidString }
        )
    }

    init(
        tokenStorage: SecureTokenStorage,
        openURL: @escaping @Sendable (URL) throws -> Void,
        dataProvider: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse),
        makeLoopbackServer: @escaping (Int) -> LoopbackServing,
        stateProvider: @escaping @Sendable () -> String
    ) {
        self.tokenStorage = tokenStorage
        self.openURL = openURL
        self.dataProvider = dataProvider
        self.makeLoopbackServer = makeLoopbackServer
        self.stateProvider = stateProvider
    }

    public func login(
        clientID: String,
        clientSecret: String,
        host: URL,
        loopbackPort: Int,
        scope: String = "repo read:org",
        timeout: TimeInterval = 180
    ) async throws -> OAuthTokens {
        let normalizedHost = try Self.normalizeHost(host)
        let authBase = normalizedHost.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let authEndpoint = URL(string: "\(authBase)/login/oauth/authorize")!
        let tokenEndpoint = URL(string: "\(authBase)/login/oauth/access_token")!

        let pkce = PKCE.generate()
        let state = self.stateProvider()

        let server = self.makeLoopbackServer(loopbackPort)
        let redirectURL = try server.start()

        var components = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURL.absoluteString),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let authorizeURL = components.url else { throw URLError(.badURL) }
        try self.openURL(authorizeURL)

        let result = try await server.waitForCallback(timeout: timeout)
        guard result.state == state else { throw URLError(.badServerResponse) }

        var tokenRequest = URLRequest(url: tokenEndpoint)
        tokenRequest.httpMethod = "POST"
        tokenRequest.addValue("application/json", forHTTPHeaderField: "Accept")
        tokenRequest.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        tokenRequest.httpBody = Self.formUrlEncoded([
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": result.code,
            "redirect_uri": redirectURL.absoluteString,
            "grant_type": "authorization_code",
            "code_verifier": pkce.verifier
        ])

        let (data, response) = try await self.dataProvider(tokenRequest)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        let tokens = OAuthTokens(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken ?? "",
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expiresIn ?? 3600))
        )
        try self.tokenStorage.save(tokens: tokens)
        try self.tokenStorage.save(clientCredentials: OAuthClientCredentials(clientID: clientID, clientSecret: clientSecret))
        server.stop()
        return tokens
    }

    public static func normalizeHost(_ host: URL) throws -> URL {
        guard var components = URLComponents(url: host, resolvingAgainstBaseURL: false) else {
            throw GitHubAPIError.invalidHost
        }
        if components.scheme == nil { components.scheme = "https" }
        guard components.scheme?.lowercased() == "https", components.host != nil else {
            throw GitHubAPIError.invalidHost
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        guard let cleaned = components.url else { throw GitHubAPIError.invalidHost }
        return cleaned
    }
}

private extension OAuthLoginFlow {
    static func formUrlEncoded(_ params: [String: String]) -> Data? {
        let encoded = params.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return encoded.data(using: .utf8)
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let scope: String
    let expiresIn: Int?
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

// MARK: - Bridge for OAuthCallbackServer Protocol

/// Bridge adapter to make OAuthCallbackServer conform to LoopbackServing
@MainActor
private final class CallbackServerBridge: LoopbackServing {
    private let server: OAuthCallbackServer

    init(server: OAuthCallbackServer) {
        self.server = server
    }

    func start() throws -> URL {
        try server.start()
    }

    func waitForCallback(timeout: TimeInterval) async throws -> (code: String, state: String) {
        try await server.waitForCallback(timeout: timeout)
    }

    func stop() {
        server.stop()
    }
}
