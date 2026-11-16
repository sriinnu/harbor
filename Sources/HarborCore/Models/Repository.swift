import Foundation

public struct Repository: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let owner: String
    public let isFork: Bool
    public let isArchived: Bool
    public let sortOrder: Int?
    public var error: String?
    public var rateLimitedUntil: Date?
    public var ciStatus: CIStatus
    public var ciRunCount: Int?
    public var stats: RepositoryStats
    public var latestRelease: Release?
    public var latestActivity: ActivityEvent?
    public var activityEvents: [ActivityEvent]
    public var traffic: TrafficStats?
    public var heatmap: [HeatmapCell]
    public var security: RepoSecurity?
    /// False when the open-PR lookup failed. Issue and PR counts are then unknown,
    /// because GitHub's open-issue total includes pull requests.
    public var pullCountsKnown: Bool

    public init(
        id: String,
        name: String,
        owner: String,
        isFork: Bool = false,
        isArchived: Bool = false,
        sortOrder: Int?,
        error: String?,
        rateLimitedUntil: Date?,
        ciStatus: CIStatus,
        ciRunCount: Int? = nil,
        openIssues: Int,
        openPulls: Int,
        stars: Int = 0,
        forks: Int = 0,
        pushedAt: Date? = nil,
        latestRelease: Release?,
        latestActivity: ActivityEvent?,
        activityEvents: [ActivityEvent] = [],
        traffic: TrafficStats?,
        heatmap: [HeatmapCell],
        security: RepoSecurity? = nil,
        pullCountsKnown: Bool = true
    ) {
        self.id = id
        self.name = name
        self.owner = owner
        self.isFork = isFork
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.error = error
        self.rateLimitedUntil = rateLimitedUntil
        self.ciStatus = ciStatus
        self.ciRunCount = ciRunCount
        self.stats = RepositoryStats(
            openIssues: openIssues,
            openPulls: openPulls,
            stars: stars,
            forks: forks,
            pushedAt: pushedAt
        )
        self.latestRelease = latestRelease
        self.latestActivity = latestActivity
        self.activityEvents = activityEvents
        self.traffic = traffic
        self.heatmap = heatmap
        self.security = security
        self.pullCountsKnown = pullCountsKnown
    }

    public var fullName: String { "\(self.owner)/\(self.name)" }

    public func withOrder(_ order: Int?) -> Repository {
        Repository(
            id: self.id,
            name: self.name,
            owner: self.owner,
            isFork: self.isFork,
            isArchived: self.isArchived,
            sortOrder: order,
            error: self.error,
            rateLimitedUntil: self.rateLimitedUntil,
            ciStatus: self.ciStatus,
            ciRunCount: self.ciRunCount,
            openIssues: self.stats.openIssues,
            openPulls: self.stats.openPulls,
            stars: self.stats.stars,
            forks: self.stats.forks,
            pushedAt: self.stats.pushedAt,
            latestRelease: self.latestRelease,
            latestActivity: self.latestActivity,
            activityEvents: self.activityEvents,
            traffic: self.traffic,
            heatmap: self.heatmap,
            security: self.security,
            pullCountsKnown: self.pullCountsKnown
        )
    }

    public var openIssues: Int {
        get { self.stats.openIssues }
        set { self.stats.openIssues = newValue }
    }

    public var openPulls: Int {
        get { self.stats.openPulls }
        set { self.stats.openPulls = newValue }
    }

    public var stars: Int {
        get { self.stats.stars }
        set { self.stats.stars = newValue }
    }

    public var forks: Int {
        get { self.stats.forks }
        set { self.stats.forks = newValue }
    }

    public var pushedAt: Date? {
        get { self.stats.pushedAt }
        set { self.stats.pushedAt = newValue }
    }
}

public enum CIStatus: Codable, Equatable, Sendable {
    case passing
    case failing
    case pending
    case unknown
}

public struct Release: Codable, Equatable, Sendable {
    public let name: String
    public let tag: String
    public let publishedAt: Date
    public let url: URL

    public init(name: String, tag: String, publishedAt: Date, url: URL) {
        self.name = name
        self.tag = tag
        self.publishedAt = publishedAt
        self.url = url
    }
}

public struct TrafficStats: Codable, Equatable, Sendable {
    public let uniqueVisitors: Int
    public let uniqueCloners: Int
    /// Total (not unique) views and clones over the last 14 days. Nil in stats cached before
    /// these existed; the panel then shows only the unique counts.
    public let views: Int?
    public let clones: Int?
    /// Per-day counts for the last 14 days, oldest first (see `dailySeries`).
    public let viewsByDay: [Int]?
    public let clonesByDay: [Int]?

