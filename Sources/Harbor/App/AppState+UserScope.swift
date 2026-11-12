import Foundation
import HarborCore

extension AppState {
    /// Everything on screen that belongs to the signed-in user, dropped at once: the repo
    /// list, the activity strips, the yearly totals, the review requests. Called on sign-out
    /// and when a different account signs in, so one account never sees another's data.
    /// Bumping `scopeEpoch` makes any load still in flight discard its result.
    func clearUserScopedState() {
        self.scopeEpoch += 1
        self.dataOwner = nil
        self.contributionTask?.cancel()
        self.contributionTask = nil
        self.detailLoads.removeAll()
        let session = self.session
        session.repositories = []
        session.menuSnapshot = nil
        session.menuDisplayIndex = [:]
        session.hasLoadedRepositories = false
        session.lastRefreshDate = nil
        session.rateLimitReset = nil
        session.lastError = nil
        session.contributionHeatmap = []
        session.contributionUser = nil
        session.contributionError = nil
        session.contributionYears = []
        session.contributionYearsState = .idle
        session.providerActivity = [:]
        session.repoActivity = [:]
        session.globalActivityEvents = []
        session.globalActivityError = nil
        session.globalCommitEvents = []
        session.globalCommitError = nil
        self.reviewRequests.clear()
        // The old account's rate-limit blocks and recent lists must not carry over either. The
        // reset is one task in a chain, so two quick changes still run in order, and
        // `settleAccountReset()` lets the next request wait for it.
        let previous = self.accountResetTask
        let reset = self.accountReset
        self.accountResetTask = Task {
            await previous?.value
            await reset()
        }
        for reset in self.accountScopeResets { reset() }
    }

    /// Starts the review-request search, or joins the one in flight. Signed out there is no
    /// token, so the search could only fail and leave a failure behind that outlives the sign-in:
    /// it does not run. Called on every refresh and every panel open, so a failed search is
    /// retried, never pinning the menu bar icon on the unchecked ring.
    @discardableResult
    func searchReviewRequests() -> Task<Void, Never>? {
        guard case .loggedIn = self.session.account else { return nil }
        return self.reviewRequests.load()
    }

    /// Returns once every account reset started so far has run. A refresh calls it before its
    /// first request, so the new account never meets the old account's limits.
    func settleAccountReset() async {
        await self.accountResetTask?.value
    }

    /// Both sign-out buttons (Settings and the menu) end here: tokens gone, the account set to
    /// logged out, and everything of that account cleared at once, with loads in flight dropped
    /// by the epoch bump. Cancels the refresh running for the old account first.
    func signOut() async {
        self.refreshTask?.cancel()
        self.refreshTask = nil
        self.menuRefreshTask?.cancel()
        self.menuRefreshTask = nil
        await self.auth.logout()
        self.session.account = .loggedOut
        self.clearUserScopedState()
        await self.settleAccountReset()
    }

    /// The profile of a new sign-in has loaded. Bumping the epoch drops any refresh that began
    /// before it, so an older load can't merge into the new account.
    func accountSignedIn(_ user: UserIdentity) {
        self.scopeEpoch += 1
        // A failure from before sign-in (the search ran without a token) must not outlive it.
        self.reviewRequests.clear()
        self.session.account = .loggedIn(user)
    }

    /// Records whose data is on screen. A different login than the one before clears it all
    /// first. Returns true when it did.
    @discardableResult
    func adoptAccountData(for login: String?) -> Bool {
        guard let login, login.isEmpty == false else { return false }
        defer { self.dataOwner = login }
        guard let owner = self.dataOwner, owner.caseInsensitiveCompare(login) != .orderedSame else { return false }
        self.clearUserScopedState()
        return true
    }
}
