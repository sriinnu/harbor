import Foundation
@testable import Harbor
import HarborCore
import Testing

struct RepositoryDisplayModelTests {
    @Test
    func mapsReleaseAndActivity() {
        let release = Release(
            name: "v1.0",
            tag: "v1.0",
            publishedAt: Date().addingTimeInterval(-3600),
            url: URL(string: "https://example.com")!
        )
        let activity = ActivityEvent(
            title: "Fix bug",
            actor: "alice",
            date: Date().addingTimeInterval(-1800),
            url: URL(string: "https://example.com/1")!
        )
        let repo = Repository(
            id: "1",
            name: "Repo",
            owner: "me",
            sortOrder: 0,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .passing,
            openIssues: 2,
            openPulls: 3,
            latestRelease: release,
            latestActivity: activity,
            activityEvents: [activity],
            traffic: TrafficStats(uniqueVisitors: 5, uniqueCloners: 2),
            heatmap: []
        )
        let vm = RepositoryDisplayModel(repo: repo, now: Date())
        #expect(vm.releaseLine?.contains(release.name) == true)
        #expect(vm.activityLine?.contains("alice") == true)
        #expect(vm.activityEvents.count == 1)
        #expect(vm.issues == 2)
        #expect(vm.pulls == 3)
        #expect(vm.trafficVisitors == 5)
    }
}
