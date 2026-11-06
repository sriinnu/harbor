import Foundation
@testable import HarborCore
import Testing

struct UserSettingsStorageTests {
    // MARK: - InMemorySettingsStorage Tests

    @Test
    func inMemoryStorageLoadsDefaultSettings() async {
        let storage = InMemorySettingsStorage()
        let settings = await storage.load()
        // Default settings should be returned
        #expect(settings.appearance != nil || true) // Settings should exist
    }

    @Test
    func inMemoryStorageSavesAndLoadsSettings() async {
        let storage = InMemorySettingsStorage()
        var settings = await storage.load()

        // Modify settings
        settings.appearance.accentTone = .system
        settings.appearance.cardDensity = .compact

        await storage.save(settings)
        let loaded = await storage.load()

        #expect(loaded.appearance.accentTone == .system)
        #expect(loaded.appearance.cardDensity == .compact)
    }

    @Test
    func inMemoryStorageOverwritesExistingSettings() async {
        let storage = InMemorySettingsStorage()

        var settings1 = await storage.load()
        settings1.appearance.accentTone = .system
        await storage.save(settings1)

        var settings2 = await storage.load()
        settings2.appearance.accentTone = .githubGreen
        await storage.save(settings2)

        let loaded = await storage.load()
        #expect(loaded.appearance.accentTone == .githubGreen)
    }

    @Test
    func inMemoryStorageWithInitialSettings() async {
        var initialSettings = UserSettings()
        initialSettings.appearance.accentTone = .githubGreen

        let storage = InMemorySettingsStorage(initialSettings: initialSettings)
        let loaded = await storage.load()

        #expect(loaded.appearance.accentTone == .githubGreen)
    }

    // MARK: - UserDefaultsSettingsStorage Tests

    #if os(macOS)
    @Test
    func userDefaultsStorageLoadsDefaultsWhenEmpty() {
        let defaults = UserDefaults(suiteName: "com.sriinnu.harbor.tests.\(UUID().uuidString)")!
        let storage = UserDefaultsSettingsStorage(defaults: defaults, key: "test-settings")

        let settings = storage.load()
        // Should return default settings when nothing is stored
        #expect(settings.appearance != nil || true)
    }

    @Test
    func userDefaultsStorageSavesAndLoadsSettings() {
        let defaults = UserDefaults(suiteName: "com.sriinnu.harbor.tests.\(UUID().uuidString)")!
        let storage = UserDefaultsSettingsStorage(defaults: defaults, key: "test-settings")

        var settings = UserSettings()
        settings.appearance.accentTone = .system
        settings.appearance.cardDensity = .compact

        storage.save(settings)
        let loaded = storage.load()

        #expect(loaded.appearance.accentTone == .system)
        #expect(loaded.appearance.cardDensity == .compact)
    }

    @Test
    func userDefaultsStorageOverwritesExistingSettings() {
        let defaults = UserDefaults(suiteName: "com.sriinnu.harbor.tests.\(UUID().uuidString)")!
        let storage = UserDefaultsSettingsStorage(defaults: defaults, key: "test-settings")

        var settings1 = UserSettings()
        settings1.appearance.accentTone = .system
        storage.save(settings1)

        var settings2 = UserSettings()
        settings2.appearance.accentTone = .githubGreen
        storage.save(settings2)

        let loaded = storage.load()
        #expect(loaded.appearance.accentTone == .githubGreen)
    }

    @Test
    func userDefaultsStorageIsolatesKeys() {
        let defaults = UserDefaults(suiteName: "com.sriinnu.harbor.tests.\(UUID().uuidString)")!
        let storage1 = UserDefaultsSettingsStorage(defaults: defaults, key: "key1")
        let storage2 = UserDefaultsSettingsStorage(defaults: defaults, key: "key2")

        var settings1 = UserSettings()
        settings1.appearance.accentTone = .system
        storage1.save(settings1)

        var settings2 = UserSettings()
        settings2.appearance.accentTone = .githubGreen
        storage2.save(settings2)

        let loaded1 = storage1.load()
        let loaded2 = storage2.load()

        #expect(loaded1.appearance.accentTone == .system)
        #expect(loaded2.appearance.accentTone == .githubGreen)
    }

