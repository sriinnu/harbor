import AppKit
import OSLog
import SwiftUI

/// Shows Harbor's themed panel under the menu bar icon: a borderless window so the theme
/// draws the whole surface, corners and background included. Closes on a click elsewhere,
/// on Escape, or when another app becomes active.
@MainActor
final class HarborPanelController {
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var resignObserver: NSObjectProtocol?
    /// Internal so tests can pin a panel that was never shown.
    var navigator: PanelNavigator?

    #if DEBUG
        /// For `PanelRenderSnapshot`, which opens a repo's detail.
        var navigatorForSnapshot: PanelNavigator? { self.navigator }
    #endif

    var isShown: Bool { self.panel?.isVisible == true }
    var window: NSWindow? { self.panel }

    func toggle(below button: NSStatusBarButton, skin: HarborPanelSkin, root: some View) {
        if self.isShown {
            // The icon respects the pins too: a running retire's result must not be thrown away.
            self.requestClose(reason: "icon")
        } else {
            self.show(below: button, skin: skin, root: root)
        }
    }

    func show(below button: NSStatusBarButton, skin: HarborPanelSkin, root: some View) {
        let navigator = PanelNavigator()
        self.navigator = navigator
        let sized = root
            .environment(\.harborPanelSkin, skin)
            .environment(\.panelNavigator, navigator)
            .environment(\.panelMaxHeight, self.maxHeight(for: button))
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { [weak self] _ in
                // Twice: `fittingSize` can still hold the previous layout inside this callback,
                // which left a pane that grew after it loaded (the pull request's) too short.
                self?.refit()
                Task { @MainActor in self?.refit() }
            })
        let hosting = NSHostingView(rootView: sized)
        let panel = KeyablePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = skin.hasShadow
        panel.appearance = ActiveTheme.menuAppearance
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        panel.onCancel = { [weak self] in
            // A running retire keeps the panel: its result must be shown, not lost with the view.
            if self?.navigator?.blocksEscape == true { return }
            // Escape steps back out of a repo's detail first, then closes the panel.
            if self?.navigator?.goBack() != true { self?.close() }
        }
        panel.onKey = { [weak self] code in self?.navigator?.handle(keyCode: code) ?? false }
        panel.onCommandKey = { [weak self] key in self?.navigator?.handle(command: key) ?? false }
        self.panel = panel
        self.position(panel, below: button, width: skin.width)
        panel.makeKeyAndOrderFront(nil)
        button.highlight(true)
        self.installMonitors(button: button)
    }

    private let logger = Logger(subsystem: "com.sriinnu.harbor", category: "panel")

    /// Outside clicks, app switches and the icon close the panel, except while a confirm or a
    /// running action has pinned it open. Escape (outside a running retire) still closes it.
    private func closeUnlessPinned(reason: String) { self.requestClose(reason: reason) }

    /// Closes unless a confirm or a running action has pinned the panel; says whether it closed.
    @discardableResult
    func requestClose(reason: String) -> Bool {
        if self.navigator?.isPinnedOpen == true {
            self.logger.notice("panel close ignored reason=\(reason, privacy: .public) pinned")
            return false
        }
        self.close(reason: reason)
        return true
    }

    /// What a panel action (open in browser, Settings, a terminal) does to the panel: close it,
    /// unless a confirm or a running action has pinned it open. The action itself still runs.
    func closeFromAction() {
        _ = self.requestClose(reason: "action")
    }

    func close(reason: String = "action") {
        if self.panel != nil { self.logger.notice("panel close reason=\(reason, privacy: .public)") }
        for monitor in self.monitors { NSEvent.removeMonitor(monitor) }
        self.monitors = []
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        self.resignObserver = nil
        self.panel?.orderOut(nil)
        self.panel = nil
        self.navigator = nil
        self.anchor?.highlight(false)
    }

    private weak var anchor: NSStatusBarButton?

    /// The tallest the panel may be on the icon's screen, leaving a margin under the bar.
    private func maxHeight(for button: NSStatusBarButton) -> CGFloat {
        let screen = button.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        return max(screen.height - 16, 200)
    }

    private func position(_ panel: NSPanel, below button: NSStatusBarButton, width: CGFloat) {
        guard let buttonWindow = button.window, let hosting = panel.contentView else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let height = min(hosting.fittingSize.height, screen.height - 12)
        var x = anchor.minX - 6
        x = min(max(x, screen.minX + 6), screen.maxX - width - 6)
        let y = anchor.minY - 4 - height
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func installMonitors(button: NSStatusBarButton) {
        self.anchor = button
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            Task { @MainActor in self?.closeUnlessPinned(reason: "click outside") }
        }) {
            self.monitors.append(global)
        }
        // A click on the icon itself is left to the button, which toggles the panel.
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self, weak button] event in
            guard let self, let panel = self.panel else { return event }
            if event.window === panel || event.window === button?.window { return event }
            self.closeUnlessPinned(reason: "click in other window")
            return event
        }) {
            self.monitors.append(local)
        }
        self.resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeUnlessPinned(reason: "app resigned active") }
        }
    }

    /// Fits the window to the content after a change, keeping its top edge under the icon.
    func refit() {
        guard let panel, let hosting = panel.contentView else { return }
        let screen = panel.screen?.visibleFrame ?? .zero
        let fitting = hosting.fittingSize.height
        // A transient zero fitting size mid-update (or no screen yet) would shrink the
        // window to nothing, which looks exactly like the panel vanishing.
        guard fitting > 40, screen.height > 0 else {
            self.logger.notice("panel refit skipped fitting=\(fitting, privacy: .public) screen=\(screen.height, privacy: .public)")
            return
        }
        let height = min(fitting, screen.height - 12)
        var frame = panel.frame
        frame.origin.y = frame.maxY - height
        frame.size.height = height
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }
}

/// A borderless panel can't become key by default; it needs to, for Escape and focus.
private final class KeyablePanel: NSPanel {
    var onCancel: (() -> Void)?
    /// Arrow keys, Return and Escape, offered before any view sees them.
    var onKey: ((UInt16) -> Bool)?
    /// Command-key shortcuts (⌘, and ⌘Q), by the character they type.
    var onCommandKey: ((String) -> Bool)?

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.modifierFlags.isDisjoint(with: [.command, .option, .control]) {
            if event.keyCode == 53 {
                self.onCancel?()
                return
            }
            if self.onKey?(event.keyCode) == true { return }
        }
        if event.type == .keyDown, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let key = event.charactersIgnoringModifiers, self.onCommandKey?(key) == true {
            return
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        self.onCancel?()
    }
}
