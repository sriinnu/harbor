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
    /// error when the user cancelled). With `addingAccount`, the account on screen stays
    /// signed in and untouched until the new one succeeds; a failure leaves it as it was.
    /// Returns the error message, if any.
    @discardableResult
    func signInToGitHub(
        clientID: String? = nil,
        clientSecret: String? = nil,
        enterpriseHost: URL? = nil,
        addingAccount: Bool = false
    ) async -> String? {
        self.loginTask?.cancel()
        let task = Task { @MainActor in
            await self.runGitHubSignIn(
                clientID: clientID, clientSecret: clientSecret, enterpriseHost: enterpriseHost, adding: addingAccount
            )
        }
        self.loginTask = task
        let message = await task.value
        if self.loginTask == task { self.loginTask = nil }
        return message
    }

    /// Signs in with a pasted personal access token (github.com only), as the only account or as
    /// another one. The token is checked with `GET /user` first; on any failure nothing changes, so
    /// a working sign-in survives a bad paste. A token for a different account than the one on
    /// screen clears the old account's data first, through the same path as an account switch.
    /// Returns the error message, or nil on success. `refreshAfter` is for tests, which must not
    /// reach GitHub.
    @discardableResult
    func signInWithToken(_ token: String, validator: GitHubTokenValidator = GitHubTokenValidator(), refreshAfter: Bool = true) async -> String? {
        self.loginTask?.cancel()
        let check: GitHubTokenCheck
        let tokens: OAuthTokens
        do {
            check = try await self.auth.validatePersonalToken(token, validator: validator)
            tokens = OAuthTokens(accessToken: try GitHubTokenValidator.clean(token), refreshToken: "", expiresAt: nil, kind: .personalAccessToken)
        } catch let error as GitHubTokenError {
            return error.localizedDescription
        } catch {
            return error.isCancellation ? nil : error.userFacingMessage
        }
        // A token pasted while an account is on screen is another account, not a replacement:
        // the same rule as the OAuth add, so it waits for a legacy sign-in that can't be named yet.
        var adding = false
        if case .loggedIn = self.session.account { adding = true }
        return await self.completeSignIn(
            login: check.login, host: self.defaultGitHubHost, tokens: tokens, adding: adding, refreshAfter: refreshAfter
        )
    }

    /// The account switch for a login that is now (or already was) the active account: the old
    /// refresh is cancelled, a different login than the one on screen clears its data through
    /// `adoptAccountData`, and the epoch bump in `accountSignedIn` drops anything still in flight.
    /// `host` is github.com unless the account lives on a GitHub Enterprise host.
    func adoptPersonalTokenAccount(login: String, host: URL? = nil) async {
        let host = host ?? self.defaultGitHubHost
        self.cancelAccountWork()
        self.session.lastError = nil
        if host.host?.lowercased() == "github.com" {
            await self.github.setAPIHost(self.defaultAPIHost)
            self.session.settings.githubHost = self.defaultGitHubHost
            self.session.settings.enterpriseHost = nil
        } else {
            await self.github.setAPIHost(host.appending(path: "/api/v3"))
            self.session.settings.githubHost = self.defaultGitHubHost
            self.session.settings.enterpriseHost = host
        }
        self.adoptAccountData(for: login)
        self.accountSignedIn(UserIdentity(username: login, host: host))
        await self.settleAccountReset()
    }

    func cancelGitHubSignIn() {
        self.loginTask?.cancel()
    }

    /// Kept for existing call sites: sign in with Harbor's built-in client.
    func quickLogin() async {
        await self.signInToGitHub()
    }

    private func runGitHubSignIn(clientID: String?, clientSecret: String?, enterpriseHost: URL?, adding: Bool) async -> String? {
        let resolvedClientID = (clientID?.isEmpty == false ? clientID : nil) ?? self.defaultClientID
        self.session.lastError = nil
        if adding {
            self.session.addAccountPrompt = nil
            self.session.isAddingAccount = true
        } else {
            self.session.account = .loggingIn(nil)
        }
        defer {
            self.session.addAccountPrompt = nil
            self.session.isAddingAccount = false
        }

        let host = enterpriseHost ?? self.defaultGitHubHost
        // An enterprise sign-in keeps the loopback port in the settings; github.com uses the default.
        let loopbackPort = enterpriseHost == nil ? self.defaultLoopbackPort : self.session.settings.loopbackPort

        do {
            let tokens: OAuthTokens
            if let clientSecret, clientSecret.isEmpty == false {
                tokens = try await self.auth.login(
                    clientID: resolvedClientID,
                    clientSecret: clientSecret,
                    host: host,
                    loopbackPort: loopbackPort
                )
            } else {
                tokens = try await self.auth.loginWithDeviceFlow(clientID: resolvedClientID, host: host) { prompt in
                    if adding {
                        self.session.addAccountPrompt = prompt
                    } else {
                        self.session.account = .loggingIn(prompt)
                    }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(prompt.userCode, forType: .string)
                    NSWorkspace.shared.open(prompt.verificationURL)
                }
            }
            try Task.checkCancellation()
            // Only call it logged in once we know who the user is.
            let login = try await self.auth.identify(tokens, host: host)
            try Task.checkCancellation()
            let failure = await self.completeSignIn(login: login, host: host, tokens: tokens)
            if failure != nil, adding == false { self.session.account = .loggedOut }
            return failure
        } catch {
            self.auth.discardStaged()
            if adding == false { self.session.account = .loggedOut }
            if error.isCancellation { return nil }
            let message = error.userFacingMessage
            // A failed extra account is the dialog's news, not an error for the account on screen.
            if adding == false { self.session.lastError = message }
            return message
        }
    }
}
