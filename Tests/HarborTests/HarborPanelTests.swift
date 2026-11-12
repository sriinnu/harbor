import Foundation
@testable import Harbor
import HarborCore
import Testing

@MainActor
struct HarborPanelTests {
    private func display(local: LocalRepoStatus?) -> RepositoryDisplayModel {
        let repo = Repository(
            id: "1", name: "harbor", owner: "me", sortOrder: 0, error: nil, rateLimitedUntil: nil, ciStatus: .passing,
            openIssues: 0, openPulls: 0, latestRelease: nil, latestActivity: nil, activityEvents: [], traffic: nil, heatmap: []
        )
        return RepositoryDisplayModel(repo: repo, localStatus: local)
    }

    private func local(clean: Bool, ahead: Int?, behind: Int?) -> LocalRepoStatus {
        LocalRepoStatus(
            path: URL(fileURLWithPath: "/tmp/harbor"), name: "harbor", fullName: "me/harbor", branch: "main", isClean: clean,
            aheadCount: ahead, behindCount: behind, syncState: .behind, upstreamBranch: "origin/main"
        )
    }

    @Test
    func behindCloneBecomesANeedsYouRow() {
        var content = HarborPanelContent()
        content.repos = [self.display(local: self.local(clean: true, ahead: 0, behind: 2))]
        let needs = content.needsYou
        #expect(needs.count == 1)
        #expect(needs.first?.kind == .behind)
        #expect(needs.first?.title == "harbor · local")
        #expect(needs.first?.detail == "main is 2 behind origin/main · clean, safe to fast-forward")
    }

    @Test
    func cloneThatIsCurrentOrUnknownIsNotWaiting() {
        var content = HarborPanelContent()
        content.repos = [
            self.display(local: self.local(clean: true, ahead: 0, behind: 0)),
            self.display(local: self.local(clean: true, ahead: nil, behind: nil)),
            self.display(local: nil)
        ]
        #expect(content.needsYou.isEmpty)
    }

    @Test
    func dirtyBehindCloneIsNotCalledSafe() {
        let line = HarborPanelContent.behindDetail(self.local(clean: false, ahead: 0, behind: 3), behind: 3)
        #expect(line == "main is 3 behind origin/main · local changes")
    }

    @Test
    func everyThemeHasAPanelInEachAppearance() {
        for id in HarborThemeID.allCases {
            #expect(HarborPanelSkin.forTheme(id, isDark: false) != nil)
            #expect(HarborPanelSkin.forTheme(id, isDark: true) != nil)
        }
        #expect(HarborPanelSkin.forTheme(.flags, isDark: false) != HarborPanelSkin.forTheme(.flags, isDark: true))
        #expect(HarborPanelSkin.forTheme(.native, isDark: false)?.colorScheme == .light)
        #expect(HarborPanelSkin.forTheme(.native, isDark: true)?.colorScheme == .dark)
    }

    @Test
    func arrowKeysMoveAndClampAndReturnActivates() {
        let navigator = PanelNavigator()
        var opened: [String] = []
        navigator.update(["a", "b", "c"].map { id in PanelNavItem(id: id, drillsIn: id == "b", perform: { opened.append(id) }) })
        #expect(navigator.selected == nil)
        #expect(navigator.handle(keyCode: 125))
        #expect(navigator.selected == "a")
        _ = navigator.handle(keyCode: 125)
        _ = navigator.handle(keyCode: 125)
        _ = navigator.handle(keyCode: 125)
        #expect(navigator.selected == "c")
        _ = navigator.handle(keyCode: 126)
        #expect(navigator.selected == "b")
        _ = navigator.handle(keyCode: 36)
        _ = navigator.handle(keyCode: 124)
        navigator.move(-1)
        _ = navigator.handle(keyCode: 124)
        #expect(opened == ["b", "b"])
        #expect(navigator.handle(keyCode: 123) == false)
    }
}
