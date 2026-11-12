import Foundation
@testable import Harbor
import HarborCore
import Testing

@MainActor
struct PanelLivelyTests {
    private let calendar = ActivityBuckets.calendar

    /// A day `offset` days before 2026-11-11 (UTC midnight), with `total` contributions.
    private func day(_ offset: Int, _ total: Int) -> MergedDay {
        let base = self.calendar.date(from: DateComponents(year: 2026, month: 11, day: 11))!
        let date = self.calendar.date(byAdding: .day, value: -offset, to: base)!
        return MergedDay(date: date, total: total, providers: [.github: total], kinds: [:])
    }

    private var now: Date {
        self.calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 15))!
    }

    // MARK: - Streak

    @Test
    func streakCountsConsecutiveDaysEndingToday() {
        let streak = ContributionStreak.compute(days: [self.day(0, 3), self.day(1, 1), self.day(2, 4)], now: self.now)
        #expect(streak == ContributionStreak(current: 3, best: 3))
    }

    @Test
    func todayWithNoCommitsYetKeepsYesterdaysStreak() {
        let days = [self.day(0, 0), self.day(1, 2), self.day(2, 2), self.day(3, 1)]
        #expect(ContributionStreak.compute(days: days, now: self.now) == ContributionStreak(current: 3, best: 3))
        // Today missing from the data altogether is the same.
        let missing = [self.day(1, 2), self.day(2, 2)]
        #expect(ContributionStreak.compute(days: missing, now: self.now) == ContributionStreak(current: 2, best: 2))
    }

    @Test
    func aGapBreaksTheCurrentStreakButNotTheBest() {
        // Active: today, yesterday; gap on day 2; then a five-day run.
        let days = [self.day(0, 1), self.day(1, 1), self.day(2, 0)] + (3 ... 7).map { self.day($0, 2) }
        #expect(ContributionStreak.compute(days: days, now: self.now) == ContributionStreak(current: 2, best: 5))
    }

    @Test
    func aWholeQuietDayEndsTheStreak() {
        // Last activity two days ago: yesterday and today are both empty.
        let days = [self.day(2, 5), self.day(3, 5), self.day(4, 5)]
        #expect(ContributionStreak.compute(days: days, now: self.now) == ContributionStreak(current: 0, best: 3))
    }

    @Test
    func daysMissingFromTheSeriesCountAsGaps() {
        // Days 1 and 3 are active; day 2 is simply absent.
        let streak = ContributionStreak.compute(days: [self.day(1, 1), self.day(3, 1)], now: self.now)
        #expect(streak == ContributionStreak(current: 1, best: 1))
    }

    @Test
    func noContributionsIsNoStreak() {
        #expect(ContributionStreak.compute(days: [], now: self.now) == ContributionStreak(current: 0, best: 0))
        #expect(ContributionStreak.compute(days: [self.day(0, 0), self.day(1, 0)], now: self.now) == ContributionStreak(current: 0, best: 0))
    }

    @Test
    func aCalendarDayAheadOfUTCStillCountsAsToday() {
        // A profile ahead of UTC already has tomorrow's date in its calendar.
        let days = [self.day(-1, 2), self.day(0, 1), self.day(1, 1)]
        #expect(ContributionStreak.compute(days: days, now: self.now) == ContributionStreak(current: 3, best: 3))
    }

    // MARK: - Celebration

    @Test
    func firstRunOnlyRecordsTheBest() {
        let result = StreakCelebration.decide(stored: 0, streak: ContributionStreak(current: 9, best: 12))
        #expect(result.newBest == 12)
        #expect(result.celebrate == false)
    }

    @Test
    func beatingTheStoredBestCelebratesOnceAndMovesTheBestUp() {
        let streak = ContributionStreak(current: 8, best: 8)
        let first = StreakCelebration.decide(stored: 7, streak: streak)
        #expect(first.newBest == 8)
        #expect(first.celebrate == true)
        #expect(StreakCelebration.decide(stored: first.newBest, streak: streak).celebrate == false)
    }

    @Test
    func tyingOrTrailingTheBestDoesNotCelebrate() {
        #expect(StreakCelebration.decide(stored: 8, streak: ContributionStreak(current: 8, best: 8)).celebrate == false)
        let trailing = StreakCelebration.decide(stored: 20, streak: ContributionStreak(current: 4, best: 6))
        #expect(trailing.newBest == 20)
        #expect(trailing.celebrate == false)
    }

    @Test
    func theStoreKeepsTheBestInItsOwnDefaults() throws {
        let suite = "harbor.tests.streak.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = StreakStore(defaults: defaults)
        #expect(store.best == 0)
        store.best = 14
        #expect(StreakStore(defaults: defaults).best == 14)
    }

    // MARK: - Greeting

    @Test
    func greetingNamesTheDaypartAndWhatIsPending() {
        #expect(PanelGreeting.text(login: "sriinnu", hour: 9, needsYou: 0, openPulls: 3) == "Morning, sriinnu · 3 PRs waiting")
        #expect(PanelGreeting.text(login: "sriinnu", hour: 14, needsYou: 0, openPulls: 1) == "Afternoon, sriinnu · 1 PR waiting")
        #expect(PanelGreeting.text(login: "sriinnu", hour: 18, needsYou: 2, openPulls: 3) == "Evening, sriinnu · 2 need you")
        #expect(PanelGreeting.text(login: "sriinnu", hour: 23, needsYou: 1, openPulls: 0) == "Night, sriinnu · 1 needs you")
    }

    @Test
    func greetingIsQuietWhenNothingIsPending() {
        #expect(PanelGreeting.text(login: "sriinnu", hour: 19, needsYou: 0, openPulls: 0) == "Evening · all quiet")
        #expect(PanelGreeting.text(login: "sriinnu", hour: 3, needsYou: 0, openPulls: 0) == "Night · all quiet")
    }

    @Test
    func daypartBoundaries() {
        let parts = [4, 5, 11, 12, 16, 17, 20, 21].map(PanelGreeting.daypart(hour:))
        #expect(parts == ["Night", "Morning", "Morning", "Afternoon", "Afternoon", "Evening", "Evening", "Night"])
    }

    // MARK: - Live status

    private func reading(
        age: TimeInterval? = 12, refreshing: Bool = false, interval: TimeInterval = 300, online: Bool = true,
        limited: Bool = false, error: Bool = false
    ) -> PanelLiveStatus.Reading {
        PanelLiveStatus.reading(now: self.now, PanelLiveStatus.Facts(
            lastRefresh: age.map { self.now.addingTimeInterval(-$0) }, isRefreshing: refreshing, interval: interval,
            isOnline: online, isRateLimited: limited, hasError: error
        ))
    }

    @Test
    func liveReadingShowsAgeAndTimeToNextRefresh() {
        #expect(self.reading() == PanelLiveStatus.Reading(dot: .live, text: "Live · updated 12s ago · next in 4m"))
        #expect(self.reading(age: 280) == PanelLiveStatus.Reading(dot: .live, text: "Live · updated 4m ago · next in 20s"))
        #expect(self.reading(age: 2) == PanelLiveStatus.Reading(dot: .live, text: "Live · updated just now · next in 4m"))
    }

    @Test
    func readingGoesAmberOrGreyOrPulsing() {
        #expect(self.reading(refreshing: true) == PanelLiveStatus.Reading(dot: .refreshing, text: "Refreshing…"))
        #expect(self.reading(limited: true) == PanelLiveStatus.Reading(dot: .amber, text: "Rate limited · updated 12s ago"))
        #expect(self.reading(age: 700) == PanelLiveStatus.Reading(dot: .amber, text: "Stale · updated 11m ago"))
        #expect(self.reading(error: true) == PanelLiveStatus.Reading(dot: .amber, text: "Stale · updated 12s ago"))
        #expect(self.reading(online: false) == PanelLiveStatus.Reading(dot: .offline, text: "Offline · updated 12s ago"))
        #expect(self.reading(age: nil) == PanelLiveStatus.Reading(dot: .amber, text: "Waiting for the first refresh"))
    }

    @Test
    func refreshOffReadsAsLiveWithoutANextTime() {
        #expect(self.reading(interval: 0) == PanelLiveStatus.Reading(dot: .live, text: "Live · updated 12s ago · auto-refresh off"))
    }

    @Test
    func rateLimitTextHidesWhenUnknownOrExpired() {
        let soon = self.now.addingTimeInterval(600)
        #expect(PanelLiveStatus.rateLimitText(remaining: 4812, reset: soon, now: self.now) == "API 4,812 left")
        #expect(PanelLiveStatus.rateLimitText(remaining: 4812, reset: self.now.addingTimeInterval(-1), now: self.now) == nil)
        #expect(PanelLiveStatus.rateLimitText(remaining: nil, reset: soon, now: self.now) == nil)
    }

    // MARK: - Small rules

    @Test
    func onlyFailingToPassingIsARecovery() {
        #expect(CIRecoveryBounce.isRecovery(from: .failing, to: .passing))
        #expect(!CIRecoveryBounce.isRecovery(from: .pending, to: .passing))
        #expect(!CIRecoveryBounce.isRecovery(from: .passing, to: .failing))
    }

    @Test
    func glowDeepensWithTheCount() {
        #expect(TodayGlow.strength(forCount: 0) == 0)
        let counts = [1, 2, 5, 12, 40]
        let strengths = counts.map(TodayGlow.strength(forCount:))
        #expect(strengths == strengths.sorted())
        #expect(Set(strengths).count == strengths.count - 1) // 12 and 40 both cap at full
        #expect(strengths.last == 1)
    }
}
