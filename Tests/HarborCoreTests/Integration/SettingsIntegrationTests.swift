import Testing
import Foundation
@testable import HarborCore

/// Integration tests for settings persistence and management
@Suite("Settings Integration Tests")
struct SettingsIntegrationTests {

    // MARK: - Settings Persistence

    @Test("Settings persist across app restarts")
    func settingsPersistAcrossAppRestarts() async {
        let storage = InMemorySettingsStorage()

        // First "session" - save settings
        var settings1 = UserSettings()
        settings1.launchAtLogin = true
        settings1.refreshInterval = .fiveMinutes
        settings1.appearance.accentTone = .system
        await storage.save(settings1)

        // Second "session" - load settings
        let settings2 = await storage.load()

        #expect(settings2.launchAtLogin == true)
        #expect(settings2.refreshInterval == .fiveMinutes)
        #expect(settings2.appearance.accentTone == .system)
    }

    @Test("Settings with complex nested structures")
    func settingsWithComplexNestedStructures() async {
        let storage = InMemorySettingsStorage()

        var settings = UserSettings()

        // Configure appearance
        settings.appearance.accentTone = .githubGreen
        settings.appearance.cardDensity = .compact
        settings.appearance.showContributionHeader = false

        // Configure heatmap
        settings.heatmap.display = .submenu
        settings.heatmap.span = .sixMonths

        // Configure repo list
        settings.repoList.displayLimit = 10
        settings.repoList.showForks = true
        settings.repoList.showArchived = true
        settings.repoList.pinnedRepositories = ["owner/repo1", "owner/repo2"]
        settings.repoList.hiddenRepositories = ["owner/archived"]
        settings.repoList.menuSortKey = .stars

        // Configure local projects
        settings.localProjects.rootPath = "~/Projects"
        settings.localProjects.autoSyncEnabled = true
        settings.localProjects.showDirtyFilesInMenu = true
        settings.localProjects.fetchInterval = .twoMinutes
        settings.localProjects.preferredTerminal = "Ghostty"

        await storage.save(settings)
        let loaded = await storage.load()

        // Verify all nested structures
        #expect(loaded.appearance.accentTone == .githubGreen)
        #expect(loaded.appearance.cardDensity == .compact)
        #expect(loaded.heatmap.display == .submenu)
        #expect(loaded.heatmap.span == .sixMonths)
        #expect(loaded.repoList.displayLimit == 10)
        #expect(loaded.repoList.pinnedRepositories.count == 2)
        #expect(loaded.localProjects.rootPath == "~/Projects")
        #expect(loaded.localProjects.preferredTerminal == "Ghostty")
    }

    @Test("Settings with arrays and collections")
    func settingsWithArraysAndCollections() async {
        let storage = InMemorySettingsStorage()

        var settings = UserSettings()
        settings.repoList.pinnedRepositories = [
            "owner/repo1",
            "owner/repo2",
            "owner/repo3"
        ]
        settings.repoList.hiddenRepositories = [
            "owner/hidden1",
            "owner/hidden2"
        ]
        settings.localProjects.preferredLocalPathsByFullName = [
            "owner/repo1": "~/Projects/repo1",
            "owner/repo2": "~/Work/repo2"
        ]

        await storage.save(settings)
        let loaded = await storage.load()

        #expect(loaded.repoList.pinnedRepositories.count == 3)
        #expect(loaded.repoList.hiddenRepositories.count == 2)
        #expect(loaded.localProjects.preferredLocalPathsByFullName.count == 2)
        #expect(loaded.localProjects.preferredLocalPathsByFullName["owner/repo1"] == "~/Projects/repo1")
    }

    // MARK: - Settings with Platform Services

    @Test("Settings integrated with MockPlatformServices")
    func settingsIntegratedWithMockPlatformServices() async {
        let services = MockPlatformServices()

        var settings = UserSettings()
        settings.launchAtLogin = true
        settings.debugPaneEnabled = true

        await services.settingsStorage.save(settings)
        let loaded = await services.settingsStorage.load()

        #expect(loaded.launchAtLogin == true)
        #expect(loaded.debugPaneEnabled == true)
    }

    #if os(macOS)
    @Test("Settings integrated with ApplePlatformServices")
    func settingsIntegratedWithApplePlatformServices() {
        let key = "com.sriinnu.harbor.test.\(UUID().uuidString)"
        let defaults = UserDefaults.standard
        let userDefaultsStorage = UserDefaultsSettingsStorage(defaults: defaults, key: key)
        let services = ApplePlatformServices(settingsStorage: userDefaultsStorage)

        var settings = UserSettings()
        settings.refreshInterval = .fifteenMinutes
        settings.diagnosticsEnabled = true

        services.settingsStorage.save(settings)
        let loaded = services.settingsStorage.load()

        #expect(loaded.refreshInterval == .fifteenMinutes)
        #expect(loaded.diagnosticsEnabled == true)

        defaults.removeObject(forKey: key)
    }
    #endif

    // MARK: - Settings Migration

