import Foundation
import Synchronization
import HarborCore

extension AppState {
    /// The data only a repo's detail shows (activity feed, run count, traffic), fetched when that detail opens and never for the whole list. Several
    /// requests run side by side; the result is folded into the row in place. Not stored
    /// anywhere else: the next open asks again.
    func loadRepoDetails(fullName: String) async {
        guard self.detailLoads.insert(fullName).inserted,
              let repo = self.session.repositories.first(where: { $0.fullName == fullName }) else { return }
        defer { self.detailLoads.remove(fullName) }
        self.session.noteOpened(fullName)
        let epoch = self.scopeEpoch
        if self.session.deferredRepoNames.contains(fullName) { await self.countDeferredRepo(repo, epoch: epoch) }
        guard Task.isCancelled == false, epoch == self.scopeEpoch,
              let repo = self.session.repositories.first(where: { $0.fullName == fullName }) else { return }
        let detailed = await self.github.loadDetails(for: repo, includeAlertCounts: false)
        guard Task.isCancelled == false, epoch == self.scopeEpoch else { return }
        let now = self.session.menuSnapshot?.capturedAt ?? Date()
        // Fold in only what the detail owns: a batch that landed meanwhile keeps its counts.
        let merged = self.session.repositories.map { $0.fullName == fullName ? $0.mergingDetails(detailed, loadedFrom: repo) : $0 }
        self.show(merged, capturedAt: now)
    }

    /// A repo the refresh left uncounted (past the recent cap or the GraphQL budget) is counted
    /// now that someone opened it: one batch query for that repo alone. A rate-limited answer
    /// comes back as the row's own error, so the row says so instead of showing nothing.
    func countDeferredRepo(_ repo: Repository, epoch: Int) async {
        let landed = Mutex<[Repository]>([])
        await self.github.enrich([repo]) { batch in landed.withLock { $0 += batch } }
        guard Task.isCancelled == false, epoch == self.scopeEpoch, let counted = landed.withLock({ $0.first }) else { return }
        let merged = self.session.repositories.map { $0.fullName == repo.fullName ? $0.mergingBatch(counted) : $0 }
        self.session.deferredRepoNames.remove(repo.fullName)
        self.show(merged, capturedAt: self.session.menuSnapshot?.capturedAt ?? Date())
    }

    /// The health card's secret-scanning and code-scanning counts, folded into the row. The
    /// Dependabot count stays the batch's, which reads it for every repo.
    func applyHealthAlerts(fullName: String, alerts: RepoSecurity, epoch: Int) {
        guard epoch == self.scopeEpoch, self.session.repositories.contains(where: { $0.fullName == fullName }) else { return }
        let merged = self.session.repositories.map { repo -> Repository in
            guard repo.fullName == fullName else { return repo }
            var updated = repo
            updated.security = RepoSecurity(
                dependabot: repo.security?.dependabot ?? alerts.dependabot,
                secretLeaks: alerts.secretLeaks,
                codeScanning: alerts.codeScanning
            )
            return updated
        }
        self.show(merged, capturedAt: self.session.menuSnapshot?.capturedAt ?? Date())
    }

    private func show(_ merged: [Repository], capturedAt now: Date) {
        self.session.repositories = merged
        self.session.menuSnapshot = MenuSnapshot(repositories: merged, capturedAt: now)
        let localIndex = self.session.localRepoIndex
        let models = merged.map { RepositoryDisplayModel(repo: $0, localStatus: localIndex.status(for: $0), now: now) }
        self.session.menuDisplayIndex = Dictionary(models.map { ($0.title, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
