import Foundation
@testable import Harbor
@testable import HarborCore
import Testing

/// The Keychain side of several accounts, through the app's own paths: per-account OAuth app
/// credentials, the refresher's account binding, the launch reconcile, and the legacy item.
/// In-memory secret stores, ephemeral defaults and stubbed HTTP only.
@MainActor
struct AccountKeychainTests {
    private static let github = URL(string: "https://github.com")!
    private static let aliceKey = "github:alice@github.com"
    private static let bobKey = "github:bob@github.com"
    private static let carolKey = "github:carol@github.com"
    private static let alice = OAuthTokens(accessToken: "gho_TESTONLYalice-access", refreshToken: "ghr_TESTONLYalice-refresh", expiresAt: .distantPast)
    private static let bob = OAuthTokens(accessToken: "gho_TESTONLYbob-access", refreshToken: "", expiresAt: nil)
    private static let carol = OAuthTokens(accessToken: "gho_TESTONLYcarol-access", refreshToken: "", expiresAt: nil)

    private struct Harness {
        let state: AppState
        let storage: KeychainTokenStorage
        let defaults: UserDefaults
        let suite: String
    }

    /// `seed` runs before the app starts, as state left by an earlier run.
    private func harness(
        store: SecretStore = InMemorySecretStore(),
        seed: (KeychainTokenStorage, SettingsStore) throws -> Void = { _, _ in }
    ) async throws -> Harness {
        let suite = "harbor.tests.keychain.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let storage = KeychainTokenStorage(service: "com.sriinnu.harbor.auth", store: store)
        let settings = SettingsStore(defaults: defaults)
        try seed(storage, settings)
        let state = AppState(platform: MockPlatformServices(tokenStorage: storage), settingsStore: settings)
        for _ in 0 ..< 200 where state.refreshTask == nil { try? await Task.sleep(for: .milliseconds(5)) }
        await state.refreshTask?.value
        await state.menuRefreshTask?.value
        return Harness(state: state, storage: storage, defaults: defaults, suite: suite)
    }

    private func finish(_ harness: Harness) { harness.defaults.removePersistentDomain(forName: harness.suite) }

    private func accounts(_ keys: String...) -> GitHubAccountIndex {
        var index = GitHubAccountIndex()
        for key in keys {
            let named = GitHubAccountKey.parse(key)!
            index.upsert(GitHubAccount(login: named.login, host: named.host, kind: .oauth))
        }
        return index
    }

