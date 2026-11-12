import Foundation
import HarborCore

/// The current and best run of consecutive days with at least one contribution.
struct ContributionStreak: Equatable {
    let current: Int
    let best: Int

    /// `days` are per-day totals (any order, gaps allowed). A day that is missing counts as
    /// zero. Today may still be empty: the streak then runs up to yesterday, so it only
    /// breaks once a whole day has passed without activity. The calendar's newest day wins
    /// over `now` when it is later, because GitHub's days follow the profile's time zone.
    static func compute(days: [MergedDay], now: Date, calendar: Calendar = ActivityBuckets.calendar) -> Self {
        let active = Set(days.filter { $0.total > 0 }.map { calendar.startOfDay(for: $0.date) })
        guard !active.isEmpty else { return Self(current: 0, best: 0) }
        let newest = days.map { calendar.startOfDay(for: $0.date) }.max() ?? now
        let today = max(calendar.startOfDay(for: now), newest)
        var best = 0
        var run = 0
        var previous: Date?
        for day in active.sorted() {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day { run += 1 } else { run = 1 }
            best = max(best, run)
            previous = day
        }
        var cursor = active.contains(today) ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        var current = 0
        while active.contains(cursor) {
            current += 1
            guard let earlier = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = earlier
        }
        return Self(current: current, best: best)
    }
}

/// What to remember and whether to celebrate once a streak has been computed.
enum StreakCelebration {
    /// `stored` is the best streak remembered from earlier (0 when none). The first time
    /// there is nothing to beat, so it only records; afterwards a current streak longer than
    /// the remembered best celebrates once, because the new best is stored right away.
    static func decide(stored: Int, streak: ContributionStreak) -> (newBest: Int, celebrate: Bool) {
        let newBest = max(stored, streak.best, streak.current)
        return (newBest, stored > 0 && streak.current > stored)
    }
}

/// The remembered best streak. A value the user earned, not a cache, so it lives in
/// UserDefaults; tests pass their own suite.
struct StreakStore {
    static let key = "harbor.streak.best"
    var defaults: UserDefaults = .standard

    var best: Int {
        get { self.defaults.integer(forKey: Self.key) }
        nonmutating set { self.defaults.set(newValue, forKey: Self.key) }
    }
}

/// "Morning, sriinnu · 3 PRs waiting" or "Evening · all quiet".
enum PanelGreeting {
    static func daypart(hour: Int) -> String {
        switch hour {
        case 5 ..< 12: "Morning"
        case 12 ..< 17: "Afternoon"
        case 17 ..< 21: "Evening"
        default: "Night"
        }
    }

    /// Things that need you come first; open pull requests next; otherwise all quiet, with
    /// no name (there is nothing to say to them).
    static func text(login: String, hour: Int, needsYou: Int, openPulls: Int) -> String {
        let part = self.daypart(hour: hour)
        if needsYou > 0 {
            return "\(part), \(login) · \(needsYou) \(needsYou == 1 ? "needs" : "need") you"
        }
        if openPulls > 0 {
            return "\(part), \(login) · \(openPulls) \(openPulls == 1 ? "PR" : "PRs") waiting"
        }
        return "\(part) · all quiet"
    }
}

/// How the live status bar reads, from facts alone so it can be tested.
enum PanelLiveStatus {
    enum Dot: Equatable {
        case live, refreshing, amber, offline
    }

    struct Reading: Equatable {
        let dot: Dot
        let text: String
    }

    /// What the status bar knows.
    struct Facts {
        var lastRefresh: Date?
        var isRefreshing = false
        /// Seconds between refreshes; 0 when automatic refresh is off.
        var interval: TimeInterval = 300
        var isOnline = true
        var isRateLimited = false
        var hasError = false
    }

    static func reading(now: Date, _ facts: Facts) -> Reading {
        let (lastRefresh, isRefreshing, interval) = (facts.lastRefresh, facts.isRefreshing, facts.interval)
        let (isOnline, isRateLimited, hasError) = (facts.isOnline, facts.isRateLimited, facts.hasError)
        let updated = lastRefresh.map { "updated \(self.ago(now.timeIntervalSince($0)))" } ?? "not updated yet"
        if !isOnline { return Reading(dot: .offline, text: "Offline · \(updated)") }
        if isRefreshing { return Reading(dot: .refreshing, text: "Refreshing…") }
        if isRateLimited { return Reading(dot: .amber, text: "Rate limited · \(updated)") }
        guard let lastRefresh else { return Reading(dot: .amber, text: "Waiting for the first refresh") }
        let age = now.timeIntervalSince(lastRefresh)
        // Two missed refreshes (or half an hour when refresh is off) is stale.
        let staleAfter = interval > 0 ? interval * 2 : 1800
        if hasError || age > staleAfter { return Reading(dot: .amber, text: "Stale · \(updated)") }
        guard interval > 0 else { return Reading(dot: .live, text: "Live · \(updated) · auto-refresh off") }
        let remaining = interval - age
        let next = remaining > 0 ? "next in \(self.span(remaining))" : "next any moment"
        return Reading(dot: .live, text: "Live · \(updated) · \(next)")
    }

    /// "12s ago", "3m ago", "2h ago"; under five seconds is "just now".
    static func ago(_ seconds: TimeInterval) -> String {
        let whole = Int(max(seconds, 0))
        if whole < 5 { return "just now" }
        return "\(self.span(TimeInterval(whole))) ago"
    }

    /// "45s", "4m", "2h": the largest whole unit, always rounded down.
    static func span(_ seconds: TimeInterval) -> String {
        let whole = Int(max(seconds, 0))
        if whole < 60 { return "\(whole)s" }
        if whole < 3600 { return "\(whole / 60)m" }
        return "\(whole / 3600)h"
    }

    /// "API 4,812 left"; nothing when the count is unknown or its window has already reset.
    static func rateLimitText(remaining: Int?, reset: Date?, now: Date) -> String? {
        guard let remaining else { return nil }
        if let reset, reset < now { return nil }
        return "API \(remaining.formatted()) left"
    }
}
