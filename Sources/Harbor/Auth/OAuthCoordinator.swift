import AppKit
import Foundation
import OSLog
import HarborCore

/// Handles GitHub App OAuth using browser + loopback, PKCE, and refresh tokens.
@MainActor
final class OAuthCoordinator {
    private let platform: PlatformServices
    private let logger = Logger(subsystem: "com.sriinnu.harbor", category: "oauth")
    private let signposter = OSSignposter(subsystem: "com.sriinnu.harbor", category: "oauth")
    private var lastHost: URL = .init(string: "https://github.com")!
    private var cachedTokens: OAuthTokens?
    private var hasLoadedTokens = false
    /// The Keychain item this app is bound to: the account it shows. Set at first use from the
    /// Keychain's active pointer (or the legacy item), then moved only by this app (`activate`,
    /// migration, removal, sign-out). `harborcli` moves the pointer too, but never this: a pointer
    /// that moved behind the app's back must not swap the token under the account on screen.
    private enum Bound: Equatable {
        case unbound
        case legacy
        case account(String)

        var item: String? {
            switch self {
            case .unbound, .legacy: nil
            case let .account(key): key
            }
        }
    }

    private var bound: Bound = .unbound
    /// The account key the legacy item moved to, while a refresh that began before the move may
    /// still be in flight.
    private var migratedLegacyKey: String?
    /// Tests stand in for `GET /user`.
    var identifyOverride: (@Sendable (OAuthTokens, URL) async throws -> String)?
    /// Tests stand in for the token endpoint a refresh posts to.
    var refreshLoadOverride: (@Sendable (URLRequest) async throws -> (Data, URLResponse))?

    init(platform: PlatformServices = ApplePlatformServices()) {
        self.platform = platform
    }

    /// Where a sign-in's tokens land until GitHub has named the login. Never the active account.
    private var staging: SecureTokenStorage {
        ScopedTokenStorage(self.platform.tokenStorage, account: GitHubAccountKey.staging)
    }

    /// Browser + loopback sign-in with your own OAuth app. The tokens go to the staging slot and
    /// are returned: nothing active changes until `commitAccount` and `activate`.
    func login(clientID: String, clientSecret: String, host: URL, loopbackPort: Int) async throws -> OAuthTokens {
        let normalizedHost = try OAuthLoginFlow.normalizeHost(host)
        let flow = OAuthLoginFlow(platform: self.platform, tokenStorage: self.staging) { url in
            NSWorkspace.shared.open(url)
        }
        let tokens = try await flow.login(
            clientID: clientID,
            clientSecret: clientSecret,
            host: normalizedHost,
            loopbackPort: loopbackPort
        )
        await DiagnosticsLogger.shared.message("Login succeeded; tokens staged via platform services.")
        return tokens
    }

    /// Sign in with GitHub's device flow: no client secret involved. Staged like `login`.
    /// `onCode` runs once GitHub issues the code the user must enter.
    func loginWithDeviceFlow(
        clientID: String,
        host: URL,
        onCode: @MainActor (DeviceAuthorization) -> Void
    ) async throws -> OAuthTokens {
        let normalizedHost = try OAuthLoginFlow.normalizeHost(host)
        let flow = OAuthDeviceFlow(tokenStorage: self.staging)
        let authorization = try await flow.start(clientID: clientID, host: normalizedHost)
        onCode(authorization)
        let tokens = try await flow.poll(authorization, clientID: clientID, host: normalizedHost)
        await DiagnosticsLogger.shared.message("Device-flow login succeeded; tokens staged via platform services.")
        return tokens
    }

    /// Asks GitHub whose token this is, with that token alone: no client state is touched, so the
    /// account on screen keeps working while a second one signs in.
    func identify(_ tokens: OAuthTokens, host: URL) async throws -> String {
        if let identifyOverride { return try await identifyOverride(tokens, host) }
        return try await GitHubAccountSignIn.identify(tokens, host: host)
    }

    /// Checks a pasted personal access token against github.com. Writes nothing.
    func validatePersonalToken(_ token: String, validator: GitHubTokenValidator = GitHubTokenValidator()) async throws -> GitHubTokenCheck {
        try await validator.validate(token)
    }

    /// Saves the staged sign-in under its account key, with the OAuth app credentials it staged,
    /// and clears the staging slot. The key becomes active only through `activate`.
    @discardableResult
    func commitAccount(_ tokens: OAuthTokens, login: String, host: URL) throws -> String {
        try self.platform.tokenStorage.commitStagedAccount(tokens, login: login, host: host)
    }

    /// Drops whatever a failed or cancelled sign-in staged.
    func discardStaged() {
        self.platform.tokenStorage.remove(account: GitHubAccountKey.staging)
    }

    /// Makes `key` the account every request uses (the app and `harborcli` alike), and reloads
    /// the tokens from the Keychain so nothing of the previous account stays cached.
    func activate(_ key: String, host: URL) throws {
        try self.platform.tokenStorage.setActiveAccount(key)
        self.bound = .account(key)
        self.lastHost = host
        self.cachedTokens = try? self.platform.tokenStorage.load(account: key)
        self.hasLoadedTokens = true
    }

    /// The key of the active account, or nil while only the legacy item (or nothing) is stored.
    var activeAccountKey: String? { self.platform.tokenStorage.activeAccount }

    /// Tokens held under one account key, or nil.
    func tokens(account key: String) -> OAuthTokens? {
        try? self.platform.tokenStorage.load(account: key)
    }

