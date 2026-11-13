import AppKit
import HarborCore
import Observation
import OSLog

/// Owns Harbor's menu bar icon directly in AppKit. SwiftUI's `MenuBarExtra` offers no
/// supported way to attach a custom `NSMenu`, and the library that reached into its
/// private AppKit classes stopped finding the status item on macOS 27.
@MainActor
final class StatusItemController {
    private let session: Session
    private let statusItem: NSStatusItem
    private let menuManager: StatusBarMenuManager
    private var renderedBadge: StatusItemBadge?
    /// Watches worktrees in the background (ledger tail and `.git` events, no polling) so the
    /// icon counts Tower's Needs you without its tab open.
    private let tower = TowerModel()
    private var towerRoots: [String]?
    private let panel = HarborPanelController()
    private let clickTarget = StatusItemClickTarget()
    private var usesPanel = false
    private let logger = Logger(subsystem: "com.sriinnu.harbor", category: "menu-state")

    init(appState: AppState) {
        self.session = appState.session
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.menuManager = StatusBarMenuManager(appState: appState)
        // Tower follows the account: a switch clears what it found, and a new pull answer rescans.
        appState.accountScopeResets.append { [weak self] in self?.tower.reset() }
        MyPullsStore.shared.onChange = { [weak self] in self?.tower.pullsChanged() }
        self.statusItem.button?.imagePosition = .imageLeading
        self.statusItem.button?.setAccessibilityLabel("Harbor")
        self.menuManager.attachMainMenu(to: self.statusItem)
        self.trackBadge()
        self.trackTheme()
        #if DEBUG
            if let directory = MenuRenderSnapshot.directory {
                let session = self.session
                let item = self.statusItem
                Task { await MenuRenderSnapshot.run(session: session, statusItem: item, into: directory) }
            }
            if let directory = PanelRenderSnapshot.directory {
                Task { await PanelRenderSnapshot.run(controller: self, session: self.session, into: directory) }
            }
        #endif
        self.watchPlacement()
    }

