import Foundation
@testable import Harbor
@testable import HarborCore
import Testing

/// How an Azure DevOps row shows in the app: no GitHub address, no made-up stars or forks.
@MainActor
struct AzureRepoRowTests {
    private func azure() -> Repository {
        let item = AzureDevOpsRepository(
            id: "g1", name: "site", url: nil, project: .init(id: "p1", name: "Web"), defaultBranch: "refs/heads/main",
            size: nil, remoteUrl: nil, sshUrl: nil, webUrl: "https://dev.azure.com/acme/Web/_git/site", isDisabled: false
        )
        return AzureRepoLister.repository(from: item, host: "dev.azure.com", organization: "acme")!
    }

    @Test
    func anAzureKeyHasNoGitHubAddress() {
        let builder = RepoWebURLBuilder(host: URL(string: "https://github.com")!)
        #expect(builder.repoURL(fullName: "azure:dev.azure.com/acme/Web/site") == nil)
        #expect(builder.repoURL(fullName: "acme/Web/site") == nil)
        #expect(builder.repoURL(fullName: "octo/repo") == URL(string: "https://github.com/octo/repo"))
    }

    @Test
    func anAzureRowShowsNoStarsForksOrCounts() {
        let model = RepositoryDisplayModel(repo: self.azure())
        #expect(model.stats.map(\.id) == [])
        #expect(model.title == "azure:dev.azure.com/acme/Web/site")
    }

    @Test
    func anAzurePinReadsAsOrgProjectRepo() {
        #expect(RepoSettingsView.readable("azure:dev.azure.com/acme/Web/site") == "acme / Web / site · Azure")
        #expect(RepoSettingsView.readable("octo/repo") == "octo/repo")
    }
}

@MainActor
struct AzureRepoPanelTests {
    private func azure() -> Repository {
        let item = AzureDevOpsRepository(
            id: "g1", name: "site", url: nil, project: .init(id: "p1", name: "Web"), defaultBranch: "refs/heads/main",
            size: nil, remoteUrl: nil, sshUrl: nil, webUrl: "https://dev.azure.com/acme/Web/_git/site", isDisabled: false
        )
        return AzureRepoLister.repository(from: item, host: "dev.azure.com", organization: "acme")!
    }

    @Test
    func aRepoListForAnAzureKeyHasNoGitHubOwner() {
        let model = RepoListModel(kind: .pulls, fullName: "azure:dev.azure.com/acme/Web/site")
        #expect([model.owner, model.name] == ["", ""])
        let github = RepoListModel(kind: .pulls, fullName: "octo/site")
        #expect([github.owner, github.name] == ["octo", "site"])
    }

    @Test
    func azureRowsAreNeverStillChecking() {
        var content = HarborPanelContent()
        content.hasLoadedRepositories = true
        content.reviewRequestsLoaded = true
        content.myPullsLoaded = true
        content.repos = [RepositoryDisplayModel(repo: self.azure())]
        #expect(content.checkingRepoCount == 0)
        #expect(content.calm == .clear)
    }

    @Test
    func theFilterMatchesReadableAzureNamesNotTheKey() {
        let model = RepositoryDisplayModel(repo: self.azure())
        #expect(model.searchName == "acme/Web/site")
        #expect(model.displayTitle == "Web/site")
        #expect(NameFilter.matches(model.searchName, query: "dev") == false)
        #expect(NameFilter.matches(model.searchName, query: "web") == true)
    }
}