    /// The pre-accounts "default" item, while it is still there.
    func legacyTokens() -> OAuthTokens? {
        try? self.platform.tokenStorage.load(account: GitHubAccountKey.legacy)
    }

    /// Every per-account key in the Keychain. Throws when the Keychain can't be listed, which is
    /// not the same as having no accounts.
    func storedAccountKeys() throws -> [String] { try self.platform.tokenStorage.storedAccountKeys() }

    /// Moves the single pre-accounts item to its own key once the login is known. Copy, read back,
    /// then delete: a failure at any step leaves the legacy item, which still signs in. Returns
    /// the account when it migrated.
    func migrateLegacyTokens(login: String, host: URL) -> GitHubAccount? {
        let storage = self.platform.tokenStorage
        guard let legacy = try? storage.load(account: GitHubAccountKey.legacy),
              let key = storage.migrateLegacyAccount(login: login, host: host) else { return nil }
        self.bound = .account(key)
        self.migratedLegacyKey = key
        self.lastHost = host
        self.cachedTokens = legacy
        self.hasLoadedTokens = true
        return GitHubAccount(login: login, host: host.host ?? "github.com", kind: legacy.kind)
    }

    /// Drops the pre-accounts item and its OAuth app credentials: a fresh sign-in replaced it.
    func removeLegacyItem() {
        self.platform.tokenStorage.remove(account: GitHubAccountKey.legacy)
    }

    /// The host the refresher posts to, so a relaunch on a GitHub Enterprise account refreshes
    /// against that host from the first request.
    func useHost(_ host: URL) { self.lastHost = host }

    /// Removes one account's tokens. When it was the active one nothing is active afterwards and
    /// the cached tokens are gone; `activate` another to carry on.
    func removeAccount(_ key: String) {
        let storage = self.platform.tokenStorage
        storage.remove(account: key)
        if self.bound == .account(key) { self.bound = .unbound }
        if storage.activeAccount == key {
            try? storage.setActiveAccount(nil)
            self.cachedTokens = nil
            self.hasLoadedTokens = true
        }
    }

    /// How the signed-in GitHub account got its token, or nil when signed out.
    var authKind: GitHubAuthKind? { self.loadTokens()?.kind }

    /// Signs out of everything: every account, the staging slot, the legacy item and the OAuth
    /// app credentials.
    func logout() async {
        self.platform.tokenStorage.clear()
        self.bound = .unbound
        self.cachedTokens = nil
        self.hasLoadedTokens = false
        await DiagnosticsLogger.shared.message("Logged out; tokens cleared from platform storage.")
    }

    /// The binding, made at first use from the Keychain's pointer and kept after that.
    private func currentBinding() -> Bound {
        if self.bound == .unbound {
            self.bound = self.activeAccountKey.map { .account($0) } ?? .legacy
        }
        return self.bound
    }

    func loadTokens() -> OAuthTokens? {
        if self.hasLoadedTokens { return self.cachedTokens }
        self.hasLoadedTokens = true
        let tokens = try? self.platform.tokenStorage.load(account: self.currentBinding().item ?? GitHubAccountKey.legacy)
        self.cachedTokens = tokens
        return tokens
    }

    func refreshIfNeeded() async throws -> OAuthTokens? {
        let signpost = self.signposter.beginInterval("refreshIfNeeded")
        defer { self.signposter.endInterval("refreshIfNeeded", signpost) }
        if let tokens = self.cachedTokens, tokens.expiresAt.map({ $0 > Date().addingTimeInterval(60) }) != false {
            return tokens
        }
        // Bound to the account this app shows, not to the Keychain's pointer: `harborcli` may have
        // moved that, and the other account's token must never be used under this account's name
        // (the next reconcile brings the difference to the surface). If the user switches in the
        // app meanwhile, the refreshed tokens are written to the account the refresh began for and
        // never to the new one. While only the legacy item exists, it is bound to its own key.
        let began = self.currentBinding()
        let storage: SecureTokenStorage = ScopedTokenStorage(self.platform.tokenStorage, account: began.item ?? GitHubAccountKey.legacy)
        let host = self.lastHost
        let load = self.refreshLoadOverride ?? { request in try await HarborURLSession.shared.data(for: request) }
        let refreshed = try await OAuthTokenRefresher(tokenStorage: storage, load: load).refreshIfNeeded(host: host)
        // After a switch the old account's tokens still go to the request that asked; the epoch drops its result.
        if let refreshed {
            if self.bound == began {
                self.cachedTokens = refreshed
                self.hasLoadedTokens = true
            } else if began == .legacy {
                self.settleLegacyRefresh(refreshed)
            }
        }
        return refreshed
    }

    /// A refresh of the pre-accounts item finished after the item had moved on. The refresher wrote
    /// to the legacy key, which re-created it. When that item became an account (migration) its
    /// own item still holds the spent refresh token: the new tokens go there. Either way the
    /// re-created legacy item goes, so nothing stale is left that a later launch could read.
    private func settleLegacyRefresh(_ refreshed: OAuthTokens) {
        let storage = self.platform.tokenStorage
        if let key = self.migratedLegacyKey, self.bound == .account(key) {
            try? storage.save(tokens: refreshed, account: key)
            self.cachedTokens = refreshed
            self.hasLoadedTokens = true
        }
        storage.remove(account: GitHubAccountKey.legacy)
    }

    // MARK: - Installation token

    // Installation flow removed: this app now uses user OAuth only.

    // PEM resolution removed; GitHub App installation tokens are not used.
}