    /// Re-checks the icon's placement whenever its window moves, its visibility changes or
    /// the displays change. The first check waits a beat, since macOS lays the bar out after
    /// the item is created.
    private func watchPlacement() {
        let center = NotificationCenter.default
        var watched: [(Notification.Name, AnyObject?)] = [(NSApplication.didChangeScreenParametersNotification, nil)]
        // Never observe these with a nil object: that would fire for every window.
        if let window = self.statusItem.button?.window {
            watched.append((NSWindow.didMoveNotification, window))
            watched.append((NSWindow.didChangeOcclusionStateNotification, window))
        }
        for (name, object) in watched {
            center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkPlacement() }
            }
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.checkPlacement()
        }
    }

    private func checkPlacement() {
        let window = self.statusItem.button?.window
        let placement = StatusItemPlacement.evaluate(
            itemFrame: window?.frame,
            screens: ScreenInfo.current(),
            windowVisible: window?.occlusionState.contains(.visible) ?? false
        )
        StatusItemPresence.shared.update(placement)
        let frame = String(describing: window?.frame ?? .zero)
        self.logger.notice("status item placement=\(String(describing: placement), privacy: .public) frame=\(frame, privacy: .public)")
    }

    private func trackBadge() {
        let (badge, roots) = withObservationTracking {
            (
                StatusItemBadge(
                    account: self.session.account, content: self.menuManager.panelContent(),
                    towerNeedsYou: self.tower.needsYouCount, towerUnchecked: self.tower.uncheckedRepos.count
                ),
                self.session.settings.localProjects.rootPaths
            )
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackBadge() }
        }
        // Outside the tracked closure: starting the tower writes its own observed state.
        self.syncTower(roots: roots)
        guard badge != self.renderedBadge else { return }
        self.renderedBadge = badge
        self.statusItem.button?.image = StatusItemIcon.image(badge: badge)
        self.statusItem.button?.title = badge.countText
        self.statusItem.button?.setAccessibilityLabel(badge.accessibilityText)
    }

    /// Starts the background Tower, and restarts it when the project folders change.
    private func syncTower(roots: [String]) {
        guard roots != self.towerRoots else { return }
        if self.towerRoots != nil { self.tower.stop() }
        self.towerRoots = roots
        self.tower.start(rootPaths: roots)
    }

    private func trackTheme() {
        let id = withObservationTracking {
            self.session.settings.appearance.theme
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackTheme() }
        }
        ActiveTheme.apply(id)
        self.applySurface(for: id)
    }

    /// A theme with a panel design opens Harbor's own panel; the rest open the system menu.
    /// `defaults write com.sriinnu.harbor HarborThemedPanel -bool NO` keeps the menu everywhere.
    private func applySurface(for id: HarborThemeID) {
        let enabled = UserDefaults.standard.object(forKey: "HarborThemedPanel") as? Bool ?? true
        let usesPanel = enabled && HarborPanelSkin.forTheme(id, isDark: false) != nil
        guard usesPanel != self.usesPanel || (!usesPanel && self.statusItem.menu == nil) else { return }
        self.usesPanel = usesPanel
        self.panel.close()
        guard usesPanel, let button = self.statusItem.button else {
            self.statusItem.button?.action = nil
            self.menuManager.attachMainMenu(to: self.statusItem)
            return
        }
        self.statusItem.menu = nil
        self.clickTarget.onClick = { [weak self] in self?.togglePanel() }
        button.target = self.clickTarget
        button.action = #selector(StatusItemClickTarget.clicked)
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }

    /// The skin for the active theme in the appearance the panel would open in.
    func currentPanelSkin() -> HarborPanelSkin? {
        let isDark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return HarborPanelSkin.forTheme(ActiveTheme.theme.id, isDark: isDark)
    }

    /// What the global hotkey opens: the themed panel, or the status item's own menu when the
    /// theme (or `HarborThemedPanel`) uses the system menu.
    enum HotkeySurface: Equatable { case panel, menu }

    static func hotkeySurface(usesPanel: Bool) -> HotkeySurface { usesPanel ? .panel : .menu }

    func openFromHotkey() {
        switch Self.hotkeySurface(usesPanel: self.usesPanel) {
        case .panel: self.togglePanel()
        case .menu: self.statusItem.button?.performClick(nil)
        }
    }

    func togglePanel() {
        guard let button = self.statusItem.button, let skin = self.currentPanelSkin() else { return }
        let manager = self.menuManager
        if !self.panel.isShown { manager.panelWillOpen() }
        let actions = manager.panelActions(close: { [weak self] in self?.panel.closeFromAction() })
        let root = HarborPanelView(session: self.session, content: { manager.panelContent() }, actions: actions, tower: self.tower)
        self.panel.toggle(below: button, skin: skin, root: root)
    }

    #if DEBUG
        /// The panel's window, for `PanelRenderSnapshot`.
        var panelForSnapshot: HarborPanelController { self.panel }
    #endif
}

/// The status button's target while the panel is in use (the controller isn't an NSObject).
@MainActor
final class StatusItemClickTarget: NSObject {
    var onClick: (() -> Void)?

    @objc func clicked() {
        self.onClick?()
    }
}

/// What the menu bar glyph says, from the Bollard design: filled when calm, a knocked-out
/// corner dot and a count when something needs you, a hollow lamp ring when something could
/// not be checked, and outline only when signed out.
enum StatusItemBadge: Equatable {
    case signedOut
    case calm
    case needsYou(Int)
    /// Nothing needs you that Harbor knows of, but a repo or the review search could not be read.
    /// The lamp is a ring, so it differs by shape and not only by colour.
    case unchecked

    /// The one rule, taken from the panel's own content so icon and panel never disagree: the
    /// count is the panel's Needs you (failing CI, alerts, review requests, behind clones), and
    /// calm is only the panel's `.clear` (or still `.checking`, which says nothing yet).
    init(account: AccountState, content: HarborPanelContent, towerNeedsYou: Int = 0, towerUnchecked: Int = 0) {
        if account == .loggedOut {
            self = .signedOut
            return
        }
        // Tower's worktrees that need you, counted only from finished scans (unknown adds nothing).
        let waiting = content.needsYou.count + max(0, towerNeedsYou)
        if waiting > 0 {
            self = .needsYou(waiting)
            return
        }
        switch content.calm {
        // A Tower repo that couldn't be read is unknown: never "all clear".
        case .clear, .checking: self = towerUnchecked > 0 ? .unchecked : .calm
        case .unchecked, .refreshFailed: self = .unchecked
        }
    }

    var countText: String {
        if case let .needsYou(count) = self { return String(count) }
        return ""
    }

