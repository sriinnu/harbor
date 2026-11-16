import Foundation

/// Names of the Keychain accounts under `com.sriinnu.harbor.auth` that hold GitHub tokens.
public enum GitHubAccountKey {
    /// Prefix of every per-account token item: `github:<login>@<host>`, lowercased.
    public static let prefix = "github:"
    /// Where a sign-in lands before Harbor knows whose token it is; moved to its own key once GitHub
    /// has named the login, or deleted when the sign-in fails.
    public static let staging = "pending"
    /// The one item Harbor used before it supported several accounts. Read as a fallback and
    /// moved to a per-account key the first time the login is known.
    public static let legacy = "default"
    /// Names the active account's key. Not a secret; it sits beside the tokens so `harborcli`
    /// reads the same account as the app without reading the app's settings.
    public static let activePointer = "active"

    /// The legacy item's OAuth app credentials, written by versions before accounts.
    public static let legacyClient = "client"
    /// Prefix of an account's OAuth app credentials: `client:<account key>`.
    public static let clientPrefix = "client:"

    /// The Keychain item holding the OAuth app credentials that go with `account`'s tokens.
    public static func clientItem(for account: String) -> String {
        account == self.legacy ? self.legacyClient : "\(self.clientPrefix)\(account)"
    }

    /// The login and host a per-account key names, or nil for any other key. Lets the account set
    /// be rebuilt from the Keychain alone.
    public static func parse(_ key: String) -> (login: String, host: String)? {
        guard key.hasPrefix(self.prefix) else { return nil }
        let rest = key.dropFirst(self.prefix.count)
        guard let at = rest.lastIndex(of: "@") else { return nil }
        let login = String(rest[rest.startIndex ..< at])
        let host = String(rest[rest.index(after: at)...])
        guard login.isEmpty == false, host.isEmpty == false else { return nil }
        return (login, host)
    }

    public static func make(login: String, host: String) -> String {
        "\(self.prefix)\(login.lowercased())@\(host.lowercased())"
    }

    public static func make(login: String, host: URL) -> String {
        self.make(login: login, host: host.host ?? "github.com")
    }
}

/// One signed-in GitHub account, as the settings index records it. Carries no secret: the token
/// is in the Keychain under `id`.
public struct GitHubAccount: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var login: String
    /// Host name only, such as `github.com` or `ghe.example.com`.
    public var host: String
    public var kind: GitHubAuthKind

    public init(login: String, host: String, kind: GitHubAuthKind) {
        self.login = login
        self.host = host
        self.kind = kind
    }

    public var id: String { GitHubAccountKey.make(login: self.login, host: self.host) }

    /// The URL of the host, such as `https://github.com`.
    public var hostURL: URL { URL(string: "https://\(self.host)") ?? HarborAuthDefaults.githubHost }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.login = try container.decode(String.self, forKey: .login)
        self.host = try container.decodeIfPresent(String.self, forKey: .host) ?? "github.com"
        self.kind = try container.decodeIfPresent(GitHubAuthKind.self, forKey: .kind) ?? .oauth
    }
}

/// The small, non-secret list of accounts Harbor knows, kept in the settings. Logins, hosts, how
/// each signed in, and which is active; never a token.
public struct GitHubAccountIndex: Codable, Equatable, Sendable {
    public var accounts: [GitHubAccount] = []
    /// The `id` of the active account.
    public var active: String?

    public init() {}

    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.accounts = try container.decodeIfPresent([GitHubAccount].self, forKey: .accounts) ?? []
        self.active = try container.decodeIfPresent(String.self, forKey: .active)
    }

    public var activeAccount: GitHubAccount? { self.account(id: self.active) }

    public func account(id: String?) -> GitHubAccount? {
        guard let id else { return nil }
        return self.accounts.first { $0.id == id }
    }

    /// Adds the account, or updates the one with the same id (same login and host), keeping its place.
    public mutating func upsert(_ account: GitHubAccount) {
        if let index = self.accounts.firstIndex(where: { $0.id == account.id }) {
            self.accounts[index] = account
        } else {
            self.accounts.append(account)
        }
    }

    public mutating func remove(id: String) {
        self.accounts.removeAll { $0.id == id }
        if self.active == id { self.active = nil }
    }
}

