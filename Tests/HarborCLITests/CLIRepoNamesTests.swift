@testable import HarborCLI
import HarborCore
import Testing

/// harborcli talks to GitHub only: an Azure DevOps pin must never become a GitHub request.
struct CLIRepoNamesTests {
    @Test
    func azurePinsAreNotTurnedIntoGitHubLookups() {
        let pins = ["octo/one", "azure:dev.azure.com/acme/Web/site", "junk", "octo/two"]
        #expect(CLIRepoNames.gitHubLookups(pins) == [
            .init(index: 0, owner: "octo", name: "one"),
            .init(index: 3, owner: "octo", name: "two")
        ])
    }

    @Test
    func anAzureNameTypedAtTheCLIIsRefusedByName() {
        #expect(CLIRepoNames.invalidNameMessage("azure:dev.azure.com/acme/Web/site")
            == "harborcli works with GitHub repositories only; azure:dev.azure.com/acme/Web/site is an Azure DevOps repository")
        #expect(CLIRepoNames.invalidNameMessage("a/b/c") == "Repository must be in owner/name format")
    }
}
