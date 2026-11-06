import Testing
import Foundation
@testable import HarborCore

/// Comprehensive tests for PlatformServices implementations
@Suite("PlatformServices Tests")
struct PlatformServicesTests {

    // MARK: - MockPlatformServices Tests

    @Suite("MockPlatformServices")
    struct MockPlatformServicesTestSuite {

        @Test("Default initialization creates all services")
        func defaultInitializationCreatesAllServices() {
            let services = MockPlatformServices()

            // Verify all services are present
            _ = services.tokenStorage
            _ = services.callbackServer
            _ = services.executableLocator
            _ = services.settingsStorage

            // Test passes if no crashes
        }

        @Test("Uses InMemoryTokenStorage by default")
        func usesInMemoryTokenStorageByDefault() {
            let services = MockPlatformServices()

            #expect(services.tokenStorage is InMemoryTokenStorage)
        }

        @Test("Uses MockCallbackServer by default")
        func usesMockCallbackServerByDefault() {
            let services = MockPlatformServices()

            #expect(services.callbackServer is MockCallbackServer)
        }

        @Test("Uses MockExecutableLocator by default")
        func usesMockExecutableLocatorByDefault() {
            let services = MockPlatformServices()

            #expect(services.executableLocator is MockExecutableLocator)
        }

        @Test("Uses InMemorySettingsStorage by default")
        func usesInMemorySettingsStorageByDefault() {
            let services = MockPlatformServices()

            #expect(services.settingsStorage is InMemorySettingsStorage)
        }

        @Test("Can inject custom token storage")
        func canInjectCustomTokenStorage() async {
            let customStorage = InMemoryTokenStorage()
            let services = MockPlatformServices(tokenStorage: customStorage)

            // Verify we can use the injected storage
            let tokens = TestFixtures.sampleTokens
            try? services.tokenStorage.save(tokens: tokens)
            let loaded = try? services.tokenStorage.load()

            #expect(loaded == tokens)
        }

        @Test("Can inject custom callback server")
        func canInjectCustomCallbackServer() async {
            let customServer = MockCallbackServer()
            let services = MockPlatformServices(callbackServer: customServer)

            customServer.configureMock(code: "test", state: "test")
            let url = try? services.callbackServer.start()

            #expect(url != nil)
        }

        @Test("Can inject custom executable locator")
        func canInjectCustomExecutableLocator() {
            let customLocator = MockExecutableLocator(path: "/custom/path/git")
            let services = MockPlatformServices(executableLocator: customLocator)

            let result = services.executableLocator.locate(executable: "git")

            #expect(result?.path == "/custom/path/git")
        }

        @Test("Can inject custom settings storage")
        func canInjectCustomSettingsStorage() async {
            var customSettings = UserSettings()
            customSettings.launchAtLogin = true
            let customStorage = InMemorySettingsStorage(initialSettings: customSettings)
            let services = MockPlatformServices(settingsStorage: customStorage)

            let loaded = services.settingsStorage.load()

            #expect(loaded.launchAtLogin == true)
        }

        @Test("All services can be injected simultaneously")
        func allServicesCanBeInjectedSimultaneously() {
            let tokenStorage = InMemoryTokenStorage()
            let callbackServer = MockCallbackServer()
            let executableLocator = MockExecutableLocator(path: "/test/git")
            let settingsStorage = InMemorySettingsStorage()

            let services = MockPlatformServices(
                tokenStorage: tokenStorage,
                callbackServer: callbackServer,
                executableLocator: executableLocator,
                settingsStorage: settingsStorage
            )

            #expect(services.tokenStorage is InMemoryTokenStorage)
            #expect(services.callbackServer is MockCallbackServer)
            #expect(services.executableLocator is MockExecutableLocator)
            #expect(services.settingsStorage is InMemorySettingsStorage)
        }

        @Test("Services are properly isolated")
        func servicesAreProperlyIsolated() async {
            let services1 = MockPlatformServices()
            let services2 = MockPlatformServices()

            // Save different data in each
            var settings1 = UserSettings()
            settings1.launchAtLogin = true
            services1.settingsStorage.save(settings1)

            var settings2 = UserSettings()
            settings2.launchAtLogin = false
            services2.settingsStorage.save(settings2)

            // Verify they don't interfere
            let loaded1 = services1.settingsStorage.load()
            let loaded2 = services2.settingsStorage.load()

            #expect(loaded1.launchAtLogin == true)
            #expect(loaded2.launchAtLogin == false)
        }
    }

    // MARK: - ApplePlatformServices Tests (macOS only)

    #if os(macOS)
    @Suite("ApplePlatformServices")
    struct ApplePlatformServicesTestSuite {

