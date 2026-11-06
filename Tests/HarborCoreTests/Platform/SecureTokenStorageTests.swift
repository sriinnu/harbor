import Testing
import Foundation
@testable import HarborCore

/// Comprehensive tests for SecureTokenStorage implementations
@Suite("SecureTokenStorage Tests")
struct SecureTokenStorageTests {

    // MARK: - InMemoryTokenStorage Tests

    @Suite("InMemoryTokenStorage")
    struct InMemoryTokenStorageTestSuite {

        @Test("Save and load OAuth tokens")
        func saveAndLoadTokens() async throws {
            let storage = InMemoryTokenStorage()
            let tokens = TestFixtures.sampleTokens

            // Save tokens
            try storage.save(tokens: tokens)

            // Load tokens
            let loaded = try storage.load()

            // Verify tokens match
            #expect(loaded == tokens)
        }

        @Test("Load returns nil when no tokens stored")
        func loadReturnsNilWhenEmpty() async throws {
            let storage = InMemoryTokenStorage()

            let loaded = try storage.load()

            #expect(loaded == nil)
        }

        @Test("Save overwrites existing tokens")
        func saveOverwritesExistingTokens() async throws {
            let storage = InMemoryTokenStorage()

            // Save first set of tokens
            let firstTokens = TestFixtures.sampleTokens
            try storage.save(tokens: firstTokens)

            // Save second set of tokens
            let secondTokens = OAuthTokens(
                accessToken: "new_access_token",
                refreshToken: "new_refresh_token",
                expiresAt: Date(timeIntervalSinceNow: 7200)
            )
            try storage.save(tokens: secondTokens)

            // Verify second tokens are loaded
            let loaded = try storage.load()
            #expect(loaded == secondTokens)
        }

        @Test("Save and load client credentials")
        func saveAndLoadClientCredentials() async throws {
            let storage = InMemoryTokenStorage()
            let credentials = TestFixtures.sampleClientCredentials

            // Save credentials
            try storage.save(clientCredentials: credentials)

            // Load credentials
            let loaded = try storage.loadClientCredentials()

            // Verify credentials match
            #expect(loaded == credentials)
        }

        @Test("Load client credentials returns nil when empty")
        func loadClientCredentialsReturnsNilWhenEmpty() async throws {
            let storage = InMemoryTokenStorage()

            let loaded = try storage.loadClientCredentials()

            #expect(loaded == nil)
        }

        @Test("Clear removes all stored data")
        func clearRemovesAllData() async throws {
            let storage = InMemoryTokenStorage()

            // Save both tokens and credentials
            try storage.save(tokens: TestFixtures.sampleTokens)
            try storage.save(clientCredentials: TestFixtures.sampleClientCredentials)

            // Clear storage
            storage.clear()

            // Verify both are nil
            let loadedTokens = try storage.load()
            let loadedCredentials = try storage.loadClientCredentials()

            #expect(loadedTokens == nil)
            #expect(loadedCredentials == nil)
        }

        @Test("Tokens with nil expiration date")
        func tokensWithNilExpiration() async throws {
            let storage = InMemoryTokenStorage()
            let tokens = OAuthTokens(
                accessToken: "token",
                refreshToken: "refresh",
                expiresAt: nil
            )

            try storage.save(tokens: tokens)
            let loaded = try storage.load()

            #expect(loaded?.expiresAt == nil)
        }

        @Test("Concurrent access to storage")
        func concurrentAccess() async throws {
            let storage = InMemoryTokenStorage()

            // Perform concurrent saves and loads
            await withTaskGroup(of: Void.self) { group in
                for i in 0..<10 {
                    group.addTask {
                        let tokens = OAuthTokens(
                            accessToken: "token_\(i)",
                            refreshToken: "refresh_\(i)",
                            expiresAt: Date()
                        )
                        try? storage.save(tokens: tokens)
                    }
                }
            }

            // Verify we can still load tokens
            let loaded = try storage.load()
            #expect(loaded != nil)
        }
    }

    // MARK: - KeychainTokenStorage Tests (macOS only)

    #if os(macOS)
    @Suite("KeychainTokenStorage")
    struct KeychainTokenStorageTestSuite {

        /// Create a unique service identifier for each test
        private static func uniqueService() -> String {
            return "com.sriinnu.harbor.test.\(UUID().uuidString)"
        }

        @Test("Save and load OAuth tokens from Keychain")
        func saveAndLoadTokensFromKeychain() throws {
            let service = Self.uniqueService()
            let storage = KeychainTokenStorage(service: service)
            let tokens = TestFixtures.sampleTokens

            // Clean up first
            storage.clear()

            // Save tokens
            try storage.save(tokens: tokens)

            // Load tokens
            let loaded = try storage.load()

            // Verify tokens match
            #expect(loaded == tokens)

            // Clean up
            storage.clear()
        }

