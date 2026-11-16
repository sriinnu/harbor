import Foundation
import HarborCore

extension AppState {
    /// Loads the user's contribution heatmap from GitHub. Nothing is saved between loads: each
    /// call asks again, and calls that arrive while one is in flight join it. The strip keeps
    /// showing the last result until the new one lands.
    func loadContributionHeatmap(for username: String) async {
        guard self.session.settings.appearance.showContributionHeader, self.session.hasLoadedRepositories else { return }
        if let running = self.contributionTask {
            await running.value
            return
        }
        let task = Task { await self.fetchContributionHeatmap(for: username) }
        self.contributionTask = task
        await task.value
        self.contributionTask = nil
    }

    private func fetchContributionHeatmap(for username: String) async {
        let hasExisting = self.session.contributionUser == username && !self.session.contributionHeatmap.isEmpty
        // Sign-out and sign-in bump the epoch: a response that lands afterwards is the old
        // account's and is dropped, not written over the cleared strip.
        let epoch = self.scopeEpoch
        do {
            let cells = try await self.contributionHeatmapLoader(username)
            guard epoch == self.scopeEpoch else { return }
            self.session.contributionUser = username
            self.session.contributionHeatmap = cells
            self.session.contributionError = nil
        } catch {
            if error.isCancellation || epoch != self.scopeEpoch { return }
            if !hasExisting {
                self.session.contributionHeatmap = []
                self.session.contributionUser = username
            }
            self.session.contributionError = error.userFacingMessage
        }
    }
}
