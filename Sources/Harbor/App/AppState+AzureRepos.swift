import Foundation
import HarborCore

/// What asking Azure DevOps for the organization's repositories came to.
enum AzureListOutcome: Equatable {
    /// No organization, or no token for it: there is nothing to list.
    case notConnected
    case listed([Repository])
    case failed(String)
}

extension AppState {
    /// The connected organization's repositories, one request through the app's one lister.
    /// The token is read once, here. Nothing is kept on disk.
    func fetchAzureRepositories() async -> AzureListOutcome {
        guard let organization = UserDefaults.standard.string(forKey: "azureOrganization"), !organization.isEmpty else {
            return .notConnected
        }
        let pat: String
        do {
            pat = try AzureDevOpsPATStore.shared.token(forOrganization: organization)
        } catch PATStoreError.tokenNotFound {
            return .notConnected
        } catch {
            return .failed(error.localizedDescription)
        }
        do {
            return try await .listed(self.azureRepoLister.repositories(organization: organization, pat: pat))
        } catch {
            // A superseded refresh is control flow, not a failure: say nothing about it.
            if error.isCancellation { return .failed("") }
            await DiagnosticsLogger.shared.message("Azure DevOps repositories: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    /// Folds an Azure DevOps answer into the session. A listing replaces the Azure rows; a
    /// failure keeps the ones already on screen and says why. GitHub's rows are left alone.
    func landAzure(_ outcome: AzureListOutcome, epoch: Int) {
        guard epoch == self.scopeEpoch else { return }
        switch outcome {
        case .notConnected:
            self.session.azureRepositories = []
            self.session.azureListError = nil
        case let .listed(rows):
            self.session.azureRepositories = rows
            self.session.azureListError = nil
        case let .failed(message):
            guard !message.isEmpty else { return }
            self.session.azureListError = message
        }
        self.showAzureRows(epoch: epoch)
        if self.session.lastError == nil { self.session.lastError = self.session.azureListError }
    }

    /// The list on screen with GitHub's rows as they are and the session's Azure rows in
    /// place of whatever Azure rows it held.
    func showAzureRows(epoch: Int) {
        guard epoch == self.scopeEpoch else { return }
        let github = self.session.repositories.filter { !$0.isAzure }
        let combined = RepoListSources.combine(github: github, azure: self.session.azureRepositories)
        let shown = self.applyPinnedOrder(to: self.applyVisibilityFilters(to: combined))
        self.session.repositories = shown
        let now = self.session.menuSnapshot?.capturedAt ?? Date()
        self.session.menuSnapshot = MenuSnapshot(repositories: shown, capturedAt: now)
        let localIndex = self.session.localRepoIndex
        let models = shown.map { RepositoryDisplayModel(repo: $0, localStatus: localIndex.status(for: $0), now: now) }
        self.session.menuDisplayIndex = Dictionary(models.map { ($0.title, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The picker's Azure rows: what this session already listed, else one request.
    func azureRepositoriesForPicker() async -> [Repository] {
        if !self.session.azureRepositories.isEmpty { return self.session.azureRepositories }
        if case let .listed(rows) = await self.fetchAzureRepositories() { return rows }
        return []
    }
}
