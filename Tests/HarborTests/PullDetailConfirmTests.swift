import Foundation
@testable import Harbor
@testable import HarborCore
import Testing

@MainActor
struct PullDetailConfirmTests {
    private func pull(head: String = "abc", status: String = "CLEAN", review: String? = nil) -> PullRequestDetail {
        PullRequestDetail(
            id: "PR_1", number: 12, title: "t", url: nil, state: .open, isDraft: false, authorLogin: nil,
            baseRef: "main", headRef: "develop", headOid: head, isCrossRepository: false, headRefID: "REF",
            mergeable: "MERGEABLE", mergeStateStatus: status, reviewDecision: review, viewerCanUpdateBranch: true,
            checks: [], threads: [], squashMergeAllowed: true, mergeCommitAllowed: false, rebaseMergeAllowed: false
        )
    }

    private func model(showing detail: PullRequestDetail) -> PullDetailModel {
        let model = PullDetailModel(owner: "o", name: "r", number: 12)
        model.apply(detail)
        return model
    }

    @Test
    func aPollThatChangesTheHeadCancelsTheMergeConfirm() {
        let model = self.model(showing: self.pull())
        model.beginConfirm(.merge)
        #expect(model.confirming == .merge)
        model.apply(self.pull(head: "def"))
        #expect(model.confirming == nil)
        #expect(model.actionError == "The pull request changed. Check it again.")
    }

    @Test
    func aPollThatMakesTheMergeUnavailableCancelsTheConfirm() {
        let model = self.model(showing: self.pull())
        model.beginConfirm(.merge)
        model.apply(self.pull(status: "BLOCKED", review: "CHANGES_REQUESTED"))
        #expect(model.confirming == nil)
        #expect(model.actionError == "The pull request changed. Check it again.")
    }

    @Test
    func aPollThatChangesNothingKeepsTheConfirm() {
        let model = self.model(showing: self.pull())
        model.beginConfirm(.merge)
        model.apply(self.pull())
        #expect(model.confirming == .merge)
        #expect(model.actionError == nil)
    }

    @Test
    func theStaleCheckNeedsTheSameHeadTheSameReadinessAndAnAllowedAction() {
        let shown = self.pull()
        let readiness = PullReadiness.evaluate(shown)
        let snapshot = PullDetailModel.ConfirmSnapshot(headOid: "abc", readiness: readiness)
        #expect(PullDetailModel.confirmStillValid(.merge, snapshot: snapshot, detail: shown, readiness: readiness))
        #expect(!PullDetailModel.confirmStillValid(.merge, snapshot: nil, detail: shown, readiness: readiness))
        #expect(!PullDetailModel.confirmStillValid(nil, snapshot: snapshot, detail: shown, readiness: readiness))
        let blocked = self.pull(status: "BLOCKED")
        let blockedReadiness = PullReadiness.evaluate(blocked)
        let blockedSnapshot = PullDetailModel.ConfirmSnapshot(headOid: "abc", readiness: blockedReadiness)
        #expect(!PullDetailModel.confirmStillValid(.merge, snapshot: blockedSnapshot, detail: blocked, readiness: blockedReadiness))
    }
}