    public init(
        uniqueVisitors: Int, uniqueCloners: Int,
        views: Int? = nil, clones: Int? = nil, viewsByDay: [Int]? = nil, clonesByDay: [Int]? = nil
    ) {
        self.uniqueVisitors = uniqueVisitors
        self.uniqueCloners = uniqueCloners
        self.views = views
        self.clones = clones
        self.viewsByDay = viewsByDay
        self.clonesByDay = clonesByDay
    }

    /// True when GitHub reports nothing for the window: the "no visitors yet" case.
    public var isEmpty: Bool {
        uniqueVisitors == 0 && uniqueCloners == 0 && (views ?? 0) == 0 && (clones ?? 0) == 0
    }

    /// `days` counts ending on the UTC day of `now`, oldest first. GitHub omits days with no
    /// traffic, so they come back as zero; points outside the window are dropped. GitHub's
    /// own window can start one day earlier than ours (it ends on the last full day), so when
    /// its oldest point sits exactly one day outside, the series ends a day sooner and keeps it.
    public static func dailySeries(_ points: [(date: Date, count: Int)], endingOn now: Date, days: Int = 14) -> [Int] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let today = calendar.startOfDay(for: now)
        func back(_ date: Date) -> Int? {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: today).day
        }
        let offset = points.contains { back($0.date) == days } ? 1 : 0
        var series = [Int](repeating: 0, count: days)
        for point in points {
            guard let ago = back(point.date).map({ $0 - offset }), ago >= 0, ago < days else { continue }
            series[days - 1 - ago] += point.count
        }
        return series
    }
}

public struct ActivityEvent: Codable, Equatable, Sendable {
    public let title: String
    public let actor: String
    public let actorAvatarURL: URL?
    public let date: Date
    public let url: URL
    public let eventType: String?
    public let metadata: ActivityMetadata?

    public init(
        title: String,
        actor: String,
        actorAvatarURL: URL? = nil,
        date: Date,
        url: URL,
        eventType: String? = nil,
        metadata: ActivityMetadata? = nil
    ) {
        self.title = title
        self.actor = actor
        self.actorAvatarURL = actorAvatarURL
        self.date = date
        self.url = url
        self.eventType = eventType
        self.metadata = metadata
    }

    public var eventTypeEnum: ActivityEventType? {
        ActivityEventType.parse(self.eventType)
    }
}

public struct HeatmapCell: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let date: Date
    public let count: Int

    public init(id: UUID = UUID(), date: Date, count: Int) {
        self.id = id
        self.date = date
        self.count = count
    }
}

/// One year of the user's GitHub contributions: the total, its split by kind and, when the
/// calendar was fetched too, the total per month.
public struct ContributionYear: Identifiable, Equatable, Codable, Sendable {
    public var id: Int { self.year }
    public let year: Int
    public let total: Int
    public let commits: Int
    public let pullRequests: Int
    public let issues: Int
    public let reviews: Int
    /// The year's contributions per month, January first (12 entries), or empty when only the
    /// total is known. The All-time grid draws from these.
    public let months: [Int]

    public init(year: Int, total: Int, commits: Int, pullRequests: Int, issues: Int, reviews: Int, months: [Int] = []) {
        self.year = year
        self.months = months
        self.total = total
        self.commits = commits
        self.pullRequests = pullRequests
        self.issues = issues
        self.reviews = reviews
    }

    /// Sums `days` into 12 monthly totals for `year` (UTC, like GitHub's calendar dates).
    /// Days outside the year are ignored.
    public static func monthlyTotals(year: Int, days: [(date: Date, count: Int)]) -> [Int] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        var totals = [Int](repeating: 0, count: 12)
        for day in days {
            let parts = calendar.dateComponents([.year, .month], from: day.date)
            guard parts.year == year, let month = parts.month, (1 ... 12).contains(month) else { continue }
            totals[month - 1] += day.count
        }
        return totals
    }
}

/// How far back the panel's "Your activity" strip looks.
public enum ActivityRange: String, CaseIterable, Codable, Sendable {
    case week
    case month
    case quarter
    case year
    case allTime
}

public struct CIStatusDetails: Codable, Sendable {
    public let status: CIStatus
    public let runCount: Int?

    public init(status: CIStatus, runCount: Int?) {
        self.status = status
        self.runCount = runCount
    }
}
