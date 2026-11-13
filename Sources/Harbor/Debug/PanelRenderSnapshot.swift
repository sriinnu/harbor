#if DEBUG
    import AppKit
    import HarborCore

    /// Renders the themed panel to PNG once data has loaded:
    /// `HARBOR_PANEL_SNAPSHOT=<dir>` writes `<theme>.png` for each theme, and
    /// `<theme>-light.png` / `<theme>-dark.png` for themes that follow the system appearance.
    /// Development builds only.
    @MainActor
    enum PanelRenderSnapshot {
        static var directory: URL? {
            ProcessInfo.processInfo.environment["HARBOR_PANEL_SNAPSHOT"].map { URL(fileURLWithPath: $0) }
        }

        /// `HARBOR_PANEL_SNAPSHOT_THEME=daylight` renders only that theme.
        private static var onlyTheme: HarborThemeID? {
            ProcessInfo.processInfo.environment["HARBOR_PANEL_SNAPSHOT_THEME"].flatMap(HarborThemeID.init(rawValue:))
        }

        /// `HARBOR_PANEL_SNAPSHOT_DETAIL=1` (or a repo's full name) also renders that repo's
        /// detail pane, as `<theme>-detail.png`, after giving its activity time to load.
        private static var detail: String? {
            ProcessInfo.processInfo.environment["HARBOR_PANEL_SNAPSHOT_DETAIL"]
        }

        /// `HARBOR_PANEL_SNAPSHOT_PR=owner/name#24` (or `preview#0`, a fixed pull request that is behind) also renders that pull request's pane, as
        /// `<theme>-pr.png`, after giving its readiness time to load.
        private static var pull: (repo: String, number: Int)? {
            guard let raw = ProcessInfo.processInfo.environment["HARBOR_PANEL_SNAPSHOT_PR"] else { return nil }
            let parts = raw.split(separator: "#").map(String.init)
            guard parts.count == 2, let number = Int(parts[1]) else { return nil }
            return (parts[0], number)
        }

        /// `HARBOR_PANEL_SNAPSHOT_TOWER=1` also renders the Tower tab as `<theme>-tower.png`;
        /// `=detail` also renders its first worktree's detail as `<theme>-tower-detail.png`.
        private static var tower: String? {
            ProcessInfo.processInfo.environment["HARBOR_PANEL_SNAPSHOT_TOWER"]
        }

        /// `HARBOR_PANEL_SNAPSHOT_LIST=issues` (or pulls, releases, runs, branches) also renders that
        /// list of the detail repo as `<theme>-list-<kind>.png`; it needs `..._DETAIL` set.
        private static var list: RepoListKind? {
            ProcessInfo.processInfo.environment["HARBOR_PANEL_SNAPSHOT_LIST"].flatMap(RepoListKind.init(rawValue:))
        }

        /// `HARBOR_PANEL_SNAPSHOT_LOCAL=behind` (or `diverged`) gives the `..._DETAIL` repo a made-up
        /// local clone in this run's session only (nothing is saved), so the local Git UI and the
        /// "behind" Needs-you row can be rendered on a machine without one. The path is real but
        /// no git command runs.
        private static var fakeLocal: String? {
            ProcessInfo.processInfo.environment["HARBOR_PANEL_SNAPSHOT_LOCAL"]
        }

        /// `HARBOR_PANEL_SNAPSHOT_HARBOR=1` also renders the Harbor tab as `<theme>-harbor.png`.
        private static var harbor: Bool {
            ProcessInfo.processInfo.environment["HARBOR_PANEL_SNAPSHOT_HARBOR"] != nil
        }

        /// `HARBOR_PANEL_SNAPSHOT_RANGE=allTime` (or week, month, quarter, year) sets the
        /// activity range first, so the strip can be rendered in each.
        private static var range: ActivityRange? {
            ProcessInfo.processInfo.environment["HARBOR_PANEL_SNAPSHOT_RANGE"].flatMap(ActivityRange.init(rawValue:))
        }

        static func run(controller: StatusItemController, session: Session, into directory: URL) async {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for _ in 0 ..< 80 where !session.hasLoadedRepositories {
                try? await Task.sleep(for: .milliseconds(500))
            }
            try? await Task.sleep(for: .seconds(2))
            if let state = self.fakeLocal, let fullName = self.detail, fullName != "1" {
                let behind = state == "behind"
                let status = LocalRepoStatus(
                    path: URL(fileURLWithPath: FileManager.default.currentDirectoryPath), name: String(fullName.split(separator: "/").last ?? ""),
                    fullName: fullName, branch: "main", isClean: behind, aheadCount: behind ? 0 : 1, behindCount: behind ? 2 : 3,
                    syncState: behind ? .behind : .dirty, dirtyCounts: behind ? nil : LocalDirtyCounts(added: 1, modified: 2, deleted: 0),
                    upstreamBranch: "origin/main"
                )
                session.localRepoIndex = LocalRepoIndex(statuses: [status])
            }
            let original = session.settings.appearance.theme
            let originalRange = session.settings.appearance.activityRange
            if let range = self.range { session.settings.appearance.activityRange = range }
            for id in HarborThemeID.allCases where self.onlyTheme == nil || self.onlyTheme == id {
                session.settings.appearance.theme = id
                try? await Task.sleep(for: .milliseconds(600))
                let forced = HarborTheme.named(id).forcedAppearance
                let variants: [(suffix: String, appearance: NSAppearance?)] = forced == nil
                    ? [("-light", NSAppearance(named: .aqua)), ("-dark", NSAppearance(named: .darkAqua))]
                    : [("", nil)]
                for variant in variants {
                    if forced == nil { NSApplication.shared.appearance = variant.appearance }
                    try? await Task.sleep(for: .milliseconds(400))
                    controller.togglePanel()
                    try? await Task.sleep(for: .seconds(self.range == nil ? 1.5 : 6))
                    let url = directory.appendingPathComponent("\(id.rawValue)\(variant.suffix).png")
                    let window = controller.panelForSnapshot.window
                    self.capture(window, to: url)
                    if let tower = self.tower {
                        controller.panelForSnapshot.navigatorForSnapshot?.showTower(false)
                        try? await Task.sleep(for: .seconds(12))
                        self.capture(window, to: directory.appendingPathComponent("\(id.rawValue)\(variant.suffix)-tower.png"))
                        if tower == "detail" {
                            controller.panelForSnapshot.navigatorForSnapshot?.showTower(true)
                            try? await Task.sleep(for: .seconds(2))
                            self.capture(window, to: directory.appendingPathComponent("\(id.rawValue)\(variant.suffix)-tower-detail.png"))
                        }
                    }
                    if self.harbor {
                        controller.panelForSnapshot.navigatorForSnapshot?.showHarbor(true)
                        try? await Task.sleep(for: .seconds(1))
                        self.capture(window, to: directory.appendingPathComponent("\(id.rawValue)\(variant.suffix)-harbor.png"))
                        controller.panelForSnapshot.navigatorForSnapshot?.showHarbor(false)
                    }
                    if let detail = self.detail {
                        controller.panelForSnapshot.navigatorForSnapshot?.showRepo(detail == "1" ? nil : detail)
                        try? await Task.sleep(for: .seconds(5))
                        self.capture(window, to: directory.appendingPathComponent("\(id.rawValue)\(variant.suffix)-detail.png"))
                    }
                    if let kind = self.list, self.detail != nil {
                        controller.panelForSnapshot.navigatorForSnapshot?.showList(kind)
                        try? await Task.sleep(for: .seconds(4))
                        self.capture(window, to: directory.appendingPathComponent("\(id.rawValue)\(variant.suffix)-list-\(kind.rawValue).png"))
                    }
                    if let pull = self.pull {
                        controller.panelForSnapshot.navigatorForSnapshot?.showPull(pull.repo, pull.number)
                        try? await Task.sleep(for: .seconds(5))
                        self.capture(window, to: directory.appendingPathComponent("\(id.rawValue)\(variant.suffix)-pr.png"))

                    }
                    // A system material is composited by the window server, so drawing the view
                    // alone shows it flat; an outside `screencapture -l` takes the real thing.
                    if id == .native, let window { await self.captureFromScreen(window, to: url) }
                    controller.panelForSnapshot.close()
                }
            }
            session.settings.appearance.theme = original
            session.settings.appearance.activityRange = originalRange
            if HarborTheme.named(original).forcedAppearance == nil { NSApplication.shared.appearance = nil }
        }

        /// Hands the window to an outside process: writes `<name>.wid` with its window number,
        /// then waits (up to 20 seconds) for that process to touch `<name>.done`. Screen
        /// capture needs a permission this app does not hold, so a script runs
        /// `screencapture -l` for it (see the dev notes in the PR).
        private static func captureFromScreen(_ window: NSWindow, to url: URL) async {
            let marker = url.deletingPathExtension()
            let done = marker.appendingPathExtension("done")
            try? FileManager.default.removeItem(at: done)
            try? "\(window.windowNumber)".write(to: marker.appendingPathExtension("wid"), atomically: true, encoding: .utf8)
            for _ in 0 ..< 40 where !FileManager.default.fileExists(atPath: done.path) {
                try? await Task.sleep(for: .milliseconds(500))
            }
        }

        private static func capture(_ window: NSWindow?, to url: URL) {
            guard let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
#endif
