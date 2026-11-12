import Foundation

/// The kinds of activity the panel can split a day into. GitHub's daily calendar carries
/// totals only, so a day can have a total with no kinds behind it.
public enum ActivityKind: String, CaseIterable, Codable, Sendable {
    case commits
    case pullRequests
    case issues
    case reviews
}

/// One provider's activity on one day. `date` is that day at UTC midnight (a calendar day,
/// not an instant); `total` can exceed the sum of `kinds` when the provider has no split.
public struct ProviderDayActivity: Equatable, Sendable {
    public let provider: ProviderType
    public let date: Date
    public let total: Int
    public let kinds: [ActivityKind: Int]

    public init(provider: ProviderType, date: Date, total: Int, kinds: [ActivityKind: Int] = [:]) {
        self.provider = provider
        self.date = date
        self.total = total
        self.kinds = kinds
    }
}

/// What a provider returned for a window of days. `partial` means a request cap cut the
/// window short, so the oldest days are undercounted.
public struct ProviderActivityResult: Equatable, Sendable {
    public let provider: ProviderType
    public let days: [ProviderDayActivity]
    public let partial: Bool

    public init(provider: ProviderType, days: [ProviderDayActivity], partial: Bool = false) {
        self.provider = provider
        self.days = days
        self.partial = partial
    }
}

/// One timestamped thing that counts as activity.
public struct ActivityTally: Sendable {
    public let date: Date
    public let kind: ActivityKind
    public let count: Int

    public init(date: Date, kind: ActivityKind, count: Int = 1) {
        self.date = date
        self.kind = kind
        self.count = count
    }
}

/// Folds timestamped events into per-day entries.
public enum ActivityDays {
    /// The calendar day an instant falls on in `timeZone`, as UTC midnight of that Y-M-D.
    public static func day(of instant: Date, in timeZone: TimeZone = .current) -> Date {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let parts = local.dateComponents([.year, .month, .day], from: instant)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        return utc.date(from: parts) ?? instant
    }

    /// One entry per day, oldest first; `total` is the sum of the counts on that day.
    public static func aggregate(
        provider: ProviderType,
        events: [ActivityTally],
        timeZone: TimeZone = .current
    ) -> [ProviderDayActivity] {
        var perDay: [Date: [ActivityKind: Int]] = [:]
        for event in events {
            perDay[self.day(of: event.date, in: timeZone), default: [:]][event.kind, default: 0] += event.count
        }
        return perDay.keys.sorted().map { day in
            let kinds = perDay[day] ?? [:]
            return ProviderDayActivity(provider: provider, date: day, total: kinds.values.reduce(0, +), kinds: kinds)
        }
    }

    static func parseTimestamp(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}

/// GitLab Events API rows to per-day activity: pushes (by commit count), merge requests,
/// issues, and comments or approvals as reviews. Everything else (joined, created a
/// project, and so on) is not contribution activity and is skipped.
public enum GitLabActivityMapper {
    public static func kind(of event: GitLabEvent) -> (kind: ActivityKind, count: Int)? {
        if event.pushData != nil || event.actionName.hasPrefix("pushed") {
            return (.commits, max(event.pushData?.commitCount ?? 1, 1))
        }
        if event.actionName == "approved" { return (.reviews, 1) }
        switch event.targetType {
        case "MergeRequest": return (.pullRequests, 1)
        case "Issue": return (.issues, 1)
        case "Note", "DiffNote", "DiscussionNote": return (.reviews, 1)
        default: return nil
        }
    }

    public static func days(events: [GitLabEvent], timeZone: TimeZone = .current) -> [ProviderDayActivity] {
        let mapped = events.compactMap { event -> ActivityTally? in
            guard let date = ActivityDays.parseTimestamp(event.createdAt), let kind = self.kind(of: event) else { return nil }
            return ActivityTally(date: date, kind: kind.kind, count: kind.count)
        }
        return ActivityDays.aggregate(provider: .gitlab, events: mapped, timeZone: timeZone)
    }
}

/// Azure DevOps has no contribution calendar. Activity is the user's commits, the pull
/// requests they opened, and the ones they were asked to review.
public enum AzureActivityMapper {
    public static func days(
        commits: [Date], opened: [Date], reviewed: [Date], timeZone: TimeZone = .current
    ) -> [ProviderDayActivity] {
        let events = commits.map { ActivityTally(date: $0, kind: .commits) }
            + opened.map { ActivityTally(date: $0, kind: .pullRequests) }
            + reviewed.map { ActivityTally(date: $0, kind: .reviews) }
        return ActivityDays.aggregate(provider: .azureDevOps, events: events, timeZone: timeZone)
    }
}
