@testable import repobarcli
import HarborCore
import Testing

struct CLISelectionTests {
    @Test
    func scopeSelectionParsesValues() {
        #expect(RepoScopeSelection(argument: "all") == .all)
        #expect(RepoScopeSelection(argument: "Pinned") == .pinned)
        #expect(RepoScopeSelection(argument: "hidden") == .hidden)
    }

    @Test
    func filterSelectionParsesValues() {
        #expect(RepoFilterSelection(argument: "all") == .all)
        #expect(RepoFilterSelection(argument: "work") == .work)
        #expect(RepoFilterSelection(argument: "issues") == .issues)
        #expect(RepoFilterSelection(argument: "pr") == .prs)
    }

    @Test
    func filterSelectionMapsToOnlyWith() {
        #expect(RepoFilterSelection.all.onlyWith == .none)
        #expect(RepoFilterSelection.work.onlyWith == RepositoryOnlyWith(requireIssues: true, requirePRs: true))
        #expect(RepoFilterSelection.issues.onlyWith == RepositoryOnlyWith(requireIssues: true))
        #expect(RepoFilterSelection.prs.onlyWith == RepositoryOnlyWith(requirePRs: true))
    }
}
