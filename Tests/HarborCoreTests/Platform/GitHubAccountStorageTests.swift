import Foundation
@testable import HarborCore
import Testing

/// Several GitHub accounts in one Keychain service: per-account keys, the active pointer, the
/// legacy "default" fallback, and the settings index. In-memory stores only; never the real Keychain.
struct GitHubAccountStorageTests {
    private static let service = "com.sriinnu.harbor.auth"
    private static let alice = OAuthTokens(accessToken: "ghp_TESTONLYalice0123456789", refreshToken: "", expiresAt: nil, kind: .personalAccessToken)
    private static let bob = OAuthTokens(accessToken: "gho_TESTONLYbob0123456789", refreshToken: "rb", expiresAt: nil)
    private static let aliceKey = "github:alice@github.com"
    private static let bobKey = "github:bob@github.com"

    private func storage() -> (KeychainTokenStorage, InMemorySecretStore) {
        let secrets = InMemorySecretStore()
        return (KeychainTokenStorage(service: Self.service, store: secrets), secrets)
    }

    @Test
    func keyIsLowercasedLoginAtHost() {
        #expect(GitHubAccountKey.make(login: "Alice", host: "GitHub.com") == "github:alice@github.com")
        #expect(GitHubAccountKey.make(login: "bob", host: URL(string: "https://ghe.example.com")!) == "github:bob@ghe.example.com")
        #expect(GitHubAccount(login: "Alice", host: "github.com", kind: .oauth).id == "github:alice@github.com")
    }

    @Test
    func loadAndSaveFollowTheActiveAccount() throws {
        let (storage, secrets) = self.storage()
        try storage.save(tokens: Self.alice, account: Self.aliceKey)
        try storage.save(tokens: Self.bob, account: Self.bobKey)
        try storage.setActiveAccount(Self.bobKey)
        #expect(try storage.load() == Self.bob)

        // A refresh writes through `save(tokens:)`: it lands on the active account, nowhere else.
        let refreshed = OAuthTokens(accessToken: "gho_TESTONLYbob-refreshed", refreshToken: "rb2", expiresAt: nil)
        try storage.save(tokens: refreshed)
        #expect(try storage.load(account: Self.bobKey) == refreshed)
        #expect(try storage.load(account: Self.aliceKey) == Self.alice)
        #expect(try secrets.data(service: Self.service, account: GitHubAccountKey.legacy) == nil)

        try storage.setActiveAccount(Self.aliceKey)
        #expect(try storage.load() == Self.alice)
    }

    @Test
    func withNoActiveAccountTheLegacyItemIsUsed_soTheCLIKeepsWorkingBeforeMigration() throws {
        let (storage, _) = self.storage()
        try storage.save(tokens: Self.alice) // what every older version wrote
        #expect(storage.activeAccount == nil)
        #expect(try storage.load(account: GitHubAccountKey.legacy) == Self.alice)
        #expect(try storage.load() == Self.alice)
        try storage.setActiveAccount(Self.bobKey)
        try storage.setActiveAccount(nil)
        #expect(try storage.load() == Self.alice)
    }

    @Test
    func activeAccountWithAMissingItemLoadsNothing_neverAnotherAccount() throws {
        let (storage, _) = self.storage()
        try storage.save(tokens: Self.alice, account: Self.aliceKey)
        try storage.setActiveAccount(Self.bobKey)
        #expect(try storage.load() == nil)
    }

    @Test
    func accountKeysListOnlyAccountItems() throws {
        let (storage, _) = self.storage()
        try storage.save(tokens: Self.alice) // legacy
        try storage.save(clientCredentials: OAuthClientCredentials(clientID: "cid", clientSecret: ""))
        try storage.save(tokens: Self.bob, account: Self.bobKey)
        try storage.save(tokens: Self.alice, account: Self.aliceKey)
        try storage.save(tokens: Self.alice, account: GitHubAccountKey.staging)
        try storage.setActiveAccount(Self.aliceKey)
        #expect(storage.accountKeys() == [Self.aliceKey, Self.bobKey])
    }

    @Test
    func clearRemovesEveryAccountThePointerTheLegacyItemAndTheStagingSlot() throws {
        let (storage, secrets) = self.storage()
        try storage.save(tokens: Self.alice)
        try storage.save(tokens: Self.alice, account: Self.aliceKey)
        try storage.save(tokens: Self.bob, account: GitHubAccountKey.staging)
        try storage.save(clientCredentials: OAuthClientCredentials(clientID: "cid", clientSecret: "s"), account: GitHubAccountKey.legacy)
        try storage.save(clientCredentials: OAuthClientCredentials(clientID: "cid", clientSecret: "s"), account: Self.aliceKey)
        try storage.save(clientCredentials: OAuthClientCredentials(clientID: "cid", clientSecret: "s"), account: GitHubAccountKey.staging)
        try storage.setActiveAccount(Self.aliceKey)
        storage.clear()
        #expect(try secrets.accounts(service: Self.service) == [])
    }