        @Test("Load returns nil when no tokens in Keychain")
        func loadReturnsNilWhenKeychainEmpty() throws {
            let service = Self.uniqueService()
            let storage = KeychainTokenStorage(service: service)

            storage.clear()
            let loaded = try storage.load()

            #expect(loaded == nil)
        }

        @Test("Save overwrites existing Keychain tokens")
        func saveOverwritesExistingKeychainTokens() throws {
            let service = Self.uniqueService()
            let storage = KeychainTokenStorage(service: service)

            storage.clear()

            // Save first tokens
            let firstTokens = TestFixtures.sampleTokens
            try storage.save(tokens: firstTokens)

            // Save second tokens
            let secondTokens = OAuthTokens(
                accessToken: "new_access",
                refreshToken: "new_refresh",
                expiresAt: Date()
            )
            try storage.save(tokens: secondTokens)

            // Verify second tokens are loaded
            let loaded = try storage.load()
            #expect(loaded == secondTokens)

            storage.clear()
        }

        @Test("Save and load client credentials from Keychain")
        func saveAndLoadClientCredentialsFromKeychain() throws {
            let service = Self.uniqueService()
            let storage = KeychainTokenStorage(service: service)
            let credentials = TestFixtures.sampleClientCredentials

            storage.clear()

            // Save credentials
            try storage.save(clientCredentials: credentials)

            // Load credentials
            let loaded = try storage.loadClientCredentials()

            // Verify credentials match
            #expect(loaded == credentials)

            storage.clear()
        }

        @Test("Clear removes all data from Keychain")
        func clearRemovesAllDataFromKeychain() throws {
            let service = Self.uniqueService()
            let storage = KeychainTokenStorage(service: service)

            storage.clear()

            // Save both
            try storage.save(tokens: TestFixtures.sampleTokens)
            try storage.save(clientCredentials: TestFixtures.sampleClientCredentials)

            // Clear
            storage.clear()

            // Verify both are nil
            let loadedTokens = try storage.load()
            let loadedCredentials = try storage.loadClientCredentials()

            #expect(loadedTokens == nil)
            #expect(loadedCredentials == nil)
        }

        @Test("Multiple storage instances with different services")
        func multipleStorageInstancesWithDifferentServices() throws {
            let service1 = Self.uniqueService()
            let service2 = Self.uniqueService()
            let storage1 = KeychainTokenStorage(service: service1)
            let storage2 = KeychainTokenStorage(service: service2)

            storage1.clear()
            storage2.clear()

            let tokens1 = OAuthTokens(
                accessToken: "token1",
                refreshToken: "refresh1",
                expiresAt: Date()
            )
            let tokens2 = OAuthTokens(
                accessToken: "token2",
                refreshToken: "refresh2",
                expiresAt: Date()
            )

            // Save different tokens in each
            try storage1.save(tokens: tokens1)
            try storage2.save(tokens: tokens2)

            // Verify they don't interfere
            let loaded1 = try storage1.load()
            let loaded2 = try storage2.load()

            #expect(loaded1 == tokens1)
            #expect(loaded2 == tokens2)

            storage1.clear()
            storage2.clear()
        }

        @Test("Handle expired tokens in Keychain")
        func handleExpiredTokensInKeychain() throws {
            let service = Self.uniqueService()
            let storage = KeychainTokenStorage(service: service)

            storage.clear()

            let expiredTokens = TestFixtures.expiredTokens
            try storage.save(tokens: expiredTokens)

            let loaded = try storage.load()
            #expect(loaded?.expiresAt ?? Date() < Date())

            storage.clear()
        }
    }
    #endif

    // MARK: - Protocol Conformance Tests

    @Suite("Protocol Conformance")
    struct ProtocolConformanceTests {

        @Test("InMemoryTokenStorage conforms to SecureTokenStorage")
        func inMemoryConformsToProtocol() async {
            let _: any SecureTokenStorage = InMemoryTokenStorage()
            // Test passes if it compiles
        }

        #if os(macOS)
        @Test("KeychainTokenStorage conforms to SecureTokenStorage")
        func keychainConformsToProtocol() {
            let _: any SecureTokenStorage = KeychainTokenStorage()
            // Test passes if it compiles
        }
        #endif

        @Test("Can use protocol type for dependency injection")
        func protocolDependencyInjection() async throws {
            let storage: any SecureTokenStorage = InMemoryTokenStorage()
            let tokens = TestFixtures.sampleTokens

            try storage.save(tokens: tokens)
            let loaded = try storage.load()

            #expect(loaded == tokens)
        }
    }
}