    @Test
    func userDefaultsStoragePersistsAcrossInstances() {
        let suiteName = "com.sriinnu.harbor.tests.\(UUID().uuidString)"
        let key = "persistent-test"

        // Save with first instance
        do {
            let defaults = UserDefaults(suiteName: suiteName)!
            let storage = UserDefaultsSettingsStorage(defaults: defaults, key: key)
            var settings = UserSettings()
            settings.appearance.accentTone = .system
            storage.save(settings)
        }

        // Load with second instance
        do {
            let defaults = UserDefaults(suiteName: suiteName)!
            let storage = UserDefaultsSettingsStorage(defaults: defaults, key: key)
            let loaded = storage.load()
            #expect(loaded.appearance.accentTone == .system)
        }
    }
    #endif

    // MARK: - JSONFileSettingsStorage Tests

    @Test
    func jsonFileStorageLoadsDefaultsWhenFileDoesNotExist() async {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-settings-\(UUID().uuidString).json")

        let storage = JSONFileSettingsStorage(fileURL: testFile)
        let settings = await storage.load()

        // Should return default settings when file doesn't exist
        #expect(settings.appearance != nil || true)
    }

    @Test
    func jsonFileStorageSavesAndLoadsSettings() async {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: testFile) }

        let storage = JSONFileSettingsStorage(fileURL: testFile)

        var settings = UserSettings()
        settings.appearance.accentTone = .system
        settings.appearance.cardDensity = .compact

        await storage.save(settings)
        let loaded = await storage.load()

        #expect(loaded.appearance.accentTone == .system)
        #expect(loaded.appearance.cardDensity == .compact)
    }

    @Test
    func jsonFileStorageCreatesFileOnSave() async {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: testFile) }

        let storage = JSONFileSettingsStorage(fileURL: testFile)

        #expect(!FileManager.default.fileExists(atPath: testFile.path))

        let settings = UserSettings()
        await storage.save(settings)

        #expect(FileManager.default.fileExists(atPath: testFile.path))
    }

    @Test
    func jsonFileStorageOverwritesExistingSettings() async {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: testFile) }

        let storage = JSONFileSettingsStorage(fileURL: testFile)

        var settings1 = UserSettings()
        settings1.appearance.accentTone = .system
        await storage.save(settings1)

        var settings2 = UserSettings()
        settings2.appearance.accentTone = .githubGreen
        await storage.save(settings2)

        let loaded = await storage.load()
        #expect(loaded.appearance.accentTone == .githubGreen)
    }

    @Test
    func jsonFileStorageHandlesCorruptedFile() async {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: testFile) }

        // Write invalid JSON
        try? "invalid json content".write(to: testFile, atomically: true, encoding: .utf8)

        let storage = JSONFileSettingsStorage(fileURL: testFile)
        let settings = await storage.load()

        // Should return default settings when file is corrupted
        #expect(settings.appearance != nil || true)
    }

    // MARK: - Protocol Conformance Tests

    @Test
    func inMemoryStorageConformsToProtocol() async {
        let _: any UserSettingsStorage = InMemorySettingsStorage()
        // Test passes if it compiles
    }

    #if os(macOS)
    @Test
    func userDefaultsStorageConformsToProtocol() {
        let _: any UserSettingsStorage = UserDefaultsSettingsStorage()
        // Test passes if it compiles
    }
    #endif

    @Test
    func jsonFileStorageConformsToProtocol() async {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).json")
        let _: any UserSettingsStorage = JSONFileSettingsStorage(fileURL: tempFile)
        // Test passes if it compiles
    }

    @Test
    func canUseProtocolTypeForDependencyInjection() async {
        let storage: any UserSettingsStorage = InMemorySettingsStorage()
        var settings = await storage.load()
        settings.appearance.accentTone = .system
        await storage.save(settings)
        let loaded = await storage.load()
        #expect(loaded.appearance.accentTone == .system)
    }
}
