import Foundation
@testable import Harbor
import HarborCore
import Testing

/// The token sign-in path in the app: stubbed HTTP, in-memory storage, no Keychain, no network.
@MainActor
struct PersonalTokenSignInTests {
    private static let token = "ghp_TESTONLYappstatetoken0123456789"
    private static let alice = UserIdentity(username: "alice", host: URL(string: "https://github.com")!)

    private func validator(login: String, status: Int = 200, scopes: String = "repo, read:org") -> GitHubTokenValidator {
        GitHubTokenValidator { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["X-OAuth-Scopes": scopes]
            )!
            return (Data(#"{"login":"\#(login)"}"#.utf8), response)
        }
    }

    /// Every state runs on its own ephemeral defaults suite, never `UserDefaults.standard`.
    private final class Suites: @unchecked Sendable {
        private var names: [String] = []
        func make() -> UserDefaults {
            let name = "harbor.tests.pat.\(UUID().uuidString)"
            self.names.append(name)
            return UserDefaults(suiteName: name)!
        }
        deinit { for name in self.names { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) } }
    }

    private let suites = Suites()

    private func appState(_ platform: MockPlatformServices) async -> AppState {
        let state = AppState(platform: platform, settingsStore: SettingsStore(defaults: self.suites.make()))
        for _ in 0 ..< 200 where state.refreshTask == nil { try? await Task.sleep(for: .milliseconds(5)) }
        await state.refreshTask?.value
        await state.menuRefreshTask?.value
        return state
    }

    private func repo(_ name: String) -> Repository {
        Repository(
            id: name, name: name, owner: "o", sortOrder: nil, error: nil, rateLimitedUntil: nil, ciStatus: .passing,
            openIssues: 0, openPulls: 0, latestRelease: nil, latestActivity: nil, traffic: nil, heatmap: [],
            pullCountsKnown: true
        )
    }

    @Test
    func aValidTokenIsStoredAsAPersonalTokenAccountAndSignOutRemovesIt() async throws {
        let storage = InMemoryTokenStorage()
        let platform = MockPlatformServices(tokenStorage: storage)
        let state = await self.appState(platform)
        // The app's own path: validate, then save under the login's key and activate.
        let message = await state.signInWithToken(Self.token, validator: self.validator(login: "Bob"), refreshAfter: false)
        #expect(message == nil)

        let expected = OAuthTokens(accessToken: Self.token, refreshToken: "", expiresAt: nil, kind: .personalAccessToken)
        #expect(storage.activeAccount == "github:bob@github.com")
        #expect(try storage.load(account: "github:bob@github.com") == expected)
        #expect(try storage.load() == expected)
        #expect(try storage.load(account: GitHubAccountKey.legacy) == nil)
        #expect(try storage.load(account: GitHubAccountKey.staging) == nil)
        #expect(state.session.settings.githubAccounts.accounts == [GitHubAccount(login: "Bob", host: "github.com", kind: .personalAccessToken)])
        #expect(state.session.settings.githubAccounts.active == "github:bob@github.com")
        #expect(state.auth.authKind == .personalAccessToken)
        #expect(state.session.account == .loggedIn(UserIdentity(username: "Bob", host: URL(string: "https://github.com")!)))

        await state.signOut()
        #expect(try storage.load() == nil)
        #expect(storage.accountKeys() == [])
        #expect(state.auth.authKind == nil)
        #expect(state.session.account == .loggedOut)
        #expect(state.session.settings.githubAccounts == GitHubAccountIndex())
    }

    @Test
    func aRejectedTokenChangesNothing() async throws {
        let platform = MockPlatformServices()
        let state = await self.appState(platform)
        try platform.tokenStorage.save(tokens: OAuthTokens(accessToken: "keep-me", refreshToken: "", expiresAt: nil))
        state.session.account = .loggedIn(Self.alice)
        let epoch = state.scopeEpoch

        let message = await state.signInWithToken(Self.token, validator: self.validator(login: "bob", status: 401))
        #expect(message == "GitHub rejected this token. It may be mistyped, expired or revoked.")
        #expect(try platform.tokenStorage.load()?.accessToken == "keep-me")
        #expect(state.session.account == .loggedIn(Self.alice))
        #expect(state.scopeEpoch == epoch)
        #expect(message?.contains(Self.token) == false)
    }

    @Test
    func aDifferentLoginClearsTheOldAccountsData() async {
        let state = await self.appState(MockPlatformServices())
        state.accountSignedIn(Self.alice)
        state.dataOwner = "alice"
        state.session.repositories = [self.repo("secret-of-alice")]
        let epoch = state.scopeEpoch

        await state.adoptPersonalTokenAccount(login: "bob")
        #expect(state.session.repositories.isEmpty)
        #expect(state.dataOwner == "bob")
        #expect(state.scopeEpoch > epoch + 1) // cleared once, then the sign-in bump
        #expect(state.session.account == .loggedIn(UserIdentity(username: "bob", host: URL(string: "https://github.com")!)))
    }

    @Test
    func theSameLoginKeepsItsDataWhenSwitchingToAToken() async {
        let state = await self.appState(MockPlatformServices())
        state.accountSignedIn(Self.alice)
        state.dataOwner = "alice"
        state.session.repositories = [self.repo("mine")]
        let epoch = state.scopeEpoch

        await state.adoptPersonalTokenAccount(login: "Alice")
        #expect(state.session.repositories.map(\.name) == ["mine"])
        #expect(state.scopeEpoch == epoch + 1) // only the sign-in bump
    }
}
