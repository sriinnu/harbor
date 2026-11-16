import Foundation
import HarborCore

/// Several GitHub accounts, one active at a time: a switcher, not a merged view. Tokens live in
/// the Keychain under `github:<login>@<host>`; the settings keep only the non-secret index.
extension AppState {
    var githubAccounts: [GitHubAccount] { self.session.settings.githubAccounts.accounts }

    /// The id (Keychain key) of the active account, from the index or, before it is written, the Keychain.
    var activeGitHubAccountID: String? {
        let index = self.session.settings.githubAccounts
        if let active = index.active, index.account(id: active) != nil { return active }
        return nil
    }

    /// Stops everything running for the current account: the refresh, the menu's refresh, the
    /// contribution load and the loads of open details. Results that still land are dropped by the
    /// epoch, but nothing new starts under the old token.
    func cancelAccountWork() {
        self.refreshTask?.cancel()
        self.refreshTask = nil
        self.menuRefreshTask?.cancel()
        self.menuRefreshTask = nil
        self.contributionTask?.cancel()
        self.contributionTask = nil
    }

    /// Writes down a sign-in that GitHub accepted: the token under its account key, the index, the
    /// active pointer, then the standard account-change path. The old account's data is cleared
    /// when this is a different account. `adding` says a sign-in is beside an account that stays
    /// (defaults to the OAuth add flow's flag). Returns an error message, or nil.
    func completeSignIn(login: String, host: URL, tokens: OAuthTokens, adding: Bool? = nil, refreshAfter: Bool = true) async -> String? {
        // The pre-accounts item must become an account before another one is added beside it.
        await self.migrateLegacyAccountIfNeeded()
        // Still there means GitHub couldn't name its login (offline, revoked). Adding beside it
        // would orphan it: the pointer would hide an item no index lists. An add waits for it to be
        // named; a primary sign-in (nothing else on screen to protect) replaces the item.
        var replacesLegacy = false
        if self.auth.activeAccountKey == nil, self.auth.legacyTokens() != nil {
            if adding ?? self.session.isAddingAccount {
                self.auth.discardStaged()
                return "Harbor couldn't confirm your current sign-in just now, so it can't add another account yet. "
                    + "Check your connection and try again."
            }
            replacesLegacy = true
        }
        self.cancelAccountWork()
        let previous = self.activeGitHubAccountID
        let key: String
        do {
            key = try self.auth.commitAccount(tokens, login: login, host: host)
            try self.auth.activate(key, host: host)
        } catch {
            self.auth.discardStaged()
            return "The sign-in worked but Harbor couldn't save it to the Keychain."
        }
        if replacesLegacy { self.auth.removeLegacyItem() }
        self.session.settings.githubAccounts.upsert(GitHubAccount(login: login, host: host.host ?? "github.com", kind: tokens.kind))
        self.session.settings.githubAccounts.active = key
        if let previous, previous != key {
            self.clearUserScopedState()
            self.dataOwner = nil
        }
        await self.adoptPersonalTokenAccount(login: login, host: host)
        self.persistSettings()
        if refreshAfter { await self.refresh() }
        return nil
    }

    /// Switches to another signed-in account: cancel what is running, swap the active token, then
    /// the standard account-change path, so nothing of the old account stays on screen (repos,
    /// activity, review requests, own pull requests, rate-limit and backoff state). Returns an
    /// error message, or nil. `refreshAfter` is for tests, which must not reach GitHub.
    @discardableResult
    func switchGitHubAccount(to id: String, refreshAfter: Bool = true) async -> String? {
        guard let account = self.session.settings.githubAccounts.account(id: id) else {
            return "That account isn't in Harbor any more."
        }
        if id == self.activeGitHubAccountID, self.session.githubUser != nil { return nil }
        guard self.auth.tokens(account: id) != nil else {
            self.session.settings.githubAccounts.remove(id: id)
            self.persistSettings()
            return "Harbor can't find the token for \(account.login) in the Keychain. Sign in to it again."
        }
        self.loginTask?.cancel()
        self.cancelAccountWork()
        do {
            try self.auth.activate(id, host: account.hostURL)
        } catch {
            return "Harbor couldn't switch accounts: the Keychain refused."
        }
        self.session.settings.githubAccounts.active = id
        self.clearUserScopedState()
        self.dataOwner = nil
        await self.adoptPersonalTokenAccount(login: account.login, host: account.hostURL)
        self.persistSettings()
        if refreshAfter { self.requestRefresh(cancelInFlight: true) }
        return nil
    }