    @Test
    func stagingSlotIsSeparateFromTheActiveAccount() throws {
        let (storage, _) = self.storage()
        try storage.save(tokens: Self.alice, account: Self.aliceKey)
        try storage.setActiveAccount(Self.aliceKey)
        let staged = ScopedTokenStorage(storage, account: GitHubAccountKey.staging)
        try staged.save(tokens: Self.bob) // what a sign-in flow does
        #expect(try storage.load() == Self.alice)
        #expect(try staged.load() == Self.bob)
        staged.clear()
        #expect(try storage.load(account: GitHubAccountKey.staging) == nil)
        #expect(try storage.load() == Self.alice)
    }

    @Test
    func inMemoryStorageHasTheSameAccountBehaviour() throws {
        let storage = InMemoryTokenStorage()
        try storage.save(tokens: Self.alice, account: Self.aliceKey)
        try storage.save(tokens: Self.bob, account: Self.bobKey)
        try storage.setActiveAccount(Self.bobKey)
        #expect(try storage.load() == Self.bob)
        #expect(storage.accountKeys() == [Self.aliceKey, Self.bobKey])
        storage.remove(account: Self.bobKey)
        #expect(try storage.load() == nil)
        storage.clear()
        #expect(storage.accountKeys() == [])
        #expect(storage.activeAccount == nil)
    }

    @Test
    func aRefreshBoundToOneAccountNeverWritesToAnother() async throws {
        let (storage, _) = self.storage()
        let expiring = OAuthTokens(accessToken: "gho_TESTONLYalice-old", refreshToken: "r1", expiresAt: .distantPast)
        try storage.save(tokens: expiring, account: Self.aliceKey)
        try storage.save(tokens: Self.bob, account: Self.bobKey)
        try storage.save(clientCredentials: OAuthClientCredentials(clientID: "cid", clientSecret: "csecret"), account: Self.aliceKey)
        try storage.setActiveAccount(Self.aliceKey)

        // The refresh starts for alice; the user switches to bob while it is on the wire.
        let refresher = OAuthTokenRefresher(tokenStorage: ScopedTokenStorage(storage, account: Self.aliceKey)) { request in
            try? storage.setActiveAccount(Self.bobKey)
            let body = #"{"access_token":"gho_TESTONLYalice-new","token_type":"bearer","scope":"repo","expires_in":3600,"refresh_token":"r2"}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let refreshed = try await refresher.refreshIfNeeded(host: HarborAuthDefaults.githubHost)
        #expect(refreshed?.accessToken == "gho_TESTONLYalice-new")
        #expect(try storage.load(account: Self.aliceKey)?.accessToken == "gho_TESTONLYalice-new")
        #expect(try storage.load(account: Self.bobKey) == Self.bob)
        #expect(try storage.load() == Self.bob)
    }

    // MARK: index

    @Test
    func indexUpsertKeepsPlaceAndRemovingTheActiveOneClearsIt() {
        var index = GitHubAccountIndex()
        index.upsert(GitHubAccount(login: "alice", host: "github.com", kind: .oauth))
        index.upsert(GitHubAccount(login: "bob", host: "github.com", kind: .personalAccessToken))
        index.active = Self.bobKey
        index.upsert(GitHubAccount(login: "Alice", host: "GitHub.com", kind: .personalAccessToken))
        #expect(index.accounts.map(\.login) == ["Alice", "bob"])
        #expect(index.activeAccount?.login == "bob")
        index.remove(id: Self.bobKey)
        #expect(index.active == nil)
        #expect(index.accounts.map(\.id) == [Self.aliceKey])
    }

    @Test
    func settingsRoundTripTheIndexAndNeverContainATokenOrAnOldFileBreaks() throws {
        var settings = UserSettings()
        settings.githubAccounts.upsert(GitHubAccount(login: "alice", host: "github.com", kind: .personalAccessToken))
        settings.githubAccounts.active = Self.aliceKey
        let data = try JSONEncoder().encode(settings)
        let json = String(bytes: data, encoding: .utf8) ?? ""
        #expect(json.contains(Self.alice.accessToken) == false)
        #expect(json.contains(Self.bob.accessToken) == false)
        #expect(try JSONDecoder().decode(UserSettings.self, from: data).githubAccounts == settings.githubAccounts)

        let old = try JSONDecoder().decode(UserSettings.self, from: Data("{}".utf8))
        #expect(old.githubAccounts == GitHubAccountIndex())
    }

    // MARK: identify

    @Test
    func identifyReturnsTheLoginAndSendsTheTokenOnlyInTheAuthorizationHeader() async throws {
        let seen = Box<URLRequest?>(nil)
        let validator = GitHubTokenValidator { request in
            seen.value = request
            return (Data(#"{"login":"carol"}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        #expect(try await validator.identify(Self.bob.accessToken) == "carol")
        #expect(seen.value?.url?.absoluteString == "https://api.github.com/user")
        #expect(seen.value?.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.bob.accessToken)")
    }

    @Test
    func identifyOfARejectedTokenSaysSoWithoutTheToken() async {
        let validator = GitHubTokenValidator { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        }
        do {
            _ = try await validator.identify(Self.bob.accessToken)
            Issue.record("expected a rejection")
        } catch {
            #expect((error as? GitHubTokenError) == .rejected)
            #expect(error.localizedDescription.contains(Self.bob.accessToken) == false)
        }
    }

    private final class Box<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }
}
