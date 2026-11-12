import Foundation
@testable import Harbor
@testable import HarborCore
import Testing

/// Two GitHub accounts as a switcher: stubbed HTTP only, in-memory storage and an ephemeral
/// defaults suite, so nothing touches the real Keychain, `~/.config` or the user's settings.
@MainActor
struct GitHubAccountsTests {
    private static let bobRefresh = "ghr_TESTONLYbob0123456789"
    private static let aliceToken = "ghp_TESTONLYalice0123456789"
    private static let bobToken = "gho_TESTONLYbob0123456789"
    private static let alice = OAuthTokens(accessToken: aliceToken, refreshToken: "", expiresAt: nil, kind: .personalAccessToken)
    private static let bob = OAuthTokens(accessToken: bobToken, refreshToken: Self.bobRefresh, expiresAt: nil)
    private static let aliceKey = "github:alice@github.com"
    private static let bobKey = "github:bob@github.com"
    private static let github = URL(string: "https://github.com")!
    private static let aliceUser = UserIdentity(username: "alice", host: github)

    private struct Harness {
        let state: AppState
        let storage: InMemoryTokenStorage
        let defaults: UserDefaults
        let suite: String
    }

    private func harness() async -> Harness {
        let suite = "harbor.tests.accounts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let storage = InMemoryTokenStorage()
        let state = AppState(platform: MockPlatformServices(tokenStorage: storage), settingsStore: SettingsStore(defaults: defaults))
        for _ in 0 ..< 200 where state.refreshTask == nil { try? await Task.sleep(for: .milliseconds(5)) }
        await state.refreshTask?.value
        await state.menuRefreshTask?.value
        return Harness(state: state, storage: storage, defaults: defaults, suite: suite)
    }

    private func finish(_ harness: Harness) {
        harness.defaults.removePersistentDomain(forName: harness.suite)
    }

    private func repo(_ name: String) -> Repository {
        Repository(
            id: name, name: name, owner: "o", sortOrder: nil, error: nil, rateLimitedUntil: nil, ciStatus: .passing,
            openIssues: 0, openPulls: 0, latestRelease: nil, latestActivity: nil, traffic: nil, heatmap: [],
            pullCountsKnown: true
        )
    }

    /// Both accounts stored and indexed, alice active and on screen with her data.
    private func signedInAsAliceWithBobKnown(_ h: Harness) async throws {
        try h.state.auth.commitAccount(Self.bob, login: "bob", host: Self.github)
        _ = try h.state.auth.commitAccount(Self.alice, login: "alice", host: Self.github)
        try h.state.auth.activate(Self.aliceKey, host: Self.github)
        h.state.session.settings.githubAccounts.upsert(GitHubAccount(login: "alice", host: "github.com", kind: .personalAccessToken))
        h.state.session.settings.githubAccounts.upsert(GitHubAccount(login: "bob", host: "github.com", kind: .oauth))
        h.state.session.settings.githubAccounts.active = Self.aliceKey
        h.state.accountSignedIn(Self.aliceUser)
        h.state.dataOwner = "alice"
    }

    // MARK: migration

    @Test
    func migration_movesTheDefaultItemToItsAccountKey_withoutLosingTheSignIn() async throws {
        let h = await self.harness()
        defer { self.finish(h) }
        let legacy = OAuthTokens(accessToken: "gho_TESTONLYlegacy0123456789", refreshToken: "rl", expiresAt: nil)
        try h.storage.save(tokens: legacy) // the single item every older version wrote
        h.state.session.account = .loggedIn(Self.aliceUser)

        await h.state.migrateLegacyAccountIfNeeded()

        #expect(try h.storage.load(account: GitHubAccountKey.legacy) == nil)
        #expect(try h.storage.load(account: Self.aliceKey) == legacy)
        #expect(h.storage.activeAccount == Self.aliceKey)
        // What `harborcli` and the refresher read, and what the app uses, is the same token as before.
        #expect(try h.storage.load() == legacy)
        #expect(h.state.auth.loadTokens() == legacy)
        #expect(h.state.session.settings.githubAccounts.accounts == [GitHubAccount(login: "alice", host: "github.com", kind: .oauth)])
        #expect(h.state.session.settings.githubAccounts.active == Self.aliceKey)
        #expect(SettingsStore(defaults: h.defaults).load().githubAccounts.active == Self.aliceKey)

        // A second launch finds nothing left to migrate and changes nothing.
        let index = h.state.session.settings.githubAccounts
        await h.state.migrateLegacyAccountIfNeeded()
        #expect(h.state.session.settings.githubAccounts == index)
        #expect(h.storage.accountKeys() == [Self.aliceKey])
    }

