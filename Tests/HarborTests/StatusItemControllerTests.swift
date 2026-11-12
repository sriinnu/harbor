import AppKit
@testable import Harbor
import HarborCore
import Testing

struct StatusItemControllerTests {
    private static let account = AccountState.loggedIn(UserIdentity(username: "me", host: URL(string: "https://github.com")!))

    /// A loaded, healthy panel: every repo answered, the review search answered with nothing.
    private static func content(_ repos: [Repository] = [], reviews: [ReviewRequest] = [], local: LocalRepoStatus? = nil) -> HarborPanelContent {
        var content = HarborPanelContent()
        content.hasLoadedRepositories = true
        content.reviewRequestsLoaded = true
        content.repos = repos.map { RepositoryDisplayModel(repo: $0, localStatus: local) }
        content.reviewRequests = reviews
        return content
    }

    private static func review(_ number: Int) -> ReviewRequest {
        ReviewRequest(repoFullName: "o/a", number: number, title: "PR \(number)", url: nil, authorLogin: nil, isDraft: false, updatedAt: nil)
    }

    @Test
    func signedOutWinsOverRepositoryStatus() {
        #expect(StatusItemBadge(account: .loggedOut, content: Self.content([Self.repo(.failing)])) == .signedOut)
    }

    @Test
    func countsExactlyWhatThePanelsNeedsYouCounts() {
        var alerting = Self.repo(.passing)
        alerting.security = RepoSecurity(dependabot: nil, secretLeaks: 1, codeScanning: nil)
        let content = Self.content([Self.repo(.failing), alerting, Self.repo(.passing)], reviews: [Self.review(1), Self.review(2), Self.review(3)])
        #expect(content.needsYou.count == 5)
        #expect(StatusItemBadge(account: Self.account, content: content) == .needsYou(5))
        #expect(StatusItemBadge.needsYou(2).countText == "2")
    }

    @Test
    func reviewRequestsAndBehindClonesCountEvenWithNoFailingRepo() {
        #expect(StatusItemBadge(account: Self.account, content: Self.content([Self.repo(.passing)], reviews: [Self.review(1)])) == .needsYou(1))
        let behind = LocalRepoStatus(
            path: URL(fileURLWithPath: "/tmp/r"), name: "r", fullName: "o/r", branch: "main", isClean: true,
            aheadCount: 0, behindCount: 3, syncState: .behind, upstreamBranch: "origin/main"
        )
        #expect(StatusItemBadge(account: Self.account, content: Self.content([Self.repo(.passing)], local: behind)) == .needsYou(1))
    }

    @Test
    func pendingRunsAndCleanReposStayCalm() {
        let badge = StatusItemBadge(account: Self.account, content: Self.content([Self.repo(.pending), Self.repo(.passing)]))
        #expect(badge == .calm)
        #expect(badge.countText.isEmpty)
    }

    @Test
    func aRepoThatCouldNotBeCheckedIsNotCalm() {
        var failed = Self.repo(.unknown)
        failed.error = "GitHub rate limit hit"
        failed.pullCountsKnown = false
        #expect(StatusItemBadge(account: Self.account, content: Self.content([failed, Self.repo(.passing)])) == .unchecked)
        // Something that needs you still wins, and shows its count.
        #expect(StatusItemBadge(account: Self.account, content: Self.content([failed, Self.repo(.failing)])) == .needsYou(1))
    }

    @Test
    func aFailedReviewSearchOrRefreshIsNotCalm() {
        var content = Self.content([Self.repo(.passing)])
        content.reviewRequestsFailure = "offline"
        #expect(StatusItemBadge(account: Self.account, content: content) == .unchecked)
        var refresh = Self.content([Self.repo(.passing)])
        refresh.error = "Couldn't list repositories"
        #expect(StatusItemBadge(account: Self.account, content: refresh) == .unchecked)
    }

    /// The icon and the panel's `calm` are one rule: calm only where the panel says it is clear
    /// or still checking, the unchecked ring only where the panel says it couldn't check.
    @Test
    func theIconNeverDisagreesWithThePanelsCalm() {
        var failed = Self.repo(.passing)
        failed.error = "x"
        failed.pullCountsKnown = false
        var waiting = Self.repo(.passing)
        waiting.pullCountsKnown = false
        var cases: [HarborPanelContent] = [
            Self.content([Self.repo(.passing)]), Self.content([failed]), Self.content([waiting]), Self.content([])
        ]
        var notLoaded = Self.content([Self.repo(.passing)])
        notLoaded.reviewRequestsLoaded = false
        var refreshFailed = Self.content([Self.repo(.passing)])
        refreshFailed.error = "x"
        cases += [notLoaded, refreshFailed]
        for content in cases where content.needsYou.isEmpty {
            let badge = StatusItemBadge(account: Self.account, content: content)
            switch content.calm {
            case .clear, .checking: #expect(badge == .calm)
            case .unchecked, .refreshFailed: #expect(badge == .unchecked)
            }
        }
    }

    @Test @MainActor
    func glyphIsATemplateOnTheDesignGrid() {
        let image = StatusItemIcon.image(badge: .calm, colored: false)
        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(image.isTemplate)
    }

    /// The coloured mark can't be a template (macOS would flatten its colours), and signing
    /// out always falls back to the grey outline template.
    @Test @MainActor
    func colouredGlyphIsNotATemplateUntilSignedOut() {
        #expect(StatusItemIcon.image(badge: .calm, colored: true).isTemplate == false)
        #expect(StatusItemIcon.image(badge: .needsYou(1), colored: true).isTemplate == false)
        #expect(StatusItemIcon.image(badge: .unchecked, colored: true).isTemplate == false)
        #expect(StatusItemIcon.image(badge: .signedOut, colored: true).isTemplate)
    }

    private static func repo(_ status: CIStatus) -> Repository {
        Repository(
            id: UUID().uuidString, name: "r", owner: "o", sortOrder: nil, error: nil,
            rateLimitedUntil: nil, ciStatus: status, openIssues: 0, openPulls: 0,
            latestRelease: nil, latestActivity: nil, traffic: nil, heatmap: []
        )
    }
}
