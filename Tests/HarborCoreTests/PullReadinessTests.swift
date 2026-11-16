import Foundation
@testable import HarborCore
import XCTest

final class PullReadinessTests: XCTestCase {
    private func pull(
        state: PullRequestDetail.State = .open, draft: Bool = false, mergeable: String = "MERGEABLE",
        status: String = "CLEAN", review: String? = nil, canUpdate: Bool = true,
        checks: [PullCheckState] = [], unresolved: Int = 0
    ) -> PullRequestDetail {
        PullRequestDetail(
            id: "PR_1", number: 24, title: "feat/needs you", url: nil, state: state, isDraft: draft,
            authorLogin: "sriinnu", baseRef: "main", headRef: "feat/needs-you", headOid: "abc",
            isCrossRepository: false, headRefID: "REF_1", mergeable: mergeable, mergeStateStatus: status,
            reviewDecision: review, viewerCanUpdateBranch: canUpdate,
            checks: checks.enumerated().map { PullCheck(name: "check \($0.offset)", state: $0.element, isRequired: true, url: nil) },
            threads: (0 ..< unresolved).map {
                PullReviewThread(
                    id: "T\($0)", isResolved: false, isOutdated: false, path: "a.swift", line: $0, viewerCanResolve: true,
                    authorLogin: "bot", excerpt: "x", url: nil
                )
            },
            squashMergeAllowed: true, mergeCommitAllowed: false, rebaseMergeAllowed: false
        )
    }

    func testCleanIsReadyToMerge() {
        let r = PullReadiness.evaluate(self.pull(checks: [.passed]))
        XCTAssertEqual(r.headline, "Ready to merge")
        XCTAssertEqual(r.reasons, [])
        XCTAssertEqual(r.kind, .ready)
        XCTAssertTrue(r.canMerge)
        XCTAssertFalse(r.isWaiting)
    }

    func testBehindWithExpectedCheckIsTheMorningsFailure() {
        // GitHub said: conversation must be resolved, required check expected, branch BEHIND.
        let r = PullReadiness.evaluate(self.pull(status: "BEHIND", checks: [.expected], unresolved: 1))
        XCTAssertEqual(r.reasons, ["Branch is behind base", "1 conversation to resolve", "1 check expected"])
        XCTAssertEqual(r.headline, "Branch is behind base")
        XCTAssertFalse(r.canMerge)
        XCTAssertTrue(r.canUpdateBranch)
        XCTAssertTrue(r.isWaiting)
        XCTAssertEqual(r.kind, .blocked)
    }

    func testBlockedByConversations() {
        let r = PullReadiness.evaluate(self.pull(status: "BLOCKED", unresolved: 3))
        XCTAssertEqual(r.reasons, ["3 conversations to resolve"])
        XCTAssertEqual(r.headline, "3 conversations to resolve")
        XCTAssertFalse(r.canMerge)
        XCTAssertFalse(r.canUpdateBranch)
        XCTAssertFalse(r.isWaiting)
    }

    func testChecksFailingRunningExpected() {
        let r = PullReadiness.evaluate(self.pull(status: "BLOCKED", checks: [.failed, .failed, .pending, .expected, .passed]))
        XCTAssertEqual(r.reasons, ["2 checks failing", "1 check running", "1 check expected"])
    }

    func testOnlyRunningChecksIsWaiting() {
        let r = PullReadiness.evaluate(self.pull(status: "BLOCKED", checks: [.pending]))
        XCTAssertEqual(r.kind, .waiting)
        XCTAssertEqual(r.reasons, ["1 check running"])
        XCTAssertTrue(r.isWaiting)
    }

    func testReviewDecisions() {
        XCTAssertEqual(PullReadiness.evaluate(self.pull(status: "BLOCKED", review: "REVIEW_REQUIRED")).reasons, ["Review required"])
        XCTAssertEqual(PullReadiness.evaluate(self.pull(status: "BLOCKED", review: "CHANGES_REQUESTED")).reasons, ["Changes requested"])
    }

