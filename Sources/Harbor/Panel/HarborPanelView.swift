import HarborCore
import SwiftUI

/// What the panel can ask of the app. Plain closures, so the views never reach into the
/// menu manager.
struct HarborPanelActions {
    var refresh: () -> Void = {}
    var openRepo: (RepositoryDisplayModel) -> Void = { _ in }
    var openRepoPath: (RepositoryDisplayModel, String) -> Void = { _, _ in }
    var openTerminal: (URL) -> Void = { _ in }
    var togglePin: (RepositoryDisplayModel, Bool) -> Void = { _, _ in }
    var openActivity: () -> Void = {}
    var selectActivityRange: (ActivityRange) -> Void = { _ in }
    /// Starts loading a repo's commit activity; called when its detail opens.
    var loadRepoActivity: (RepositoryDisplayModel) -> Void = { _ in }
    var openSettings: () -> Void = {}
    var openAbout: () -> Void = {}
    var openGitHub: () -> Void = {}
    var supportHarbor: () -> Void = {}
    var signIn: () -> Void = {}
    /// Switches to another signed-in GitHub account, by its account id.
    var switchAccount: (String) -> Void = { _ in }
    /// First run: the folder picker for local projects.
    var addProjectFolder: () -> Void = {}
    /// First run: hides the welcome for good (also called once the app is set up).
    var dismissWelcome: () -> Void = {}
    /// The GitHub API budget left, for the status bar; nil when none has been seen yet.
    var loadRateLimit: () async -> RateLimitSnapshot? = { nil }
    /// Runs a Git command on a local clone and returns its fresh status.
    var runLocalGit: LocalGitCommandRunner = { _, _ in nil }
    var quit: () -> Void = {}
}

/// One thing waiting on you.
struct PanelNeed: Identifiable {
    let id: String
    /// The repo it opens; nil for a review request on a repo that is not in the list.
    let repo: RepositoryDisplayModel?
    let kind: StatusGlyph.Kind
    let title: String
    let detail: String
    let age: String?
    /// Set for a review request: the row opens this pull request's pane.
    var pull: PanelPullTarget?
}

struct PanelPullTarget: Equatable {
    let fullName: String
    let number: Int
}

/// What the panel shows, gathered fresh by the menu builder each time the session changes.
struct HarborPanelContent {
    var login: String?
    /// The signed-in GitHub accounts, for the switcher beside the name; empty or one means no switcher.
    var accounts: [AccountChoice] = []
    var providers: [ProviderType] = []
    var lastRefresh: Date?
    var isRefreshing = false
    var rateLimitReset: Date?
    var error: String?
    /// The rows drawn: the Pinned/All filter and the display limit applied.
    var repos: [RepositoryDisplayModel] = []
    /// Every repo of the account, unfiltered and unlimited. Needs you, calm and the menu bar
    /// icon are judged on these, so a failing repo below the display limit still counts.
    /// nil means `repos` is everything.
    var judged: [RepositoryDisplayModel]?
    var pinned: Set<String> = []
    var activity = PanelActivity()
    var hasLoadedRepositories = false
    /// Each opened repo's commit activity, keyed by full name.
    var repoActivity: [String: RepoActivitySlice] = [:]
    /// The range every strip shares (the user's, and each repo's).
    var activityRange: ActivityRange = .quarter
    /// Pull requests asking for the user's review, from one search each time the panel opens.
    var reviewRequests: [ReviewRequest] = []
    /// GitHub's count of them, which can be more than `reviewRequests` holds.
    var reviewRequestsTotal: Int?
    /// Why the review-request search failed; nil when it worked.
    var reviewRequestsFailure: String?
    /// True once a review-request search has answered (list or failure) in this session. Before
    /// that, no review requests means "not asked yet", not "none". In-memory, never saved.
    var reviewRequestsLoaded = false
    /// The user's own open pull requests; Needs you lists the ones with a reason.
    var myPulls: [MyPullRequest] = []
    /// Why the search for them failed; nil when it worked.
    var myPullsFailure: String?
    /// True once the search for the user's own pull requests has answered (list or failure).
    /// Before that, no pulls means "not asked yet", not "none".
    var myPullsLoaded = false
    /// Full names of listed repos this refresh did not count. Not "checking": their counts load
    /// when opened, and the calm line says how many were left out.
    var deferredRepos: Set<String> = []

