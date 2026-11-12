import Foundation
@testable import Harbor
@testable import HarborCore
import Testing

/// "My pull requests" in Needs you, and notifications only on a change into it.
@MainActor
struct NeedsYouTests {
    private static let user = UserIdentity(username: "me", host: URL(string: "https://github.com")!)

    private func pull(
        _ number: Int, draft: Bool = false, review: String? = nil, mergeable: String? = "MERGEABLE", checks: String? = "SUCCESS"
    ) -> MyPullRequest {
        MyPullRequest(
            repoFullName: "o/a", number: number, title: "PR \(number)", headBranch: "b\(number)", isDraft: draft,
            reviewDecision: review, mergeable: mergeable, checksState: checks
        )
    }

    // MARK: classification

    @Test
    func reasons_classifyEachCaseExactly() {
        #expect(self.pull(1, review: "CHANGES_REQUESTED").reasons == [.changesRequested])
        #expect(self.pull(2, checks: "FAILURE").reasons == [.checksFailing])
        #expect(self.pull(3, checks: "ERROR").reasons == [.checksFailing])
        #expect(self.pull(4, mergeable: "CONFLICTING").reasons == [.conflict])
        #expect(self.pull(5, review: "APPROVED").reasons == [.readyToMerge])
        #expect(self.pull(6, review: "APPROVED", checks: nil).reasons == [.readyToMerge])
        #expect(self.pull(7, review: "CHANGES_REQUESTED", mergeable: "CONFLICTING", checks: "FAILURE").reasons
            == [.changesRequested, .checksFailing, .conflict])
    }

    @Test
    func reasons_notReadyUnlessApprovedGreenMergeableAndNotDraft() {
        #expect(self.pull(1).reasons == [])
        #expect(self.pull(2, review: "REVIEW_REQUIRED").reasons == [])
        #expect(self.pull(3, review: "APPROVED", checks: "PENDING").reasons == [])
        #expect(self.pull(4, review: "APPROVED", mergeable: "UNKNOWN").reasons == [])
        #expect(self.pull(5, draft: true, review: "APPROVED").reasons == [])
        #expect(self.pull(6, draft: true, checks: "FAILURE").reasons == [.checksFailing])
        #expect(self.pull(7, review: "APPROVED", mergeable: "CONFLICTING").reasons == [.conflict])
    }

    @Test
    func needs_listOnlyPullsWithAReason_withExactRows() {
        let rows = HarborPanelContent.myPullNeeds([self.pull(1), self.pull(2, checks: "FAILURE"), self.pull(3, review: "APPROVED")])
        #expect(rows.map(\.id) == ["mine:o/a#2", "mine:o/a#3"])
        #expect(rows.map(\.detail) == ["o/a #2 · checks failing", "o/a #3 · ready to merge"])
        #expect(rows.map(\.kind) == [.fail, .pass])
        #expect(rows[0].pull == PanelPullTarget(fullName: "o/a", number: 2))
        var content = HarborPanelContent()
        content.myPulls = [self.pull(2, checks: "FAILURE")]
        #expect(content.needsYou.map(\.id) == ["mine:o/a#2"])
    }

    @Test
    func wire_decodesTheSharedQuery() throws {
        let json = """
        {"data":{"search":{"nodes":[
          {"number":9,"title":"T","url":"https://github.com/o/a/pull/9","updatedAt":"2026-11-01T10:00:00Z","isDraft":false,
           "headRefName":"feat","reviewDecision":"CHANGES_REQUESTED","mergeable":"CONFLICTING",
           "repository":{"nameWithOwner":"o/a"},
           "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE"}}}]}},
          {}, null,
          {"number":10,"title":"U","headRefName":"x","reviewDecision":null,"mergeable":"MERGEABLE",
           "repository":{"nameWithOwner":"o/b"},"commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]}}
        ]}}}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let pulls = try decoder.decode(MyPullRequestsWire.self, from: Data(json.utf8)).pulls()
        #expect(pulls.map(\.id) == ["o/a#9", "o/b#10"])
        #expect(pulls[0].reasons == [.changesRequested, .checksFailing, .conflict])
        #expect(pulls[0].headBranch == "feat")
        #expect(pulls[1].checksState == nil)
        #expect(pulls[1].reasons == [])
    }

    // MARK: transitions

    private func item(_ key: String) -> NeedsYouWatcher.Item {
        NeedsYouWatcher.Item(key: key, title: key, detail: "d")
    }

    @Test
    func watcher_baselineIsSilent_newEntryOnce_sameEntryNever_reEntryAgain() {
        var watcher = NeedsYouWatcher()
        #expect(watcher.observe([self.item("a")]) == [])
        #expect(watcher.observe([self.item("a")]) == [])
        #expect(watcher.observe([self.item("a"), self.item("b")]) == [self.item("b")])
        #expect(watcher.observe([self.item("a"), self.item("b")]) == [])
        #expect(watcher.observe([self.item("a")]) == [])
        #expect(watcher.observe([self.item("a"), self.item("b")]) == [self.item("b")])
        watcher.reset()
        #expect(watcher.observe([self.item("a"), self.item("b")]) == [])
    }

    @Test
    func watcher_aNewReasonOnAKnownPullIsNews() {
        var watcher = NeedsYouWatcher()
        _ = watcher.observe(NeedsYouWatcher.items(mine: [self.pull(1, checks: "FAILURE")]))
        let entered = watcher.observe(NeedsYouWatcher.items(mine: [self.pull(1, mergeable: "CONFLICTING", checks: "FAILURE")]))
        #expect(entered.map(\.key) == ["mine:o/a#1:conflict"])
        #expect(NeedsYouWatcher.message(for: entered) == "Merge conflict · o/a #1: PR 1")
    }

    @Test
    func message_oneIsNamed_manyAreCounted_noneIsNil() {
        #expect(NeedsYouWatcher.message(for: []) == nil)
        #expect(NeedsYouWatcher.message(for: [self.item("a"), self.item("b")]) == "2 new things need you")
        let review = ReviewRequest(repoFullName: "o/a", number: 4, title: "Fix", url: nil, authorLogin: nil, isDraft: false, updatedAt: nil)
        #expect(NeedsYouWatcher.message(for: NeedsYouWatcher.items(reviews: [review])) == "Review requested · o/a #4: Fix")
    }

    // MARK: stores and account scope

    private func appState() async -> AppState {
        let state = AppState(platform: MockPlatformServices())
        for _ in 0 ..< 200 where state.refreshTask == nil { try? await Task.sleep(for: .milliseconds(5)) }
        await state.refreshTask?.value
        await state.menuRefreshTask?.value
        return state
    }

    private final class Box<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }

    @Test
    func store_baselineThenEntryNotifiesOnce_accountSwitchBaselinesAgain() async {
        let state = await self.appState()
        state.session.account = .loggedIn(Self.user)
        let answer = Box([self.pull(1, checks: "FAILURE")])
        state.myPulls = MyPullsStore(fetch: { answer.value })
        let posted = Box<[String]>([])
        state.postNeedsYouNotification = { posted.value.append($0) }

        await state.searchMyPulls()?.value // first load: baseline
        #expect(posted.value == [])
        await state.searchMyPulls()?.value // same again
        #expect(posted.value == [])
        answer.value = [self.pull(1, checks: "FAILURE"), self.pull(2, review: "CHANGES_REQUESTED")]
        await state.searchMyPulls()?.value
        #expect(posted.value == ["Changes requested · o/a #2: PR 2"])
        await state.searchMyPulls()?.value
        #expect(posted.value == ["Changes requested · o/a #2: PR 2"])

        state.accountSignedIn(Self.user) // account change: clear, then baseline again
        #expect(state.myPulls.pulls.isEmpty)
        answer.value = [self.pull(3, checks: "FAILURE")]
        await state.searchMyPulls()?.value
        #expect(posted.value.count == 1)
    }

    @Test
    func reviewStore_firstLoadIsSilent_newRequestNotifies_settingOffSilences() async {
        let state = await self.appState()
        state.session.account = .loggedIn(Self.user)
        func request(_ n: Int) -> ReviewRequest {
            ReviewRequest(repoFullName: "o/a", number: n, title: "R\(n)", url: nil, authorLogin: nil, isDraft: false, updatedAt: nil)
        }
        let answer = Box([request(1)])
        state.reviewRequests = ReviewRequestsStore(fetch: { ReviewRequestList(requests: answer.value, total: nil) })
        let posted = Box<[String]>([])
        state.postNeedsYouNotification = { posted.value.append($0) }

        await state.searchReviewRequests()?.value
        #expect(posted.value == [])
        answer.value = [request(1), request(2)]
        await state.searchReviewRequests()?.value
        #expect(posted.value == ["Review requested · o/a #2: R2"])

        state.session.settings.notifyNeedsYou = false
        answer.value = [request(1), request(2), request(3)]
        await state.searchReviewRequests()?.value
        #expect(posted.value.count == 1)
    }

    @Test
    func store_failureKeepsTheBaseline_noNotificationOnRecovery() async {
        let state = await self.appState()
        state.session.account = .loggedIn(Self.user)
        let mode = Box(0)
        state.myPulls = MyPullsStore(fetch: {
            if mode.value == 1 { throw URLError(.notConnectedToInternet) }
            return [self.pull(1, checks: "FAILURE")]
        })
        let posted = Box<[String]>([])
        state.postNeedsYouNotification = { posted.value.append($0) }
        await state.searchMyPulls()?.value
        mode.value = 1
        await state.searchMyPulls()?.value
        #expect(state.myPulls.failure == "No internet connection.")
        mode.value = 0
        await state.searchMyPulls()?.value
        #expect(posted.value == [])
    }

    @Test
    func settings_notifyDefaultsOn_andOldFilesStillLoad() throws {
        #expect(UserSettings().notifyNeedsYou)
        let old = try JSONDecoder().decode(UserSettings.self, from: Data("{}".utf8))
        #expect(old.notifyNeedsYou)
        let off = try JSONDecoder().decode(UserSettings.self, from: Data(#"{"notifyNeedsYou":false}"#.utf8))
        #expect(off.notifyNeedsYou == false)
    }

    @Test
    func badge_countsMyPullsOnceThroughNeedsYou_andTowerSeparately() {
        var content = HarborPanelContent()
        content.hasLoadedRepositories = true
        content.reviewRequestsLoaded = true
        content.myPullsLoaded = true
        content.myPulls = [self.pull(1, checks: "FAILURE"), self.pull(2, mergeable: "CONFLICTING")]
        let account = AccountState.loggedIn(Self.user)
        #expect(StatusItemBadge(account: account, content: content) == .needsYou(2))
        #expect(StatusItemBadge(account: account, content: content, towerNeedsYou: 3) == .needsYou(5))
    }
}
