import Foundation

public struct UserSettings: Equatable, Codable, Sendable {
    public var appearance = AppearanceSettings()
    public var heatmap = HeatmapSettings()
    public var repoList = RepoListSettings()
    public var localProjects = LocalProjectsSettings()
    public var refreshInterval: RefreshInterval = .fiveMinutes
    public var launchAtLogin = false
    public var debugPaneEnabled: Bool = false
    public var diagnosticsEnabled: Bool = false
    public var autoCheckForUpdates: Bool = false
    public var autoDownloadUpdates: Bool = false
    public var quietIndicators = QuietIndicatorSettings()
    public var healthCheckEnabled: Bool = true
    public var githubHost: URL = .init(string: "https://github.com")!
    public var enterpriseHost: URL?
    public var loopbackPort: Int = 53682

    public init() {}
}

public struct HeatmapSettings: Equatable, Codable, Sendable {
    public var display: HeatmapDisplay = .inline
    public var span: HeatmapSpan = .twelveMonths

    public init() {}
}

public struct RepoListSettings: Equatable, Codable, Sendable {
    public var displayLimit: Int = 6
    public var showForks = false
    public var showArchived = false
    public var menuSortKey: RepositorySortKey = .activity
    public var pinnedRepositories: [String] = [] // owner/name
    public var hiddenRepositories: [String] = [] // owner/name

    public init() {}
}

public struct AppearanceSettings: Equatable, Codable, Sendable {
    public var showContributionHeader = true
    public var cardDensity: CardDensity = .comfortable
    public var accentTone: AccentTone = .githubGreen
    public var activityScope: GlobalActivityScope = .myActivity

    public init() {}
}

public struct LocalProjectsSettings: Equatable, Codable, Sendable {
    public var rootPath: String?
    public var rootBookmarkData: Data?
    public var autoSyncEnabled: Bool = true
    public var showDirtyFilesInMenu: Bool = false
    public var fetchInterval: LocalProjectsRefreshInterval = .fiveMinutes
    public var worktreeFolderName: String = ".work"
    public var preferredTerminal: String?
    public var ghosttyOpenMode: GhosttyOpenMode = .tab
    public var preferredLocalPathsByFullName: [String: String] = [:]

    public init() {
        #if DEBUG
            self.rootPath = "~/Projects"
        #endif
    }
}

public enum LocalProjectsRefreshInterval: String, CaseIterable, Equatable, Codable, Sendable {
    case oneMinute
    case twoMinutes
    case fiveMinutes
    case fifteenMinutes

    public var seconds: TimeInterval {
        switch self {
        case .oneMinute: 60
        case .twoMinutes: 120
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        }
    }

    public var label: String {
        switch self {
        case .oneMinute: "1 minute"
        case .twoMinutes: "2 minutes"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        }
    }
}

public enum GhosttyOpenMode: String, CaseIterable, Equatable, Codable, Sendable {
    case newWindow
    case tab

    public var label: String {
        switch self {
        case .newWindow: "New Window"
        case .tab: "Tab"
        }
    }
}

public enum RefreshInterval: CaseIterable, Equatable, Codable, Sendable {
    case disabled
    case thirtySeconds
    case oneMinute
    case twoMinutes
    case fiveMinutes
    case tenMinutes
    case fifteenMinutes

    public var seconds: TimeInterval {
        switch self {
        case .disabled: 0
        case .thirtySeconds: 30
        case .oneMinute: 60
        case .twoMinutes: 120
        case .fiveMinutes: 300
        case .tenMinutes: 600
        case .fifteenMinutes: 900
        }
    }

    public var label: String {
        switch self {
        case .disabled: "Disabled"
        case .thirtySeconds: "30 seconds"
        case .oneMinute: "1 minute"
        case .twoMinutes: "2 minutes"
        case .fiveMinutes: "5 minutes"
        case .tenMinutes: "10 minutes"
        case .fifteenMinutes: "15 minutes"
        }
    }

    public var shortLabel: String {
        switch self {
        case .disabled: "Off"
        case .thirtySeconds: "30s"
        case .oneMinute: "1m"
        case .twoMinutes: "2m"
        case .fiveMinutes: "5m"
        case .tenMinutes: "10m"
        case .fifteenMinutes: "15m"
        }
    }
}

public enum HeatmapDisplay: String, CaseIterable, Equatable, Codable, Sendable {
    case inline
    case submenu

    public var label: String {
        switch self {
        case .inline: "Inline"
        case .submenu: "Submenu"
        }
    }
}

public enum CardDensity: String, CaseIterable, Equatable, Codable, Sendable {
    case comfortable
    case compact

    public var label: String {
        switch self {
        case .comfortable: "Comfortable"
        case .compact: "Compact"
        }
    }
}

public enum AccentTone: String, CaseIterable, Equatable, Codable, Sendable {
    case system
    case githubGreen

    public var label: String {
        switch self {
        case .system: "System accent"
        case .githubGreen: "GitHub greens"
        }
    }
}

public enum GlobalActivityScope: String, CaseIterable, Equatable, Codable, Sendable {
    case allActivity
    case myActivity

    public var label: String {
        switch self {
        case .allActivity: "All activity"
        case .myActivity: "My activity"
        }
    }
}