    @Test
    func migration_withoutAKnownLoginLeavesTheLegacyItemSigningIn() async throws {
        let h = await self.harness()
        defer { self.finish(h) }
        try h.storage.save(tokens: Self.bob)
        // Nothing to name the account with and no network: the legacy item stays and still loads.
        h.state.session.account = .loggedOut
        let before = h.state.session.settings.githubAccounts
        h.state.auth.identifyOverride = { _, _ in throw URLError(.notConnectedToInternet) }
        await h.state.migrateLegacyAccountIfNeeded()
        #expect(try h.storage.load(account: GitHubAccountKey.legacy) == Self.bob)
        #expect(try h.storage.load() == Self.bob)
        #expect(h.storage.activeAccount == nil)
        #expect(h.state.session.settings.githubAccounts == before)
    }

    // MARK: switching

    @Test
    func switching_clearsEverythingOfTheOtherAccount_andSwapsTheToken() async throws {
        let h = await self.harness()
        defer { self.finish(h) }
        try await self.signedInAsAliceWithBobKnown(h)
        let state = h.state
        state.session.repositories = [self.repo("alices-secret-repo")]
        state.session.rateLimitReset = Date().addingTimeInterval(600)
        state.session.contributionUser = "alice"
        state.reviewRequests = ReviewRequestsStore(fetch: {
            ReviewRequestList(requests: [ReviewRequest(repoFullName: "o/a", number: 1, title: "alice review", url: nil, authorLogin: nil, isDraft: false, updatedAt: nil)], total: 1)
        })
        state.myPulls = MyPullsStore(fetch: {
            [MyPullRequest(repoFullName: "o/a", number: 2, title: "alice pr", headBranch: "b", isDraft: false, reviewDecision: nil, mergeable: "MERGEABLE", checksState: "FAILURE")]
        })
        await state.reviewRequests.load()?.value
        await state.myPulls.load()?.value
        #expect(state.reviewRequests.requests.count == 1)
        #expect(state.myPulls.pulls.count == 1)

        let resets = Counter()
        state.accountReset = { resets.count += 1 }
        let running = Task { _ = try? await Task.sleep(for: .seconds(30)) }
        state.refreshTask = running
        let epoch = state.scopeEpoch

        let message = await state.switchGitHubAccount(to: Self.bobKey, refreshAfter: false)

        #expect(message == nil)
        #expect(running.isCancelled)
        #expect(state.refreshTask == nil)
        #expect(state.session.repositories.isEmpty)
        #expect(state.session.rateLimitReset == nil)
        #expect(state.session.contributionUser == nil)
        #expect(state.reviewRequests.requests.isEmpty)
        #expect(state.reviewRequests.hasAnswered == false)
        #expect(state.myPulls.pulls.isEmpty)
        #expect(state.myPulls.hasAnswered == false)
        #expect(resets.count >= 1) // the rate-limit and backoff reset ran, and the account waited for it
        #expect(state.scopeEpoch > epoch + 1)
        #expect(state.dataOwner == "bob")
        #expect(state.session.account == .loggedIn(UserIdentity(username: "bob", host: Self.github)))
        // The token swap: the Keychain pointer (so `harborcli`), the app's cache and the index all say bob.
        #expect(h.storage.activeAccount == Self.bobKey)
        #expect(try h.storage.load() == Self.bob)
        #expect(state.auth.loadTokens() == Self.bob)
        #expect(state.auth.authKind == .oauth)
        #expect(state.session.settings.githubAccounts.active == Self.bobKey)
        #expect(SettingsStore(defaults: h.defaults).load().githubAccounts.active == Self.bobKey)
        // Alice's token is untouched, ready for the switch back.
        #expect(try h.storage.load(account: Self.aliceKey) == Self.alice)
    }