    /// The strip for one repo's detail pane: loading while the fetch runs, nothing when the
    /// repo has no commits to show. A failure comes back as a note instead.
    func repoStrip(for repo: RepositoryDisplayModel) -> (activity: PanelActivity?, note: String?) {
        let range = self.activityRange
        let slice = self.repoActivity[repo.title] ?? RepoActivitySlice()
        switch slice.state {
        case .idle, .loading:
            // The cells already on screen stay up while the new request runs.
            if !slice.days.isEmpty { return (PanelActivity(range: range, githubDays: slice.days, isRepo: true), nil) }
            return (PanelActivity(range: range, isRepo: true, isLoadingRepo: true), nil)
        case .ready:
            guard !slice.days.isEmpty else { return (nil, nil) }
            return (PanelActivity(range: range, githubDays: slice.days, isRepo: true), nil)
        case let .failed(reason):
            return (nil, reason)
        }
    }

    /// The repos Needs you and calm are judged on.
    var judgedRepos: [RepositoryDisplayModel] { self.judged ?? self.repos }

    /// Failing builds and security alerts first, then pull requests waiting on your review,
    /// then local clones that are behind their upstream.
    var needsYou: [PanelNeed] {
        var items: [PanelNeed] = []
        for repo in self.judgedRepos where repo.ciStatus == .failing || (repo.source.security?.openAlertCount ?? 0) > 0 {
            items.append(PanelNeed(
                id: "need:\(repo.id)", repo: repo, kind: repo.ciStatus == .failing ? .fail : .pending,
                title: repo.title, detail: Self.reasons(for: repo), age: repo.latestActivityAge
            ))
        }
        items += Self.reviewNeeds(self.reviewRequests)
        items += Self.myPullNeeds(self.myPulls)
        for repo in self.judgedRepos {
            guard let local = repo.localStatus, let behind = local.behindCount, behind > 0 else { continue }
            items.append(PanelNeed(
                id: "behind:\(repo.id)", repo: repo, kind: .behind, title: "\(repo.source.name) · local",
                detail: Self.behindDetail(local, behind: behind), age: nil
            ))
        }
        return items
    }

    /// Repos whose counts could not be read: the batch failed or GitHub left them out, or a
    /// detail read failed. They carry an error on the row.
    var uncheckedRepoCount: Int {
        self.judgedRepos.count(where: { $0.source.error != nil })
    }

    /// Repos still waiting for their first answer in this refresh: no error, counts not in yet.
    var checkingRepoCount: Int {
        self.judgedRepos.count(where: {
            $0.source.error == nil && !$0.source.pullCountsKnown && !self.deferredRepos.contains($0.source.fullName)
        })
    }

    /// What the panel (and the menu bar icon) may say about calm. Only `.clear` may show "All
    /// clear": every repo answered, none with an error, the review-request search has answered
    /// and worked, and no refresh failure is on screen.
    enum Calm: Equatable {
        case clear
        /// Answers are still on their way (repos, or the first review-request search).
        case checking(repos: Int)
        /// Something could not be read: this many repos, and whether the review search too.
        case unchecked(repos: Int, reviews: Bool)
        /// The refresh itself failed and its banner is up; what is below may be old.
        case refreshFailed
    }

    var calm: Calm {
        let failed = self.uncheckedRepoCount
        let reviewsFailed = self.reviewRequestsFailure != nil
        if failed > 0 || reviewsFailed || self.myPullsFailure != nil { return .unchecked(repos: failed, reviews: reviewsFailed) }
        if self.error != nil { return .refreshFailed }
        let waiting = self.checkingRepoCount
        return waiting > 0 || !self.reviewRequestsLoaded || !self.myPullsLoaded ? .checking(repos: waiting) : .clear
    }

    /// The notice under Needs you when something could not be checked.
    var uncheckedNotice: String? {
        guard case let .unchecked(repos, reviews) = self.calm else { return nil }
        var parts: [String] = []
        if repos > 0 { parts.append(repos == 1 ? "1 repo" : "\(repos) repos") }
        if reviews { parts.append("your review requests") }
        if self.myPullsFailure != nil { parts.append("your pull requests") }
        return parts.isEmpty ? nil : "Couldn't check " + parts.joined(separator: " or ")
    }

