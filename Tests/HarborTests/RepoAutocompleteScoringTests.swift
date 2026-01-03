import Foundation
@testable import HarborCore
import Testing

struct RepoAutocompleteScoringTests {
    @Test
    func exactFullNameWins() {
        let exact = Self.repo(owner: "steipete", name: "RepoBar")
        let prefix = Self.repo(owner: "steipete", name: "Repo")

        let scored = RepoAutocompleteScoring.scored(
            repos: [prefix, exact],
            query: "steipete/RepoBar",
            sourceRank: 0
        )
        let sorted = RepoAutocompleteScoring.sort(scored)
        #expect(sorted.first?.repo.fullName == "steipete/RepoBar")
    }

    @Test
    func repoNameBeatsOwnerMatch() {
        let ownerMatch = Self.repo(owner: "repo", name: "alpha")
        let repoMatch = Self.repo(owner: "steipete", name: "repo")

        let scored = RepoAutocompleteScoring.scored(
            repos: [ownerMatch, repoMatch],
            query: "repo",
            sourceRank: 0
        )
        let sorted = RepoAutocompleteScoring.sort(scored)
        #expect(sorted.first?.repo.fullName == "steipete/repo")
    }

    @Test
    func subsequenceMatchesAreIncluded() {
        let repo = Self.repo(owner: "steipete", name: "RepoBar")
        let score = RepoAutocompleteScoring.score(repo: repo, query: "rpb")
        #expect(score != nil)
    }

    @Test
    func ownerPlusRepoBeatsRepoOnly() {
        let exactOwner = Self.repo(owner: "steipete", name: "repo")
        let otherOwner = Self.repo(owner: "other", name: "repo")

        let scored = RepoAutocompleteScoring.scored(
            repos: [otherOwner, exactOwner],
            query: "steipete/repo",
            sourceRank: 0
        )
        let sorted = RepoAutocompleteScoring.sort(scored)
        #expect(sorted.first?.repo.fullName == "steipete/repo")
    }
}

private extension RepoAutocompleteScoringTests {
    static func repo(owner: String, name: String) -> Repository {
        Repository(
            id: UUID().uuidString,
            name: name,
            owner: owner,
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            ciRunCount: nil,
            openIssues: 0,
            openPulls: 0,
            stars: 0,
            pushedAt: nil,
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )
    }
}