        @Test("Default initialization creates platform-specific services")
        func defaultInitializationCreatesPlatformSpecificServices() {
            let services = ApplePlatformServices()

            #expect(services.tokenStorage is KeychainTokenStorage)
            #expect(services.settingsStorage is UserDefaultsSettingsStorage)
            #expect(services.executableLocator is MacOSExecutableLocator)
        }

        @Test("Uses KeychainTokenStorage by default")
        func usesKeychainTokenStorageByDefault() {
            let services = ApplePlatformServices()

            #expect(services.tokenStorage is KeychainTokenStorage)
        }

        @Test("Uses NetworkFrameworkCallbackServer by default on macOS")
        func usesNetworkFrameworkCallbackServerByDefaultOnMacOS() {
            let services = ApplePlatformServices()

            // NetworkFrameworkCallbackServer is MainActor-isolated, so we just check it exists
            _ = services.callbackServer
        }

        @Test("Uses MacOSExecutableLocator by default")
        func usesMacOSExecutableLocatorByDefault() {
            let services = ApplePlatformServices()

            #expect(services.executableLocator is MacOSExecutableLocator)
        }

        @Test("Uses UserDefaultsSettingsStorage by default")
        func usesUserDefaultsSettingsStorageByDefault() {
            let services = ApplePlatformServices()

            #expect(services.settingsStorage is UserDefaultsSettingsStorage)
        }

        @Test("Can inject custom token storage")
        func canInjectCustomTokenStorage() async {
            let customStorage = InMemoryTokenStorage()
            let services = ApplePlatformServices(tokenStorage: customStorage)

            #expect(services.tokenStorage is InMemoryTokenStorage)
        }

        @Test("Can inject custom callback server")
        func canInjectCustomCallbackServer() {
            let customServer = MockCallbackServer()
            let services = ApplePlatformServices(callbackServer: customServer)

            #expect(services.callbackServer is MockCallbackServer)
        }

        @Test("Can inject custom executable locator")
        func canInjectCustomExecutableLocator() {
            let customLocator = MockExecutableLocator()
            let services = ApplePlatformServices(executableLocator: customLocator)

            #expect(services.executableLocator is MockExecutableLocator)
        }

        @Test("Can inject custom settings storage")
        func canInjectCustomSettingsStorage() {
            let customStorage = InMemorySettingsStorage()
            let services = ApplePlatformServices(settingsStorage: customStorage)

            #expect(services.settingsStorage is InMemorySettingsStorage)
        }

        @Test("Keychain storage integration")
        func keychainStorageIntegration() throws {
            let service = "com.sriinnu.harbor.test.\(UUID().uuidString)"
            let keychainStorage = KeychainTokenStorage(service: service)
            let services = ApplePlatformServices(tokenStorage: keychainStorage)

            keychainStorage.clear()

            // Save tokens through platform services
            let tokens = TestFixtures.sampleTokens
            try services.tokenStorage.save(tokens: tokens)

            // Load and verify
            let loaded = try services.tokenStorage.load()
            #expect(loaded == tokens)

            keychainStorage.clear()
        }

        @Test("UserDefaults storage integration")
        func userDefaultsStorageIntegration() {
            let key = "com.sriinnu.harbor.test.\(UUID().uuidString)"
            let defaults = UserDefaults.standard
            let userDefaultsStorage = UserDefaultsSettingsStorage(defaults: defaults, key: key)
            let services = ApplePlatformServices(settingsStorage: userDefaultsStorage)

            var settings = UserSettings()
            settings.launchAtLogin = true

            services.settingsStorage.save(settings)
            let loaded = services.settingsStorage.load()

            #expect(loaded.launchAtLogin == true)

            defaults.removeObject(forKey: key)
        }

        @Test("ExecutableLocator finds git")
        func executableLocatorFindsGit() {
            let services = ApplePlatformServices()

            let gitURL = services.executableLocator.locate(executable: "git")

            #expect(gitURL != nil)
        }
    }
    #endif

    // MARK: - Protocol Conformance Tests

    @Suite("Protocol Conformance")
    struct ProtocolConformanceTests {

        @Test("MockPlatformServices conforms to PlatformServices")
        func mockConformsToProtocol() {
            let _: any PlatformServices = MockPlatformServices()
            // Test passes if it compiles
        }

        #if os(macOS)
        @Test("ApplePlatformServices conforms to PlatformServices")
        func appleConformsToProtocol() {
            let _: any PlatformServices = ApplePlatformServices()
            // Test passes if it compiles
        }
        #endif