    /// "N repos not counted yet", whenever repos were left out of this refresh and the all-clear
    /// line (which says it itself) is not what is showing: the cap on what a refresh counts must
    /// be stated next to any Needs you list, not only when everything is calm.
    var notCountedNote: String? {
        guard deferredRepos.isEmpty == false else { return nil }
        if needsYou.isEmpty, case .clear = calm { return nil }
        let count = deferredRepos.count
        return "\(count) \(count == 1 ? "repo" : "repos") not counted yet"
    }

    /// Review requests GitHub counted beyond the rows Needs you lists.
    var moreReviewRequests: Int {
        guard let total = self.reviewRequestsTotal else { return 0 }
        return max(total - min(self.reviewRequests.count, Self.maxReviewRows), 0)
    }

    /// Open pull requests across the listed repos, for the greeting.
    var openPullCount: Int {
        self.repos.filter(\.source.pullCountsKnown).reduce(0) { $0 + $1.pulls }
    }

    static func reasons(for repo: RepositoryDisplayModel) -> String {
        var reasons: [String] = []
        if repo.ciStatus == .failing { reasons.append("CI failing") }
        if let alerts = repo.source.security?.openAlertCount, alerts > 0 {
            reasons.append(alerts == 1 ? "1 security alert" : "\(alerts) security alerts")
        }
        return reasons.joined(separator: " · ")
    }

    static func behindDetail(_ local: LocalRepoStatus, behind: Int) -> String {
        var line = "\(local.branch) is \(behind) behind \(local.upstreamBranch ?? "origin")"
        if !local.isClean {
            line += " · local changes"
        } else if (local.aheadCount ?? 0) == 0 {
            line += " · clean, safe to fast-forward"
        }
        return line
    }
}

/// Harbor's own menu bar surface: the theme's design drawn whole, background and all,
/// instead of rows inside the system menu.
struct HarborPanelView: View {
    @Bindable var session: Session
    let content: () -> HarborPanelContent
    let actions: HarborPanelActions
    /// The one Tower: the status item owns it and keeps it running for the icon's count; the tab only shows it.
    let tower: TowerModel
    @Environment(\.harborPanelSkin) private var skin
    @Environment(\.panelNavigator) private var navigator
    @Environment(\.panelMaxHeight) private var maxHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var detail: RepositoryDisplayModel?
    /// The Tower tab (agent worktrees across repos) instead of the repo list.
    @State private var showsTower = false
    /// The open pull request, over the repo detail it was opened from.
    @State private var pull: PullDetailModel?
    /// The open list (issues, pull requests, ...), over the repo detail it was opened from.
    @State private var list: RepoListModel?
    /// The Harbor tab: one boat per repository.
    @State private var showsHarbor = false
    /// Git actions on local clones, shared by the repo detail and the Needs-you rows.
    @State private var localGit = LocalGitHub()
    @State private var listHeight: CGFloat?
    @State private var topHeight: CGFloat = 0
    @State private var bottomHeight: CGFloat = 0

