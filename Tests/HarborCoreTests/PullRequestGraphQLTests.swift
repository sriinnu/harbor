import Foundation
@testable import HarborCore
import XCTest

/// The GraphQL documents are pinned exactly: a changed field or argument is a changed
/// request, and should show up here as a failing diff.
final class PullRequestGraphQLTests: XCTestCase {
    func testReadinessDocument() {
        XCTAssertEqual(PullRequestGraphQL.readiness, """
        query PullReadiness($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) {
            squashMergeAllowed
            mergeCommitAllowed
            rebaseMergeAllowed
            pullRequest(number: $number) {
              id
              number
              title
              url
              state
              isDraft
              author { login }
              baseRefName
              headRefName
              headRefOid
              isCrossRepository
              headRef { id }
              mergeable
              mergeStateStatus
              reviewDecision
              viewerCanUpdateBranch
              commits(last: 1) {
                nodes {
                  commit {
                    statusCheckRollup {
                      contexts(first: 50) {
                        totalCount
                        nodes {
                          __typename
                          ... on CheckRun { name status conclusion detailsUrl isRequired(pullRequestNumber: $number) }
                          ... on StatusContext { context state targetUrl isRequired(pullRequestNumber: $number) }
                        }
                      }
                    }
                  }
                }
              }
              reviewThreads(first: 50) {
                totalCount
                nodes {
                  id
                  isResolved
                  isOutdated
                  path
                  line
                  viewerCanResolve
                  comments(first: 1) { nodes { author { login } bodyText url } }
                }
              }
            }
          }
        }
        """)
    }

    func testTotalsComeFromGitHubsCountNotTheFetchedNodes() throws {
        let json = """
        {"data":{"repository":{"squashMergeAllowed":true,"mergeCommitAllowed":false,"rebaseMergeAllowed":false,
        "pullRequest":{"id":"PR_1","number":7,"title":"t","url":null,"state":"OPEN","isDraft":false,"author":null,
        "baseRefName":"main","headRefName":"dev","headRefOid":"abc","isCrossRepository":false,"headRef":{"id":"R"},
        "mergeable":"MERGEABLE","mergeStateStatus":"BLOCKED","reviewDecision":null,"viewerCanUpdateBranch":false,
        "commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"totalCount":73,"nodes":[
        {"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"FAILURE"}]}}}}]},
        "reviewThreads":{"totalCount":61,"nodes":[]}}}}}
        """
        let detail = try XCTUnwrap(JSONDecoder().decode(PullReadinessWire.self, from: Data(json.utf8)).detail())
        XCTAssertEqual(detail.checks.count, 1)
        XCTAssertEqual(detail.checksTotal, 73)
        XCTAssertEqual(detail.threadsTotal, 61)
    }

    func testResolveThreadDocument() {
        XCTAssertEqual(PullRequestGraphQL.resolveThread, """
        mutation ResolveThread($id: ID!) {
          resolveReviewThread(input: { threadId: $id }) { thread { id isResolved } }
        }
        """)
    }

    func testUpdateBranchDocument() {
        XCTAssertEqual(PullRequestGraphQL.updateBranch, """
        mutation UpdateBranch($id: ID!, $oid: GitObjectID!) {
          updatePullRequestBranch(input: { pullRequestId: $id, expectedHeadOid: $oid, updateMethod: MERGE }) {
            pullRequest { id }
          }
        }
        """)
    }

    func testMergeDocument() {
        XCTAssertEqual(PullRequestGraphQL.merge, """
        mutation MergePull($id: ID!, $oid: GitObjectID!, $method: PullRequestMergeMethod!) {
          mergePullRequest(input: { pullRequestId: $id, expectedHeadOid: $oid, mergeMethod: $method }) {
            pullRequest { id state }
          }
        }
        """)
    }

    func testDeleteBranchDocument() {
        XCTAssertEqual(PullRequestGraphQL.deleteBranch, """
        mutation DeleteBranch($id: ID!) {
          deleteRef(input: { refId: $id }) { clientMutationId }
        }
        """)
    }

    func testMutationErrorsKeepGitHubsOwnMessage() {
        let refused = Data(#"{"errors":[{"type":"UNPROCESSABLE","message":"Pull request is not mergeable"}],"data":{"mergePullRequest":null}}"#.utf8)
        XCTAssertEqual(GraphQLFailure.message(in: refused), "Pull request is not mergeable")
        let badToken = Data(#"{"message":"Bad credentials","documentation_url":"https://docs.github.com/graphql"}"#.utf8)
        XCTAssertEqual(GraphQLFailure.message(in: badToken), "Bad credentials")
        XCTAssertNil(GraphQLFailure.message(in: Data(#"{"data":{"resolveReviewThread":{"thread":{"id":"x","isResolved":true}}}}"#.utf8)))
    }

    func testVariablesEncodeAsTheirOwnTypes() throws {
        let data = try JSONEncoder().encode(["owner": GraphQLVariable.string("a"), "number": .int(24), "flag": .bool(true)])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["owner"] as? String, "a")
        XCTAssertEqual(json["number"] as? Int, 24)
        XCTAssertEqual(json["flag"] as? Bool, true)
    }
}