    @Test
    func switching_dropsASearchStillInFlightForTheOldAccount() async throws {
        let h = await self.harness()
        defer { self.finish(h) }
        try await self.signedInAsAliceWithBobKnown(h)
        let state = h.state
        state.reviewRequests = ReviewRequestsStore(fetch: {
            try await Task.sleep(for: .milliseconds(150))
            return ReviewRequestList(requests: [ReviewRequest(repoFullName: "o/a", number: 1, title: "alice review", url: nil, authorLogin: nil, isDraft: false, updatedAt: nil)], total: 1)
        })
        let search = state.reviewRequests.load()
        await state.switchGitHubAccount(to: Self.bobKey, refreshAfter: false)
        await search?.value
        #expect(state.reviewRequests.requests.isEmpty)
        #expect(state.reviewRequests.hasAnswered == false)
    }

    @Test
    func switching_toAnAccountWhoseTokenIsGoneSaysSo_andChangesNothing() async throws {
        let h = await self.harness()
        defer { self.finish(h) }
        try await self.signedInAsAliceWithBobKnown(h)
        h.storage.remove(account: Self.bobKey)
        let epoch = h.state.scopeEpoch
        let message = await h.state.switchGitHubAccount(to: Self.bobKey, refreshAfter: false)
        #expect(message == "Harbor can't find the token for bob in the Keychain. Sign in to it again.")
        #expect(h.state.session.account == .loggedIn(Self.aliceUser))
        #expect(h.state.scopeEpoch == epoch)
        #expect(h.storage.activeAccount == Self.aliceKey)
        #expect(h.state.session.settings.githubAccounts.accounts.map(\.login) == ["alice"])
    }

    // MARK: adding and removing

    @Test
    func addingASecondAccount_keepsTheFirstsTokenAndClearsItsData() async throws {
        let h = await self.harness()
        defer { self.finish(h) }
        h.state.session.account = .loggedIn(Self.aliceUser)
        try h.storage.save(tokens: Self.alice) // alice still on the legacy item
        h.state.dataOwner = "alice"
        h.state.session.repositories = [self.repo("alices-secret-repo")]

        let failure = await h.state.completeSignIn(login: "bob", host: Self.github, tokens: Self.bob, refreshAfter: false)

        #expect(failure == nil)
        #expect(try h.storage.load(account: Self.aliceKey) == Self.alice) // migrated first, then bob added beside it
        #expect(try h.storage.load(account: Self.bobKey) == Self.bob)
        #expect(try h.storage.load(account: GitHubAccountKey.legacy) == nil)
        #expect(try h.storage.load(account: GitHubAccountKey.staging) == nil)
        #expect(h.storage.activeAccount == Self.bobKey)
        #expect(h.state.session.settings.githubAccounts.accounts.map(\.login) == ["alice", "bob"])
        #expect(h.state.session.repositories.isEmpty)
        #expect(h.state.session.account == .loggedIn(UserIdentity(username: "bob", host: Self.github)))
    }

    @Test
    func removingTheActiveAccount_switchesToTheOtherAndDeletesItsToken() async throws {
        let h = await self.harness()
        defer { self.finish(h) }
        try await self.signedInAsAliceWithBobKnown(h)
        h.state.session.repositories = [self.repo("alices-secret-repo")]

        await h.state.removeGitHubAccount(Self.aliceKey, refreshAfter: false)

        #expect(try h.storage.load(account: Self.aliceKey) == nil)
        #expect(h.storage.accountKeys() == [Self.bobKey])
        #expect(h.storage.activeAccount == Self.bobKey)
        #expect(try h.storage.load() == Self.bob)
        #expect(h.state.session.settings.githubAccounts.accounts.map(\.login) == ["bob"])
        #expect(h.state.session.settings.githubAccounts.active == Self.bobKey)
        #expect(h.state.session.repositories.isEmpty)
        #expect(h.state.session.account == .loggedIn(UserIdentity(username: "bob", host: Self.github)))
        #expect(h.state.dataOwner == "bob")
    }

