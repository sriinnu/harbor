import Foundation
import HarborCore

/// One calendar day with every provider's activity folded together.
struct MergedDay: Equatable {
    let date: Date
    let total: Int
    /// Each provider's share of `total`.
    let providers: [ProviderType: Int]
    /// The split by kind, for the providers that have one (GitHub's daily calendar has none).
    let kinds: [ActivityKind: Int]
}

/// One cell of the activity strip: a run of days with its contribution total.
struct ActivityBucket: Equatable {
    /// First day, at UTC midnight (the calendar's dates are plain days, not instants).
    let start: Date
    /// Last day, inclusive.
    let end: Date
    let count: Int
    let providers: [ProviderType: Int]
    let kinds: [ActivityKind: Int]
}

/// One month of the All-time grid.
struct MonthBucket: Equatable {
    let year: Int
    /// 1 to 12.
    let month: Int
    let count: Int
    let providers: [ProviderType: Int]
    /// After the current month, so the grid leaves it blank instead of drawing an empty cell.
    let isFuture: Bool
}

/// The nouns a strip uses: "contributions" for the user's activity, "commits" for one repo.
struct ActivityWords: Equatable {
    var singular = "contribution"
    var plural = "contributions"
    /// What the All range is called in the caption.
    var allTimeName = "all time"

    static let contributions = ActivityWords()
    /// GitHub's commit activity covers the last 52 weeks only, so All is that, not forever.
    static let commits = ActivityWords(singular: "commit", plural: "commits", allTimeName: "last 52 weeks")
}

enum ActivityMerge {
    /// GitHub's calendar as per-day entries (counts only, no split).
    static func github(_ cells: [HeatmapCell]) -> [ProviderDayActivity] {
        cells.map { ProviderDayActivity(provider: .github, date: $0.date, total: $0.count) }
    }

    /// One entry per day, oldest first, adding providers and kinds that fall on the same day.
    static func perDay(_ entries: [ProviderDayActivity]) -> [MergedDay] {
        let calendar = ActivityBuckets.calendar
        var days: [Date: MergedDay] = [:]
        for entry in entries {
            let key = calendar.startOfDay(for: entry.date)
            let old = days[key]
            days[key] = MergedDay(
                date: key,
                total: (old?.total ?? 0) + entry.total,
                providers: (old?.providers ?? [:]).merging([entry.provider: entry.total], uniquingKeysWith: +),
                kinds: (old?.kinds ?? [:]).merging(entry.kinds, uniquingKeysWith: +)
            )
        }
        return days.keys.sorted().compactMap { days[$0] }
    }
}

/// Turns the contribution calendar and the other providers' activity (and, for all time,
/// the per-year GitHub totals) into the cells the strip draws for each range.
enum ActivityBuckets {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// Bucket count and days per bucket for the ranges backed by the daily calendar.
    /// A year is 53 weekly buckets because GitHub's calendar spans up to 53 weeks.
    static func layout(_ range: ActivityRange) -> (buckets: Int, days: Int)? {
        switch range {
        case .week: (7, 1)
        case .month: (30, 1)
        case .quarter: (13, 7)
        case .year: (53, 7)
        case .allTime: nil
        }
    }

    /// `entries` holds every provider's days (GitHub's from the calendar). All time uses
    /// `years` for GitHub, which carries the split by kind, and `entries` for the others.
    static func buckets(
        for range: ActivityRange, entries: [ProviderDayActivity], years: [ContributionYear], now: Date,
        daily: Bool = false
    ) -> [ActivityBucket] {
        guard let layout = self.layout(range) else {
            // A repo has only its daily series (no per-year totals), so All folds that by year.
            return self.yearly(years, others: daily ? entries : entries.filter { $0.provider != .github }, now: now)
        }
        return self.trailing(ActivityMerge.perDay(entries), buckets: layout.buckets, daysPerBucket: layout.days, now: now)
    }

