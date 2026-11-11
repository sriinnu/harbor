import AppKit
@testable import Harbor
import HarborCore
import Testing

struct StatusItemControllerTests {
    @Test
    func signedOutWinsOverRepositoryStatus() {
        #expect(StatusItemBadge(account: .loggedOut, repositories: [Self.repo(.failing)]) == .signedOut)
    }

    @Test
    func countsReposThatNeedYou() {
        let account = AccountState.loggedIn(UserIdentity(username: "me", host: URL(string: "https://github.com")!))
        var alerting = Self.repo(.passing)
        alerting.security = RepoSecurity(dependabot: nil, secretLeaks: 1, codeScanning: nil)
        #expect(StatusItemBadge(account: account, repositories: [Self.repo(.failing), alerting, Self.repo(.passing)]) == .needsYou(2))
        #expect(StatusItemBadge.needsYou(2).countText == "2")
    }

    @Test
    func pendingRunsAndCleanReposStayCalm() {
        let account = AccountState.loggedIn(UserIdentity(username: "me", host: URL(string: "https://github.com")!))
        let badge = StatusItemBadge(account: account, repositories: [Self.repo(.pending), Self.repo(.passing)])
        #expect(badge == .calm)
        #expect(badge.countText.isEmpty)
    }

    @Test @MainActor
    func glyphIsATemplateOnTheDesignGrid() {
        let image = StatusItemIcon.image(badge: .calm)
        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(image.isTemplate)
    }

    private static func repo(_ status: CIStatus) -> Repository {
        Repository(
            id: UUID().uuidString, name: "r", owner: "o", sortOrder: nil, error: nil,
            rateLimitedUntil: nil, ciStatus: status, openIssues: 0, openPulls: 0,
            latestRelease: nil, latestActivity: nil, traffic: nil, heatmap: []
        )
    }
}
