import Foundation
import HarborCore

/// One repo's commit activity and how fetching it ended.
struct RepoActivitySlice: Equatable {
    var state: ActivityLoadState = .idle
    var days: [HeatmapCell] = []

    /// GitHub pads the current week with future days at zero; drop them so the strip ends today.
    static func pastDays(_ cells: [HeatmapCell], now: Date = Date()) -> [HeatmapCell] {
        cells.filter { $0.date <= now }
    }
}

extension AppState {
    /// Fills `session.repoActivity` for a repo each time its detail opens: one
    /// `stats/commit_activity` request, never skipped because an earlier open already
    /// fetched. The cells already on screen stay up while the new request runs; only a
    /// request already in flight is joined. Memory only. Every repo the app lists comes from
    /// GitHub (GitLab and Azure DevOps repos are not in the list), so there is no other
    /// provider to ask.
    func loadRepoActivity(fullName: String, owner: String, name: String, known: [HeatmapCell]) async {
        Task { await self.loadRepoDetails(fullName: fullName) }
        var slice = self.session.repoActivity[fullName] ?? RepoActivitySlice()
        if case .loading = slice.state { return }
        if slice.days.isEmpty, !known.isEmpty { slice.days = RepoActivitySlice.pastDays(known) }
        slice.state = .loading
        self.session.repoActivity[fullName] = slice
        let epoch = self.scopeEpoch
        do {
            let cells = try await self.commitActivityLoader(owner, name)
            guard epoch == self.scopeEpoch else { return }
            self.session.repoActivity[fullName] = RepoActivitySlice(state: .ready, days: RepoActivitySlice.pastDays(cells))
        } catch {
            guard epoch == self.scopeEpoch else { return }
            // A superseded or abandoned request is not a failure: say nothing, and keep what
            // was on screen so the next open asks again.
            if error.isCancellation {
                let kept = slice.days
                self.session.repoActivity[fullName] = kept.isEmpty ? nil : RepoActivitySlice(state: .idle, days: kept)
            } else {
                // The failure shows, over the old cells; the old cells are not shown as current.
                self.session.repoActivity[fullName] = RepoActivitySlice(state: .failed(error.userFacingMessage))
            }
        }
    }
}