    var body: some View {
        let content = self.content()
        ZStack(alignment: .topLeading) {
            if let pull {
                HarborPullDetailPane(model: pull, onBack: { self.leavePull() })
                    .pinsPanelOpen("pull-action", while: pull.confirming != nil || pull.running != nil)
                    .transition(.move(edge: .trailing))
            } else if let detail, let list {
                HarborRepoListPane(
                    model: list,
                    onBack: { self.leaveList() },
                    openPull: { self.showPull(fullName: "\(list.owner)/\(list.name)", number: $0) },
                    openWeb: { self.actions.openRepoPath(detail, list.kind.webPath) }
                )
                .transition(.move(edge: .trailing))
            } else if let detail {
                let strip = content.repoStrip(for: detail)
                HarborRepoDetailPane(
                    repo: detail,
                    activity: strip.activity,
                    activityNote: strip.note,
                    isPinned: content.pinned.contains(detail.title),
                    actions: self.actions,
                    onBack: { self.leaveDetail() },
                    openPull: { self.showPull(of: detail, number: $0) },
                    openList: { self.openList($0, of: detail) },
                    localGit: detail.localStatus.map { self.localGit.model(for: $0.path) }
                )
                .transition(.move(edge: .trailing))
            } else {
                self.main(content)
                    .transition(.move(edge: .leading))
            }
        }
        .padding(self.skin.padding)
        .frame(width: self.skin.width, alignment: .topLeading)
        .background { PanelSurface() }
        .clipShape(RoundedRectangle(cornerRadius: self.skin.cornerRadius, style: .continuous))
        .overlay { self.frameLines }
        .environment(\.colorScheme, self.skin.colorScheme)
        .environment(\.menuRowStyle, self.skin.row)
        .onPreferenceChange(PanelNavKey.self) { items in self.navigator?.update(items) }
        .onChange(of: self.filterScope(content), initial: true) { _, scope in self.navigator?.setFilterScope(scope) }
        .onAppear {
            self.navigator?.goBack = { self.leaveDetail() }
            self.localGit.runner = self.actions.runLocalGit
            self.navigator?.showPull = { title, number in
                #if DEBUG
                    if number == 0 {
                        self.pull = PullDetailModel.preview()
                        return
                    }
                #endif
                self.detail = self.content().repos.first(where: { $0.title == title })
                self.showPull(fullName: title, number: number)
            }
            self.navigator?.showRepo = { title in
                let repos = self.content().repos
                if let repo = repos.first(where: { $0.title == title }) ?? (title == nil ? repos.first : nil) { self.show(repo) }
            }
            self.navigator?.commands = [",": self.actions.openSettings, "q": self.actions.quit, "t": { self.setTower(!self.showsTower) }]
            self.navigator?.showList = { kind in
                if let detail = self.detail { self.openList(kind, of: detail) }
            }
            self.navigator?.showHarbor = { self.setMode($0 ? .harbor : .repos) }
            self.navigator?.showTower = { openFirst in
                self.setTower(true)
                guard openFirst else { return }
                Task {
                    for _ in 0 ..< 40 where self.tower.rows.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
                    self.tower.openRow = self.tower.rows(in: .needsYou).first?.id ?? self.tower.rows.first?.id
                }
            }
        }
    }

    /// The border, and the chart's second ruled line inside it.
    private var frameLines: some View {
        let shape = RoundedRectangle(cornerRadius: self.skin.cornerRadius, style: .continuous)
        return ZStack {
            shape.strokeBorder(self.skin.border.color, lineWidth: self.skin.border.width)
            if let rule = self.skin.insetRule {
                RoundedRectangle(cornerRadius: max(self.skin.cornerRadius - 3, 0), style: .continuous)
                    .strokeBorder(rule.color, lineWidth: rule.width)
                    .padding(self.skin.border.width + 3)
            }
        }
        .allowsHitTesting(false)
    }

    /// Which rows typing narrows on the screen shown (nil: typing does nothing here).
    private func filterScope(_ content: HarborPanelContent) -> String? {
        guard content.login != nil, self.pull == nil, !self.showsTower else { return nil }
        if self.detail != nil { return self.list != nil ? "list:" : nil }
        return self.showsHarbor ? "boat:" : "repo:"
    }

    private var filterQuery: String { self.navigator?.filter ?? "" }

    /// The repos the typed filter leaves. While filtering, the whole account is searched (minus
    /// hidden repos), not only the rows the display limit draws.
    private func filteredRepos(_ content: HarborPanelContent) -> [RepositoryDisplayModel] {
        guard !NameFilter.tokens(self.filterQuery).isEmpty else { return content.repos }
        let hidden = Set(self.session.settings.repoList.hiddenRepositories)
        let pool = content.judgedRepos.filter { !hidden.contains($0.title) }
        return NameFilter.filter(pool, query: self.filterQuery, name: \.title)
    }

    private func showPull(of repo: RepositoryDisplayModel, number: Int) {
        self.showPull(fullName: repo.title, number: number)
    }