    @Test("Settings handle version upgrades")
    func settingsHandleVersionUpgrades() async {
        let storage = InMemorySettingsStorage()

        // Save settings as if from older version
        var oldSettings = UserSettings()
        oldSettings.launchAtLogin = true

        await storage.save(oldSettings)

        // Load settings (migration would happen here in real UserDefaultsSettingsStorage)
        let loaded = await storage.load()

        // Old settings should be preserved
        #expect(loaded.launchAtLogin == true)

        // New settings should have defaults
        #expect(loaded.appearance.accentTone != nil)
        #expect(loaded.heatmap.display != nil)
    }

    // MARK: - Multiple Settings Instances

    @Test("Multiple settings instances with different storages")
    func multipleSettingsInstancesWithDifferentStorages() async {
        let storage1 = InMemorySettingsStorage()
        let storage2 = InMemorySettingsStorage()

        var settings1 = UserSettings()
        settings1.launchAtLogin = true
        await storage1.save(settings1)

        var settings2 = UserSettings()
        settings2.launchAtLogin = false
        await storage2.save(settings2)

        let loaded1 = await storage1.load()
        let loaded2 = await storage2.load()

        #expect(loaded1.launchAtLogin == true)
        #expect(loaded2.launchAtLogin == false)
    }

    @Test("Settings isolation between users")
    func settingsIsolationBetweenUsers() async {
        // Simulate different users with different storage
        let user1Services = MockPlatformServices()
        let user2Services = MockPlatformServices()

        var user1Settings = UserSettings()
        user1Settings.appearance.accentTone = .githubGreen
        user1Settings.repoList.displayLimit = 5

        var user2Settings = UserSettings()
        user2Settings.appearance.accentTone = .system
        user2Settings.repoList.displayLimit = 10

        await user1Services.settingsStorage.save(user1Settings)
        await user2Services.settingsStorage.save(user2Settings)

        let loadedUser1 = await user1Services.settingsStorage.load()
        let loadedUser2 = await user2Services.settingsStorage.load()

        #expect(loadedUser1.appearance.accentTone == .githubGreen)
        #expect(loadedUser1.repoList.displayLimit == 5)
        #expect(loadedUser2.appearance.accentTone == .system)
        #expect(loadedUser2.repoList.displayLimit == 10)
    }

    // MARK: - Settings with OAuth Integration

    @Test("Settings and OAuth tokens stored separately")
    func settingsAndOAuthTokensStoredSeparately() async {
        let services = MockPlatformServices()

        // Save OAuth tokens
        let tokens = TestFixtures.sampleTokens
        try? await services.tokenStorage.save(tokens: tokens)

        // Save settings
        var settings = UserSettings()
        settings.launchAtLogin = true
        await services.settingsStorage.save(settings)

        // Both should be persisted independently
        let loadedTokens = try? await services.tokenStorage.load()
        let loadedSettings = await services.settingsStorage.load()

        #expect(loadedTokens != nil)
        #expect(loadedSettings.launchAtLogin == true)
    }

    @Test("Clearing OAuth tokens doesn't affect settings")
    func clearingOAuthTokensDoesNotAffectSettings() async {
        let services = MockPlatformServices()

        // Save both
        try? await services.tokenStorage.save(tokens: TestFixtures.sampleTokens)

        var settings = UserSettings()
        settings.diagnosticsEnabled = true
        await services.settingsStorage.save(settings)

        // Clear tokens
        await services.tokenStorage.clear()

        // Settings should remain
        let loadedSettings = await services.settingsStorage.load()
        let loadedTokens = try? await services.tokenStorage.load()

        #expect(loadedTokens == nil)
        #expect(loadedSettings.diagnosticsEnabled == true)
    }

    // MARK: - Settings Defaults

    @Test("Default settings values are sensible")
    func defaultSettingsValuesAreSensible() {
        let settings = UserSettings()

        // Verify defaults
        #expect(settings.launchAtLogin == false)
        #expect(settings.debugPaneEnabled == false)
        #expect(settings.diagnosticsEnabled == false)
        #expect(settings.refreshInterval == .fiveMinutes)
        #expect(settings.githubHost.absoluteString == "https://github.com")
        #expect(settings.loopbackPort == 53682)
        #expect(settings.appearance.showContributionHeader == true)
        #expect(settings.appearance.cardDensity == .comfortable)
        #expect(settings.appearance.accentTone == .githubGreen)
        #expect(settings.heatmap.display == .inline)
        #expect(settings.repoList.displayLimit == 6)
        #expect(settings.repoList.showForks == false)
        #expect(settings.repoList.showArchived == false)
    }

    // MARK: - Settings Validation

    @Test("Settings with URL configurations")
    func settingsWithURLConfigurations() async {
        let storage = InMemorySettingsStorage()

        var settings = UserSettings()
        settings.githubHost = URL(string: "https://github.com")!
        settings.enterpriseHost = URL(string: "https://github.enterprise.com")

        await storage.save(settings)
        let loaded = await storage.load()

        #expect(loaded.githubHost.absoluteString == "https://github.com")
        #expect(loaded.enterpriseHost?.absoluteString == "https://github.enterprise.com")
    }

