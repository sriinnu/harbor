import Foundation
@testable import HarborCore
import Testing

/// Per-account OAuth app credentials, and the sign-in/sign-out `harborcli` shares with the app.
/// In-memory stores and stubbed HTTP only; never the real Keychain, network or `~/.config`.
struct GitHubAccountSignInTests {
    private static let github = URL(string: "https://github.com")!
    private static let aliceKey = "github:alice@github.com"
    private static let bobKey = "github:bob@github.com"
    private static let aliceToken = "gho_TESTONLYalice-access"
    private static let bobToken = "gho_TESTONLYbob-access"
    /// Alice signed in through her own OAuth app: expiring token, refresh token, client secret.
    private static let alice = OAuthTokens(accessToken: aliceToken, refreshToken: "ghr_TESTONLYalice-refresh", expiresAt: .distantPast)
    private static let bob = OAuthTokens(accessToken: bobToken, refreshToken: "", expiresAt: nil)

    private final class Capture: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String] = []
        var bodies: [String] { self.lock.withLock { self.stored } }
        func add(_ body: String) { self.lock.withLock { self.stored.append(body) } }
    }

    private func storage() -> KeychainTokenStorage {
        KeychainTokenStorage(service: "com.sriinnu.harbor.auth", store: InMemorySecretStore())
    }

    private func staging(_ storage: SecureTokenStorage) -> ScopedTokenStorage {
        ScopedTokenStorage(storage, account: GitHubAccountKey.staging)
    }

    private func signInAlice(_ storage: KeychainTokenStorage) async throws {
        try self.staging(storage).save(tokens: Self.alice)
        try self.staging(storage).save(clientCredentials: OAuthClientCredentials(clientID: "alice-app", clientSecret: "alice-secret"))
        _ = try await GitHubAccountSignIn.finish(
            tokens: Self.alice, host: Self.github, storage: storage, activate: true, identify: { _, _ in "alice" }
        )
    }

    private func refresher(_ storage: SecureTokenStorage, capture: Capture) -> OAuthTokenRefresher {
        OAuthTokenRefresher(tokenStorage: storage) { request in
            capture.add(String(bytes: request.httpBody ?? Data(), encoding: .utf8) ?? "")
            let body = #"{"access_token":"gho_TESTONLYalice-new","token_type":"bearer","scope":"repo","expires_in":3600,"refresh_token":"ghr_TESTONLYalice-refresh2"}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    // MARK: M1: the OAuth app credentials belong to their account

    @Test
    func aDeviceFlowSignInForBobLeavesAlicesOAuthAppAlone() async throws {
        let storage = self.storage()
        try await self.signInAlice(storage)

        // Bob signs in with the built-in client: the device flow saves an empty secret.
        try self.staging(storage).save(tokens: Self.bob)
        try self.staging(storage).save(clientCredentials: OAuthClientCredentials(clientID: "harbor-builtin", clientSecret: ""))
        _ = try await GitHubAccountSignIn.finish(
            tokens: Self.bob, host: Self.github, storage: storage, activate: false, identify: { _, _ in "bob" }
        )

        #expect(try storage.loadClientCredentials(account: Self.aliceKey) == OAuthClientCredentials(clientID: "alice-app", clientSecret: "alice-secret"))
        #expect(try storage.loadClientCredentials(account: Self.bobKey) == OAuthClientCredentials(clientID: "harbor-builtin", clientSecret: ""))

        // Alice's token has expired: her refresh still goes out with her own app's secret.
        let capture = Capture()
        let refreshed = try await self.refresher(ScopedTokenStorage(storage, account: Self.aliceKey), capture: capture)
            .refreshIfNeeded(host: Self.github)
        #expect(refreshed?.accessToken == "gho_TESTONLYalice-new")
        #expect(capture.bodies.count == 1)
        #expect(capture.bodies.first?.contains("client_id=alice-app") == true)
        #expect(capture.bodies.first?.contains("client_secret=alice-secret") == true)
        #expect(capture.bodies.first?.contains("refresh_token=ghr_TESTONLYalice-refresh") == true)
    }

    @Test
    func aSecondCustomAppDoesNotReplaceTheFirstOnesSecret() async throws {
        let storage = self.storage()
        try await self.signInAlice(storage)
        try self.staging(storage).save(tokens: Self.bob)
        try self.staging(storage).save(clientCredentials: OAuthClientCredentials(clientID: "bob-app", clientSecret: "bob-secret"))
        _ = try await GitHubAccountSignIn.finish(
            tokens: Self.bob, host: Self.github, storage: storage, activate: false, identify: { _, _ in "bob" }
        )
        #expect(try storage.loadClientCredentials(account: Self.aliceKey)?.clientSecret == "alice-secret")
        #expect(try storage.loadClientCredentials(account: Self.bobKey)?.clientSecret == "bob-secret")
    }

    @Test
    func aSignInThatCannotBeIdentifiedWritesNoAccountsCredentials() async throws {
        let storage = self.storage()
        try await self.signInAlice(storage)
        try self.staging(storage).save(tokens: Self.bob)
        try self.staging(storage).save(clientCredentials: OAuthClientCredentials(clientID: "harbor-builtin", clientSecret: ""))

        await #expect(throws: GitHubTokenError.rejected) {
            _ = try await GitHubAccountSignIn.finish(
                tokens: Self.bob, host: Self.github, storage: storage, activate: true, identify: { _, _ in throw GitHubTokenError.rejected }
            )
        }
        #expect(try storage.loadClientCredentials(account: Self.aliceKey)?.clientSecret == "alice-secret")
        #expect(try storage.load(account: GitHubAccountKey.staging) == nil)
        #expect(try storage.loadClientCredentials(account: GitHubAccountKey.staging) == nil)
        #expect(try storage.storedAccountKeys() == [Self.aliceKey])
        #expect(storage.activeAccount == Self.aliceKey)
    }

    @Test
    func removingAnAccountRemovesItsOAuthAppCredentialsOnly() async throws {
        let storage = self.storage()
        try await self.signInAlice(storage)
        try self.staging(storage).save(tokens: Self.bob)
        try self.staging(storage).save(clientCredentials: OAuthClientCredentials(clientID: "bob-app", clientSecret: "bob-secret"))
        _ = try await GitHubAccountSignIn.finish(
            tokens: Self.bob, host: Self.github, storage: storage, activate: false, identify: { _, _ in "bob" }
        )
        storage.remove(account: Self.bobKey)
        #expect(try storage.loadClientCredentials(account: Self.bobKey) == nil)
        #expect(try storage.loadClientCredentials(account: Self.aliceKey)?.clientSecret == "alice-secret")
        storage.clear()
        #expect(try storage.loadClientCredentials(account: Self.aliceKey) == nil)
    }

    @Test
    func theLegacyItemKeepsItsOAuthAppWhenItMigrates() throws {
        let storage = self.storage()
        try storage.save(tokens: Self.alice, account: GitHubAccountKey.legacy)
        try storage.save(clientCredentials: OAuthClientCredentials(clientID: "alice-app", clientSecret: "alice-secret"), account: GitHubAccountKey.legacy)

        #expect(storage.migrateLegacyAccount(login: "alice", host: Self.github) == Self.aliceKey)
        #expect(try storage.load(account: GitHubAccountKey.legacy) == nil)
        #expect(try storage.loadClientCredentials(account: GitHubAccountKey.legacy) == nil)
        #expect(try storage.loadClientCredentials(account: Self.aliceKey)?.clientSecret == "alice-secret")
        #expect(storage.activeAccount == Self.aliceKey)
    }

    // MARK: M2: harborcli sign-in and sign-out know about accounts

    @Test
    func aCLISignInAsBobDoesNotTouchAlicesTokenOrThePointer() async throws {
        let storage = self.storage()
        try await self.signInAlice(storage)
        try self.staging(storage).save(tokens: Self.bob)

        let outcome = try await GitHubAccountSignIn.finish(
            tokens: Self.bob, host: Self.github, storage: storage, activate: false, identify: { _, _ in "Bob" }
        )
        #expect(outcome == GitHubSignInOutcome(login: "Bob", key: Self.bobKey, activated: false, legacyBlockedActivation: false))
        #expect(storage.activeAccount == Self.aliceKey)
        #expect(try storage.load() == Self.alice)
        #expect(try storage.load(account: Self.bobKey) == Self.bob)
        #expect(try storage.load(account: GitHubAccountKey.staging) == nil)
        #expect(try storage.storedAccountKeys() == [Self.aliceKey, Self.bobKey])
    }

    @Test
    func activateSwitchesThePointerAndTheFirstAccountIsActiveByDefault() async throws {
        let storage = self.storage()
        try self.staging(storage).save(tokens: Self.alice)
        let first = try await GitHubAccountSignIn.finish(
            tokens: Self.alice, host: Self.github, storage: storage, activate: false, identify: { _, _ in "alice" }
        )
        #expect(first.activated)
        #expect(storage.activeAccount == Self.aliceKey)

        try self.staging(storage).save(tokens: Self.bob)
        let second = try await GitHubAccountSignIn.finish(
            tokens: Self.bob, host: Self.github, storage: storage, activate: true, identify: { _, _ in "bob" }
        )
        #expect(second.activated)
        #expect(storage.activeAccount == Self.bobKey)
        #expect(try storage.load() == Self.bob)
    }

    @Test
    func aLiveLegacyItemIsNeverHiddenByActivatingAnotherAccount() async throws {
        let storage = self.storage()
        try storage.save(tokens: Self.alice, account: GitHubAccountKey.legacy)
        try self.staging(storage).save(tokens: Self.bob)

        let outcome = try await GitHubAccountSignIn.finish(
            tokens: Self.bob, host: Self.github, storage: storage, activate: true, identify: { _, _ in "bob" }
        )
        #expect(outcome == GitHubSignInOutcome(login: "bob", key: Self.bobKey, activated: false, legacyBlockedActivation: true))
        #expect(storage.activeAccount == nil)
        #expect(try storage.load() == Self.alice) // still the legacy item
    }

    @Test
    func aKeychainThatCannotBeListNeverGrabsThePointer() async throws {
        let storage = KeychainTokenStorage(service: "s", store: ListingFailsStore())
        try self.staging(storage).save(tokens: Self.bob)
        let outcome = try await GitHubAccountSignIn.finish(
            tokens: Self.bob, host: Self.github, storage: storage, activate: false, identify: { _, _ in "bob" }
        )
        #expect(outcome.activated == false)
        #expect(storage.activeAccount == nil)
    }

    @Test
    func signOutRemovesOnlyTheActiveAccountAndPassesThePointerOn() async throws {
        let storage = self.storage()
        try await self.signInAlice(storage)
        try self.staging(storage).save(tokens: Self.bob)
        _ = try await GitHubAccountSignIn.finish(
            tokens: Self.bob, host: Self.github, storage: storage, activate: false, identify: { _, _ in "bob" }
        )

        let outcome = GitHubAccountSignIn.signOut(storage: storage, all: false)
        #expect(outcome == .account(key: Self.aliceKey, next: Self.bobKey))
        #expect(try storage.load(account: Self.aliceKey) == nil)
        #expect(try storage.loadClientCredentials(account: Self.aliceKey) == nil)
        #expect(try storage.load(account: Self.bobKey) == Self.bob)
        #expect(storage.activeAccount == Self.bobKey)

        #expect(GitHubAccountSignIn.signOut(storage: storage, all: false) == .account(key: Self.bobKey, next: nil))
        #expect(storage.activeAccount == nil)
        #expect(GitHubAccountSignIn.signOut(storage: storage, all: false) == .nobodyActive(stored: 0))
    }

    @Test
    func signOutAllRemovesEveryAccount() async throws {
        let storage = self.storage()
        try await self.signInAlice(storage)
        try self.staging(storage).save(tokens: Self.bob)
        _ = try await GitHubAccountSignIn.finish(
            tokens: Self.bob, host: Self.github, storage: storage, activate: false, identify: { _, _ in "bob" }
        )
        #expect(GitHubAccountSignIn.signOut(storage: storage, all: true) == .everything)
        #expect(try storage.storedAccountKeys() == [])
        #expect(storage.activeAccount == nil)
    }

    @Test
    func signOutWithOnlyTheLegacyItemRemovesIt() throws {
        let storage = self.storage()
        try storage.save(tokens: Self.alice, account: GitHubAccountKey.legacy)
        #expect(GitHubAccountSignIn.signOut(storage: storage, all: false) == .legacyItem)
        #expect(try storage.load() == nil)
    }

    // MARK: the account set is readable from the Keychain alone

    @Test
    func aKeyNamesItsLoginAndHost() {
        let parsed = GitHubAccountKey.parse("github:alice@ghe.example.com")
        #expect(parsed?.login == "alice")
        #expect(parsed?.host == "ghe.example.com")
        #expect(GitHubAccountKey.parse("pending") == nil)
        #expect(GitHubAccountKey.parse("client:github:alice@github.com") == nil)
        #expect(GitHubAccountKey.parse("github:@github.com") == nil)
    }

    @Test
    func listingFailureIsAnErrorNotAnEmptyList() {
        let storage = KeychainTokenStorage(service: "s", store: ListingFailsStore())
        #expect(throws: TokenStoreError.loadFailed) { _ = try storage.storedAccountKeys() }
    }
}

/// A Keychain that works but cannot be listed: locked, or the prompt was denied.
struct ListingFailsStore: SecretStore {
    private let inner = InMemorySecretStore()
    func data(service: String, account: String) throws -> Data? { try self.inner.data(service: service, account: account) }
    func set(_ data: Data, service: String, account: String, label: String?) throws {
        try self.inner.set(data, service: service, account: account, label: label)
    }
    func remove(service: String, account: String) throws { try self.inner.remove(service: service, account: account) }
    func accounts(service _: String) throws -> [String] { throw TokenStoreError.loadFailed }
}