    private func showPull(fullName: String, number: Int) {
        if self.navigator?.blocksLeavingDetail == true { return }
        let parts = fullName.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return }
        withAnimation(.snappy(duration: 0.22)) { self.pull = PullDetailModel(owner: parts[0], name: parts[1], number: number) }
        self.navigator?.reset()
    }

    private func leavePull() {
        withAnimation(.snappy(duration: 0.22)) { self.pull = nil }
        self.navigator?.reset()
    }

    private func openList(_ kind: RepoListKind, of repo: RepositoryDisplayModel) {
        if self.navigator?.blocksLeavingDetail == true { return }
        withAnimation(.snappy(duration: 0.22)) { self.list = RepoListModel(kind: kind, fullName: repo.title) }
        self.navigator?.reset()
    }

    private func leaveList() {
        withAnimation(.snappy(duration: 0.22)) { self.list = nil }
        self.navigator?.reset()
    }

    @discardableResult
    private func leaveDetail() -> Bool {
        // A run cleanup deleting in this detail holds it: leaving would cancel it unreported.
        if self.pull == nil, self.list == nil, self.detail != nil, self.navigator?.blocksLeavingDetail == true { return true }
        if self.showsTower, self.tower.openRow != nil {
            self.tower.openRow = nil
            return true
        }
        if self.pull != nil {
            self.leavePull()
            return true
        }
        if self.list != nil {
            self.leaveList()
            return true
        }
        guard self.detail != nil else { return false }
        withAnimation(.snappy(duration: 0.22)) { self.detail = nil }
        self.navigator?.reset()
        return true
    }

    private func main(_ content: HarborPanelContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let login = content.login {
                VStack(alignment: .leading, spacing: 0) {
                    MenuAccountHeader(
                        login: login,
                        providers: content.providers,
                        lastRefresh: content.lastRefresh,
                        isRefreshing: content.isRefreshing,
                        onRefresh: self.actions.refresh,
                        accounts: content.accounts,
                        onSwitch: self.actions.switchAccount
                    )
                    self.greeting(content, login: login)
                    PanelSeparator()
                }
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { self.topHeight = $0 })
                self.scrollingList(content)
            } else if self.showsWelcome {
                PanelWelcomeView(actions: self.actions)
            } else {
                self.signedOut
            }
            VStack(alignment: .leading, spacing: 0) {
                PanelSeparator()
                if content.login != nil { self.statusBar(content) }
                self.footer
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { self.bottomHeight = $0 })
        }
        .onAppear { self.settleWelcome(signedIn: content.login != nil) }
        .onChange(of: content.login != nil) { _, signedIn in self.settleWelcome(signedIn: signedIn) }
        .onChange(of: self.session.settings.localProjects.rootPaths.isEmpty) { _, _ in
            self.settleWelcome(signedIn: self.content().login != nil)
        }
    }

    /// The welcome shows for an app that was never set up (see `FirstRun`). Only the signed-out
    /// screen asks: signed in, the panel is the list.
    private var showsWelcome: Bool {
        FirstRun.isVisible(
            dismissed: self.session.settings.firstRunDismissed,
            signedIn: false,
            hasProjectFolders: !self.session.settings.localProjects.rootPaths.isEmpty
        )
    }

    /// Once the user is signed in or has a folder the app is set up: remember it, so a later
    /// sign-out does not bring the welcome back.
    private func settleWelcome(signedIn: Bool) {
        guard !self.session.settings.firstRunDismissed else { return }
        if signedIn || !self.session.settings.localProjects.rootPaths.isEmpty { self.actions.dismissWelcome() }
    }

    /// Everything between the header and the footer scrolls once the panel would outgrow
    /// the screen.
    private func scrollingList(_ content: HarborPanelContent) -> some View {
        let available = self.maxHeight - 2 * self.skin.padding - self.topHeight - self.bottomHeight
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    self.banner(content)
                    self.modeBar
                    let filtering = !NameFilter.tokens(self.filterQuery).isEmpty && !self.showsTower
                    if filtering { PanelFilterBar(query: self.filterQuery, matches: self.filteredRepos(content).count) }
                    if self.showsTower {
                        TowerView(model: self.tower, actions: self.actions)
                    } else if self.showsHarbor {
                        HarborBoatsView(repos: self.filteredRepos(content), open: { self.show($0) })
                    } else {
                        // Filtering shows only the matches: Needs you and the activity chart wait.
                        if !filtering { self.needsYouSection(content) }
                        if content.hasLoadedRepositories, !filtering { self.filterBar }
                        self.repoList(content)
                        if !content.activity.isEmpty, !filtering {
                            PanelSeparator()
                            PanelActivitySection(
                                activity: content.activity,
                                selectRange: self.actions.selectActivityRange,
                                openProfile: self.actions.openActivity
                            )
                        }
                    }
                }
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { self.listHeight = $0 })
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: self.listHeight.map { min($0, max(available, 120)) })
            .onChange(of: self.navigator?.scrollRequest) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    @ViewBuilder
    private func banner(_ content: HarborPanelContent) -> some View {
        if let reset = content.rateLimitReset {
            PanelNotice(kind: .pending, text: "Rate limited · resets \(reset.formatted(date: .omitted, time: .shortened))")
        } else if let error = content.error {
            PanelNotice(kind: .fail, text: error)
        }
    }

    @ViewBuilder
    private func needsYouSection(_ content: HarborPanelContent) -> some View {
        let waiting = content.needsYou
        if !waiting.isEmpty {
            MenuSectionHeader(title: "Needs you · \(waiting.count)")
            ForEach(waiting.prefix(8)) { need in self.needRow(need) }
            if content.moreReviewRequests > 0 {
                Text("+\(content.moreReviewRequests) more review requests on GitHub")
                    .font(.system(size: self.skin.row.detailSize))
                    .foregroundStyle(self.skin.secondaryText)
                    .padding(.horizontal, self.skin.row.itemPadding)
                    .padding(.vertical, 2)
            }
            self.uncheckedNotice(content)
            self.notCountedNote(content)
            PanelSeparator()
        } else if content.hasLoadedRepositories, !content.judgedRepos.isEmpty {
            switch content.calm {
            case .clear:
                PanelAllClear(repoCount: content.judgedRepos.count - content.deferredRepos.count, notCounted: content.deferredRepos.count)
            case let .checking(repos):
                PanelCheckingNote(repoCount: repos)
                self.notCountedNote(content)
            case .unchecked:
                self.uncheckedNotice(content)
                self.notCountedNote(content)
            case .refreshFailed: self.notCountedNote(content) // the banner above says why it failed
            }
        } else if content.reviewRequestsFailure != nil {
            self.uncheckedNotice(content)
        }
    }

    @ViewBuilder
    private func notCountedNote(_ content: HarborPanelContent) -> some View {
        if let text = content.notCountedNote {
            Text(text)
                .font(.system(size: self.skin.row.detailSize))
                .foregroundStyle(self.skin.secondaryText)
                .padding(.horizontal, self.skin.row.itemPadding)
                .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func uncheckedNotice(_ content: HarborPanelContent) -> some View {
        if let text = content.uncheckedNotice { PanelNotice(kind: .pending, text: text) }
    }

    private func needRow(_ need: PanelNeed) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelRow(id: need.id, action: { self.open(need) }) {
                NeedsYouRow(kind: need.kind, title: need.title, detail: need.detail, age: need.age)
            }
            if need.kind == .behind, let local = need.repo?.localStatus {
                LocalGitBehindStrip(model: self.localGit.model(for: local.path), status: local)
            }
        }
    }

    private func open(_ need: PanelNeed) {
        if let pull = need.pull {
            self.showPull(fullName: pull.fullName, number: pull.number)
        } else if let repo = need.repo {
            self.show(repo)
        }
    }

    private func greeting(_ content: HarborPanelContent, login: String) -> some View {
        Text(PanelGreeting.text(
            login: login, hour: Calendar.current.component(.hour, from: Date()),
            needsYou: content.needsYou.count, openPulls: content.openPullCount
        ))
        .font(.system(size: self.skin.row.detailSize))
        .foregroundStyle(self.skin.secondaryText)
        .lineLimit(1)
        .contentTransition(.numericText())
        .animation(self.reduceMotion ? nil : .snappy, value: content.needsYou.count + content.openPullCount)
        .padding(.horizontal, self.skin.row.itemPadding)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusBar(_ content: HarborPanelContent) -> some View {
        PanelStatusBar(
            lastRefresh: content.lastRefresh,
            isRefreshing: content.isRefreshing,
            interval: self.session.settings.refreshInterval.seconds,
            isRateLimited: content.rateLimitReset != nil,
            hasError: (content.error != nil && content.rateLimitReset == nil) || content.uncheckedNotice != nil,
            loadRateLimit: self.actions.loadRateLimit
        )
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            PanelSegmented(
                options: [MenuRepoSelection.pinned, .all],
                label: \.label,
                selection: self.$session.menuRepoSelection
            )
            .accessibilityLabel("Repositories shown")
            Spacer()
            Text("Sort: \(self.session.settings.repoList.menuSortKey.panelLabel)")
                .font(.system(size: self.skin.row.detailSize))
                .foregroundStyle(self.skin.secondaryText)
        }
        .padding(.horizontal, self.skin.row.itemPadding)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func repoList(_ content: HarborPanelContent) -> some View {
        let repos = self.filteredRepos(content)
        if repos.isEmpty {
            Text(content.hasLoadedRepositories ? "No repositories match." : "Loading repositories…")
                .font(.system(size: 12))
                .foregroundStyle(self.skin.secondaryText)
                .padding(12)
        } else {
            ForEach(repos, id: \.id) { repo in
                PanelRow(id: "repo:\(repo.id)", showsChevron: true, action: { self.show(repo) }) {
                    CompactRepoRow(
                        repo: repo, isPinned: content.pinned.contains(repo.title),
                        onOpenExternally: { self.actions.openRepo(repo) }
                    )
                }
            }
        }
    }

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Harbor")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(self.skin.text)
                .accessibilityAddTraits(.isHeader)
            Text("Sign in to see your repositories, builds and reviews.")
                .font(.system(size: 12))
                .foregroundStyle(self.skin.secondaryText)
            Button("Sign in with GitHub", action: self.actions.signIn)
                .buttonStyle(PanelPrimaryButtonStyle())
                .padding(.top, 4)
        }
        .padding(12)
    }

    private var footer: some View {
        PanelFooterBar(actions: self.actions)
    }

    /// "Repos | Harbor | Tower": the Tower reads the agent ledger and git on its own, only while shown.
    private var modeBar: some View {
        HStack {
            PanelSegmented(options: PanelMode.allCases, label: \.label, selection: Binding(get: { self.mode }, set: { self.setMode($0) }))
                .accessibilityLabel("View")
            Spacer()
            Text("⌘T")
                .font(.system(size: self.skin.row.detailSize))
                .foregroundStyle(self.skin.tertiaryText)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, self.skin.row.itemPadding)
        .padding(.top, 4)
    }

    private var mode: PanelMode { self.showsTower ? .tower : (self.showsHarbor ? .harbor : .repos) }

    private func setMode(_ mode: PanelMode) {
        guard mode != self.mode else { return }
        // A running `--execute` keeps its Tower tab: leaving would drop the result.
        if mode != .tower, self.tower.retireExecuting { return }
        if self.navigator?.blocksLeavingDetail == true { return }
        self.showsHarbor = mode == .harbor
        if mode == .harbor { self.navigator?.reset() }
        self.setTower(mode == .tower)
    }

    private func setTower(_ on: Bool) {
        if !on, self.tower.retireExecuting { return }
        if self.navigator?.blocksLeavingDetail == true { return }
        if on { self.showsHarbor = false }
        guard on != self.showsTower else { return }
        self.showsTower = on
        self.navigator?.reset()
        if on {
            // Already running for the icon; opening the tab looks at every repo again.
            self.tower.refresh()
        } else {
            self.tower.openRow = nil
        }
    }

    private func show(_ repo: RepositoryDisplayModel) {
        withAnimation(.snappy(duration: 0.22)) { self.detail = repo }
        self.actions.loadRepoActivity(repo)
        self.navigator?.reset()
    }
}

/// The panel's "Repos | Harbor | Tower" switch.
enum PanelMode: CaseIterable, Hashable {
    case repos, harbor, tower

    var label: String {
        switch self {
        case .repos: "Repos"
        case .harbor: "Harbor"
        case .tower: "Tower"
        }
    }
}

extension RepositorySortKey {
    var panelLabel: String {
        self.rawValue.prefix(1).uppercased() + self.rawValue.dropFirst()
    }
}