    /// The last `buckets * daysPerBucket` days ending on the newest day in `days` (today
    /// when there are none), summed per bucket. Days missing from `days` count as zero.
    static func trailing(_ days: [MergedDay], buckets: Int, daysPerBucket: Int, now: Date) -> [ActivityBucket] {
        let calendar = self.calendar
        let anchor = calendar.startOfDay(for: days.map(\.date).max() ?? now)
        let span = buckets * daysPerBucket
        var totals = [Int](repeating: 0, count: buckets)
        var providers = [[ProviderType: Int]](repeating: [:], count: buckets)
        var kinds = [[ActivityKind: Int]](repeating: [:], count: buckets)
        for day in days {
            guard let back = calendar.dateComponents([.day], from: day.date, to: anchor).day, back >= 0, back < span else { continue }
            let index = buckets - 1 - back / daysPerBucket
            totals[index] += day.total
            providers[index].merge(day.providers, uniquingKeysWith: +)
            kinds[index].merge(day.kinds, uniquingKeysWith: +)
        }
        return (0 ..< buckets).map { index in
            let startBack = (buckets - index) * daysPerBucket - 1
            let endBack = (buckets - 1 - index) * daysPerBucket
            return ActivityBucket(
                start: calendar.date(byAdding: .day, value: -startBack, to: anchor) ?? anchor,
                end: calendar.date(byAdding: .day, value: -endBack, to: anchor) ?? anchor,
                count: totals[index], providers: providers[index], kinds: kinds[index]
            )
        }
    }

