import Foundation
@testable import HarborCore
import Testing

struct SettingsStoreTests {
    @Test
    func saveAndLoad() throws {
        let suiteName = "harbor.settings.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        #expect(store.load() == UserSettings())

        var settings = UserSettings()
        settings.repoList.displayLimit = 9
        settings.repoList.pinnedRepositories = ["steipete/Harbor", "steipete/clawdis"]
        settings.repoList.hiddenRepositories = ["steipete/agent-scripts"]
        settings.enterpriseHost = URL(string: "https://ghe.example.com")!
        settings.debugPaneEnabled = true

        store.save(settings)
        #expect(store.load() == settings)
    }

    @Test
    func saveAndLoad_persistsLocalProjectsBookmark() throws {
        let suiteName = "harbor.settings.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        var settings = UserSettings()
        settings.localProjects.rootPaths = ["~/Projects"]
        settings.localProjects.rootBookmarks = ["~/Projects": Data([0x01, 0x02, 0x03, 0x04])]

        store.save(settings)
        let loaded = store.load()
        #expect(loaded.localProjects.rootPaths == ["~/Projects"])
        #expect(loaded.localProjects.rootBookmarkList == [Data([0x01, 0x02, 0x03, 0x04])])
    }
}
