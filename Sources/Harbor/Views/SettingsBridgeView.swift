import AppKit
import SwiftUI

/// SwiftUI only opens the `Settings` scene through an action read from a view inside a
/// scene, and the menu bar icon is plain AppKit. This view lives in an invisible window
/// so `SettingsOpener` always has that action.
struct SettingsBridgeView: View {
    let appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        InvisibleWindowMarker()
            .frame(width: 1, height: 1)
            .onAppear {
                SettingsOpener.shared.configure {
                    self.openSettings()
                }
                self.presentLoginSettingsIfNeeded()
            }
    }

    private func presentLoginSettingsIfNeeded() {
        // `session.account` starts as `.loggedOut` until the first refresh, so ask the
        // token store; otherwise Settings pops up on every launch for signed-in users.
        guard self.appState.auth.loadTokens() == nil else { return }
        self.appState.session.settingsSelectedTab = .accounts
        SettingsOpener.shared.open()
    }
}

private struct InvisibleWindowMarker: NSViewRepresentable {
    func makeNSView(context _: Context) -> MarkerView { MarkerView() }
    func updateNSView(_: MarkerView, context _: Context) {}

    final class MarkerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window = self.window else { return }
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        }
    }
}
