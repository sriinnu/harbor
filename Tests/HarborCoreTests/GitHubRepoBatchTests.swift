import Foundation
@testable import HarborCore
import Testing

struct GitHubRepoBatchTests {
    @Test
    func query_forTwoRepos_isExact() {
        let expected = """
        query RepoBatch($o0: String!, $n0: String!, $o1: String!, $n1: String!) {
          r0: repository(owner: $o0, name: $n0) { ...RepoBatchFields }
          r1: repository(owner: $o1, name: $n1) { ...RepoBatchFields }
        }
        fragment RepoBatchFields on Repository {
          pullRequests(states: OPEN) { totalCount }
          issues(states: OPEN) { totalCount }
          releases(first: 5, orderBy: {field: CREATED_AT, direction: DESC}) {
            nodes { name tagName createdAt publishedAt url isDraft }
          }
          vulnerabilityAlerts(first: 100, states: OPEN) { totalCount nodes { securityVulnerability { severity } } }
          defaultBranchRef {
            target {
              ... on Commit {
                oid
                committedDate
                messageHeadline
                url
                author { name user { login avatarUrl } }
                statusCheckRollup { state }
              }
            }
          }
        }
        """
        #expect(GitHubRepoBatch.query(count: 2) == expected)
    }

    @Test
    func query_neverContainsOwnerOrName() {
        let repos = [RepoRef(owner: "evil\") { x }", name: "n")]
        let query = GitHubRepoBatch.query(count: repos.count)
        #expect(query.contains("evil") == false)
        #expect(GitHubRepoBatch.variables(for: repos) == ["o0": .string("evil\") { x }"), "n0": .string("n")])
    }

    @Test
    func chunks_splitInOrder() {
        let repos = (0 ..< (GitHubRepoBatch.maxPerQuery * 2 + 1)).map { RepoRef(owner: "o", name: "r\($0)") }
        let groups = GitHubRepoBatch.chunks(repos)
        #expect(groups.map(\.count) == [GitHubRepoBatch.maxPerQuery, GitHubRepoBatch.maxPerQuery, 1])
        #expect(groups.flatMap { $0 } == repos)
        #expect(GitHubRepoBatch.chunks([]).isEmpty)
    }

    @Test
    func parse_readsCountsReleaseCICommitAndAlerts_andSkipsNullRepos() throws {
        let json = """
        {"data": {
          "r0": {
            "pullRequests": {"totalCount": 3},
            "issues": {"totalCount": 7},
            "releases": {"nodes": [
              {"name": "", "tagName": "v1.0", "createdAt": "2026-01-01T00:00:00Z", "publishedAt": "2026-01-02T00:00:00Z", "url": "https://github.com/o/a/releases/v1.0", "isDraft": false},
              {"name": "draft", "tagName": "v2.0", "createdAt": "2026-03-01T00:00:00Z", "publishedAt": null, "url": "https://github.com/o/a/releases/v2.0", "isDraft": true}
            ]},
            "vulnerabilityAlerts": {"nodes": [
              {"securityVulnerability": {"severity": "HIGH"}},
              {"securityVulnerability": {"severity": "MODERATE"}},
              {"securityVulnerability": {"severity": "HIGH"}}
            ]},
            "defaultBranchRef": {"target": {
              "oid": "abc", "committedDate": "2026-02-03T04:05:06Z", "messageHeadline": "Fix it",
              "url": "https://github.com/o/a/commit/abc",
              "author": {"name": "Ada", "user": {"login": "ada", "avatarUrl": "https://avatars.example/ada"}},
              "statusCheckRollup": {"state": "FAILURE"}
            }}
          },
          "r1": null
        }, "errors": [{"type": "NOT_FOUND", "path": ["r1"]}]}
        """
        let repos = [RepoRef(owner: "o", name: "a"), RepoRef(owner: "o", name: "gone")]
        let parsed = try GitHubRepoBatch.parse(Data(json.utf8), repos: repos)
        #expect(parsed.keys.sorted { $0.name < $1.name } == [repos[0]])
        let snapshot = try #require(parsed[repos[0]])
        #expect(snapshot.openPulls == 3)
        #expect(snapshot.openIssues == 7)
        #expect(snapshot.ci == .failing)
        #expect(snapshot.release == Release(
            name: "v1.0",
            tag: "v1.0",
            publishedAt: Date(timeIntervalSince1970: 1_767_312_000),
            url: URL(string: "https://github.com/o/a/releases/v1.0")!
        ))
        #expect(snapshot.dependabot == DependabotTally(critical: 0, high: 2, medium: 1, low: 0))
        #expect(snapshot.latestCommit == ActivityEvent(
            title: "Fix it",
            actor: "ada",
            actorAvatarURL: URL(string: "https://avatars.example/ada"),
            date: Date(timeIntervalSince1970: 1_770_091_506),
            url: URL(string: "https://github.com/o/a/commit/abc")!,
            eventType: "PushEvent"
        ))
    }

    @Test
    func parse_withoutData_throws() {
        #expect(throws: URLError.self) {
            try GitHubRepoBatch.parse(Data(#"{"errors":[{"message":"bad"}]}"#.utf8), repos: [RepoRef(owner: "o", name: "a")])
        }
    }

    @Test
    func ciStatus_mapsRollupStates() {
        #expect(GitHubRepoBatch.ciStatus(rollup: "SUCCESS") == .passing)
        #expect(GitHubRepoBatch.ciStatus(rollup: "ERROR") == .failing)
        #expect(GitHubRepoBatch.ciStatus(rollup: "FAILURE") == .failing)
        #expect(GitHubRepoBatch.ciStatus(rollup: "PENDING") == .pending)
        #expect(GitHubRepoBatch.ciStatus(rollup: "EXPECTED") == .pending)
        #expect(GitHubRepoBatch.ciStatus(rollup: nil) == .unknown)
    }

    @Test
    func applying_fillsCountsAndKeepsOtherSecurityFields() {
        var repo = Repository(
            id: "1", name: "a", owner: "o", sortOrder: nil, error: "old", rateLimitedUntil: nil,
            ciStatus: .unknown, openIssues: 99, openPulls: 0, latestRelease: nil, latestActivity: nil,
            traffic: nil, heatmap: [], security: RepoSecurity(dependabot: nil, secretLeaks: 4, codeScanning: 5),
            pullCountsKnown: false
        )
        repo.pullCountsKnown = false
        let tally = DependabotTally(critical: 1, high: 0, medium: 0, low: 0)
        let updated = repo.applying(RepoSnapshot(openPulls: 2, openIssues: 5, ci: .passing, release: nil, dependabot: tally, latestCommit: nil))
        #expect(updated.openPulls == 2)
        #expect(updated.openIssues == 5)
        #expect(updated.ciStatus == .passing)
        #expect(updated.pullCountsKnown)
        #expect(updated.security == RepoSecurity(dependabot: tally, secretLeaks: 4, codeScanning: 5))
    }
}