    private func response(_ request: URLRequest, _ body: String, status: Int = 200) -> (Data, URLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    /// Bob signs in with Harbor's built-in client: the real device flow code, stubbed HTTP, staged
    /// where the app stages it.
    private func deviceFlowSignIn(_ h: Harness, token: String) async throws -> OAuthTokens {
        let flow = OAuthDeviceFlow(
            tokenStorage: ScopedTokenStorage(h.storage, account: GitHubAccountKey.staging),
            dataProvider: { request in
                let body = request.url?.path.hasSuffix("/device/code") == true
                    ? #"{"device_code":"dev","user_code":"ABCD-1234","verification_uri":"https://github.com/login/device","expires_in":900,"interval":1}"#
                    : #"{"access_token":"\#(token)","token_type":"bearer","scope":"repo"}"#
                return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            sleep: { _ in }
        )
        let authorization = try await flow.start(clientID: "harbor-builtin", host: Self.github)
        return try await flow.poll(authorization, clientID: "harbor-builtin", host: Self.github)
    }

    // MARK: M1

    @Test
    func addingBobByDeviceFlowKeepsAlicesOwnOAuthAppRefreshing() async throws {
        let h = try await self.harness()
        defer { self.finish(h) }
        try h.storage.save(tokens: Self.alice, account: Self.aliceKey)
        try h.storage.save(clientCredentials: OAuthClientCredentials(clientID: "alice-app", clientSecret: "alice-secret"), account: Self.aliceKey)
        try h.state.auth.activate(Self.aliceKey, host: Self.github)
        h.state.session.settings.githubAccounts = self.accounts(Self.aliceKey)
        h.state.session.settings.githubAccounts.active = Self.aliceKey
        h.state.accountSignedIn(UserIdentity(username: "alice", host: Self.github))
        h.state.dataOwner = "alice"
        // The add runs beside alice: her account must still refresh with her own app afterwards.
        h.state.session.isAddingAccount = true
        h.state.auth.identifyOverride = { _, _ in "bob" }
        let bobTokens = try await self.deviceFlowSignIn(h, token: Self.bob.accessToken)
        #expect(await h.state.completeSignIn(login: "bob", host: Self.github, tokens: bobTokens, refreshAfter: false) == nil)
        h.state.session.isAddingAccount = false

        #expect(try h.storage.loadClientCredentials(account: Self.aliceKey) == OAuthClientCredentials(clientID: "alice-app", clientSecret: "alice-secret"))
        #expect(try h.storage.loadClientCredentials(account: Self.bobKey) == OAuthClientCredentials(clientID: "harbor-builtin", clientSecret: ""))

        // Back on alice, whose token has expired.
        h.state.session.settings.githubAccounts.active = Self.aliceKey
        try h.state.auth.activate(Self.aliceKey, host: Self.github)
        let posted = PostedBodies()
        h.state.auth.refreshLoadOverride = { request in
            posted.add(String(bytes: request.httpBody ?? Data(), encoding: .utf8) ?? "")
            let body = #"{"access_token":"gho_TESTONLYalice-new","token_type":"bearer","scope":"repo","expires_in":3600,"refresh_token":"ghr_TESTONLYalice-refresh2"}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let refreshed = try await h.state.auth.refreshIfNeeded()
        #expect(refreshed?.accessToken == "gho_TESTONLYalice-new")
        #expect(posted.bodies.count == 1)
        #expect(posted.bodies.first?.contains("client_id=alice-app") == true)
        #expect(posted.bodies.first?.contains("client_secret=alice-secret") == true)
    }

    // MARK: refresher binding (S3)

    private final class PostedBodies: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String] = []
        var bodies: [String] { self.lock.withLock { self.stored } }
        func add(_ body: String) { self.lock.withLock { self.stored.append(body) } }
    }

    private let refreshed = #"{"access_token":"gho_TESTONLYrefreshed","token_type":"bearer","scope":"repo","expires_in":3600,"refresh_token":"ghr_TESTONLYrefreshed2"}"#

    @Test
    func aRefreshForAliceFinishingAfterASwitchWritesToAlicesItemOnly() async throws {
        let h = try await self.harness()
        defer { self.finish(h) }
        try h.storage.save(tokens: Self.alice, account: Self.aliceKey)
        try h.storage.save(clientCredentials: OAuthClientCredentials(clientID: "alice-app", clientSecret: "alice-secret"), account: Self.aliceKey)
        try h.storage.save(tokens: Self.bob, account: Self.bobKey)
        try h.state.auth.activate(Self.aliceKey, host: Self.github)
        let storage = h.storage
        let body = self.refreshed
        let bobKey = Self.bobKey
        h.state.auth.refreshLoadOverride = { request in
            // The user switches to bob while alice's refresh is in flight.
            try storage.setActiveAccount(bobKey)
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        _ = try await h.state.auth.refreshIfNeeded()

        #expect(try h.storage.load(account: Self.aliceKey)?.accessToken == "gho_TESTONLYrefreshed")
        #expect(try h.storage.load(account: Self.bobKey) == Self.bob)
        #expect(h.storage.activeAccount == Self.bobKey)
    }

    @Test
    func aRefreshOfTheLegacyItemFinishingAfterASwitchStaysOnTheLegacyItem() async throws {
        let h = try await self.harness()
        defer { self.finish(h) }
        try h.storage.save(tokens: Self.alice, account: GitHubAccountKey.legacy)
        try h.storage.save(clientCredentials: OAuthClientCredentials(clientID: "alice-app", clientSecret: "alice-secret"), account: GitHubAccountKey.legacy)
        try h.storage.save(tokens: Self.bob, account: Self.bobKey)
        let storage = h.storage
        let body = self.refreshed
        let bobKey = Self.bobKey
        h.state.auth.refreshLoadOverride = { request in
            try storage.setActiveAccount(bobKey)
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        _ = try await h.state.auth.refreshIfNeeded()

        #expect(try h.storage.load(account: GitHubAccountKey.legacy)?.accessToken == "gho_TESTONLYrefreshed")
        #expect(try h.storage.load(account: Self.bobKey) == Self.bob)
    }

    // MARK: launch reconcile (S1)

    @Test
    func aKeychainThatCannotBeListLeavesTheIndexAlone() async throws {
        let store = UnlistableStore()
        let h = try await self.harness(store: store) { storage, settings in
            try storage.save(tokens: Self.alice, account: Self.aliceKey)
            try storage.save(tokens: Self.bob, account: Self.bobKey)
            try storage.setActiveAccount(Self.aliceKey)
            var saved = UserSettings()
            saved.githubAccounts = self.accounts(Self.aliceKey, Self.bobKey)
            saved.githubAccounts.active = Self.aliceKey
            settings.save(saved)
        }
        defer { self.finish(h) }

        // Launch ran the reconcile against a Keychain that refused to list.
        #expect(h.state.session.settings.githubAccounts.accounts.map(\.id) == [Self.aliceKey, Self.bobKey])
        #expect(h.state.session.settings.githubAccounts.active == Self.aliceKey)
        #expect(SettingsStore(defaults: h.defaults).load().githubAccounts.accounts.map(\.id) == [Self.aliceKey, Self.bobKey])
        #expect(try h.storage.load(account: Self.bobKey) == Self.bob)
    }

    @Test
    func accountsInTheKeychainButNotTheIndexAreAddedAndGoneOnesLeave() async throws {
        let h = try await self.harness { storage, settings in
            // `harborcli` stored alice and bob; the app's settings only know a carol whose token is gone.
            try storage.save(tokens: Self.alice, account: Self.aliceKey)
            try storage.save(tokens: Self.bob, account: Self.bobKey)
            try storage.setActiveAccount(Self.bobKey)
            var saved = UserSettings()
            saved.githubAccounts = self.accounts(Self.carolKey)
            saved.githubAccounts.active = Self.carolKey
            settings.save(saved)
        }
        defer { self.finish(h) }

        #expect(h.state.session.settings.githubAccounts.accounts == [
            GitHubAccount(login: "alice", host: "github.com", kind: .oauth),
            GitHubAccount(login: "bob", host: "github.com", kind: .oauth)
        ])
        #expect(h.state.session.settings.githubAccounts.active == Self.bobKey)
        #expect(SettingsStore(defaults: h.defaults).load().githubAccounts.active == Self.bobKey)
    }

    // MARK: legacy item (S2)

    @Test
    func addingAnAccountWhileTheLegacyItemCannotBeNamedChangesNothing() async throws {
        let h = try await self.harness()
        defer { self.finish(h) }
        try h.storage.save(tokens: Self.alice, account: GitHubAccountKey.legacy)
        h.state.auth.identifyOverride = { _, _ in throw URLError(.notConnectedToInternet) }
        h.state.session.isAddingAccount = true
        try h.storage.save(tokens: Self.bob, account: GitHubAccountKey.staging)

        let message = await h.state.completeSignIn(login: "bob", host: Self.github, tokens: Self.bob, refreshAfter: false)
        #expect(message == "Harbor couldn't confirm your current sign-in just now, so it can't add another account yet. Check your connection and try again.")
        #expect(try h.storage.load(account: GitHubAccountKey.legacy) == Self.alice)
        #expect(try h.storage.load(account: GitHubAccountKey.staging) == nil)
        #expect(try h.storage.load(account: Self.bobKey) == nil)
        #expect(h.storage.activeAccount == nil)
        #expect(h.state.session.settings.githubAccounts == GitHubAccountIndex())
    }

    @Test
    func aPrimarySignInReplacesALegacyItemThatCannotBeNamed() async throws {
        let h = try await self.harness()
        defer { self.finish(h) }
        try h.storage.save(tokens: Self.alice, account: GitHubAccountKey.legacy)
        h.state.auth.identifyOverride = { _, _ in throw URLError(.notConnectedToInternet) }
        try h.storage.save(tokens: Self.bob, account: GitHubAccountKey.staging)

        let message = await h.state.completeSignIn(login: "bob", host: Self.github, tokens: Self.bob, refreshAfter: false)
        #expect(message == nil)
        #expect(try h.storage.load(account: GitHubAccountKey.legacy) == nil)
        #expect(h.storage.activeAccount == Self.bobKey)
        #expect(h.state.session.settings.githubAccounts.accounts.map(\.id) == [Self.bobKey])
    }

    // MARK: pasted token beside a legacy item (N5)

    @Test
    func aTokenPastedWhileAnAccountIsOnScreenWaitsForALegacyItemThatCannotBeNamed() async throws {
        // A Keychain that refuses the active pointer: the legacy item can't be moved to its own key.
        let h = try await self.harness(store: PointerRefusingStore()) { storage, _ in
            try storage.save(tokens: Self.alice, account: GitHubAccountKey.legacy)
        }
        defer { self.finish(h) }
        h.state.session.account = .loggedIn(UserIdentity(username: "alice", host: Self.github))
        let validator = GitHubTokenValidator { request in
            (Data(#"{"login":"bob"}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["X-OAuth-Scopes": "repo, read:org"])!)
        }
        let message = await h.state.signInWithToken("ghp_TESTONLYpastedbob0123456789", validator: validator, refreshAfter: false)
        #expect(message == "Harbor couldn't confirm your current sign-in just now, so it can't add another account yet. Check your connection and try again.")
        #expect(try h.storage.load(account: GitHubAccountKey.legacy) == Self.alice)
        #expect(try h.storage.load(account: GitHubAccountKey.staging) == nil)
        #expect(try h.storage.load(account: Self.bobKey) == nil)
    }

    // MARK: pointer moved by harborcli (N1)

    @Test
    func aPointerMovedByTheCLIDoesNotSwapTheTokenUnderTheAccountOnScreen() async throws {
        let h = try await self.harness()
        defer { self.finish(h) }
        try h.storage.save(tokens: Self.alice, account: Self.aliceKey)
        try h.storage.save(clientCredentials: OAuthClientCredentials(clientID: "alice-app", clientSecret: "alice-secret"), account: Self.aliceKey)
        try h.storage.save(tokens: Self.bob, account: Self.bobKey)
        try h.state.auth.activate(Self.aliceKey, host: Self.github)
        // `harborcli login` on bob's account, with activation, while the app runs on alice.
        try h.storage.setActiveAccount(Self.bobKey)
        let posted = PostedBodies()
        h.state.auth.refreshLoadOverride = { request in
            posted.add(String(bytes: request.httpBody ?? Data(), encoding: .utf8) ?? "")
            return (Data(#"{"access_token":"gho_TESTONLYalice-new","token_type":"bearer","scope":"repo","expires_in":3600,"refresh_token":"ghr_TESTONLYalice-refresh2"}"#.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        // Alice's token has expired: the refresh is hers, with her app's credentials.
        let refreshed = try await h.state.auth.refreshIfNeeded()
        #expect(refreshed?.accessToken == "gho_TESTONLYalice-new")
        #expect(posted.bodies.count == 1)
        #expect(posted.bodies.first?.contains("client_id=alice-app") == true)
        #expect(h.state.auth.loadTokens()?.accessToken == "gho_TESTONLYalice-new")
        #expect(try h.storage.load(account: Self.aliceKey)?.accessToken == "gho_TESTONLYalice-new")
        #expect(try h.storage.load(account: Self.bobKey) == Self.bob)
        #expect(h.storage.activeAccount == Self.bobKey) // the CLI's pointer is left for reconcile to surface
    }

    // MARK: legacy refresh racing migration (N6)

    @Test
    func aLegacyRefreshFinishingAfterMigrationLandsOnTheAccountsOwnItem() async throws {
        let h = try await self.harness()
        defer { self.finish(h) }
        try h.storage.save(tokens: Self.alice, account: GitHubAccountKey.legacy)
        try h.storage.save(clientCredentials: OAuthClientCredentials(clientID: "alice-app", clientSecret: "alice-secret"), account: GitHubAccountKey.legacy)
        let auth = h.state.auth
        let body = self.refreshed
        h.state.auth.refreshLoadOverride = { request in
            // The login becomes known and the legacy item moves while the refresh is in flight.
            await MainActor.run { _ = auth.migrateLegacyTokens(login: "alice", host: Self.github) }
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        _ = try await h.state.auth.refreshIfNeeded()

        #expect(h.storage.activeAccount == Self.aliceKey)
        #expect(try h.storage.load(account: Self.aliceKey)?.accessToken == "gho_TESTONLYrefreshed")
        #expect(try h.storage.load(account: Self.aliceKey)?.refreshToken == "ghr_TESTONLYrefreshed2")
        #expect(try h.storage.load(account: GitHubAccountKey.legacy) == nil)
        #expect(h.state.auth.loadTokens()?.accessToken == "gho_TESTONLYrefreshed")
    }

    // MARK: removing the active account (nit)

    @Test
    func removingTheActiveAccountSkipsANextAccountWhoseTokenIsGone() async throws {
        let h = try await self.harness()
        defer { self.finish(h) }
        try h.storage.save(tokens: Self.alice, account: Self.aliceKey)
        try h.storage.save(tokens: Self.carol, account: Self.carolKey)
        try h.state.auth.activate(Self.aliceKey, host: Self.github)
        // Bob is listed first among the others, but his token is gone from the Keychain.
        h.state.session.settings.githubAccounts = self.accounts(Self.aliceKey, Self.bobKey, Self.carolKey)
        h.state.session.settings.githubAccounts.active = Self.aliceKey
        h.state.accountSignedIn(UserIdentity(username: "alice", host: Self.github))

        await h.state.removeGitHubAccount(Self.aliceKey, refreshAfter: false)
        #expect(h.storage.activeAccount == Self.carolKey)
        #expect(h.state.session.settings.githubAccounts.active == Self.carolKey)
        #expect(h.state.session.settings.githubAccounts.accounts.map(\.id) == [Self.carolKey])
        #expect(try h.storage.load(account: Self.aliceKey) == nil)
    }
}

/// A Keychain that refuses to write the active-account pointer, so nothing can be activated or migrated.
private struct PointerRefusingStore: SecretStore {
    private let inner = InMemorySecretStore()
    func data(service: String, account: String) throws -> Data? { try self.inner.data(service: service, account: account) }
    func set(_ data: Data, service: String, account: String, label: String?) throws {
        guard account != GitHubAccountKey.activePointer else { throw TokenStoreError.saveFailed }
        try self.inner.set(data, service: service, account: account, label: label)
    }
    func remove(service: String, account: String) throws { try self.inner.remove(service: service, account: account) }
    func accounts(service: String) throws -> [String] { try self.inner.accounts(service: service) }
}

/// A Keychain that works but cannot be listed: locked, or the prompt was denied.
private struct UnlistableStore: SecretStore {
    private let inner = InMemorySecretStore()
    func data(service: String, account: String) throws -> Data? { try self.inner.data(service: service, account: account) }
    func set(_ data: Data, service: String, account: String, label: String?) throws {
        try self.inner.set(data, service: service, account: account, label: label)
    }
    func remove(service: String, account: String) throws { try self.inner.remove(service: service, account: account) }
    func accounts(service _: String) throws -> [String] { throw TokenStoreError.loadFailed }
}
