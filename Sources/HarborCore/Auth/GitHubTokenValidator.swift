import Foundation

/// What Harbor learned about a pasted personal access token from `GET /user`.
public struct GitHubTokenCheck: Equatable, Sendable {
    public let login: String
    /// Scopes from `X-OAuth-Scopes`. Nil for a fine-grained token, which sends no such header.
    public let scopes: [String]?

    public var isFineGrained: Bool { self.scopes == nil }
}

/// Why a pasted token was not accepted. Every message is safe to show and log: none carries
/// the token.
public enum GitHubTokenError: Error, Equatable, LocalizedError {
    case empty
    case malformed
    case rejected
    case missingScopes([String])
    case needsSSO
    case forbidden
    case rateLimited
    case network(String)
    case unexpected(Int)

    public var errorDescription: String? {
        switch self {
        case .empty:
            "Paste a token first."
        case .malformed:
            "That doesn't look like a token: it has spaces or line breaks in it."
        case .rejected:
            "GitHub rejected this token. It may be mistyped, expired or revoked."
        case let .missingScopes(missing):
            "This token is missing the \(missing.joined(separator: " and ")) "
                + "scope\(missing.count == 1 ? "" : "s"). Edit the token on GitHub, tick "
                + "\(missing.count == 1 ? "it" : "them"), and paste it again."
        case .needsSSO:
            "This token is valid but not yet authorized for your organization's SAML single sign-on. "
                + "On github.com/settings/tokens choose Configure SSO beside the token, then try again."
        case .forbidden:
            "GitHub refused this token (403). An organization may restrict personal access tokens."
        case .rateLimited:
            "GitHub is rate limiting this network right now. Try again in a minute."
        case let .network(detail):
            "Couldn't reach GitHub: \(detail)"
        case let .unexpected(code):
            "GitHub answered with an unexpected status (\(code))."
        }
    }
}

/// Checks a personal access token against github.com before Harbor stores it. github.com only:
/// Harbor's API host is not switched for GitHub Enterprise by any sign-in path yet.
public struct GitHubTokenValidator: Sendable {
    /// Classic-token scopes Harbor calls GitHub with. `repo` covers private repos, PR merge and
    /// branch updates, review threads and run cleanup; `read:org` lists the organizations'
    /// repos (`/user/repos` with `affiliation=organization_member`). Matches the device flow.
    public static let requiredScopes = ["repo", "read:org"]

    /// Scopes that already include a required one.
    private static let implied: [String: Set<String>] = ["read:org": ["write:org", "admin:org"]]

    public static let tokensPage = URL(string: "https://github.com/settings/tokens/new?scopes=repo,read:org&description=Harbor")!

    private let apiHost: URL
    private let load: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(
        apiHost: URL = HarborAuthDefaults.apiHost,
        load: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await HarborURLSession.shared.data(for: request)
        }
    ) {
        self.apiHost = apiHost
        self.load = load
    }

    /// Trims one trailing newline or stray spaces; refuses a token with whitespace inside.
    public static func clean(_ raw: String) throws -> String {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.isEmpty == false else { throw GitHubTokenError.empty }
        guard token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              token.unicodeScalars.allSatisfy({ $0.isASCII })
        else { throw GitHubTokenError.malformed }
        return token
    }

    public static func missingScopes(in granted: [String]) -> [String] {
        let have = Set(granted)
        return self.requiredScopes.filter { required in
            have.contains(required) == false && have.isDisjoint(with: self.implied[required] ?? [])
        }
    }

    public func validate(_ raw: String) async throws -> GitHubTokenCheck {
        let token = try Self.clean(raw)
        var request = URLRequest(url: self.apiHost.appending(path: "/user"))
        request.timeoutInterval = 20
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: HTTPURLResponse
        do {
            let (body, reply) = try await self.load(request)
            guard let http = reply as? HTTPURLResponse else { throw GitHubTokenError.unexpected(-1) }
            data = body
            response = http
        } catch let error as GitHubTokenError {
            throw error
        } catch {
            // `URLError` descriptions name the host, never the Authorization header.
            if let urlError = error as? URLError, urlError.code == .cancelled { throw CancellationError() }
            throw GitHubTokenError.network((error as? URLError)?.userFacingMessage ?? "network error.")
        }

        switch response.statusCode {
        case 200:
            break
        case 401:
            throw GitHubTokenError.rejected
        case 403, 429:
            if response.value(forHTTPHeaderField: "X-GitHub-SSO") != nil { throw GitHubTokenError.needsSSO }
            let body = String(bytes: data.prefix(2048), encoding: .utf8)?.lowercased() ?? ""
            if response.statusCode == 429 || response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0"
                || body.contains("rate limit") { throw GitHubTokenError.rateLimited }
            throw GitHubTokenError.forbidden
        default:
            throw GitHubTokenError.unexpected(response.statusCode)
        }

        struct User: Decodable { let login: String }
        guard let user = try? JSONDecoder().decode(User.self, from: data), user.login.isEmpty == false else {
            throw GitHubTokenError.unexpected(200)
        }

        let header = response.value(forHTTPHeaderField: "X-OAuth-Scopes")
        let scopes = header.map { value in
            value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.isEmpty == false }
        }
        if let scopes {
            let missing = Self.missingScopes(in: scopes)
            if missing.isEmpty == false { throw GitHubTokenError.missingScopes(missing) }
        }
        return GitHubTokenCheck(login: user.login, scopes: scopes)
    }

    /// Who a token belongs to: `GET /user` with that token only, no scope check, touching no client
    /// state. For a sign-in that already produced a token (device flow, browser flow) and needs
    /// the login to name its Keychain account.
    public func identify(_ token: String) async throws -> String {
        var request = URLRequest(url: self.apiHost.appending(path: "/user"))
        request.timeoutInterval = 20
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: HTTPURLResponse
        do {
            let (body, reply) = try await self.load(request)
            guard let http = reply as? HTTPURLResponse else { throw GitHubTokenError.unexpected(-1) }
            data = body
            response = http
        } catch let error as GitHubTokenError {
            throw error
        } catch {
            if let urlError = error as? URLError, urlError.code == .cancelled { throw CancellationError() }
            throw GitHubTokenError.network((error as? URLError)?.userFacingMessage ?? "network error.")
        }
        guard response.statusCode == 200 else {
            throw response.statusCode == 401 ? GitHubTokenError.rejected : GitHubTokenError.unexpected(response.statusCode)
        }
        struct User: Decodable { let login: String }
        guard let user = try? JSONDecoder().decode(User.self, from: data), user.login.isEmpty == false else {
            throw GitHubTokenError.unexpected(200)
        }
        return user.login
    }
}
