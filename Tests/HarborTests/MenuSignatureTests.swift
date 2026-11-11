import Foundation
@testable import Harbor
import HarborCore
import Testing

struct MenuSignatureTests {
    @Test
    func repoSubmenuSignatureChangesWithRepoCounts() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let range = HeatmapRange(start: now.addingTimeInterval(-86400), end: now)
        let settings = UserSettings()
        let repo = Repository(
            id: "1",
            name: "Repo",
            owner: "me",
            sortOrder: 0,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: 1,
            openPulls: 2,
            latestRelease: nil,
            latestActivity: nil,
            activityEvents: [],
            traffic: nil,
            heatmap: []
        )
        let display = RepositoryDisplayModel(repo: repo, now: now)
        let signatureA = RepoSubmenuSignature(
            repo: display,
            settings: settings,
            heatmapRange: range,
            recentCounts: RepoRecentCountSignature(
                commits: nil,
                commitsDigest: nil,
                releases: nil,
                discussions: nil,
                tags: nil,
                branches: nil,
                contributors: nil
            ),
            isPinned: false
        )

        let updatedRepo = Repository(
            id: "1",
            name: "Repo",
            owner: "me",
            sortOrder: 0,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: 3,
            openPulls: 2,
            latestRelease: nil,
            latestActivity: nil,
            activityEvents: [],
            traffic: nil,
            heatmap: []
        )
        let updatedDisplay = RepositoryDisplayModel(repo: updatedRepo, now: now)
        let signatureB = RepoSubmenuSignature(
            repo: updatedDisplay,
            settings: settings,
            heatmapRange: range,
            recentCounts: RepoRecentCountSignature(
                commits: nil,
                commitsDigest: nil,
                releases: nil,
                discussions: nil,
                tags: nil,
                branches: nil,
                contributors: nil
            ),
            isPinned: false
        )

        #expect(signatureA != signatureB)
    }

    @Test
    func menuBuildSignatureChangesWithPinnedRepos() {
        let now = Date(timeIntervalSinceReferenceDate: 2_000_000)
        var settings = UserSettings()
        settings.repoList.pinnedRepositories = []
        let repo = Repository(
            id: "2",
            name: "Other",
            owner: "me",
            sortOrder: 0,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .passing,
            openIssues: 0,
            openPulls: 0,
            latestRelease: nil,
            latestActivity: nil,
            activityEvents: [],
            traffic: nil,
            heatmap: []
        )
        let display = RepositoryDisplayModel(repo: repo, now: now)
        let signatureA = MenuBuildSignature(
            account: AccountSignature(.loggedOut),
            settings: MenuSettingsSignature(settings: settings, selection: .all),
            hasLoadedRepositories: true,
            lastRefresh: nil,
            rateLimitReset: nil,
            lastError: nil,
            contribution: ContributionSignature(user: nil, error: nil, heatmapCount: 0),
            globalActivity: ActivitySignature(events: [], error: nil),
            globalCommits: CommitSignature(commits: [], error: nil),
            heatmapRangeStart: now.timeIntervalSinceReferenceDate,
            heatmapRangeEnd: now.timeIntervalSinceReferenceDate,
            reposDigest: RepoSignature.digest(for: [display]),
            timeBucket: Int(now.timeIntervalSinceReferenceDate / 60)
        )

        settings.repoList.pinnedRepositories = [repo.fullName]
        let signatureB = MenuBuildSignature(
            account: AccountSignature(.loggedOut),
            settings: MenuSettingsSignature(settings: settings, selection: .all),
            hasLoadedRepositories: true,
            lastRefresh: nil,
            rateLimitReset: nil,
            lastError: nil,
            contribution: ContributionSignature(user: nil, error: nil, heatmapCount: 0),
            globalActivity: ActivitySignature(events: [], error: nil),
            globalCommits: CommitSignature(commits: [], error: nil),
            heatmapRangeStart: now.timeIntervalSinceReferenceDate,
            heatmapRangeEnd: now.timeIntervalSinceReferenceDate,
            reposDigest: RepoSignature.digest(for: [display]),
            timeBucket: Int(now.timeIntervalSinceReferenceDate / 60)
        )

        #expect(signatureA != signatureB)
    }
}
