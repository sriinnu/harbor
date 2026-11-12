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
    public var autoCheckForUpdates: Bool = true
    public var autoDownloadUpdates: Bool = true
    public var quietIndicators = QuietIndicatorSettings()
    public var healthCheckEnabled: Bool = true
    public var githubHost: URL = .init(string: "https://github.com")!
    public var enterpriseHost: URL?
    public var loopbackPort: Int = 53682
    public var hotkey = HotkeySettings()
    /// Post a notification when something newly needs the user (a review request, or their own
    /// pull request turning red, conflicted, changed-requested or ready).
    public var notifyNeedsYou: Bool = true
    /// The panel's first-run welcome was dismissed or made unnecessary (signed in, or a folder
    /// added). Never reset: it must not come back after a sign-out. Not a secret.
    public var firstRunDismissed: Bool = false
    /// The signed-in GitHub accounts: logins, hosts, which is active. Never a token; those are in the Keychain.
    public var githubAccounts = GitHubAccountIndex()

    public init() {}

    /// Settings saved before a field existed must still load: a thrown key error makes the
    /// store discard the user's whole settings file.
    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.appearance = try container.decodeIfPresent(AppearanceSettings.self, forKey: .appearance) ?? self.appearance
        self.heatmap = try container.decodeIfPresent(HeatmapSettings.self, forKey: .heatmap) ?? self.heatmap
        self.repoList = try container.decodeIfPresent(RepoListSettings.self, forKey: .repoList) ?? self.repoList
        self.localProjects = try container.decodeIfPresent(LocalProjectsSettings.self, forKey: .localProjects) ?? self.localProjects
        self.refreshInterval = try container.decodeIfPresent(RefreshInterval.self, forKey: .refreshInterval) ?? self.refreshInterval
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? self.launchAtLogin
        self.debugPaneEnabled = try container.decodeIfPresent(Bool.self, forKey: .debugPaneEnabled) ?? self.debugPaneEnabled
        self.diagnosticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .diagnosticsEnabled) ?? self.diagnosticsEnabled
        self.autoCheckForUpdates = try container.decodeIfPresent(Bool.self, forKey: .autoCheckForUpdates) ?? self.autoCheckForUpdates
        self.autoDownloadUpdates = try container.decodeIfPresent(Bool.self, forKey: .autoDownloadUpdates) ?? self.autoDownloadUpdates
        self.quietIndicators = try container.decodeIfPresent(QuietIndicatorSettings.self, forKey: .quietIndicators) ?? self.quietIndicators
        self.healthCheckEnabled = try container.decodeIfPresent(Bool.self, forKey: .healthCheckEnabled) ?? self.healthCheckEnabled
        self.githubHost = try container.decodeIfPresent(URL.self, forKey: .githubHost) ?? self.githubHost
        self.enterpriseHost = try container.decodeIfPresent(URL.self, forKey: .enterpriseHost)
        self.loopbackPort = try container.decodeIfPresent(Int.self, forKey: .loopbackPort) ?? self.loopbackPort
        self.hotkey = try container.decodeIfPresent(HotkeySettings.self, forKey: .hotkey) ?? self.hotkey
        self.notifyNeedsYou = try container.decodeIfPresent(Bool.self, forKey: .notifyNeedsYou) ?? self.notifyNeedsYou
        self.firstRunDismissed = try container.decodeIfPresent(Bool.self, forKey: .firstRunDismissed) ?? self.firstRunDismissed
        self.githubAccounts = try container.decodeIfPresent(GitHubAccountIndex.self, forKey: .githubAccounts) ?? self.githubAccounts
    }
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
    public var theme: HarborThemeID = .native
    public var showHarborView = true
    public var activityRange: ActivityRange = .quarter

    public init() {}

    /// Settings saved before a field existed must still load: a thrown key error
    /// makes the store discard the user's whole settings file.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.showContributionHeader = try container.decodeIfPresent(Bool.self, forKey: .showContributionHeader) ?? true
        self.cardDensity = try container.decodeIfPresent(CardDensity.self, forKey: .cardDensity) ?? .comfortable
        self.accentTone = try container.decodeIfPresent(AccentTone.self, forKey: .accentTone) ?? .githubGreen
        self.activityScope = try container.decodeIfPresent(GlobalActivityScope.self, forKey: .activityScope) ?? .myActivity
        self.theme = try container.decodeIfPresent(HarborThemeID.self, forKey: .theme) ?? .native
        self.showHarborView = try container.decodeIfPresent(Bool.self, forKey: .showHarborView) ?? true
        self.activityRange = try container.decodeIfPresent(ActivityRange.self, forKey: .activityRange) ?? .quarter
    }
}

