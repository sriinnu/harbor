@testable import Harbor
import HarborCore
import Testing
import Foundation

struct ActivityBucketsTests {
    private static let utc = TimeZone(secondsFromGMT: 0)!

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        ActivityBuckets.calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private var now: Date { self.day(2024, 3, 15) }

    /// One github entry per day from `from` to `now`, each with `count`.
    private func daily(from: Date, count: Int = 1) -> [ProviderDayActivity] {
        var entries: [ProviderDayActivity] = []
        var current = from
        while current <= self.now {
            entries.append(ProviderDayActivity(provider: .github, date: current, total: count))
            current = ActivityBuckets.calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return entries
    }

    // MARK: Buckets

    @Test
    func sevenDaysIsSevenDailyCellsEndingOnTheNewestDay() {
        var entries = self.daily(from: self.day(2024, 3, 9))
        entries[0] = ProviderDayActivity(provider: .github, date: self.day(2024, 3, 9), total: 1)
        // The day before the window must not leak in.
        entries.append(ProviderDayActivity(provider: .github, date: self.day(2024, 3, 8), total: 100))
        let buckets = ActivityBuckets.buckets(for: .week, entries: entries, years: [], now: self.now)
        #expect(buckets.count == 7)
        #expect(buckets.first?.start == self.day(2024, 3, 9))
        #expect(buckets.first?.end == self.day(2024, 3, 9))
        #expect(buckets.last?.start == self.day(2024, 3, 15))
        #expect(buckets.last?.end == self.day(2024, 3, 15))
        #expect(buckets.map(\.count) == [1, 1, 1, 1, 1, 1, 1])
        #expect(ActivityBuckets.total(buckets) == 7)
    }

    @Test
    func thirtyDaysStartsTwentyNineDaysBack() {
        let buckets = ActivityBuckets.buckets(for: .month, entries: self.daily(from: self.day(2024, 2, 1), count: 2), years: [], now: self.now)
        #expect(buckets.count == 30)
        #expect(buckets.first?.start == self.day(2024, 2, 15))
        #expect(buckets.last?.end == self.day(2024, 3, 15))
        #expect(ActivityBuckets.total(buckets) == 60)
    }

    @Test
    func quarterIsThirteenWeeklyCells() {
        let buckets = ActivityBuckets.buckets(for: .quarter, entries: self.daily(from: self.day(2023, 12, 1)), years: [], now: self.now)
        #expect(buckets.count == 13)
        #expect(buckets.first?.start == self.day(2023, 12, 16))
        #expect(buckets.first?.end == self.day(2023, 12, 22))
        #expect(buckets.last?.start == self.day(2024, 3, 9))
        #expect(buckets.last?.end == self.day(2024, 3, 15))
        #expect(buckets.map(\.count) == Array(repeating: 7, count: 13))
        #expect(ActivityBuckets.total(buckets) == 91)
    }

    @Test
    func yearIsFiftyThreeWeeklyCellsAndMissingDaysAreZero() {
        // Only the newest day has activity; every other cell is empty but present.
        let entries = [ProviderDayActivity(provider: .github, date: self.day(2024, 3, 15), total: 5)]
        let buckets = ActivityBuckets.buckets(for: .year, entries: entries, years: [], now: self.now)
        #expect(buckets.count == 53)
        #expect(buckets.first?.start == self.day(2023, 3, 11))
        #expect(buckets.map(\.count) == Array(repeating: 0, count: 52) + [5])
        #expect(ActivityBuckets.total(buckets) == 5)
    }

    @Test
    func aWeekBoundaryFallsOnTheSeventhDay() {
        let entries = [
            ProviderDayActivity(provider: .github, date: self.day(2024, 3, 9), total: 4),
            ProviderDayActivity(provider: .github, date: self.day(2024, 3, 8), total: 3)
        ] + [ProviderDayActivity(provider: .github, date: self.day(2024, 3, 15), total: 1)]
        let buckets = ActivityBuckets.trailing(ActivityMerge.perDay(entries), buckets: 2, daysPerBucket: 7, now: self.now)
        // Newest week is Mar 9...15, the one before is Mar 2...8.
        #expect(buckets.map(\.count) == [3, 5])
        #expect(buckets[0].end == self.day(2024, 3, 8))
        #expect(buckets[1].start == self.day(2024, 3, 9))
    }

    @Test
    func noDataStillDrawsEmptyCellsEndingToday() {
        let buckets = ActivityBuckets.buckets(for: .week, entries: [], years: [], now: self.now)
        #expect(buckets.count == 7)
        #expect(buckets.last?.end == self.day(2024, 3, 15))
        #expect(ActivityBuckets.levels(buckets) == [0, 0, 0, 0, 0, 0, 0])
    }

    // MARK: Merge

    @Test
    func mergeAddsProvidersAndKindsOnTheSameDay() {
        let merged = ActivityMerge.perDay([
            ProviderDayActivity(provider: .github, date: self.day(2024, 3, 15), total: 3),
            ProviderDayActivity(provider: .gitlab, date: self.day(2024, 3, 15), total: 4, kinds: [.commits: 3, .reviews: 1]),
            ProviderDayActivity(provider: .azureDevOps, date: self.day(2024, 3, 14), total: 2, kinds: [.commits: 2])
        ])
        #expect(merged == [
            MergedDay(date: self.day(2024, 3, 14), total: 2, providers: [.azureDevOps: 2], kinds: [.commits: 2]),
            MergedDay(date: self.day(2024, 3, 15), total: 7, providers: [.github: 3, .gitlab: 4], kinds: [.commits: 3, .reviews: 1])
        ])
    }

    @Test
    func bucketsKeepEachProvidersShare() {
        let entries = [
            ProviderDayActivity(provider: .github, date: self.day(2024, 3, 15), total: 3),
            ProviderDayActivity(provider: .gitlab, date: self.day(2024, 3, 15), total: 4, kinds: [.commits: 4]),
            ProviderDayActivity(provider: .gitlab, date: self.day(2024, 3, 13), total: 1, kinds: [.issues: 1])
        ]
        let buckets = ActivityBuckets.buckets(for: .week, entries: entries, years: [], now: self.now)
        #expect(buckets[6] == ActivityBucket(
            start: self.day(2024, 3, 15), end: self.day(2024, 3, 15), count: 7,
            providers: [.github: 3, .gitlab: 4], kinds: [.commits: 4]
        ))
        #expect(buckets[4].count == 1)
        #expect(buckets[4].providers == [.gitlab: 1])
        #expect(buckets[4].kinds == [.issues: 1])
        #expect(ActivityBuckets.total(buckets) == 8)
    }

    // MARK: All time

    @Test
    func allTimeIsOneCellPerYearWithGitHubYearsAndOtherProvidersFolded() {
        let years = [
            ContributionYear(year: 2023, total: 100, commits: 60, pullRequests: 20, issues: 10, reviews: 10),
            ContributionYear(year: 2022, total: 40, commits: 30, pullRequests: 5, issues: 3, reviews: 2)
        ]
        let entries = [
            // GitHub's daily cells are ignored here: the years are the GitHub source.
            ProviderDayActivity(provider: .github, date: self.day(2024, 3, 15), total: 999),
            ProviderDayActivity(provider: .gitlab, date: self.day(2023, 5, 2), total: 5, kinds: [.commits: 5]),
            ProviderDayActivity(provider: .azureDevOps, date: self.day(2024, 1, 10), total: 2, kinds: [.commits: 2])
        ]
        let buckets = ActivityBuckets.buckets(for: .allTime, entries: entries, years: years, now: self.now)
        #expect(buckets == [
            ActivityBucket(
                start: self.day(2022, 1, 1), end: self.day(2022, 12, 31), count: 40, providers: [.github: 40],
                kinds: [.commits: 30, .pullRequests: 5, .issues: 3, .reviews: 2]
            ),
            ActivityBucket(
                start: self.day(2023, 1, 1), end: self.day(2023, 12, 31), count: 105, providers: [.github: 100, .gitlab: 5],
                kinds: [.commits: 65, .pullRequests: 20, .issues: 10, .reviews: 10]
            ),
            ActivityBucket(
                start: self.day(2024, 1, 1), end: self.day(2024, 3, 15), count: 2, providers: [.azureDevOps: 2],
                kinds: [.commits: 2]
            )
        ])
        #expect(ActivityBuckets.total(buckets) == 147)
    }

    // MARK: Levels and words

    @Test
    func levelsScaleAgainstTheBusiestBucket() {
        let buckets = [0, 1, 2, 4, 8].map {
            ActivityBucket(start: self.now, end: self.now, count: $0, providers: [:], kinds: [:])
        }
        #expect(ActivityBuckets.levels(buckets) == [0, 1, 1, 2, 4])
    }

    @Test
    func captionsSpellOutTotalsProvidersAndKinds() {
        let bucket = ActivityBucket(
            start: self.day(2023, 1, 1), end: self.day(2023, 12, 31), count: 1204,
            providers: [.github: 1000, .gitlab: 204], kinds: [.commits: 800, .pullRequests: 1, .reviews: 90]
        )
        #expect(ActivityBuckets.totalLine([bucket, bucket], range: .month) == "2,408 contributions · last 30 days")
        #expect(ActivityBuckets.totalLine([ActivityBucket(start: self.now, end: self.now, count: 1, providers: [:], kinds: [:])], range: .allTime) == "1 contribution · all time")
        #expect(ActivityBuckets.hoverHead(bucket, range: .allTime) == "2023 · 1,204 contributions")
        #expect(ActivityBuckets.kindsLine(bucket.kinds) == "800 commits · 1 PR · 90 reviews")
        #expect(ActivityBuckets.kindsLine([:]) == nil)
        #expect(ActivityBuckets.providerLine(shares: [.github: 1000], unavailable: [:], connected: [.github]) == nil)
        #expect(ActivityBuckets.providerLine(
            shares: bucket.providers, unavailable: [.azureDevOps: "rate limited"],
            connected: [.github, .gitlab, .azureDevOps], partial: [.gitlab]
        ) == "GitHub 1,000 · GitLab 204+ · Azure DevOps unavailable (rate limited)")
    }

    @Test
    func hoverHeadNamesTheDayOrTheWeekSpan() {
        let single = ActivityBucket(start: self.day(2024, 3, 15), end: self.day(2024, 3, 15), count: 7, providers: [:], kinds: [:])
        let week = ActivityBucket(start: self.day(2024, 3, 9), end: self.day(2024, 3, 15), count: 31, providers: [:], kinds: [:])
        let locale = Locale.current
        let weekday = Date.FormatStyle(date: .complete, time: .omitted, locale: locale, timeZone: Self.utc)
        let short = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: Self.utc)
        #expect(ActivityBuckets.hoverHead(single, range: .week) == "\(single.start.formatted(weekday)) · 7 contributions")
        #expect(ActivityBuckets.hoverHead(week, range: .quarter) == "\(week.start.formatted(short)) – \(week.end.formatted(short)) · 31 contributions")
    }

    // MARK: Monthly (All-time grid)

    @Test
    func monthlyFoldsDaysByCalendarMonthWithExactBoundaries() {
        let entries = [
            ProviderDayActivity(provider: .gitlab, date: self.day(2024, 1, 31), total: 2),
            ProviderDayActivity(provider: .gitlab, date: self.day(2024, 2, 1), total: 3),
            ProviderDayActivity(provider: .gitlab, date: self.day(2024, 2, 29), total: 4),
            ProviderDayActivity(provider: .gitlab, date: self.day(2024, 3, 1), total: 5)
        ]
        let months = ActivityBuckets.monthly(years: [], others: entries, now: self.now)
        #expect(months.count == 12)
        #expect(months.map(\.count) == [2, 7, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        #expect(months[1] == MonthBucket(year: 2024, month: 2, count: 7, providers: [.gitlab: 7], isFuture: false))
    }

    @Test
    func monthlyShowsQuietYearsBetweenTheFirstAndLastActiveYear() {
        let years = [
            ContributionYear(year: 2021, total: 3, commits: 3, pullRequests: 0, issues: 0, reviews: 0,
                             months: [0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
            ContributionYear(year: 2022, total: 0, commits: 0, pullRequests: 0, issues: 0, reviews: 0, months: Array(repeating: 0, count: 12)),
            ContributionYear(year: 2023, total: 9, commits: 9, pullRequests: 0, issues: 0, reviews: 0,
                             months: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9])
        ]
        let months = ActivityBuckets.monthly(years: years, others: [], now: self.now)
        #expect(months.count == 36)
        #expect(months.first == MonthBucket(year: 2021, month: 1, count: 0, providers: [:], isFuture: false))
        #expect(months[2] == MonthBucket(year: 2021, month: 3, count: 3, providers: [.github: 3], isFuture: false))
        #expect(months[12 ..< 24].allSatisfy { $0.year == 2022 && $0.count == 0 })
        #expect(months.last == MonthBucket(year: 2023, month: 12, count: 9, providers: [.github: 9], isFuture: false))
    }

    @Test
    func monthlyMarksMonthsAfterNowAsFutureAndAddsProvidersTogether() {
        let years = [ContributionYear(year: 2024, total: 4, commits: 4, pullRequests: 0, issues: 0, reviews: 0,
                                      months: [0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0])]
        let others = [ProviderDayActivity(provider: .azureDevOps, date: self.day(2024, 3, 2), total: 6)]
        let months = ActivityBuckets.monthly(years: years, others: others, now: self.now)
        #expect(months[2] == MonthBucket(year: 2024, month: 3, count: 10, providers: [.github: 4, .azureDevOps: 6], isFuture: false))
        #expect(months.map(\.isFuture) == [false, false, false] + Array(repeating: true, count: 9))
    }

    @Test
    func monthlyIsEmptyWithNoActivityAndTheHoverNamesTheMonth() {
        #expect(ActivityBuckets.monthly(years: [], others: [], now: self.now).isEmpty)
        let bucket = MonthBucket(year: 2025, month: 3, count: 42, providers: [:], isFuture: false)
        #expect(ActivityBuckets.monthHoverHead(bucket) == "Mar 2025 · 42 contributions")
        #expect(ActivityBuckets.monthHoverHead(MonthBucket(year: 2025, month: 12, count: 1, providers: [:], isFuture: false)) == "Dec 2025 · 1 contribution")
        #expect(ActivityBuckets.levels(counts: [0, 1, 2, 4, 8]) == [0, 1, 1, 2, 4])
    }

    @Test
    func monthlyTotalsSplitADaysListByMonthAndIgnoreOtherYears() {
        let days: [(date: Date, count: Int)] = [
            (self.day(2023, 12, 31), 50), (self.day(2024, 1, 1), 1), (self.day(2024, 1, 31), 2),
            (self.day(2024, 12, 31), 4), (self.day(2025, 1, 1), 70)
        ]
        #expect(ContributionYear.monthlyTotals(year: 2024, days: days) == [3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4])
    }
}

