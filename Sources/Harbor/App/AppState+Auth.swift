import Foundation
import HarborCore

extension AppState {
    /// Legacy entry point kept for callers that cannot open the Account settings UI directly.
    /// OAuth credentials are intentionally never bundled with Harbor.
    func quickLogin() async {
        self.session.account = .loggedOut
        self.session.lastError = "Enter your GitHub OAuth App credentials in Account settings before signing in."
    }
}