    @Test
    func removingTheLastAccount_signsOutAndLeavesNothingInTheKeychain() async throws {
        let h = await self.harness()
        defer { self.finish(h) }
        try await self.signedInAsAliceWithBobKnown(h)
        await h.state.removeGitHubAccount(Self.bobKey, refreshAfter: false)
        await h.state.signOut() // the Settings and menu buttons end here

        #expect(h.state.session.account == .loggedOut)
        #expect(h.storage.accountKeys() == [])
        #expect(h.storage.activeAccount == nil)
        #expect(try h.storage.load() == nil)
        #expect(h.state.auth.loadTokens() == nil)
        #expect(h.state.session.settings.githubAccounts == GitHubAccountIndex())
        #expect(h.state.reviewRequests.requests.isEmpty)
    }

    @Test
    func removingTheOtherAccount_leavesTheActiveOneAndItsDataAlone() async throws {
        let h = await self.harness()
        defer { self.finish(h) }
        try await self.signedInAsAliceWithBobKnown(h)
        h.state.session.repositories = [self.repo("mine")]
        let epoch = h.state.scopeEpoch
        await h.state.removeGitHubAccount(Self.bobKey, refreshAfter: false)
        #expect(try h.storage.load(account: Self.bobKey) == nil)
        #expect(h.storage.activeAccount == Self.aliceKey)
        #expect(h.state.session.repositories.map(\.name) == ["mine"])
        #expect(h.state.scopeEpoch == epoch)
        #expect(h.state.session.account == .loggedIn(Self.aliceUser))
    }

    @Test
    func signOutWithTheLegacyItemOnly_stillClearsIt() async throws {
        let h = await self.harness()
        defer { self.finish(h) }
        try h.storage.save(tokens: Self.alice)
        h.state.session.account = .loggedIn(Self.aliceUser)
        await h.state.signOut()
        #expect(try h.storage.load() == nil)
        #expect(h.state.session.account == .loggedOut)
    }

    @Test
    func aRefusedExtraTokenChangesNothing() async throws {
        let h = await self.harness()
        defer { self.finish(h) }
        try await self.signedInAsAliceWithBobKnown(h)
        let validator = GitHubTokenValidator { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        }
        let epoch = h.state.scopeEpoch
        let message = await h.state.signInWithToken("ghp_TESTONLYrefused0123456789", validator: validator)
        #expect(message == "GitHub rejected this token. It may be mistyped, expired or revoked.")
        #expect(h.storage.activeAccount == Self.aliceKey)
        #expect(h.storage.accountKeys() == [Self.aliceKey, Self.bobKey])
        #expect(try h.storage.load(account: GitHubAccountKey.staging) == nil)
        #expect(h.state.scopeEpoch == epoch)
        #expect(h.state.session.account == .loggedIn(Self.aliceUser))
    }

    // MARK: secrets

    @Test
    func noTokenReachesSettingsDiagnosticsOrAMessage() async throws {
        let h = await self.harness()
        defer { self.finish(h) }
        try await self.signedInAsAliceWithBobKnown(h)
        let failures = [
            await h.state.switchGitHubAccount(to: "github:nobody@github.com", refreshAfter: false),
            await h.state.signInWithToken(Self.bobToken, validator: GitHubTokenValidator { request in
                (Data(), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
            })
        ]
        await h.state.switchGitHubAccount(to: Self.bobKey, refreshAfter: false)
        h.state.persistSettings()

        var haystacks: [String] = failures.compactMap { $0 }
        haystacks.append(String(bytes: try JSONEncoder().encode(h.state.session.settings), encoding: .utf8) ?? "")
        haystacks.append(String(describing: await h.state.diagnostics()))
        haystacks.append(String(describing: h.state.session.settings.githubAccounts))
        haystacks.append(String(describing: h.state.session.account))
        haystacks.append(h.state.session.lastError ?? "")
        // The persisted settings blob itself.
        haystacks.append(String(bytes: h.defaults.data(forKey: SettingsStore.storageKey) ?? Data(), encoding: .utf8) ?? "")
        for secret in [Self.aliceToken, Self.bobToken, Self.bobRefresh] {
            for text in haystacks {
                #expect(text.contains(secret) == false)
            }
        }
        #expect(haystacks.contains { $0.contains("alice") }) // the logins are there; the tokens are not
    }

    private final class Counter: @unchecked Sendable {
        var count = 0
    }
}
