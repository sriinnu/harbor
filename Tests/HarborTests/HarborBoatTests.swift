import Foundation
@testable import Harbor
import HarborCore
import Testing

struct HarborBoatTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func repo(ci: CIStatus, heatmap: [HeatmapCell] = []) -> RepositoryDisplayModel {
        RepositoryDisplayModel(repo: Repository(
            id: "1", name: "boat", owner: "o", sortOrder: nil, error: nil, rateLimitedUntil: nil,
            ciStatus: ci, openIssues: 0, openPulls: 0, latestRelease: nil, latestActivity: nil,
            traffic: nil, heatmap: heatmap
        ), now: Self.now)
    }

    @Test
    func conditionComesFromRealStatus() {
        #expect(HarborBoat(repo: Self.repo(ci: .failing), now: Self.now).condition == .storm)
        #expect(HarborBoat(repo: Self.repo(ci: .passing), now: Self.now).condition == .moored)
    }

    @Test
    func tideIsTheShareOfActiveDaysInTwoWeeks() {
        let day: TimeInterval = 86400
        let cells = [
            HeatmapCell(date: Self.now.addingTimeInterval(-day), count: 3),
            HeatmapCell(date: Self.now.addingTimeInterval(-2 * day), count: 0),
            HeatmapCell(date: Self.now.addingTimeInterval(-3 * day), count: 1),
            HeatmapCell(date: Self.now.addingTimeInterval(-30 * day), count: 9)
        ]
        #expect(HarborBoat(repo: Self.repo(ci: .passing, heatmap: cells), now: Self.now).tide == 2.0 / 14.0)
        #expect(HarborBoat(repo: Self.repo(ci: .passing), now: Self.now).tide == 0)
    }
}
