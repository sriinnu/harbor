import Foundation
import HarborCore

extension AppState {
    /// Preloads the user's contribution heatmap so the header can render without remote images.
    func loadContributionHeatmapIfNeeded(for username: String) async {
        guard self.session.settings.appearance.showContributionHeader, self.session.hasLoadedRepositories else { return }
        if self.session.contributionUser == username, !self.session.contributionHeatmap.isEmpty { return }
        let hasExisting = self.session.contributionUser == username && !self.session.contributionHeatmap.isEmpty
        if let cached = ContributionCacheStore.load(), cached.username == username, cached.isValid {
            await MainActor.run {
                self.session.contributionUser = username
                self.session.contributionHeatmap = cached.cells
                self.session.contributionError = nil
            }
            return
        }
        do {
            let cells = try await self.github.userContributionHeatmap(login: username)
            await MainActor.run {
                self.session.contributionUser = username
                self.session.contributionHeatmap = cells
                self.session.contributionError = nil
            }
            let cache = ContributionCache(
                username: username,
                expires: Date().addingTimeInterval(24 * 60 * 60),
                cells: cells
            )
            ContributionCacheStore.save(cache)
        } catch {
            await MainActor.run {
                if !hasExisting {
                    self.session.contributionHeatmap = []
                    self.session.contributionUser = username
                }
                self.session.contributionError = error.userFacingMessage
            }
        }
    }

    func clearContributionCache() {
        ContributionCacheStore.clear()
        self.session.contributionHeatmap = []
        self.session.contributionUser = nil
        self.session.contributionError = nil
    }
}