struct ProviderActivityMapperTests {
    private func utc(_ year: Int, _ month: Int, _ day: Int) -> Date {
        ActivityBuckets.calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test
    func gitlabEventsBecomeDailyKinds() {
        let events = [
            GitLabEvent(actionName: "pushed to", targetType: nil, createdAt: "2024-03-15T10:00:00.123Z", pushData: .init(commitCount: 3)),
            GitLabEvent(actionName: "pushed new", targetType: nil, createdAt: "2024-03-15T11:00:00Z", pushData: .init(commitCount: nil)),
            GitLabEvent(actionName: "opened", targetType: "MergeRequest", createdAt: "2024-03-15T12:00:00.000Z"),
            GitLabEvent(actionName: "approved", targetType: "MergeRequest", createdAt: "2024-03-15T13:00:00.000Z"),
            GitLabEvent(actionName: "commented on", targetType: "DiffNote", createdAt: "2024-03-14T09:00:00.000Z"),
            GitLabEvent(actionName: "closed", targetType: "Issue", createdAt: "2024-03-14T10:00:00.000Z"),
            GitLabEvent(actionName: "joined", targetType: nil, createdAt: "2024-03-14T11:00:00.000Z")
        ]
        let days = GitLabActivityMapper.days(events: events, timeZone: TimeZone(secondsFromGMT: 0)!)
        #expect(days == [
            ProviderDayActivity(provider: .gitlab, date: self.utc(2024, 3, 14), total: 2, kinds: [.reviews: 1, .issues: 1]),
            ProviderDayActivity(provider: .gitlab, date: self.utc(2024, 3, 15), total: 6, kinds: [.commits: 4, .pullRequests: 1, .reviews: 1])
        ])
    }

    @Test
    func aLateEventLandsOnTheUsersLocalDay() {
        let events = [GitLabEvent(actionName: "opened", targetType: "Issue", createdAt: "2024-03-15T23:30:00Z")]
        let plusTwo = GitLabActivityMapper.days(events: events, timeZone: TimeZone(secondsFromGMT: 2 * 3600)!)
        let minusFive = GitLabActivityMapper.days(events: events, timeZone: TimeZone(secondsFromGMT: -5 * 3600)!)
        #expect(plusTwo.map(\.date) == [self.utc(2024, 3, 16)])
        #expect(minusFive.map(\.date) == [self.utc(2024, 3, 15)])
    }

    @Test
    func gitlabEventsDecodeFromTheAPIShape() throws {
        let json = """
        [{"action_name":"pushed to","target_type":null,"created_at":"2024-03-15T10:00:00.123Z","push_data":{"commit_count":2,"ref":"main"}}]
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let events = try decoder.decode([GitLabEvent].self, from: Data(json.utf8))
        #expect(events.count == 1)
        #expect(events[0].pushData?.commitCount == 2)
        #expect(GitLabActivityMapper.kind(of: events[0])?.count == 2)
    }

    @Test
    func azureActivityCountsCommitsOpenedAndReviewedPullRequests() {
        let days = AzureActivityMapper.days(
            commits: [self.utc(2024, 3, 15), self.utc(2024, 3, 15), self.utc(2024, 3, 14)],
            opened: [self.utc(2024, 3, 15)],
            reviewed: [self.utc(2024, 3, 14), self.utc(2024, 3, 14)],
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        #expect(days == [
            ProviderDayActivity(provider: .azureDevOps, date: self.utc(2024, 3, 14), total: 3, kinds: [.commits: 1, .reviews: 2]),
            ProviderDayActivity(provider: .azureDevOps, date: self.utc(2024, 3, 15), total: 3, kinds: [.commits: 2, .pullRequests: 1])
        ])
    }
}