    /// Removes one account and its token. Another account is never dropped by it. Removing the
    /// active account switches to the next one, or signs out when it was the last.
    func removeGitHubAccount(_ id: String, refreshAfter: Bool = true) async {
        let accounts = self.session.settings.githubAccounts
        guard accounts.account(id: id) != nil else { return }
        guard id == self.activeGitHubAccountID else {
            self.auth.removeAccount(id)
            self.session.settings.githubAccounts.remove(id: id)
            self.persistSettings()
            return
        }
        self.loginTask?.cancel()
        self.cancelAccountWork()
        let remaining = accounts.accounts.filter { $0.id != id }
        guard remaining.isEmpty == false else {
            // The last one: everything goes, as a plain sign-out always did.
            await self.auth.logout()
            self.session.settings.githubAccounts = GitHubAccountIndex()
            self.persistSettings()
            self.session.account = .loggedOut
            self.clearUserScopedState()
            await self.settleAccountReset()
            return
        }
        self.auth.removeAccount(id)
        self.session.settings.githubAccounts.remove(id: id)
        self.persistSettings()
        // The removed account's data goes now; the switch below brings the next one in.
        self.session.account = .loggedOut
        self.clearUserScopedState()
        // An account whose token is gone is dropped by the switch; the next one is tried.
        for candidate in remaining {
            let failure = await self.switchGitHubAccount(to: candidate.id, refreshAfter: refreshAfter)
            guard failure != nil else { return }
        }
        // None of them could sign in: nothing is left to be.
        await self.auth.logout()
        self.session.settings.githubAccounts = GitHubAccountIndex()
        self.persistSettings()
        await self.settleAccountReset()
    }

    /// The first time the login behind the pre-accounts "default" Keychain item is known, moves it
    /// to its own `github:<login>@<host>` item and records the account, with no new sign-in.
    /// Copy, read back, then delete, so any failure leaves the old item signing in as before.
    func migrateLegacyAccountIfNeeded() async {
        guard self.auth.activeAccountKey == nil, let legacy = self.auth.legacyTokens() else { return }
        let host = self.session.settings.enterpriseHost ?? self.defaultGitHubHost
        let login: String
        if case let .loggedIn(user) = self.session.account {
            login = user.username
        } else if let named = try? await self.auth.identify(legacy, host: host) {
            login = named
        } else {
            return
        }
        guard let account = self.auth.migrateLegacyTokens(login: login, host: host) else { return }
        self.session.settings.githubAccounts.upsert(account)
        self.session.settings.githubAccounts.active = account.id
        self.persistSettings()
    }

    /// Makes the settings index agree with the Keychain: the Keychain alone names the accounts,
    /// so `harborcli` (which keeps its own settings domain) and a reset settings file both find
    /// their way back. Accounts whose token is gone leave the list, accounts the index lacks are
    /// added (the key carries login and host), and at launch (`adoptActive`) the active one is
    /// the one the Keychain, and so `harborcli`, uses. A Keychain that can't be listed (locked,
    /// prompt denied) changes nothing: that is not the same as having no accounts.
    func reconcileAccountIndex(adoptActive: Bool = true) {
        guard let keys = try? self.auth.storedAccountKeys() else { return }
        var index = self.session.settings.githubAccounts
        let stored = Set(keys)
        index.accounts.removeAll { stored.contains($0.id) == false }
        for key in keys where index.account(id: key) == nil {
            guard let named = GitHubAccountKey.parse(key) else { continue }
            let kind = self.auth.tokens(account: key)?.kind ?? .oauth
            index.upsert(GitHubAccount(login: named.login, host: named.host, kind: kind))
        }
        if adoptActive, let keychainActive = self.auth.activeAccountKey, index.account(id: keychainActive) != nil {
            index.active = keychainActive
        } else if let active = index.active, index.account(id: active) == nil {
            index.active = nil
        }
        if index != self.session.settings.githubAccounts {
            self.session.settings.githubAccounts = index
            self.persistSettings()
        }
        // The refresher posts to the active account's host from the first request after a relaunch.
        if let active = index.activeAccount {
            self.auth.useHost(active.hostURL)
        } else if let enterprise = self.session.settings.enterpriseHost {
            self.auth.useHost(enterprise)
        }
    }
}
