import AppKit
import HarborCore
import SwiftUI

extension StatusBarMenuBuilder {
    func paddedSeparator() -> NSMenuItem {
        self.viewItem(for: MenuPaddedSeparatorView(), enabled: false)
    }

    func repoCardSeparator() -> NSMenuItem {
        self.viewItem(for: RepoCardSeparatorRowView(), enabled: false)
    }

    func repoMenuItem(for repo: RepositoryDisplayModel, isPinned: Bool) -> NSMenuItem {
        let row = CompactRepoRow(repo: repo, isPinned: isPinned)
        return self.viewItem(for: row, enabled: true, highlightable: true, submenu: self.repoSubmenu(for: repo, isPinned: isPinned))
    }

    /// A row in "Needs you": why the repo is waiting on you. It opens the repo's submenu.
    func needsYouItem(for repo: RepositoryDisplayModel, isPinned: Bool) -> NSMenuItem {
        var reasons: [String] = []
        if repo.ciStatus == .failing { reasons.append("CI failing") }
        if let alerts = repo.source.security?.openAlertCount, alerts > 0 {
            reasons.append(alerts == 1 ? "1 security alert" : "\(alerts) security alerts")
        }
        let row = NeedsYouRow(
            kind: repo.ciStatus == .failing ? .fail : .pending,
            title: repo.title,
            detail: reasons.joined(separator: " · "),
            age: repo.latestActivityAge
        )
        // Its own submenu: an NSMenu can belong to only one item, and the repo's row below
        // already holds the shared one. Attaching it twice throws and stops the menu build.
        return self.viewItem(for: row, enabled: true, highlightable: true, submenu: self.makeRepoSubmenu(for: repo, isPinned: isPinned))
    }

    func connectedProviders(_ session: Session) -> [ProviderType] {
        var providers: [ProviderType] = []
        if case .loggedIn = session.account { providers.append(.github) }
        if session.azureUser != nil { providers.append(.azureDevOps) }
        if session.gitlabUser != nil { providers.append(.gitlab) }
        return providers
    }

    func repoSubmenu(for repo: RepositoryDisplayModel, isPinned: Bool) -> NSMenu {
        let signature = RepoSubmenuSignature(
            repo: repo,
            settings: self.appState.session.settings,
            heatmapRange: self.appState.session.heatmapRange,
            recentCounts: RepoRecentCountSignature(
                commits: self.target.cachedRecentCommitCount(fullName: repo.title),
                commitsDigest: self.target.cachedRecentCommitDigest(fullName: repo.title),
                releases: self.target.cachedRecentListCount(fullName: repo.title, kind: .releases),
                discussions: self.target.cachedRecentListCount(fullName: repo.title, kind: .discussions),
                tags: self.target.cachedRecentListCount(fullName: repo.title, kind: .tags),
                branches: self.target.cachedRecentListCount(fullName: repo.title, kind: .branches),
                contributors: self.target.cachedRecentListCount(fullName: repo.title, kind: .contributors)
            ),
            isPinned: isPinned
        )
        if let cached = self.repoSubmenuCache[repo.title], cached.signature == signature {
            return cached.menu
        }
        let menu = self.makeRepoSubmenu(for: repo, isPinned: isPinned)
        self.repoSubmenuCache[repo.title] = RepoSubmenuCacheEntry(menu: menu, signature: signature)
        return menu
    }

    func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    func infoMessageItem(_ title: String) -> NSMenuItem {
        let view = MenuInfoTextRowView(text: title, lineLimit: 5)
        return self.viewItem(for: view, enabled: false)
    }

    func actionItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        represented: Any? = nil,
        systemImage: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self.target
        if let represented { item.representedObject = represented }
        if let systemImage, let image = self.cachedSystemImage(named: systemImage) {
            item.image = image
        }
        return item
    }

    func cachedSystemImage(named name: String) -> NSImage? {
        let key = "\(name)|\(self.isLightAppearance ? "light" : "dark")"
        if let cached = self.systemImageCache[key] {
            return cached
        }
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        image.size = NSSize(width: 14, height: 14)
        if name == "eye.slash", self.isLightAppearance {
            let config = NSImage.SymbolConfiguration(hierarchicalColor: .secondaryLabelColor)
            let tinted = image.withSymbolConfiguration(config)
            tinted?.isTemplate = false
            if let tinted {
                self.systemImageCache[key] = tinted
                return tinted
            }
        }
        image.isTemplate = true
        self.systemImageCache[key] = image
        return image
    }

    func viewItem(
        for content: some View,
        enabled: Bool,
        highlightable: Bool = false,
        submenu: NSMenu? = nil
    ) -> NSMenuItem {
        let item = self.menuItemFactory.makeItem(
            for: content,
            enabled: enabled,
            highlightable: highlightable,
            showsSubmenuIndicator: submenu != nil,
            submenu: submenu,
            target: submenu != nil ? self.target : nil,
            action: submenu != nil ? #selector(self.target.menuItemNoOp(_:)) : nil
        )
        return item
    }
}
