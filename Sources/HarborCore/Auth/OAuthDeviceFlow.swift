import Foundation

/// What the user needs to finish a device-flow sign-in: a short code to type
/// at a verification URL in any browser.
public struct DeviceAuthorization: Equatable, Sendable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURL: URL
    public let expiresAt: Date
    public let pollInterval: TimeInterval

    public init(deviceCode: String, userCode: String, verificationURL: URL, expiresAt: Date, pollInterval: TimeInterval) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURL = verificationURL
        self.expiresAt = expiresAt
        self.pollInterval = pollInterval
    }
}

public enum DeviceFlowError: Error, Equatable, LocalizedError {
    /// The user didn't enter the code before it expired.
    case expired
    /// The user pressed Cancel on GitHub's authorization page.
    case denied
    /// Device flow isn't enabled on the OAuth app (Settings → Developer settings → OAuth Apps → Enable Device Flow).
    case disabled
    case server(code: String, description: String?)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .expired: "The sign-in code expired. Start sign-in again."
        case .denied: "Sign-in was cancelled on GitHub."
        case .disabled: "Device sign-in is turned off for this GitHub OAuth app. Enable Device Flow in the app's settings on GitHub."
        case let .server(code, description): description.map { "GitHub sign-in failed: \($0)" } ?? "GitHub sign-in failed (\(code))."
        case .invalidResponse: "GitHub returned an unexpected response during sign-in."
        }
    }
}

/// GitHub's OAuth device authorization grant (RFC 8628).
///
/// It needs only the public client ID, so Harbor never ships a client secret:
/// a native app cannot keep one confidential.
public struct OAuthDeviceFlow: Sendable {
    public static let grantType = "urn:ietf:params:oauth:grant-type:device_code"

    private let tokenStorage: SecureTokenStorage
    private let dataProvider: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let now: @Sendable () -> Date

    public init(
        tokenStorage: SecureTokenStorage,
        dataProvider: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await HarborURLSession.shared.data(for: request)
        },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.tokenStorage = tokenStorage
        self.dataProvider = dataProvider
        self.sleep = sleep
        self.now = now
    }

    /// Asks GitHub for a device code and the user code to show.
    public func start(clientID: String, host: URL, scope: String = "repo read:org") async throws -> DeviceAuthorization {
        let base = try Self.base(host)
        let request = Self.post(URL(string: "\(base)/login/device/code")!, [
            "client_id": clientID,
            "scope": scope
        ])
        let (data, response) = try await self.dataProvider(request)
        guard let http = response as? HTTPURLResponse else { throw DeviceFlowError.invalidResponse }
        if let failure = try? JSONDecoder().decode(ErrorBody.self, from: data), let code = failure.error {
            throw Self.error(for: code, description: failure.errorDescription)
        }
        guard http.statusCode == 200,
              let body = try? JSONDecoder().decode(CodeBody.self, from: data),
              let url = URL(string: body.verificationURI)
        else { throw DeviceFlowError.invalidResponse }
        return DeviceAuthorization(
            deviceCode: body.deviceCode,
            userCode: body.userCode,
            verificationURL: url,
            expiresAt: self.now().addingTimeInterval(TimeInterval(body.expiresIn)),
            pollInterval: TimeInterval(body.interval ?? 5)
        )
    }

    /// Polls until the user approves, denies, or the code expires, then stores the token.
    /// Cancelling the calling task stops polling with `CancellationError`.
    @discardableResult
    public func poll(_ authorization: DeviceAuthorization, clientID: String, host: URL) async throws -> OAuthTokens {
        let base = try Self.base(host)
        let endpoint = URL(string: "\(base)/login/oauth/access_token")!
        var interval = authorization.pollInterval

        while true {
            try await self.sleep(interval)
            try Task.checkCancellation()
            guard self.now() < authorization.expiresAt else { throw DeviceFlowError.expired }

            let request = Self.post(endpoint, [
                "client_id": clientID,
                "device_code": authorization.deviceCode,
                "grant_type": Self.grantType
            ])
            let (data, response) = try await self.dataProvider(request)
            guard response is HTTPURLResponse else { throw DeviceFlowError.invalidResponse }

            if let failure = try? JSONDecoder().decode(ErrorBody.self, from: data), let code = failure.error {
                switch code {
                case "authorization_pending":
                    continue
                case "slow_down":
                    // GitHub sends the new minimum interval; RFC 8628 says add 5s otherwise.
                    interval = failure.interval.map(TimeInterval.init) ?? interval + 5
                    continue
                default:
                    throw Self.error(for: code, description: failure.errorDescription)
                }
            }

            guard let body = try? JSONDecoder().decode(TokenBody.self, from: data) else {
                throw DeviceFlowError.invalidResponse
            }
            let tokens = OAuthTokens(
                accessToken: body.accessToken,
                refreshToken: body.refreshToken ?? "",
                // Classic OAuth-app tokens don't expire; never invent an expiry.
                expiresAt: body.expiresIn.map { self.now().addingTimeInterval(TimeInterval($0)) }
            )
            try self.tokenStorage.save(tokens: tokens)
            try self.tokenStorage.save(clientCredentials: OAuthClientCredentials(clientID: clientID, clientSecret: ""))
            return tokens
        }
    }
}

private extension OAuthDeviceFlow {
    static func base(_ host: URL) throws -> String {
        let normalized = try OAuthLoginFlow.normalizeHost(host)
        return normalized.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func post(_ url: URL, _ params: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = params
            .sorted { $0.key < $1.key }
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
            .data(using: .utf8)
        return request
    }

    static func error(for code: String, description: String?) -> DeviceFlowError {
        switch code {
        case "expired_token": .expired
        case "access_denied": .denied
        case "device_flow_disabled": .disabled
        default: .server(code: code, description: description)
        }
    }

    struct CodeBody: Decodable {
        let deviceCode: String
        let userCode: String
        let verificationURI: String
        let expiresIn: Int
        let interval: Int?

        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code"
            case userCode = "user_code"
            case verificationURI = "verification_uri"
            case expiresIn = "expires_in"
            case interval
        }
    }

    struct TokenBody: Decodable {
        let accessToken: String
        let expiresIn: Int?
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
        }
    }

    struct ErrorBody: Decodable {
        let error: String?
        let errorDescription: String?
        let interval: Int?

        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
            case interval
        }
    }
}