    func testConflictsDraftAndUnknown() {
        XCTAssertEqual(
            PullReadiness.evaluate(self.pull(mergeable: "CONFLICTING", status: "DIRTY")).reasons,
            ["Merge conflicts to resolve"]
        )
        let draft = PullReadiness.evaluate(self.pull(draft: true, status: "DRAFT"))
        XCTAssertEqual(draft.reasons, ["Draft pull request"])
        XCTAssertFalse(draft.canMerge)
        let unknown = PullReadiness.evaluate(self.pull(mergeable: "UNKNOWN", status: "UNKNOWN"))
        XCTAssertEqual(unknown.reasons, ["GitHub is still working out mergeability"])
        XCTAssertEqual(unknown.kind, .waiting)
        XCTAssertTrue(unknown.isWaiting)
    }

    func testBlockedWithNoVisibleCause() {
        XCTAssertEqual(PullReadiness.evaluate(self.pull(status: "BLOCKED")).reasons, ["Blocked by branch protection"])
    }

    func testUnstableStillMerges() {
        let r = PullReadiness.evaluate(self.pull(status: "UNSTABLE", checks: [.failed]))
        XCTAssertEqual(r.headline, "Ready to merge (a check that isn't required is failing or still running)")
        XCTAssertTrue(r.canMerge)
    }

    func testUnstableWithOnlyPendingChecksUsesTheSameWording() {
        let r = PullReadiness.evaluate(self.pull(status: "UNSTABLE", checks: [.pending]))
        XCTAssertEqual(r.headline, "Ready to merge (a check that isn't required is failing or still running)")
    }

    func testCountsPastTheFetchedFiftyAreLowerBounds() {
        let base = self.pull(status: "BLOCKED", checks: Array(repeating: .failed, count: 50), unresolved: 50)
        XCTAssertEqual(base.checksTotal, 50)
        let truncated = PullRequestDetail(
            id: base.id, number: base.number, title: base.title, url: nil, state: .open, isDraft: false,
            authorLogin: nil, baseRef: "main", headRef: "x", headOid: "abc", isCrossRepository: false,
            headRefID: nil, mergeable: "MERGEABLE", mergeStateStatus: "BLOCKED", reviewDecision: nil,
            viewerCanUpdateBranch: false, checks: base.checks, threads: base.threads,
            squashMergeAllowed: true, mergeCommitAllowed: false, rebaseMergeAllowed: false,
            checksTotal: 73, threadsTotal: 61
        )
        XCTAssertEqual(truncated.checksTotal, 73)
        XCTAssertEqual(truncated.threadsTotal, 61)
        XCTAssertEqual(PullReadiness.evaluate(truncated).reasons, ["50+ conversations to resolve", "50+ checks failing"])
    }

    func testMergeConfirmationNamesTheBranchOnlyWhenItWillBeDeleted() {
        let pull = self.pull()
        XCTAssertEqual(pull.mergeConfirmation(method: .squash, deleteBranch: false), "Squash and merge #24 into main?")
        XCTAssertEqual(
            pull.mergeConfirmation(method: .squash, deleteBranch: true),
            "Squash and merge #24 into main and delete branch feat/needs-you?"
        )
    }

    func testBehindWithoutPermissionCannotUpdate() {
        XCTAssertFalse(PullReadiness.evaluate(self.pull(status: "BEHIND", canUpdate: false)).canUpdateBranch)
    }

    func testMergedAndClosedAreFinished() {
        let merged = PullReadiness.evaluate(self.pull(state: .merged, status: "UNKNOWN"))
        XCTAssertEqual(merged.headline, "Merged")
        XCTAssertEqual(merged.kind, .finished)
        XCTAssertFalse(merged.canMerge)
        XCTAssertFalse(merged.isWaiting)
        XCTAssertEqual(PullReadiness.evaluate(self.pull(state: .closed)).headline, "Closed without merging")
    }

    func testAllowedMethodsFollowTheRepoAndDefaultToSquash() {
        let detail = self.pull()
        XCTAssertEqual(detail.allowedMergeMethods, [.squash])
        XCTAssertEqual(detail.defaultMergeMethod, .squash)
    }