    /// One bucket per year with activity, oldest first; the current year ends today.
    static func yearly(_ years: [ContributionYear], others: [ProviderDayActivity], now: Date) -> [ActivityBucket] {
        let calendar = self.calendar
        let today = calendar.startOfDay(for: now)
        var byYear: [Int: (providers: [ProviderType: Int], kinds: [ActivityKind: Int])] = [:]
        for year in years {
            byYear[year.year] = (
                [.github: year.total],
                [.commits: year.commits, .pullRequests: year.pullRequests, .issues: year.issues, .reviews: year.reviews]
            )
        }
        for day in ActivityMerge.perDay(others) {
            let year = calendar.component(.year, from: day.date)
            var entry = byYear[year] ?? ([:], [:])
            entry.providers.merge(day.providers, uniquingKeysWith: +)
            entry.kinds.merge(day.kinds, uniquingKeysWith: +)
            byYear[year] = entry
        }
        return byYear.keys.sorted().compactMap { year in
            guard let entry = byYear[year],
                  let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
                  let december = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) else { return nil }
            return ActivityBucket(
                start: start, end: min(december, today),
                count: entry.providers.values.reduce(0, +), providers: entry.providers, kinds: entry.kinds
            )
        }
    }

    /// Every month from January of the first active year to December of the last, oldest
    /// first, so the grid is whole rows and a quiet year in between still gets one. GitHub's
    /// months come from `years` (when they carry them); `others` are per-day entries (a
    /// repo's own series, or the other providers) folded by month. Empty months count zero.
    static func monthly(years: [ContributionYear], others: [ProviderDayActivity], now: Date) -> [MonthBucket] {
        let calendar = self.calendar
        var counts: [Int: [ProviderType: Int]] = [:]
        var activeYears: Set<Int> = []
        func key(_ year: Int, _ month: Int) -> Int { year * 12 + month - 1 }
        for year in years {
            if year.total > 0 { activeYears.insert(year.year) }
            for (index, count) in year.months.prefix(12).enumerated() where count > 0 {
                counts[key(year.year, index + 1), default: [:]][.github, default: 0] += count
                activeYears.insert(year.year)
            }
        }
        for day in ActivityMerge.perDay(others) where day.total > 0 {
            let parts = calendar.dateComponents([.year, .month], from: day.date)
            guard let year = parts.year, let month = parts.month else { continue }
            for (provider, count) in day.providers where count > 0 {
                counts[key(year, month), default: [:]][provider, default: 0] += count
            }
            activeYears.insert(year)
        }
        guard let first = activeYears.min(), let last = activeYears.max() else { return [] }
        let nowParts = calendar.dateComponents([.year, .month], from: now)
        let current = key(nowParts.year ?? last, nowParts.month ?? 12)
        return (first ... last).flatMap { year in
            (1 ... 12).map { month in
                let providers = counts[key(year, month)] ?? [:]
                return MonthBucket(
                    year: year, month: month, count: providers.values.reduce(0, +),
                    providers: providers, isFuture: key(year, month) > current
                )
            }
        }
    }

    static func total(_ buckets: [ActivityBucket]) -> Int {
        buckets.reduce(0) { $0 + $1.count }
    }

    /// Levels 0 to 4 against the busiest bucket; an empty bucket is always 0.
    static func levels(_ buckets: [ActivityBucket]) -> [Int] {
        self.levels(counts: buckets.map(\.count))
    }

    /// The same scale for any list of counts (the All-time grid's months).
    static func levels(counts: [Int]) -> [Int] {
        let busiest = max(counts.max() ?? 0, 1)
        return counts.map { $0 == 0 ? 0 : max(1, Int((Double($0) / Double(busiest) * 4).rounded(.up))) }
    }

    // MARK: - Words

    static func rangeName(_ range: ActivityRange, words: ActivityWords = .contributions) -> String {
        switch range {
        case .week: "last 7 days"
        case .month: "last 30 days"
        case .quarter: "last quarter"
        case .year: "last year"
        case .allTime: words.allTimeName
        }
    }

    static func contributions(_ count: Int, words: ActivityWords = .contributions) -> String {
        count == 1 ? "1 \(words.singular)" : "\(count.formatted()) \(words.plural)"
    }

    /// "142 contributions · last 30 days".
    static func totalLine(_ buckets: [ActivityBucket], range: ActivityRange, words: ActivityWords = .contributions) -> String {
        "\(self.contributions(self.total(buckets), words: words)) · \(self.rangeName(range, words: words))"
    }

    /// "GitHub 120 · GitLab 20 · Azure DevOps unavailable": each provider's share, and the
    /// ones that could not be reached. Nil when only GitHub is connected.
    static func providerLine(
        shares: [ProviderType: Int], unavailable: [ProviderType: String], connected: [ProviderType],
        partial: Set<ProviderType> = []
    ) -> String? {
        guard connected.contains(where: { $0 != .github }) else { return nil }
        return connected.map { provider in
            if let reason = unavailable[provider] { return "\(provider.displayName) unavailable (\(reason))" }
            // A capped fetch undercounts its oldest days, so its number is a floor.
            return "\(provider.displayName) \((shares[provider] ?? 0).formatted())\(partial.contains(provider) ? "+" : "")"
        }.joined(separator: " · ")
    }

    /// "12 commits · 3 PRs · 1 issue · 4 reviews", only for kinds that have a count.
    static func kindsLine(_ kinds: [ActivityKind: Int]) -> String? {
        let names: [ActivityKind: [String]] = [
            .commits: ["commit", "commits"], .pullRequests: ["PR", "PRs"],
            .issues: ["issue", "issues"], .reviews: ["review", "reviews"]
        ]
        let parts = ActivityKind.allCases.compactMap { kind -> String? in
            guard let count = kinds[kind], count > 0, let words = names[kind] else { return nil }
            return "\(count.formatted()) \(words[count == 1 ? 0 : 1])"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// The hovered month: "Mar 2025 · 42 contributions".
    static func monthHoverHead(_ bucket: MonthBucket, words: ActivityWords = .contributions) -> String {
        let name = self.monthNames.indices.contains(bucket.month - 1) ? self.monthNames[bucket.month - 1] : "?"
        return "\(name) \(bucket.year) · \(self.contributions(bucket.count, words: words))"
    }

    /// The hovered cell: its date or span and count.
    static func hoverHead(_ bucket: ActivityBucket, range: ActivityRange, words: ActivityWords = .contributions) -> String {
        let utc = TimeZone(secondsFromGMT: 0)!
        let day = Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: utc)
        let weekday = Date.FormatStyle(date: .complete, time: .omitted, timeZone: utc)
        let when: String
        switch range {
        case .week, .month: when = bucket.start.formatted(weekday)
        case .quarter, .year: when = "\(bucket.start.formatted(day)) – \(bucket.end.formatted(day))"
        case .allTime: when = "\(self.calendar.component(.year, from: bucket.start))"
        }
        return "\(when) · \(self.contributions(bucket.count, words: words))"
    }
}