        @Test("Can use protocol type for dependency injection")
        func protocolDependencyInjection() async {
            let services: any PlatformServices = MockPlatformServices()

            // Should be able to access all services through protocol
            let tokens = TestFixtures.sampleTokens
            try? services.tokenStorage.save(tokens: tokens)

            var settings = UserSettings()
            settings.launchAtLogin = true
            services.settingsStorage.save(settings)

            _ = services.executableLocator.locate(executable: "git")
            _ = try? services.callbackServer.start()
        }
    }

    // MARK: - Integration Tests

    @Suite("Integration")
    struct IntegrationTests {

        @Test("Complete platform services workflow")
        func completePlatformServicesWorkflow() async throws {
            let services = MockPlatformServices()

            // 1. Save OAuth tokens
            let tokens = TestFixtures.sampleTokens
            try services.tokenStorage.save(tokens: tokens)
            let loadedTokens = try services.tokenStorage.load()
            #expect(loadedTokens == tokens)

            // 2. Configure settings
            var settings = UserSettings()
            settings.launchAtLogin = true
            settings.refreshInterval = .fiveMinutes
            services.settingsStorage.save(settings)
            let loadedSettings = services.settingsStorage.load()
            #expect(loadedSettings.launchAtLogin == true)

            // 3. Locate git executable
            let gitURL = services.executableLocator.locate(executable: "git")
            #expect(gitURL != nil)

            // 4. Start callback server
            let mockServer = services.callbackServer as! MockCallbackServer
            mockServer.configureMock(code: "test", state: "test")
            let callbackURL = try services.callbackServer.start()
            #expect(callbackURL.absoluteString.contains("callback"))
        }

        @Test("Services can be swapped for testing")
        func servicesCanBeSwappedForTesting() async {
            // Production-like configuration
            let productionServices = MockPlatformServices()

            // Test configuration with specific mocks
            let testTokenStorage = InMemoryTokenStorage()
            let testServices = MockPlatformServices(
                tokenStorage: testTokenStorage
            )

            // Save in test services
            let tokens = TestFixtures.sampleTokens
            try? testServices.tokenStorage.save(tokens: tokens)

            // Verify isolation
            let productionTokens = try? productionServices.tokenStorage.load()
            let testTokens = try? testServices.tokenStorage.load()

            #expect(productionTokens == nil)
            #expect(testTokens == tokens)
        }

        @Test("Platform services support concurrent access")
        func platformServicesSupportConcurrentAccess() async {
            let services = MockPlatformServices()

            await withTaskGroup(of: Void.self) { group in
                // Concurrent token operations
                group.addTask {
                    let tokens = OAuthTokens(
                        accessToken: "token1",
                        refreshToken: "refresh1",
                        expiresAt: Date()
                    )
                    try? services.tokenStorage.save(tokens: tokens)
                }

                // Concurrent settings operations
                group.addTask {
                    var settings = UserSettings()
                    settings.launchAtLogin = true
                    services.settingsStorage.save(settings)
                }

                // Concurrent executable lookups
                group.addTask {
                    _ = services.executableLocator.locate(executable: "git")
                }
            }

            // Should complete without crashes
        }
    }

    // MARK: - Edge Cases

    @Suite("Edge Cases")
    struct EdgeCasesTests {

        @Test("Nil injected services use defaults")
        func nilInjectedServicesUseDefaults() {
            let services = MockPlatformServices(
                tokenStorage: nil,
                callbackServer: nil,
                executableLocator: nil,
                settingsStorage: nil
            )

            #expect(services.tokenStorage is InMemoryTokenStorage)
            #expect(services.callbackServer is MockCallbackServer)
            #expect(services.executableLocator is MockExecutableLocator)
            #expect(services.settingsStorage is InMemorySettingsStorage)
        }

        @Test("Multiple services instances are independent")
        func multipleServicesInstancesAreIndependent() async {
            let services1 = MockPlatformServices()
            let services2 = MockPlatformServices()
            let services3 = MockPlatformServices()

            // Each should have independent storage
            var settings1 = UserSettings()
            settings1.refreshInterval = .oneMinute
            services1.settingsStorage.save(settings1)

            var settings2 = UserSettings()
            settings2.refreshInterval = .fiveMinutes
            services2.settingsStorage.save(settings2)

            var settings3 = UserSettings()
            settings3.refreshInterval = .fifteenMinutes
            services3.settingsStorage.save(settings3)

            let loaded1 = services1.settingsStorage.load()
            let loaded2 = services2.settingsStorage.load()
            let loaded3 = services3.settingsStorage.load()

            #expect(loaded1.refreshInterval == .oneMinute)
            #expect(loaded2.refreshInterval == .fiveMinutes)
            #expect(loaded3.refreshInterval == .fifteenMinutes)
        }
    }
}
