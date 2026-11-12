import Foundation
@testable import Harbor
import HarborCore
import Testing

@MainActor
struct PanelListsAndBoatsTests {
    private let now = ISO8601DateFormatter().date(from: "2026-11-11T12:00:00Z")!

    private func request(_ number: Int, repo: String = "o/kosha", title: String = "Bump") -> ReviewRequest {
        ReviewRequest(
            repoFullName: repo, number: number, title: title, url: nil, authorLogin: "ana", isDraft: false,
            updatedAt: self.now.addingTimeInterval(-7200)
        )
    }

    @Test
    func reviewRequestsBecomeRowsThatOpenThePullPane() {
        let needs = HarborPanelContent.reviewNeeds([self.request(91, title: "Bump hono")], now: self.now)
        #expect(needs.count == 1)
        #expect(needs[0].id == "review:o/kosha#91")
        #expect(needs[0].kind == .review)
        #expect(needs[0].title == "Bump hono")
        #expect(needs[0].detail == "o/kosha #91 · @ana · 2h")
        #expect(needs[0].pull == PanelPullTarget(fullName: "o/kosha", number: 91))
        #expect(needs[0].repo == nil)
    }

    @Test
    func reviewRequestsSitBetweenFailingBuildsAndBehindClones() {
        let repo = { (title: String, ci: CIStatus, behind: Int) -> RepositoryDisplayModel in
            let parts = title.split(separator: "/").map(String.init)
            let source = Repository(
                id: title, name: parts[1], owner: parts[0], sortOrder: 0, error: nil, rateLimitedUntil: nil, ciStatus: ci,
                openIssues: 0, openPulls: 0, latestRelease: nil, latestActivity: nil, activityEvents: [], traffic: nil, heatmap: []
            )
            let local = behind > 0 ? LocalRepoStatus(
                path: URL(fileURLWithPath: "/tmp/\(parts[1])"), name: parts[1], fullName: title, branch: "main", isClean: true,
                aheadCount: 0, behindCount: behind, syncState: .behind, upstreamBranch: "origin/main"
            ) : nil
            return RepositoryDisplayModel(repo: source, localStatus: local)
        }
        var content = HarborPanelContent()
        content.repos = [repo("o/behind", .passing, 2), repo("o/broken", .failing, 0)]
        content.reviewRequests = [self.request(3)]
        #expect(content.needsYou.map(\.id).count == 3)
        #expect(content.needsYou.map(\.kind) == [.fail, .review, .behind])
    }

    @Test
    func manyReviewRequestsAreCappedSoBehindClonesStayListed() {
        let many = (1 ... 9).map { self.request($0) }
        let needs = HarborPanelContent.reviewNeeds(many, now: self.now)
        #expect(needs.map(\.id) == ["review:o/kosha#1", "review:o/kosha#2", "review:o/kosha#3", "review:o/kosha#4"])
    }

    @Test
    func harborSummaryWording() {
        #expect(HarborBoatsView.summary(moored: 5, listing: 0, storm: 0, shown: 5, total: 5) == "5 moored")
        #expect(HarborBoatsView.summary(moored: 5, listing: 1, storm: 2, shown: 8, total: 8) == "5 moored · 1 listing · 2 in a storm")
        #expect(HarborBoatsView.summary(moored: 24, listing: 0, storm: 0, shown: 24, total: 31) == "24 moored · showing 24 of 31")
    }

    @Test
    func panelModesAreLabelledInOrder() {
        #expect(PanelMode.allCases.map(\.label) == ["Repos", "Harbor", "Tower"])
    }

    @Test
    func localGitModelAsksBeforeMovingCommitsAndNotBeforeFetching() async throws {
        let recorder = CommandRecorder()
        let model = LocalGitModel(path: URL(fileURLWithPath: "/tmp/r")) { command, _ in
            await recorder.record(command)
            return nil
        }
        model.request(.pullFastForward)
        #expect(model.confirming == .pullFastForward)
        #expect(model.needsPanelOpen)
        #expect(await recorder.ran.isEmpty)
        model.cancel()
        #expect(model.confirming == nil)
        model.request(.fetch)
        // Wait for the run to finish rather than a fixed sleep, which flakes under a loaded test run.
        let deadline = Date().addingTimeInterval(5)
        while await recorder.ran.isEmpty || model.running != nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await recorder.ran == [.fetch])
        #expect(model.running == nil)
    }
}

private actor CommandRecorder {
    private(set) var ran: [LocalGitCommand] = []
    func record(_ command: LocalGitCommand) { self.ran.append(command) }
}
