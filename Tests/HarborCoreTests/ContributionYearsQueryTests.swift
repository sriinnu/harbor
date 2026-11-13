import Foundation
@testable import HarborCore
import XCTest

final class ContributionYearsQueryTests: XCTestCase {
    func testEachYearGetsItsOwnWindowAndTheCurrentYearEndsNow() {
        let now = ISO8601DateFormatter().date(from: "2024-03-15T10:20:30Z")!
        let query = GraphQLClient.contributionYearsQuery(years: [2023, 2024], now: now)
        XCTAssertTrue(query.contains(#"y2023: contributionsCollection(from: "2023-01-01T00:00:00Z", to: "2023-12-31T23:59:59Z")"#))
        XCTAssertTrue(query.contains(#"y2024: contributionsCollection(from: "2024-01-01T00:00:00Z", to: "2024-03-15T10:20:30Z")"#))
        XCTAssertEqual(query.components(separatedBy: "totalPullRequestReviewContributions").count - 1, 2)
        // Each window also asks for its days, so the All-time grid can be drawn by month.
        XCTAssertEqual(query.components(separatedBy: "weeks { contributionDays { date contributionCount } }").count - 1, 2)
    }
}