    /// The lamp as text, for the status button's VoiceOver label: the icon says it by shape and
    /// colour only, and the hollow ring ("could not check") must not read as "all fine".
    var accessibilityText: String {
        switch self {
        case .signedOut: "Harbor, signed out"
        case .calm: "Harbor, all clear"
        case let .needsYou(count): "Harbor, \(count) \(count == 1 ? "item needs" : "items need") you"
        case .unchecked: "Harbor, some repositories could not be checked"
        }
    }
}

enum StatusItemIcon {
    static let side: CGFloat = 18

    /// A template image, so macOS tints it for light and dark menu bars. The drawing uses
    /// the design's y-down coordinates.
    /// `defaults write com.sriinnu.harbor HarborColorIcon -bool NO` keeps the plain template mark.
    static var usesColor: Bool { UserDefaults.standard.object(forKey: "HarborColorIcon") as? Bool ?? true }

    /// The mark in the logo's colours: pilings in the menu bar's text colour, an amber
    /// harbour light, teal water. The drawing handler runs at draw time, so it picks up the
    /// menu bar's light or dark appearance. Signed out, it falls back to a grey outline template.
    static func image(badge: StatusItemBadge, colored: Bool = Self.usesColor) -> NSImage {
        let color = colored && badge != .signedOut
        let image = NSImage(size: NSSize(width: self.side, height: self.side), flipped: true) { _ in
            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let ink = color ? (isDark ? NSColor(white: 0.96, alpha: 1) : NSColor(red: 0.07, green: 0.16, blue: 0.32, alpha: 1)) : .black
            let lamp = color ? NSColor(red: 1, green: 0.76, blue: 0.29, alpha: 1) : .black
            let water = color ? (isDark ? NSColor(red: 0.42, green: 0.85, blue: 0.89, alpha: 1) : NSColor(red: 0.05, green: 0.50, blue: 0.56, alpha: 1)) : .black
            let parts = self.dockParts()
            let wave = self.wave()
            if badge == .signedOut {
                NSColor.black.set()
                for part in parts {
                    part.lineWidth = 1.1
                    part.stroke()
                }
                wave.lineWidth = 1.1
                wave.stroke()
                return true
            }
            ink.setFill()
            parts.forEach { $0.fill() }
            water.setStroke()
            wave.stroke()
            if case .needsYou = badge {
                // The harbour light comes on: a bigger lamp with a clear ring around it.
                let context = NSGraphicsContext.current
                context?.compositingOperation = .clear
                self.circle(radius: 4.0).fill()
                context?.compositingOperation = .sourceOver
                lamp.setFill()
                self.circle(radius: 2.5).fill()
            } else if badge == .unchecked {
                // A hollow ring where the lamp should glow: not lit, not known to be fine.
                lamp.setStroke()
                let ring = self.circle(radius: 2.2)
                ring.lineWidth = 1.2
                ring.stroke()
            } else {
                lamp.setFill()
                self.circle(radius: 1.7).fill()
            }
            return true
        }
        image.isTemplate = !color
        image.accessibilityDescription = "Harbor"
        return image
    }

    /// The harbour light, sitting over the short piling so the mark reads "Hi".
    private static func circle(radius: CGFloat) -> NSBezierPath {
        let center = NSPoint(x: 13.2, y: 3.4)
        return NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    /// The H: two pier pilings joined by a dock, the right piling shorter.
    private static func dockParts() -> [NSBezierPath] {
        func bar(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSBezierPath {
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: min(width, height) / 2, yRadius: min(width, height) / 2)
        }
        return [
            bar(3.2, 3.2, 2.8, 10.4),
            bar(11.8, 6.6, 2.8, 7.0),
            bar(3.2, 8.3, 11.4, 2.4)
        ]
    }

    /// One swell of water under the dock.
    private static func wave() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 1.6, y: 15.9))
        path.curve(to: NSPoint(x: 9, y: 15.9), controlPoint1: NSPoint(x: 3.5, y: 14.3), controlPoint2: NSPoint(x: 7.1, y: 14.3))
        path.curve(to: NSPoint(x: 16.4, y: 15.9), controlPoint1: NSPoint(x: 10.9, y: 17.5), controlPoint2: NSPoint(x: 14.5, y: 17.5))
        path.lineWidth = 1.4
        path.lineCapStyle = .round
        return path
    }
}