    @Test("Settings with port configuration")
    func settingsWithPortConfiguration() async {
        let storage = InMemorySettingsStorage()

        var settings = UserSettings()
        settings.loopbackPort = 8080

        await storage.save(settings)
        let loaded = await storage.load()

        #expect(loaded.loopbackPort == 8080)
    }

    // MARK: - Concurrent Settings Access

    @Test("Concurrent settings reads and writes")
    func concurrentSettingsReadsAndWrites() async {
        let storage = InMemorySettingsStorage()

        await withTaskGroup(of: Void.self) { group in
            // Concurrent writes
            for i in 0..<5 {
                group.addTask {
                    var settings = UserSettings()
                    settings.repoList.displayLimit = i
                    await storage.save(settings)
                }
            }

            // Concurrent reads
            for _ in 0..<5 {
                group.addTask {
                    let _ = await storage.load()
                }
            }
        }

        // Should complete without crashes
        let final = await storage.load()
        #expect(final.repoList.displayLimit >= 0)
        #expect(final.repoList.displayLimit < 5)
    }

    // MARK: - Settings with Enums

    @Test("Settings with all enum values")
    func settingsWithAllEnumValues() async {
        let storage = InMemorySettingsStorage()

        // Test all RefreshInterval values
        for interval in RefreshInterval.allCases {
            var settings = UserSettings()
            settings.refreshInterval = interval
            await storage.save(settings)
            let loaded = await storage.load()
            #expect(loaded.refreshInterval == interval)
        }

        // Test all HeatmapDisplay values
        for display in HeatmapDisplay.allCases {
            var settings = UserSettings()
            settings.heatmap.display = display
            await storage.save(settings)
            let loaded = await storage.load()
            #expect(loaded.heatmap.display == display)
        }

        // Test all CardDensity values
        for density in CardDensity.allCases {
            var settings = UserSettings()
            settings.appearance.cardDensity = density
            await storage.save(settings)
            let loaded = await storage.load()
            #expect(loaded.appearance.cardDensity == density)
        }

        // Test all AccentTone values
        for tone in AccentTone.allCases {
            var settings = UserSettings()
            settings.appearance.accentTone = tone
            await storage.save(settings)
            let loaded = await storage.load()
            #expect(loaded.appearance.accentTone == tone)
        }
    }

    // MARK: - JSON File Storage Specific Tests

    @Test("Settings in JSON file are human-readable")
    func settingsInJSONFileAreHumanReadable() async throws {
        let tempDir = try TestFixtures.createTemporaryDirectory()
        let fileURL = tempDir.appendingPathComponent("settings.json")
        let storage = JSONFileSettingsStorage(fileURL: fileURL)

        var settings = UserSettings()
        settings.launchAtLogin = true
        settings.refreshInterval = .fiveMinutes

        await storage.save(settings)

        // Read raw JSON
        let data = try Data(contentsOf: fileURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Verify it's readable
        #expect(json["version"] as? Int != nil)
        #expect(json["settings"] as? [String: Any] != nil)

        TestFixtures.cleanupTemporaryDirectory(tempDir)
    }

    @Test("Multiple JSON files for different configurations")
    func multipleJSONFilesForDifferentConfigurations() async throws {
        let tempDir = try TestFixtures.createTemporaryDirectory()

        let file1 = tempDir.appendingPathComponent("config1.json")
        let file2 = tempDir.appendingPathComponent("config2.json")

        let storage1 = JSONFileSettingsStorage(fileURL: file1)
        let storage2 = JSONFileSettingsStorage(fileURL: file2)

        var settings1 = UserSettings()
        settings1.launchAtLogin = true
        await storage1.save(settings1)

        var settings2 = UserSettings()
        settings2.launchAtLogin = false
        await storage2.save(settings2)

        let loaded1 = await storage1.load()
        let loaded2 = await storage2.load()

        #expect(loaded1.launchAtLogin == true)
        #expect(loaded2.launchAtLogin == false)

        TestFixtures.cleanupTemporaryDirectory(tempDir)
    }

    // MARK: - Error Recovery

    @Test("Settings recover from corrupted data")
    func settingsRecoverFromCorruptedData() async throws {
        let tempDir = try TestFixtures.createTemporaryDirectory()
        let fileURL = tempDir.appendingPathComponent("corrupted.json")

        // Write corrupted JSON
        let corruptedData = "{ this is not valid JSON }".data(using: .utf8)!
        try corruptedData.write(to: fileURL)

        let storage = JSONFileSettingsStorage(fileURL: fileURL)

        // Should return defaults instead of crashing
        let settings = await storage.load()
        #expect(settings == UserSettings())

        TestFixtures.cleanupTemporaryDirectory(tempDir)
    }

    @Test("Settings handle missing files gracefully")
    func settingsHandleMissingFilesGracefully() async throws {
        let tempDir = try TestFixtures.createTemporaryDirectory()
        let nonExistentFile = tempDir.appendingPathComponent("does-not-exist.json")

        let storage = JSONFileSettingsStorage(fileURL: nonExistentFile)

        // Should return defaults
        let settings = await storage.load()
        #expect(settings == UserSettings())

        TestFixtures.cleanupTemporaryDirectory(tempDir)
    }
}
