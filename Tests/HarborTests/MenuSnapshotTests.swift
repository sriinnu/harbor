import Foundation
@testable import RepoBar
import HarborCore
import Testing

struct MenuSnapshotTests {
    @Test
    func staleChecksUseInterval() {
        let repo = Repository(
            id: "1",
            name: "Repo",
            owner: "me",
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: 0,
            openPulls: 0,
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )
        let now = Date()
        let snapshot = MenuSnapshot(repositories: [repo], capturedAt: now)
        #expect(snapshot.isStale(now: now.addingTimeInterval(10), interval: 30) == false)
        #expect(snapshot.isStale(now: now.addingTimeInterval(31), interval: 30))
    }
}
