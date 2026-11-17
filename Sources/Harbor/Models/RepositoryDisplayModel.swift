import Foundation
import HarborCore

struct RepositoryDisplayModel: Identifiable, Equatable {
    struct Stat: Identifiable, Equatable {
        let id: String
        let label: String?
        let value: Int
        let systemImage: String
    }

    let source: Repository
    let id: String
    /// The row's identity (`RepoKey` string). Never shown: an Azure key reads `azure:…`.
    let title: String
    /// What people read: `owner/name`, or `project/name` for an Azure DevOps repo.
    var displayTitle: String { self.source.displayName }
    /// What the panel's text filter matches: the readable name, plus organization and
    /// project for Azure, never the `azure:dev.azure.com` key.
    var searchName: String {
        guard let azure = self.source.azure else { return self.title }
        return "\(azure.organization)/\(azure.project)/\(self.source.name)"
    }
    let releaseLine: String?
    let lastPushAge: String?
    let ciStatus: CIStatus
    let ciRunCount: Int?
    let issues: Int
    let pulls: Int
    let stats: [Stat]
    let trafficVisitors: Int?
    let trafficCloners: Int?
    let stars: Int
    let forks: Int
    let activityLine: String?
    let activityURL: URL?
    let activityEvents: [ActivityEvent]
    let latestActivityAge: String?
    let heatmap: [HeatmapCell]
    let sortOrder: Int?
    let error: String?
    let rateLimitedUntil: Date?
    let localStatus: LocalRepoStatus?

    init(repo: Repository, localStatus: LocalRepoStatus? = nil, now: Date = Date()) {
        self.source = repo
        self.id = repo.id
        self.title = repo.fullName
        self.ciStatus = repo.ciStatus
        self.ciRunCount = repo.ciRunCount
        self.issues = repo.stats.openIssues
        self.pulls = repo.stats.openPulls
        self.trafficVisitors = repo.traffic?.uniqueVisitors
        self.trafficCloners = repo.traffic?.uniqueCloners
        self.stars = repo.stats.stars
        self.forks = repo.stats.forks
        self.heatmap = repo.heatmap
        self.sortOrder = repo.sortOrder
        self.error = repo.error
        self.rateLimitedUntil = repo.rateLimitedUntil
        self.localStatus = localStatus

        if let release = repo.latestRelease {
            self.releaseLine = ReleaseFormatter.menuLine(for: release, now: now)
        } else {
            self.releaseLine = nil
        }

        if let pushedAt = repo.stats.pushedAt {
            self.lastPushAge = RelativeFormatter.string(from: pushedAt, relativeTo: now)
        } else {
            self.lastPushAge = nil
        }

        self.activityLine = repo.activityLine
        self.activityURL = repo.activityURL
        if repo.activityEvents.isEmpty, let latest = repo.latestActivity {
            self.activityEvents = [latest]
        } else {
            self.activityEvents = repo.activityEvents
        }
        if let activityDate = repo.latestActivity?.date ?? self.activityEvents.first?.date {
            self.latestActivityAge = RelativeFormatter.string(from: activityDate, relativeTo: now)
        } else {
            self.latestActivityAge = nil
        }

        var stats: [Stat] = []
        if repo.pullCountsKnown {
            stats.append(Stat(id: "issues", label: "Issues", value: repo.stats.openIssues, systemImage: "exclamationmark.circle"))
            stats.append(Stat(id: "prs", label: "PRs", value: repo.stats.openPulls, systemImage: "arrow.triangle.branch"))
        }
        // Azure DevOps has no stars or forks; its rows show none rather than a made-up zero.
        if !repo.isAzure {
            stats.append(Stat(id: "stars", label: nil, value: repo.stats.stars, systemImage: "star"))
            stats.append(Stat(id: "forks", label: "Forks", value: repo.stats.forks, systemImage: "tuningfork"))
        }
        if let alerts = repo.security?.openAlertCount, alerts > 0 {
            stats.append(Stat(id: "security", label: "Alerts", value: alerts, systemImage: "exclamationmark.shield"))
        }
        self.stats = stats
    }
}
