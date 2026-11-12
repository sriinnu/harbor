import AppKit
import Foundation
import HarborCore

extension AppState {
    /// The single GitHub sign-in path, shared by the menu and Settings.
    ///
    /// With no custom secret it uses GitHub's device flow (Harbor ships no
    /// client secret). A custom client ID + secret, e.g. for your own OAuth app
    /// or GitHub Enterprise, uses the browser loopback flow instead.
    ///
    /// Every exit leaves `account` in a settled state: `.loggedIn` only once the
    /// profile has loaded, otherwise `.loggedOut` with `lastError` set (or no
    /// error when the user cancelled). Returns the error message, if any.
    @discardableResult
    func signInToGitHub(clientID: String? = nil, clientSecret: String? = nil, enterpriseHost: URL? = nil) async -> String? {
        self.loginTask?.cancel()
        let task = Task { @MainActor in
            await self.runGitHubSignIn(clientID: clientID, clientSecret: clientSecret, enterpriseHost: enterpriseHost)
        }
        self.loginTask = task
        let message = await task.value
        if self.loginTask == task { self.loginTask = nil }
        return message
    }

    func cancelGitHubSignIn() {
        self.loginTask?.cancel()
    }

    /// Kept for existing call sites: sign in with Harbor's built-in client.
    func quickLogin() async {
        await self.signInToGitHub()
    }

    private func runGitHubSignIn(clientID: String?, clientSecret: String?, enterpriseHost: URL?) async -> String? {
        let resolvedClientID = (clientID?.isEmpty == false ? clientID : nil) ?? self.defaultClientID
        self.session.account = .loggingIn(nil)
        self.session.lastError = nil

        if enterpriseHost == nil {
            self.session.settings.loopbackPort = self.defaultLoopbackPort
            await self.github.setAPIHost(self.defaultAPIHost)
            self.session.settings.githubHost = self.defaultGitHubHost
            self.session.settings.enterpriseHost = nil
        }
        let host = enterpriseHost ?? self.defaultGitHubHost

        do {
            if let clientSecret, clientSecret.isEmpty == false {
                try await self.auth.login(
                    clientID: resolvedClientID,
                    clientSecret: clientSecret,
                    host: host,
                    loopbackPort: self.session.settings.loopbackPort
                )
            } else {
                try await self.auth.loginWithDeviceFlow(clientID: resolvedClientID, host: host) { prompt in
                    self.session.account = .loggingIn(prompt)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(prompt.userCode, forType: .string)
                    NSWorkspace.shared.open(prompt.verificationURL)
                }
            }
            try Task.checkCancellation()
            // Only call it logged in once we know who the user is.
            let user = try await self.github.currentUser()
            self.accountSignedIn(user)
            await self.refresh()
            return nil
        } catch {
            self.session.account = .loggedOut
            if error.isCancellation { return nil }
            let message = error.userFacingMessage
            self.session.lastError = message
            return message
        }
    }

}
