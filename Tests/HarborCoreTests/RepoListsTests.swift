import Foundation
@testable import HarborCore
import XCTest

/// The list documents are pinned exactly (a changed field is a changed request), and each
/// list's decoding is checked against the shape GitHub returned when the queries were run.
final class RepoListsTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-11T12:00:00Z")!

    // MARK: Documents

    func testIssuesDocument() {
        XCTAssertEqual(RepoListGraphQL.issues, """
        query RepoIssues($owner: String!, $name: String!) {
          repository(owner: $owner, name: $name) {
            issues(first: 30, states: OPEN, orderBy: {field: UPDATED_AT, direction: DESC}) {
              totalCount
              nodes {
                number
                title
                url
                updatedAt
                author { login }
                comments { totalCount }
              }
            }
          }
        }
        """)
    }

    func testPullsDocument() {
        XCTAssertEqual(RepoListGraphQL.pulls, """
        query RepoPulls($owner: String!, $name: String!) {
          repository(owner: $owner, name: $name) {
            pullRequests(first: 30, states: OPEN, orderBy: {field: UPDATED_AT, direction: DESC}) {
              totalCount
              nodes {
                number
                title
                url
                updatedAt
                isDraft
                author { login }
                headRefName
                baseRefName
              }
            }
          }
        }
        """)
    }

    func testReleasesDocument() {
        XCTAssertEqual(RepoListGraphQL.releases, """
        query RepoReleases($owner: String!, $name: String!) {
          repository(owner: $owner, name: $name) {
            releases(first: 20, orderBy: {field: CREATED_AT, direction: DESC}) {
              totalCount
              nodes {
                name
                tagName
                url
                publishedAt
                createdAt
                isPrerelease
                author { login }
              }
            }
          }
        }
        """)
    }

    func testRunsDocument() {
        XCTAssertEqual(RepoListGraphQL.runs, """
        query RepoRuns($owner: String!, $name: String!) {
          repository(owner: $owner, name: $name) {
            defaultBranchRef {
              name
              target {
                ... on Commit {
                  history(first: 10) {
                    nodes {
                      checkSuites(first: 6) {
                        nodes {
                          status
                          conclusion
                          updatedAt
                          workflowRun { runNumber url event workflow { name } }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        """)
    }

    func testBranchesDocument() {
        XCTAssertEqual(RepoListGraphQL.branches, """
        query RepoBranches($owner: String!, $name: String!) {
          repository(owner: $owner, name: $name) {
            url
            defaultBranchRef { name }
            refs(refPrefix: "refs/heads/", first: 50, orderBy: {field: ALPHABETICAL, direction: ASC}) {
              totalCount
              nodes {
                name
                target { ... on Commit { committedDate } }
              }
            }
          }
        }
        """)
    }

    func testReviewRequestsDocument() {
        XCTAssertEqual(RepoListGraphQL.reviewRequests, """
        query ReviewRequests {
          search(query: "is:open is:pr review-requested:@me archived:false", type: ISSUE, first: 20) {
            issueCount
            nodes {
              ... on PullRequest {
                number
                title
                url
                updatedAt
                isDraft
                author { login }
                repository { nameWithOwner }
              }
            }
          }
        }
        """)
    }

    func testEachKindHasItsOwnDocument() {
        XCTAssertEqual(
            RepoListKind.allCases.map { RepoListGraphQL.document(for: $0) },
            [RepoListGraphQL.issues, RepoListGraphQL.pulls, RepoListGraphQL.releases, RepoListGraphQL.runs, RepoListGraphQL.branches]
        )
    }

    // MARK: Decoding

    private func page(_ kind: RepoListKind, _ json: String) throws -> RepoListPage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let wire = try decoder.decode(RepoListWire.self, from: Data(json.utf8))
        return try XCTUnwrap(wire.page(for: kind, now: self.now))
    }

    func testIssuesDecodeToExactRows() throws {
        let page = try self.page(.issues, """
        {"data":{"repository":{"issues":{"totalCount":112,"nodes":[
          {"number":7,"title":"Panel flickers","url":"https://github.com/o/r/issues/7","updatedAt":"2026-11-11T09:00:00Z",
           "author":{"login":"ana"},"comments":{"totalCount":3}},
          {"number":4,"title":"Ghost author","url":"https://github.com/o/r/issues/4","updatedAt":"2026-11-08T12:00:00Z",
           "author":null,"comments":{"totalCount":1}},
          null
        ]}}}}
        """)
        XCTAssertEqual(page.rows, [
            RepoListRow(id: "issue:7", title: "Panel flickers", subtitle: "#7 · @ana · 3h · 3 comments",
                        url: URL(string: "https://github.com/o/r/issues/7"), mark: .issue),
            RepoListRow(id: "issue:4", title: "Ghost author", subtitle: "#4 · 3d · 1 comment",
                        url: URL(string: "https://github.com/o/r/issues/4"), mark: .issue)
        ])
        XCTAssertEqual(page.total, 112)
        XCTAssertEqual(page.truncationNote, "Showing 2 of 112 · open on GitHub for the rest")
    }

    func testPullsCarryTheirNumberForThePane() throws {
        let page = try self.page(.pulls, """
        {"data":{"repository":{"pullRequests":{"totalCount":2,"nodes":[
          {"number":22,"title":"Add lists","url":"https://github.com/o/r/pull/22","updatedAt":"2026-11-11T11:30:00Z",
           "isDraft":false,"author":{"login":"ana"},"headRefName":"feat/lists","baseRefName":"main"},
          {"number":21,"title":"WIP","url":"https://github.com/o/r/pull/21","updatedAt":"2026-10-20T12:00:00Z",
           "isDraft":true,"author":{"login":"bo"},"headRefName":"wip","baseRefName":"main"}
        ]}}}}
        """)
        XCTAssertEqual(page.rows, [
            RepoListRow(id: "pull:22", title: "Add lists", subtitle: "#22 · @ana · 30m · feat/lists → main", pullNumber: 22,
                        url: URL(string: "https://github.com/o/r/pull/22"), mark: .pull),
            RepoListRow(id: "pull:21", title: "WIP", subtitle: "#21 · @bo · draft · 3w · wip → main", pullNumber: 21,
                        url: URL(string: "https://github.com/o/r/pull/21"), mark: .draftPull)
        ])
        XCTAssertNil(page.truncationNote)
    }

    func testReleasesUseTheTagWhenTheNameIsEmpty() throws {
        let page = try self.page(.releases, """
        {"data":{"repository":{"releases":{"totalCount":2,"nodes":[
          {"name":"Harbor 0.2.1","tagName":"v0.2.1","url":"https://github.com/o/r/releases/tag/v0.2.1",
           "publishedAt":"2026-11-07T12:00:00Z","createdAt":"2026-11-07T11:00:00Z","isPrerelease":false,"author":{"login":"ana"}},
          {"name":"","tagName":"v0.3.0-rc1","url":"https://github.com/o/r/releases/tag/v0.3.0-rc1",
           "publishedAt":null,"createdAt":"2026-11-11T10:00:00Z","isPrerelease":true,"author":null}
        ]}}}}
        """)
        XCTAssertEqual(page.rows.map(\.title), ["Harbor 0.2.1", "v0.3.0-rc1"])
        XCTAssertEqual(page.rows.map(\.subtitle), ["v0.2.1 · @ana · 4d", "v0.3.0-rc1 · 2h · pre-release"])
        XCTAssertEqual(page.rows.map(\.mark), [.release, .prerelease])
    }

    func testRunsKeepOnlyWorkflowRunsNewestFirstAndDeduplicated() throws {
        let page = try self.page(.runs, """
        {"data":{"repository":{"defaultBranchRef":{"name":"main","target":{"history":{"nodes":[
          {"checkSuites":{"nodes":[
            {"status":"QUEUED","conclusion":null,"updatedAt":"2026-11-11T11:00:00Z","workflowRun":null},
            {"status":"COMPLETED","conclusion":"FAILURE","updatedAt":"2026-11-11T11:10:00Z",
             "workflowRun":{"runNumber":76,"url":"https://github.com/o/r/actions/runs/76","event":"push","workflow":{"name":"CI"}}}
          ]}},
          {"checkSuites":{"nodes":[
            {"status":"COMPLETED","conclusion":"SUCCESS","updatedAt":"2026-11-10T11:00:00Z",
             "workflowRun":{"runNumber":74,"url":"https://github.com/o/r/actions/runs/74","event":"pull_request","workflow":{"name":"Docs"}}},
            {"status":"IN_PROGRESS","conclusion":null,"updatedAt":"2026-11-11T11:50:00Z",
             "workflowRun":{"runNumber":77,"url":"https://github.com/o/r/actions/runs/77","event":"push","workflow":{"name":"Release"}}},
            {"status":"COMPLETED","conclusion":"FAILURE","updatedAt":"2026-11-11T11:10:00Z",
             "workflowRun":{"runNumber":76,"url":"https://github.com/o/r/actions/runs/76","event":"push","workflow":{"name":"CI"}}}
          ]}}
        ]}}}}}}
        """)
        XCTAssertEqual(page.rows, [
            RepoListRow(id: "run:77", title: "Release", subtitle: "#77 · push · main · 10m · running",
                        url: URL(string: "https://github.com/o/r/actions/runs/77"), mark: .run(.pending)),
            RepoListRow(id: "run:76", title: "CI", subtitle: "#76 · push · main · 50m · failed",
                        url: URL(string: "https://github.com/o/r/actions/runs/76"), mark: .run(.failing)),
            RepoListRow(id: "run:74", title: "Docs", subtitle: "#74 · pull_request · main · 1d · passed",
                        url: URL(string: "https://github.com/o/r/actions/runs/74"), mark: .run(.passing))
        ])
    }

    func testRunConclusionsMapToCIStatus() {
        struct Case {
            let status: String
            let conclusion: String?
            let expected: CIStatus
            let words: String
        }
        let cases = [
            Case(status: "COMPLETED", conclusion: "SUCCESS", expected: .passing, words: "passed"),
            Case(status: "COMPLETED", conclusion: "FAILURE", expected: .failing, words: "failed"),
            Case(status: "COMPLETED", conclusion: "TIMED_OUT", expected: .failing, words: "timed out"),
            Case(status: "COMPLETED", conclusion: "CANCELLED", expected: .unknown, words: "cancelled"),
            Case(status: "COMPLETED", conclusion: "SKIPPED", expected: .unknown, words: "skipped"),
            Case(status: "QUEUED", conclusion: nil, expected: .pending, words: "queued"),
            Case(status: "IN_PROGRESS", conclusion: nil, expected: .pending, words: "running")
        ]
        for item in cases {
            let label = "\(item.status) \(item.conclusion ?? "nil")"
            XCTAssertEqual(RepoListWire.ciStatus(status: item.status, conclusion: item.conclusion), item.expected, label)
            XCTAssertEqual(RepoListWire.outcome(status: item.status, conclusion: item.conclusion), item.words, label)
        }
    }

    func testBranchesPutTheDefaultFirstThenNewestAndEncodeTheURL() throws {
        let page = try self.page(.branches, """
        {"data":{"repository":{"url":"https://github.com/o/r","defaultBranchRef":{"name":"main"},
          "refs":{"totalCount":3,"nodes":[
            {"name":"feat/a b","target":{"committedDate":"2026-11-01T12:00:00Z"}},
            {"name":"main","target":{"committedDate":"2026-11-11T11:00:00Z"}},
            {"name":"fix","target":{"committedDate":"2026-11-10T12:00:00Z"}}
          ]}}}}
        """)
        XCTAssertEqual(page.rows, [
            RepoListRow(id: "branch:main", title: "main", subtitle: "default · updated 1h",
                        url: URL(string: "https://github.com/o/r/tree/main"), mark: .defaultBranch),
            RepoListRow(id: "branch:fix", title: "fix", subtitle: "updated 1d",
                        url: URL(string: "https://github.com/o/r/tree/fix"), mark: .branch),
            RepoListRow(id: "branch:feat/a b", title: "feat/a b", subtitle: "updated 10d",
                        url: URL(string: "https://github.com/o/r/tree/feat/a%20b"), mark: .branch)
        ])
    }

    func testAMissingRepositoryIsNotAnEmptyList() throws {
        let decoder = JSONDecoder()
        let wire = try decoder.decode(RepoListWire.self, from: Data(#"{"data":{"repository":null}}"#.utf8))
        XCTAssertNil(wire.page(for: .issues, now: self.now))
    }

    func testAgeWording() {
        let cases: [(TimeInterval, String)] = [
            (5, "now"), (59 * 60, "59m"), (3 * 3600, "3h"), (13 * 86400, "13d"), (14 * 86400, "2w"), (400 * 86400, "1y")
        ]
        for (seconds, expected) in cases {
            XCTAssertEqual(RepoListText.age(self.now.addingTimeInterval(-seconds), now: self.now), expected)
        }
        XCTAssertNil(RepoListText.age(nil, now: self.now))
    }

    // MARK: Review requests

    func testReviewRequestsMapAndDropNonPullNodes() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let wire = try decoder.decode(ReviewRequestsWire.self, from: Data("""
        {"data":{"search":{"nodes":[
          {"number":91,"title":"Bump hono","url":"https://github.com/o/kosha/pull/91","updatedAt":"2026-11-10T12:00:00Z",
           "isDraft":false,"author":{"login":"dependabot"},"repository":{"nameWithOwner":"o/kosha"}},
          {},
          null,
          {"number":5,"title":"Ghost PR","url":null,"updatedAt":"2026-11-11T11:55:00Z",
           "isDraft":true,"author":null,"repository":{"nameWithOwner":"o/harbor"}}
        ]}}}
        """.utf8))
        let requests = wire.requests()
        XCTAssertEqual(requests, [
            ReviewRequest(repoFullName: "o/kosha", number: 91, title: "Bump hono",
                          url: URL(string: "https://github.com/o/kosha/pull/91"), authorLogin: "dependabot",
                          isDraft: false, updatedAt: self.now.addingTimeInterval(-86400)),
            ReviewRequest(repoFullName: "o/harbor", number: 5, title: "Ghost PR", url: nil, authorLogin: nil,
                          isDraft: true, updatedAt: self.now.addingTimeInterval(-300))
        ])
        XCTAssertEqual(requests.map { $0.detailLine(now: self.now) }, ["o/kosha #91 · @dependabot · 1d", "o/harbor #5 · draft · 5m"])
        XCTAssertEqual(requests.map(\.id), ["o/kosha#91", "o/harbor#5"])
    }
}
