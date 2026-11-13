import Foundation

/// What `GitHubAccountSignIn.finish` did with a sign-in that GitHub accepted.
public struct GitHubSignInOutcome: Equatable, Sendable {
    public let login: String
    public let key: String
    /// True when this account is now the one every request uses.
    public let activated: Bool
    /// True when the account was saved but not activated because the pre-accounts item is still
    /// the live sign-in: the app moves it to its own key the next time it knows the login.
    public let legacyBlockedActivation: Bool
}

/// What `GitHubAccountSignIn.signOut` removed.
public enum GitHubSignOutOutcome: Equatable, Sendable {
    /// Every account, the pointer, the staging slot, the legacy item and the OAuth app credentials.
    case everything
    /// One account. `next` is the account that took over as active, if any remain.
    case account(key: String, next: String?)
    case legacyItem
    /// Nothing is active. `stored` counts accounts that remain signed in.
    case nobodyActive(stored: Int)
}

/// Sign-in and sign-out for the active-account model, shared by the app's rules and `harborcli`.
/// Everything goes through a `SecureTokenStorage`; nothing here knows which settings file the
/// caller keeps, so the account set stays discoverable from the Keychain alone.
public enum GitHubAccountSignIn {
    /// The REST API root for a GitHub host.
    public static func apiHost(for host: URL) -> URL {
        host.host?.lowercased() == "github.com" ? HarborAuthDefaults.apiHost : host.appending(path: "/api/v3")
    }

    /// Names a token's owner with `GET /user` (or `identify` in tests).
    public static func identify(_ tokens: OAuthTokens, host: URL) async throws -> String {
        try await GitHubTokenValidator(apiHost: self.apiHost(for: host)).identify(tokens.accessToken)
    }

    /// Finishes a sign-in whose tokens sit in the staging slot: identify the login, save under
    /// that account's key, and activate it only when asked or when it is the first account. A
    /// sign-in that cannot be identified leaves nothing behind and no other account touched.
    public static func finish(
        tokens: OAuthTokens,
        host: URL,
        storage: SecureTokenStorage,
        activate: Bool,
        identify: @Sendable (OAuthTokens, URL) async throws -> String
    ) async throws -> GitHubSignInOutcome {
        let login: String
        do {
            login = try await identify(tokens, host)
        } catch {
            storage.remove(account: GitHubAccountKey.staging)
            throw error
        }
        // A listing that fails reads as "other accounts may exist": never grab the pointer then.
        let others = (try? storage.storedAccountKeys())
        let first = others?.isEmpty == true
        let legacyLive = storage.activeAccount == nil && (try? storage.load(account: GitHubAccountKey.legacy)) != nil

        let key: String
        do {
            key = try storage.commitStagedAccount(tokens, login: login, host: host)
        } catch {
            storage.remove(account: GitHubAccountKey.staging)
            throw error
        }
        if storage.activeAccount == key {
            return GitHubSignInOutcome(login: login, key: key, activated: true, legacyBlockedActivation: false)
        }
        guard activate || first else {
            return GitHubSignInOutcome(login: login, key: key, activated: false, legacyBlockedActivation: false)
        }
        if legacyLive {
            return GitHubSignInOutcome(login: login, key: key, activated: false, legacyBlockedActivation: true)
        }
        try storage.setActiveAccount(key)
        return GitHubSignInOutcome(login: login, key: key, activated: true, legacyBlockedActivation: false)
    }

    /// Signs out the active account only, or with `all` everything. When the active account goes,
    /// the next stored one (sorted) takes over, as the app's own account removal does.
    @discardableResult
    public static func signOut(storage: SecureTokenStorage, all: Bool) -> GitHubSignOutOutcome {
        if all {
            storage.clear()
            return .everything
        }
        if let active = storage.activeAccount {
            storage.remove(account: active)
            let next = ((try? storage.storedAccountKeys()) ?? []).first
            try? storage.setActiveAccount(next)
            return .account(key: active, next: next)
        }
        if (try? storage.load(account: GitHubAccountKey.legacy)) != nil {
            storage.remove(account: GitHubAccountKey.legacy)
            return .legacyItem
        }
        return .nobodyActive(stored: storage.accountKeys().count)
    }
}