public struct LocalProjectsSettings: Equatable, Codable, Sendable {
    /// Ordered folders Harbor scans for Git repositories. Empty means the user removed them all.
    public var rootPaths: [String] = []
    /// Security-scoped bookmarks, keyed by the matching entry in `rootPaths`.
    public var rootBookmarks: [String: Data] = [:]
    public var autoSyncEnabled: Bool = false
    public var showDirtyFilesInMenu: Bool = false
    public var fetchInterval: LocalProjectsRefreshInterval = .fiveMinutes
    public var worktreeFolderName: String = ".work"
    public var preferredTerminal: String?
    public var ghosttyOpenMode: GhosttyOpenMode = .tab
    public var preferredLocalPathsByFullName: [String: String] = [:]

    public static let defaultRootPath = "~/Projects"

    public init() {
        #if DEBUG
            self.rootPaths = [Self.defaultRootPath]
        #endif
    }

    /// Bookmarks of the folders currently in the list, in list order.
    public var rootBookmarkList: [Data] {
        self.rootPaths.compactMap { self.rootBookmarks[$0] }
    }

    /// Adds a folder unless one with the same resolved real path is already listed.
    /// Returns whether the folder was added.
    @discardableResult
    public mutating func addRoot(_ path: String, bookmark: Data? = nil) -> Bool {
        let key = Self.realPath(path)
        guard self.rootPaths.contains(where: { Self.realPath($0) == key }) == false else { return false }
        self.rootPaths.append(path)
        if let bookmark { self.rootBookmarks[path] = bookmark }
        return true
    }

    public mutating func removeRoot(_ path: String) {
        self.rootPaths.removeAll { $0 == path }
        self.rootBookmarks[path] = nil
    }

    private static func realPath(_ path: String) -> String {
        URL(fileURLWithPath: PathFormatter.expandTilde(path)).resolvingSymlinksInPath().standardizedFileURL.path
    }

    private enum CodingKeys: String, CodingKey {
        case rootPaths
        case rootBookmarks
        case rootPath // legacy single folder, read only
        case rootBookmarkData // legacy single bookmark, read only
        case autoSyncEnabled
        case showDirtyFilesInMenu
        case fetchInterval
        case worktreeFolderName
        case preferredTerminal
        case ghosttyOpenMode
        case preferredLocalPathsByFullName
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let paths = try container.decodeIfPresent([String].self, forKey: .rootPaths) {
            self.rootPaths = paths
            self.rootBookmarks = try container.decodeIfPresent([String: Data].self, forKey: .rootBookmarks) ?? [:]
        } else if let legacy = try container.decodeIfPresent(String.self, forKey: .rootPath) {
            self.rootPaths = legacy.isEmpty ? [] : [legacy]
            if let bookmark = try container.decodeIfPresent(Data.self, forKey: .rootBookmarkData), legacy.isEmpty == false {
                self.rootBookmarks = [legacy: bookmark]
            }
        } else {
            // Never chose a folder, or cleared it: same as a fresh install, so an upgrade
            // never auto-syncs a folder the user didn't pick.
            self.rootPaths = []
        }
        self.autoSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoSyncEnabled) ?? false
        self.showDirtyFilesInMenu = try container.decodeIfPresent(Bool.self, forKey: .showDirtyFilesInMenu) ?? false
        self.fetchInterval = try container.decodeIfPresent(LocalProjectsRefreshInterval.self, forKey: .fetchInterval) ?? .fiveMinutes
        self.worktreeFolderName = try container.decodeIfPresent(String.self, forKey: .worktreeFolderName) ?? ".work"
        self.preferredTerminal = try container.decodeIfPresent(String.self, forKey: .preferredTerminal)
        self.ghosttyOpenMode = try container.decodeIfPresent(GhosttyOpenMode.self, forKey: .ghosttyOpenMode) ?? .tab
        self.preferredLocalPathsByFullName = try container.decodeIfPresent([String: String].self, forKey: .preferredLocalPathsByFullName) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.rootPaths, forKey: .rootPaths)
        try container.encode(self.rootBookmarks, forKey: .rootBookmarks)
        try container.encode(self.autoSyncEnabled, forKey: .autoSyncEnabled)
        try container.encode(self.showDirtyFilesInMenu, forKey: .showDirtyFilesInMenu)
        try container.encode(self.fetchInterval, forKey: .fetchInterval)
        try container.encode(self.worktreeFolderName, forKey: .worktreeFolderName)
        try container.encodeIfPresent(self.preferredTerminal, forKey: .preferredTerminal)
        try container.encode(self.ghosttyOpenMode, forKey: .ghosttyOpenMode)
        try container.encode(self.preferredLocalPathsByFullName, forKey: .preferredLocalPathsByFullName)
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
