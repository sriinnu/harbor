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
    private let logger = Logger(subsystem: "com.sriinnu.harbor", category: "menu-state")

    init(appState: AppState) {
        self.session = appState.session
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.menuManager = StatusBarMenuManager(appState: appState)
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
        #endif
        let frame = self.statusItem.button?.window?.frame ?? .zero
        self.logger.info("status item created frame=\(String(describing: frame), privacy: .public)")
    }

    private func trackBadge() {
        let badge = withObservationTracking {
            StatusItemBadge(account: self.session.account, repositories: self.session.repositories)
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackBadge() }
        }
        guard badge != self.renderedBadge else { return }
        self.renderedBadge = badge
        self.statusItem.button?.image = StatusItemIcon.image(badge: badge)
        self.statusItem.button?.title = badge.countText
    }

    private func trackTheme() {
        let id = withObservationTracking {
            self.session.settings.appearance.theme
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackTheme() }
        }
        ActiveTheme.apply(id)
    }
}

/// What the menu bar glyph says, from the Bollard design: filled when calm, a knocked-out
/// corner dot and a count when something needs you, and outline only when signed out.
enum StatusItemBadge: Equatable {
    case signedOut
    case calm
    case needsYou(Int)

    init(account: AccountState, repositories: [Repository]) {
        if account == .loggedOut {
            self = .signedOut
            return
        }
        let waiting = repositories.count(where: { $0.ciStatus == .failing || ($0.security?.openAlertCount ?? 0) > 0 })
        self = waiting > 0 ? .needsYou(waiting) : .calm
    }

    var countText: String {
        if case let .needsYou(count) = self { return String(count) }
        return ""
    }
}

enum StatusItemIcon {
    static let side: CGFloat = 18

    /// A template image, so macOS tints it for light and dark menu bars. The drawing uses
    /// the design's y-down coordinates.
    static func image(badge: StatusItemBadge) -> NSImage {
        let image = NSImage(size: NSSize(width: self.side, height: self.side), flipped: true) { _ in
            NSColor.black.set()
            let parts = self.bollardParts()
            if badge == .signedOut {
                for part in parts {
                    part.lineWidth = 1.1
                    part.stroke()
                }
                return true
            }
            parts.forEach { $0.fill() }
            if case .needsYou = badge {
                let context = NSGraphicsContext.current
                context?.compositingOperation = .clear
                self.circle(radius: 4.1).fill()
                context?.compositingOperation = .sourceOver
                self.circle(radius: 2.6).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Harbor"
        return image
    }

    private static func circle(radius: CGFloat) -> NSBezierPath {
        let center = NSPoint(x: 14.7, y: 3.3)
        return NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    private static func polygon(_ points: [NSPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: points[0])
        points.dropFirst().forEach { path.line(to: $0) }
        path.close()
        return path
    }

    private static func bollardParts() -> [NSBezierPath] {
        let dome = NSBezierPath()
        dome.move(to: NSPoint(x: 5.2, y: 3.7))
        dome.curve(to: NSPoint(x: 12.8, y: 3.7), controlPoint: NSPoint(x: 9, y: 1.1))
        dome.close()
        func bar(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) -> NSBezierPath {
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: radius, yRadius: radius)
        }
        return [
            bar(2.8, 3.5, 12.4, 2.5, 1.25),
            dome,
            self.polygon([NSPoint(x: 5.8, y: 6.6), NSPoint(x: 12.2, y: 6.6), NSPoint(x: 11.7, y: 8.4), NSPoint(x: 6.3, y: 8.4)]),
            self.polygon([NSPoint(x: 6.3, y: 11.4), NSPoint(x: 11.7, y: 11.4), NSPoint(x: 12.3, y: 13.4), NSPoint(x: 5.7, y: 13.4)]),
            bar(4.2, 9, 9.6, 1.8, 0.9),
            bar(3.2, 13.4, 11.6, 2.4, 0.7)
        ]
    }
}
