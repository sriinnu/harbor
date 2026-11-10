import Foundation
@testable import Harbor
@testable import HarborCore
import Testing

struct RepoSecurityTests {
    @Test
    func unknownIsNeverReportedAsZero() {
        #expect(RepoSecurityText.dependabot(nil) == "Dependabot: unavailable")
        #expect(RepoSecurityText.count("Leaked secrets", nil) == "Leaked secrets: unavailable")
        #expect(RepoSecurityText.count("Leaked secrets", 0) == "Leaked secrets: 0 open")
        #expect(RepoSecurity(dependabot: nil, secretLeaks: nil, codeScanning: nil).isAvailable == false)
    }

    @Test
    func dependabotListsSeverityMostSevereFirst() {
        let tally = DependabotTally(critical: 1, high: 2, medium: 0, low: 3)
        #expect(RepoSecurityText.dependabot(tally) == "Dependabot: 6 open (1 critical, 2 high, 3 low)")
    }

    @Test
    func alertCountAddsEveryKnownSource() {
        let security = RepoSecurity(dependabot: DependabotTally(critical: 1, high: 0, medium: 0, low: 0), secretLeaks: 2, codeScanning: nil)
        #expect(security.openAlertCount == 3)
    }

    @Test
    func nextLinkIsFollowedVerbatim() {
        let header = #"<https://api.github.com/x?per_page=100&after=abc>; rel="next", <https://api.github.com/x?before=z>; rel="prev""#
        #expect(GitHubPagination.nextURL(from: header)?.absoluteString == "https://api.github.com/x?per_page=100&after=abc")
        #expect(GitHubPagination.nextURL(from: #"<https://api.github.com/x?before=z>; rel="prev""#) == nil)
    }

    @Test @MainActor
    func failedPullLookupHidesCountsInsteadOfShowingZero() {
        var repo = Repository(
            id: "1", name: "r", owner: "o", sortOrder: nil, error: "bad", rateLimitedUntil: nil,
            ciStatus: .unknown, openIssues: 4, openPulls: 0, latestRelease: nil, latestActivity: nil,
            traffic: nil, heatmap: []
        )
        repo.pullCountsKnown = false
        #expect(RepositoryDisplayModel(repo: repo).stats.map(\.id) == ["stars", "forks"])
    }
}