    func testExcerptIsOneShortLine() {
        XCTAssertEqual(PullReviewThread.excerpt(from: "first line\n\n  second   line  "), "first line second line")
        XCTAssertEqual(PullReviewThread.excerpt(from: String(repeating: "a", count: 10), limit: 4), "aaaa…")
    }
}

final class PullReadinessDecodingTests: XCTestCase {
    /// The shape GitHub returned for sriinnu/harbor #24, with a pending check, a commit
    /// status that is expected, and one open conversation added.
    private let json = #"""
    {"data":{"repository":{"squashMergeAllowed":true,"mergeCommitAllowed":false,"rebaseMergeAllowed":false,
    "pullRequest":{"id":"PR_kwDOQylNX88AAAABOCxiHA","number":24,"title":"feat/needs you","url":"https://github.com/sriinnu/harbor/pull/24",
    "state":"OPEN","isDraft":false,"author":{"login":"sriinnu"},"baseRefName":"main","headRefName":"feat/needs-you",
    "headRefOid":"f1f85b6","isCrossRepository":false,"headRef":{"id":"REF_1"},"mergeable":"MERGEABLE","mergeStateStatus":"BEHIND",
    "reviewDecision":null,"viewerCanUpdateBranch":true,
    "commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[
      {"__typename":"CheckRun","name":"macOS (Xcode 26.1)","status":"IN_PROGRESS","conclusion":null,"detailsUrl":"https://github.com/x/y/runs/1","isRequired":true},
      {"__typename":"CheckRun","name":"lint","status":"COMPLETED","conclusion":"FAILURE","detailsUrl":null,"isRequired":false},
      {"__typename":"StatusContext","context":"ci/legacy","state":"EXPECTED","targetUrl":null,"isRequired":true}
    ]}}}}]},
    "reviewThreads":{"nodes":[
      {"id":"PRRT_1","isResolved":false,"isOutdated":false,"path":"Sources/A.swift","line":176,"viewerCanResolve":true,
       "comments":{"nodes":[{"author":{"login":"copilot"},"bodyText":"This won't compile.\nAwait the values.","url":"https://github.com/sriinnu/harbor/pull/24#discussion_r1"}]}},
      {"id":"PRRT_2","isResolved":true,"isOutdated":true,"path":null,"line":null,"viewerCanResolve":false,"comments":{"nodes":[]}}
    ]}}}}}
    """#

    func testDecodesTheRealShape() throws {
        let wire = try JSONDecoder().decode(PullReadinessWire.self, from: Data(self.json.utf8))
        let detail = try XCTUnwrap(wire.detail())
        XCTAssertEqual(detail.number, 24)
        XCTAssertEqual(detail.headRefID, "REF_1")
        XCTAssertEqual(detail.checks.map(\.state), [.pending, .failed, .expected])
        XCTAssertEqual(detail.checks.map(\.isRequired), [true, false, true])
        XCTAssertEqual(detail.checks.map(\.name), ["macOS (Xcode 26.1)", "lint", "ci/legacy"])
        XCTAssertEqual(detail.threads.count, 2)
        XCTAssertEqual(detail.unresolvedThreads.map(\.id), ["PRRT_1"])
        let thread = detail.threads[0]
        XCTAssertEqual(thread.authorLogin, "copilot")
        XCTAssertEqual(thread.excerpt, "This won't compile. Await the values.")
        XCTAssertEqual(thread.url?.absoluteString, "https://github.com/sriinnu/harbor/pull/24#discussion_r1")
        XCTAssertEqual(detail.threads[1].path, nil)
        XCTAssertEqual(
            PullReadiness.evaluate(detail).reasons,
            ["Branch is behind base", "1 conversation to resolve", "1 check failing", "1 check running", "1 check expected"]
        )
    }

    func testMissingPullRequestDecodesToNil() throws {
        let body = #"{"data":{"repository":{"squashMergeAllowed":true,"mergeCommitAllowed":true,"rebaseMergeAllowed":true,"pullRequest":null}}}"#
        XCTAssertNil(try JSONDecoder().decode(PullReadinessWire.self, from: Data(body.utf8)).detail())
    }
}
