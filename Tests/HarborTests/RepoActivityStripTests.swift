@testable import Harbor
import Foundation
import HarborCore
import Testing

struct RepoActivityStripTests {
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        ActivityBuckets.calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test
    func pastDays_dropsTheFutureDaysGitHubPadsTheWeekWith() {
        let now = self.day(2024, 3, 15)
        let cells = [14, 15, 16, 17].map { HeatmapCell(date: self.day(2024, 3, $0), count: $0) }
        #expect(RepoActivitySlice.pastDays(cells, now: now).map(\.count) == [14, 15])
    }

    @Test
    func allTimeForARepoFoldsItsDaysByYear() {
        let now = self.day(2024, 3, 15)
        let entries = [
            ProviderDayActivity(provider: .github, date: self.day(2023, 12, 30), total: 2),
            ProviderDayActivity(provider: .github, date: self.day(2024, 1, 2), total: 5),
            ProviderDayActivity(provider: .github, date: self.day(2024, 3, 1), total: 1)
        ]
        let repo = ActivityBuckets.buckets(for: .allTime, entries: entries, years: [], now: now, daily: true)
        #expect(repo.map(\.count) == [2, 6])
        // The user's own All range never folds GitHub's days; it waits for the yearly totals.
        #expect(ActivityBuckets.buckets(for: .allTime, entries: entries, years: [], now: now).isEmpty)
    }

    @Test
    func repoWordsCountCommitsAndNameTheWindowHonestly() {
        let now = self.day(2024, 3, 15)
        let entries = [ProviderDayActivity(provider: .github, date: now, total: 3)]
        let buckets = ActivityBuckets.buckets(for: .week, entries: entries, years: [], now: now, daily: true)
        #expect(ActivityBuckets.totalLine(buckets, range: .week, words: .commits) == "3 commits · last 7 days")
        #expect(ActivityBuckets.totalLine(buckets, range: .allTime, words: .commits) == "3 commits · last 52 weeks")
        #expect(ActivityBuckets.hoverHead(buckets[6], range: .week, words: .commits) == "Friday, March 15, 2024 · 3 commits")
        #expect(ActivityBuckets.totalLine(buckets, range: .week) == "3 contributions · last 7 days")
    }
}
