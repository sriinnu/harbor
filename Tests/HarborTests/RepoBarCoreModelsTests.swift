import Foundation
@testable import HarborCore
import Testing

struct RepoBarCoreModelsTests {
    @Test
    func userIdentity_init() {
        let host = URL(string: "https://github.com")!
        let identity = UserIdentity(username: "steipete", host: host)
        #expect(identity.username == "steipete")
        #expect(identity.host == host)
    }

    @Test
    func repository_fullName_and_withOrder() {
        var repo = Repository(
            id: "1",
            name: "RepoBar",
            owner: "steipete",
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: 1,
            openPulls: 2,
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )
        #expect(repo.fullName == "steipete/RepoBar")
        repo = repo.withOrder(5)
        #expect(repo.sortOrder == 5)
    }

    @Test
    func localProjectsRefreshInterval_labels() {
        #expect(LocalProjectsRefreshInterval.oneMinute.label == "1 minute")
        #expect(LocalProjectsRefreshInterval.twoMinutes.label == "2 minutes")
        #expect(LocalProjectsRefreshInterval.fiveMinutes.label == "5 minutes")
        #expect(LocalProjectsRefreshInterval.fifteenMinutes.label == "15 minutes")
        #expect(LocalProjectsRefreshInterval.fiveMinutes.seconds == 300)
    }

    @Test
    func userSettings_defaults() {
        let settings = UserSettings()
        #expect(settings.localProjects.worktreeFolderName == ".work")
        #expect(settings.localProjects.autoSyncEnabled == true)
    }

    @Test
    func repoRecentItems_init() {
        let now = Date()
        let url = URL(string: "https://example.com")!
        _ = RepoIssueSummary(
            number: 1,
            title: "Issue",
            url: url,
            updatedAt: now,
            authorLogin: "user",
            authorAvatarURL: url,
            assigneeLogins: ["a"],
            commentCount: 2,
            labels: [RepoIssueLabel(name: "bug", colorHex: "ff0000")]
        )
        _ = RepoPullRequestSummary(
            number: 2,
            title: "PR",
            url: url,
            updatedAt: now,
            authorLogin: nil,
            authorAvatarURL: nil,
            isDraft: false,
            commentCount: 1,
            reviewCommentCount: 0,
            labels: [],
            headRefName: "feature",
            baseRefName: "main"
        )
        _ = RepoReleaseSummary(
            name: "v1",
            tag: "v1.0",
            url: url,
            publishedAt: now,
            isPrerelease: false,
            authorLogin: "user",
            authorAvatarURL: url,
            assetCount: 1,
            downloadCount: 2,
            assets: []
        )
        _ = RepoWorkflowRunSummary(
            name: "CI",
            url: url,
            updatedAt: now,
            status: .passing,
            conclusion: "success",
            branch: "main",
            event: "push",
            actorLogin: "user",
            actorAvatarURL: url,
            runNumber: 12
        )
        _ = RepoDiscussionSummary(
            title: "Discussion",
            url: url,
            updatedAt: now,
            authorLogin: nil,
            authorAvatarURL: nil,
            commentCount: 0,
            categoryName: "General"
        )
        _ = RepoTagSummary(name: "v1.0", commitSHA: "abc123")
    }

    @Test
    func backoffTracker_lifecycle() async {
        let tracker = BackoffTracker()
        let url = URL(string: "https://example.com")!
        let now = Date()
        #expect(await tracker.isCoolingDown(url: url, now: now) == false)
        await tracker.setCooldown(url: url, until: now.addingTimeInterval(60))
        #expect(await tracker.isCoolingDown(url: url, now: now) == true)
        #expect(await tracker.cooldown(for: url, now: now) != nil)
        #expect(await tracker.count() == 1)
        await tracker.clear()
        #expect(await tracker.count() == 0)
    }

    @Test
    func gitExecutableLocator_version() {
        let result = GitExecutableLocator.version(at: URL(fileURLWithPath: "/usr/bin/git"))
        #expect(result.version != nil)
        #expect(result.error == nil)
    }
}
