import Foundation
@testable import Harbor
@testable import HarborCore
import Testing

/// The panel's first-run welcome and what VoiceOver says for its rows and lamps.
@MainActor
struct FirstRunAndAccessibilityTests {
    // MARK: First run

    @Test
    func firstRun_showsOnlyWhenNothingIsSetUpAndNotDismissed() {
        func visible(_ dismissed: Bool, _ signedIn: Bool, _ folders: Bool) -> Bool {
            FirstRun.isVisible(dismissed: dismissed, signedIn: signedIn, hasProjectFolders: folders)
        }
        #expect(visible(false, false, false) == true)
        #expect(visible(false, true, false) == false)
        #expect(visible(false, false, true) == false)
        #expect(visible(false, true, true) == false)
        #expect(visible(true, false, false) == false)
        #expect(visible(true, true, true) == false)
    }

    @Test
    func firstRunFlag_isFalseInSettingsSavedBeforeItExisted() throws {
        let empty = try JSONDecoder().decode(UserSettings.self, from: Data("{}".utf8))
        #expect(empty.firstRunDismissed == false)
        let older = try JSONDecoder().decode(UserSettings.self, from: Data(#"{"launchAtLogin":true,"loopbackPort":4000}"#.utf8))
        #expect(older.firstRunDismissed == false)
        #expect(older.launchAtLogin == true)
        #expect(older.loopbackPort == 4000)
    }

    @Test
    func firstRunFlag_survivesASaveAndLoad() throws {
        var settings = UserSettings()
        settings.firstRunDismissed = true
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(UserSettings.self, from: data).firstRunDismissed == true)
        #expect((String(data: data, encoding: .utf8) ?? "").contains("\"firstRunDismissed\":true"))
    }

    // MARK: Lamps as text

    @Test
    func glyphKinds_haveExactSpokenStates() {
        #expect(StatusGlyph.Kind.pass.spokenState == "passing")
        #expect(StatusGlyph.Kind.fail.spokenState == "failing")
        #expect(StatusGlyph.Kind.pending.spokenState == "pending")
        #expect(StatusGlyph.Kind.none.spokenState == "not checked")
        #expect(StatusGlyph.Kind.review.spokenState == "review requested")
        #expect(StatusGlyph.Kind.behind.spokenState == "behind upstream")
    }

    @Test
    func menuBarLamp_saysItsStateIncludingTheHollowRing() {
        #expect(StatusItemBadge.signedOut.accessibilityText == "Harbor, signed out")
        #expect(StatusItemBadge.calm.accessibilityText == "Harbor, all clear")
        #expect(StatusItemBadge.needsYou(1).accessibilityText == "Harbor, 1 item needs you")
        #expect(StatusItemBadge.needsYou(3).accessibilityText == "Harbor, 3 items need you")
        #expect(StatusItemBadge.unchecked.accessibilityText == "Harbor, some repositories could not be checked")
    }

    @Test
    func noticeKinds_sayHowSeriousTheyAre() {
        #expect(PanelNotice.spokenKind(.fail) == "Error")
        #expect(PanelNotice.spokenKind(.pending) == "Warning")
        #expect(PanelNotice.spokenKind(.pass) == "OK")
    }

    // MARK: Rows as one element

    private func model(_ name: String, ci: CIStatus) -> RepositoryDisplayModel {
        let repo = Repository(
            id: name, name: name, owner: "o", sortOrder: nil, error: nil, rateLimitedUntil: nil, ciStatus: ci,
            openIssues: 1, openPulls: 2, latestRelease: nil, latestActivity: nil, traffic: nil, heatmap: [],
            pullCountsKnown: true
        )
        return RepositoryDisplayModel(repo: repo)
    }

    @Test
    func repoRow_readsNameCIStateAndCountsInOneLabel() {
        #expect(CompactRepoRow.spokenLabel(repo: self.model("harbor", ci: .failing), isPinned: false)
            == "harbor, CI failing, 2 pull requests, 1 issue")
        #expect(CompactRepoRow.spokenLabel(repo: self.model("harbor", ci: .unknown), isPinned: true)
            == "harbor, CI not checked, pinned, 2 pull requests, 1 issue")
    }

    @Test
    func needsYouRow_startsWithTheStateTheLampDraws() {
        #expect(NeedsYouRow.spokenLabel(kind: .review, title: "o/a #7", detail: "Fix the thing", age: "2d")
            == "review requested: o/a #7, Fix the thing, 2d")
        #expect(NeedsYouRow.spokenLabel(kind: .fail, title: "o/a", detail: "CI failing", age: nil) == "failing: o/a, CI failing")
    }

    @Test
    func towerRow_readsGlyphsAsWords() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let row = TowerRow(
            repoPath: "/r", repoName: "harbor", path: "/r/w", branch: "feat/x", agent: "claude", task: nil, note: "adding tests",
            evidence: nil, build: nil, delivered: nil, advice: nil, isLocked: false, isPrunable: false, ahead: 2, behind: 1,
            dirty: 3, forecast: nil, collisions: ["a.swift"], lastActivity: now.addingTimeInterval(-300), timeline: [],
            lane: .working, reason: "agent inside"
        )
        #expect(TowerRowLine.spokenLabel(row, now: now)
            == "claude, harbor, feat/x, agent inside, adding tests, 2 ahead, 1 behind main, 3 uncommitted, 1 files shared with another worktree, 5 minutes ago")
        #expect(TowerFormat.spokenAge(now.addingTimeInterval(-10), now: now) == "active now")
        #expect(TowerFormat.spokenAge(now.addingTimeInterval(-3600), now: now) == "1 hour ago")
        #expect(TowerFormat.spokenAge(nil, now: now) == nil)
    }
}
