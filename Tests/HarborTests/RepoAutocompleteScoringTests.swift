import Foundation
@testable import HarborCore
import Testing

struct RepoAutocompleteScoringTests {
    // The picker lists your repos; strangers' only when "Include public repos" is ticked.

    @Test
    func noMatchAmongYourReposIsAnEmptyList() {
        let mine = [Self.repo(owner: "sriinnu", name: "ribhu"), Self.repo(owner: "sriinnu", name: "docs")]
        let list = RepoAutocompleteScoring.suggestions(mine: mine, public: [], query: "astral", limit: 8)
        #expect(list.map(\.fullName) == [])
    }

    @Test
    func yourReposComeBeforeABetterPublicMatch() {
        let mine = [Self.repo(owner: "sriinnu", name: "astral-notes"), Self.repo(owner: "sriinnu", name: "docs")]
        let others = [Self.repo(owner: "astralapp", name: "astral"), Self.repo(owner: "sriinnu", name: "astral-notes")]
        let list = RepoAutocompleteScoring.suggestions(mine: mine, public: others, query: "astral", limit: 8)
        #expect(list.map(\.fullName) == ["sriinnu/astral-notes", "astralapp/astral"])
        // The old merge ranked by score alone and put the stranger's exact match first.
        let old = RepoAutocompleteScoring.merge(
            local: RepoAutocompleteScoring.scored(repos: mine, query: "astral", sourceRank: 0),
            remote: RepoAutocompleteScoring.scored(repos: others, query: "astral", sourceRank: 1),
            limit: 8
        )
        #expect(old.map(\.fullName) == ["astralapp/astral", "sriinnu/astral-notes"])
    }

    @Test
    func anEmptyQueryListsYourReposInOrder() {
        let mine = (1...10).map { Self.repo(owner: "sriinnu", name: "r\($0)") }
        let list = RepoAutocompleteScoring.suggestions(mine: mine, public: [Self.repo(owner: "x", name: "y")], query: "  ", limit: 3)
        #expect(list.map(\.fullName) == ["sriinnu/r1", "sriinnu/r2", "sriinnu/r3"])
    }

    @Test
    func exactFullNameWins() {
        let exact = Self.repo(owner: "steipete", name: "Harbor")
        let prefix = Self.repo(owner: "steipete", name: "Repo")

        let scored = RepoAutocompleteScoring.scored(
            repos: [prefix, exact],
            query: "steipete/Harbor",
            sourceRank: 0
        )
        let sorted = RepoAutocompleteScoring.sort(scored)
        #expect(sorted.first?.repo.fullName == "steipete/Harbor")
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
        let repo = Self.repo(owner: "steipete", name: "Harbor")
        let score = RepoAutocompleteScoring.score(repo: repo, query: "hrb")
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
