import SwiftUI

/// While a confirm, a destructive action or a long write is pending or running, the panel must
/// not close on an outside click or when the app resigns active. Views opt in with
/// `.pinsPanelOpen("reason", while: isPending)`.
private struct PinsPanelOpen: ViewModifier {
    let reason: String
    let active: Bool
    @Environment(\.panelNavigator) private var navigator

    func body(content: Content) -> some View {
        content
            .onChange(of: self.active, initial: true) { _, on in self.navigator?.pin(self.reason, on) }
            .onDisappear { self.navigator?.pin(self.reason, false) }
    }
}

extension View {
    func pinsPanelOpen(_ reason: String, while active: Bool) -> some View {
        self.modifier(PinsPanelOpen(reason: reason, active: active))
    }
}

/// Pin reasons views use, so the panel controller can tell them apart.
enum PanelPin {
    static let towerRetire = "tower-retire"
    /// A run cleanup is scanning, waiting on its confirm, or deleting.
    static let runCleanup = "run-cleanup"
    /// `--execute` is running. Unlike other pins this one also swallows Escape: the panel
    /// closing would throw the result away, a failure included.
    static let towerExecuting = "tower-executing"
    /// A run cleanup is deleting. Leaving the repo detail would cancel it with no line saying
    /// how many were removed, so, like a running retire, it holds the detail and swallows Escape.
    static let runCleanupDeleting = "run-cleanup-deleting"
}

extension PanelNavigator {
    /// True while Escape must not close the panel (or step back).
    var blocksEscape: Bool {
        self.pinReasons.contains(PanelPin.towerExecuting) || self.pinReasons.contains(PanelPin.runCleanupDeleting)
    }

    /// True while the repo detail must stay open: a cleanup is deleting runs in it.
    var blocksLeavingDetail: Bool { self.pinReasons.contains(PanelPin.runCleanupDeleting) }
}
