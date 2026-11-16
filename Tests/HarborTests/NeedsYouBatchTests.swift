import Foundation
@testable import Harbor
import HarborCore
import Testing

/// One notification per refresh: what entered Needs you through the review search and through the
/// own-pull-requests search is posted together.
@MainActor
struct NeedsYouBatchTests {
    private static let user = UserIdentity(username: "me", host: URL(string: "https://github.com")!)

    private final class Box<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }

    private func review(_ n: Int) -> ReviewRequest {
        ReviewRequest(repoFullName: "o/a", number: n, title: "R\(n)", url: nil, authorLogin: nil, isDraft: false, updatedAt: nil)
    }

    private func pull(_ n: Int, checks: String = "FAILURE") -> MyPullRequest {
        MyPullRequest(
            repoFullName: "o/a", number: n, title: "PR \(n)", headBranch: "b\(n)", isDraft: false,
            reviewDecision: nil, mergeable: "MERGEABLE", checksState: checks
        )
    }

    private struct Setup {
        let state: AppState
        let reviews: Box<[ReviewRequest]>
        let pulls: Box<[MyPullRequest]>
        let posted: Box<[String]>
    }

    /// Both stores past their baseline, with `R1` and `PR 1` already known.
    private func setup() async -> Setup {
        let suite = "harbor.tests.needsyou.\(UUID().uuidString)"
        let state = AppState(platform: MockPlatformServices(), settingsStore: SettingsStore(defaults: UserDefaults(suiteName: suite)!))
        for _ in 0 ..< 200 where state.refreshTask == nil { try? await Task.sleep(for: .milliseconds(5)) }
        await state.refreshTask?.value
        await state.menuRefreshTask?.value
        state.session.account = .loggedIn(Self.user)
        let reviews = Box([self.review(1)])
        let pulls = Box([self.pull(1)])
        state.reviewRequests = ReviewRequestsStore(fetch: { ReviewRequestList(requests: reviews.value, total: nil) })
        state.myPulls = MyPullsStore(fetch: { pulls.value })
        let posted = Box<[String]>([])
        state.postNeedsYouNotification = { posted.value.append($0) }
        await Self.refreshBoth(state)
        #expect(posted.value == []) // baselines
        return Setup(state: state, reviews: reviews, pulls: pulls, posted: posted)
    }

    /// What a refresh does: start both searches, then wait for both.
    private static func refreshBoth(_ state: AppState) async {
        let review = state.searchReviewRequests()
        let mine = state.searchMyPulls()
        await review?.value
        await mine?.value
    }

    @Test
    func aMixedBatchIsOneNotification() async {
        let s = await self.setup()
        s.reviews.value = [self.review(1), self.review(2)]
        s.pulls.value = [self.pull(1), self.pull(2)]
        await Self.refreshBoth(s.state)
        #expect(s.posted.value == ["2 new things need you"])
        await Self.refreshBoth(s.state)
        #expect(s.posted.value == ["2 new things need you"])
    }

    @Test
    func manyFromBothSearchesAreCountedTogether() async {
        let s = await self.setup()
        s.reviews.value = [self.review(1), self.review(2), self.review(3)]
        s.pulls.value = [self.pull(1), self.pull(2), self.pull(3)]
        await Self.refreshBoth(s.state)
        #expect(s.posted.value == ["4 new things need you"])
    }

    @Test
    func aSingleItemKeepsItsOwnLine_whicheverSearchFoundIt() async {
        let s = await self.setup()
        s.reviews.value = [self.review(1), self.review(2)]
        await Self.refreshBoth(s.state)
        #expect(s.posted.value == ["Review requested · o/a #2: R2"])
        s.pulls.value = [self.pull(1), self.pull(2)]
        await Self.refreshBoth(s.state)
        #expect(s.posted.value == ["Review requested · o/a #2: R2", "Checks failing · o/a #2: PR 2"])
    }

    @Test
    func theSettingOffSilencesTheBatch_andTheBaselineStillMoves() async {
        let s = await self.setup()
        s.state.session.settings.notifyNeedsYou = false
        s.reviews.value = [self.review(1), self.review(2)]
        s.pulls.value = [self.pull(1), self.pull(2)]
        await Self.refreshBoth(s.state)
        #expect(s.posted.value == [])
        s.state.session.settings.notifyNeedsYou = true
        await Self.refreshBoth(s.state)
        #expect(s.posted.value == []) // already seen: not news when the setting comes back on
    }

    @Test
    func anAccountChangeDropsAPendingBatchAndBaselinesAgain() async {
        let s = await self.setup()
        s.state.needsYouPending = [NeedsYouWatcher.Item(key: "review:o/a#9", title: "old", detail: "d")]
        s.state.accountSignedIn(Self.user)
        #expect(s.state.needsYouPending.isEmpty)
        s.reviews.value = [self.review(1), self.review(2)]
        s.pulls.value = [self.pull(1), self.pull(2)]
        await Self.refreshBoth(s.state)
        #expect(s.posted.value == []) // the first answer after the change is a baseline
    }

    @Test
    func aFailedSearchDoesNotHoldBackTheOthersBatch() async {
        let s = await self.setup()
        s.state.myPulls = MyPullsStore(fetch: { throw URLError(.notConnectedToInternet) })
        s.reviews.value = [self.review(1), self.review(2)]
        await Self.refreshBoth(s.state)
        #expect(s.posted.value == ["Review requested · o/a #2: R2"])
    }
}