/// A view of a token storage bound to one Keychain account: the staging slot while a sign-in is
/// in flight, or the account a refresher is bound to. Tokens and client credentials both go to
/// that account's own items, so one sign-in never replaces another account's OAuth app.
public struct ScopedTokenStorage: SecureTokenStorage {
    private let base: SecureTokenStorage
    private let account: String

    public init(_ base: SecureTokenStorage, account: String) {
        self.base = base
        self.account = account
    }

    public func save(tokens: OAuthTokens) throws { try self.base.save(tokens: tokens, account: self.account) }
    public func load() throws -> OAuthTokens? { try self.base.load(account: self.account) }
    public func save(clientCredentials: OAuthClientCredentials) throws {
        try self.base.save(clientCredentials: clientCredentials, account: self.account)
    }
    public func loadClientCredentials() throws -> OAuthClientCredentials? {
        try self.base.loadClientCredentials(account: self.account)
    }
    public func save(clientCredentials: OAuthClientCredentials, account: String) throws {
        try self.base.save(clientCredentials: clientCredentials, account: account)
    }
    public func loadClientCredentials(account: String) throws -> OAuthClientCredentials? {
        try self.base.loadClientCredentials(account: account)
    }
    public func clear() { self.base.remove(account: self.account) }

    public var activeAccount: String? { self.base.activeAccount }
    public func setActiveAccount(_ key: String?) throws { try self.base.setActiveAccount(key) }
    public func save(tokens: OAuthTokens, account: String) throws { try self.base.save(tokens: tokens, account: account) }
    public func load(account: String) throws -> OAuthTokens? { try self.base.load(account: account) }
    public func remove(account: String) { self.base.remove(account: account) }
    public func storedAccountKeys() throws -> [String] { try self.base.storedAccountKeys() }
}

/// Sign-in bookkeeping shared by the app and `harborcli`, so both leave the Keychain in the same
/// shape: tokens under `github:<login>@<host>`, the OAuth app credentials beside them, the
/// active pointer naming the account every request uses.
public extension SecureTokenStorage {
    /// Saves a staged sign-in under its account key: the tokens and, when the flow staged them,
    /// the OAuth app credentials. Clears the staging slot. Does not change the active account.
    @discardableResult
    func commitStagedAccount(_ tokens: OAuthTokens, login: String, host: URL) throws -> String {
        let key = GitHubAccountKey.make(login: login, host: host)
        let staged = try self.loadClientCredentials(account: GitHubAccountKey.staging)
        try self.save(tokens: tokens, account: key)
        if let staged { try self.save(clientCredentials: staged, account: key) }
        self.remove(account: GitHubAccountKey.staging)
        return key
    }

    /// Moves the pre-accounts item (and its OAuth app credentials) to its own key and makes it
    /// active. Copy, read back, then delete: a failure at any step leaves the legacy item, which
    /// still signs in. Returns the new key, or nil when there is nothing to migrate or it failed.
    func migrateLegacyAccount(login: String, host: URL) -> String? {
        guard self.activeAccount == nil,
              let legacy = try? self.load(account: GitHubAccountKey.legacy) else { return nil }
        let key = GitHubAccountKey.make(login: login, host: host)
        let client = try? self.loadClientCredentials(account: GitHubAccountKey.legacy)
        guard (try? self.save(tokens: legacy, account: key)) != nil,
              (try? self.load(account: key)) == legacy else { return nil }
        if let client, (try? self.save(clientCredentials: client, account: key)) == nil {
            self.remove(account: key)
            return nil
        }
        guard (try? self.setActiveAccount(key)) != nil else { return nil }
        self.remove(account: GitHubAccountKey.legacy)
        return key
    }
}
