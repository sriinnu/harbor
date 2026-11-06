import Foundation
@testable import HarborCore
import XCTest

// MARK: - In-Memory PAT Storage Tests

final class InMemoryPATStorageTests: XCTestCase {

    // XCTest makes a fresh instance per test method, so each test gets its own storage.
    private var storage = InMemoryPATStorage()

    // MARK: - Save and Load Tests

    func testSaveAndLoadToken() async throws {
        let token = PATToken(
            token: "test-token-12345",
            organization: "myorg",
            createdAt: Date(),
            expiresAt: nil
        )

        await storage.save(pat: token)

        let loaded = try await storage.load(forOrganization: "myorg")

        XCTAssertEqual(loaded.token, token.token)
        XCTAssertEqual(loaded.organization, token.organization)
    }

    func testSaveAndLoadTokenWithExpiration() async throws {
        let expiration = Date().addingTimeInterval(86400) // 24 hours from now
        let token = PATToken(
            token: "test-token-abc",
            organization: "acme",
            createdAt: Date(),
            expiresAt: expiration
        )

        await storage.save(pat: token)

        let loaded = try await storage.load(forOrganization: "acme")

        XCTAssertEqual(loaded.token, token.token)
        XCTAssertEqual(loaded.organization, token.organization)
        XCTAssertEqual(loaded.expiresAt, expiration)
    }

    func testLoadNonexistentTokenThrows() async {
        do { _ = try await storage.load(forOrganization: "nonexistent"); XCTFail("Expected an error") } catch {
            XCTAssertEqual(error as? PATStoreError, .tokenNotFound)
        }
    }

    func testLoadTokenCaseInsensitive() async throws {
        let token = PATToken(
            token: "test-token",
            organization: "MyOrg",
            createdAt: Date(),
            expiresAt: nil
        )

        await storage.save(pat: token)

        // Should find with different case
        let loaded = try await storage.load(forOrganization: "MYORG")

        XCTAssertEqual(loaded.token, token.token)
    }

    // MARK: - Organization-Specific Storage Tests

    func testOrganizationSpecificStorage() async throws {
        let token1 = PATToken(token: "token1", organization: "org1", createdAt: Date())
        let token2 = PATToken(token: "token2", organization: "org2", createdAt: Date())

        await storage.save(pat: token1)
        await storage.save(pat: token2)

        let loaded1 = try await storage.load(forOrganization: "org1")
        let loaded2 = try await storage.load(forOrganization: "org2")

        XCTAssertEqual(loaded1.token, "token1")
        XCTAssertEqual(loaded2.token, "token2")
    }

    func testOverwriteExistingToken() async throws {
        let token1 = PATToken(token: "old-token", organization: "org", createdAt: Date())
        let token2 = PATToken(token: "new-token", organization: "org", createdAt: Date())

        await storage.save(pat: token1)
        await storage.save(pat: token2)

        let loaded = try await storage.load(forOrganization: "org")

        XCTAssertEqual(loaded.token, "new-token")
    }

    func testMultipleOrganizationsRemainSeparate() async throws {
        let tokens = [
            PATToken(token: "token-a", organization: "org-a", createdAt: Date()),
            PATToken(token: "token-b", organization: "org-b", createdAt: Date()),
            PATToken(token: "token-c", organization: "org-c", createdAt: Date())
        ]

        for token in tokens {
            await storage.save(pat: token)
        }

        for token in tokens {
            let loaded = try await storage.load(forOrganization: token.organization)
            XCTAssertEqual(loaded.token, token.token)
        }
    }

    // MARK: - Token Not Found Error Tests

    func testTokenNotFoundErrorForMissingOrganization() async {
        do { _ = try await storage.load(forOrganization: "does-not-exist"); XCTFail("Expected an error") } catch {
            XCTAssertEqual(error as? PATStoreError, PATStoreError.tokenNotFound)
        }
    }

    func testTokenNotFoundAfterDeletion() async throws {
        let token = PATToken(token: "token", organization: "org", createdAt: Date())
        await storage.save(pat: token)

        await storage.delete(forOrganization: "org")

        do { _ = try await storage.load(forOrganization: "org"); XCTFail("Expected an error") } catch {
            XCTAssertEqual(error as? PATStoreError, PATStoreError.tokenNotFound)
        }
    }

    // MARK: - Token Expiration Check Tests

    func testNonExpiredToken() async throws {
        let futureDate = Date().addingTimeInterval(3600) // 1 hour from now
        let token = PATToken(
            token: "valid-token",
            organization: "org",
            createdAt: Date(),
            expiresAt: futureDate
        )

        await storage.save(pat: token)

        let loaded = try await storage.load(forOrganization: "org")

        XCTAssertFalse(loaded.isExpired)
    }

    func testExpiredToken() async throws {
        let pastDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let token = PATToken(
            token: "expired-token",
            organization: "org",
            createdAt: Date(),
            expiresAt: pastDate
        )

        await storage.save(pat: token)

        let loaded = try await storage.load(forOrganization: "org")

        XCTAssertTrue(loaded.isExpired)
    }

    func testTokenWithoutExpirationNeverExpires() async throws {
        let token = PATToken(
            token: "eternal-token",
            organization: "org",
            createdAt: Date(),
            expiresAt: nil
        )

        await storage.save(pat: token)

        let loaded = try await storage.load(forOrganization: "org")

        XCTAssertFalse(loaded.isExpired)
    }

    // MARK: - List Organizations Tests

    func testListEmptyOrganizations() async throws {
        let organizations = await storage.listOrganizations()

        XCTAssertTrue(organizations.isEmpty)
    }

    func testListSingleOrganization() async throws {
        let token = PATToken(token: "token", organization: "myorg", createdAt: Date())
        await storage.save(pat: token)

        let organizations = await storage.listOrganizations()

        XCTAssertEqual(organizations.count, 1)
        XCTAssertTrue(organizations.contains("myorg"))
    }

    func testListMultipleOrganizations() async throws {
        let tokens = [
            PATToken(token: "t1", organization: "org-a", createdAt: Date()),
            PATToken(token: "t2", organization: "org-b", createdAt: Date()),
            PATToken(token: "t3", organization: "org-c", createdAt: Date())
        ]

        for token in tokens {
            await storage.save(pat: token)
        }

        let organizations = await storage.listOrganizations()

        XCTAssertEqual(organizations.count, 3)
        XCTAssertTrue(organizations.contains("org-a"))
        XCTAssertTrue(organizations.contains("org-b"))
        XCTAssertTrue(organizations.contains("org-c"))
    }

    func testListOrganizationsCaseInsensitive() async throws {
        let token = PATToken(token: "token", organization: "MixedCase", createdAt: Date())
        await storage.save(pat: token)

        let organizations = await storage.listOrganizations()

        XCTAssertEqual(organizations.count, 1)
        XCTAssertTrue(organizations.contains("mixedcase"))
    }

    // MARK: - Delete Organization Token Tests

    func testDeleteOrganizationToken() async throws {
        let token = PATToken(token: "token", organization: "org", createdAt: Date())
        await storage.save(pat: token)

        await storage.delete(forOrganization: "org")

        do { let value = await storage.hasToken(forOrganization: "org"); XCTAssertFalse(value) }
    }

    func testDeleteNonexistentOrganizationDoesNotThrow() async {
        // Should not throw even if organization doesn't exist
        await storage.delete(forOrganization: "nonexistent")
    }

    func testDeleteMaintainsOtherOrganizations() async throws {
        let tokens = [
            PATToken(token: "t1", organization: "org-a", createdAt: Date()),
            PATToken(token: "t2", organization: "org-b", createdAt: Date())
        ]

        for token in tokens {
            await storage.save(pat: token)
        }

        await storage.delete(forOrganization: "org-a")

        do { let value = await storage.hasToken(forOrganization: "org-a"); XCTAssertFalse(value) }
        do { let value = await storage.hasToken(forOrganization: "org-b"); XCTAssertTrue(value) }
    }

    func testDeleteCaseInsensitive() async throws {
        let token = PATToken(token: "token", organization: "MyOrg", createdAt: Date())
        await storage.save(pat: token)

        await storage.delete(forOrganization: "myorg")

        do { let value = await storage.hasToken(forOrganization: "myorg"); XCTAssertFalse(value) }
    }

    // MARK: - Clear All Tests

    func testClearAll() async throws {
        let tokens = [
            PATToken(token: "t1", organization: "org-a", createdAt: Date()),
            PATToken(token: "t2", organization: "org-b", createdAt: Date()),
            PATToken(token: "t3", organization: "org-c", createdAt: Date())
        ]

        for token in tokens {
            await storage.save(pat: token)
        }

        await storage.clearAll()

        do { let value = await storage.listOrganizations().isEmpty; XCTAssertTrue(value) }
        do { let value = await storage.hasToken(forOrganization: "org-a"); XCTAssertFalse(value) }
        do { let value = await storage.hasToken(forOrganization: "org-b"); XCTAssertFalse(value) }
        do { let value = await storage.hasToken(forOrganization: "org-c"); XCTAssertFalse(value) }
    }

    // MARK: - Has Token Tests

    func testHasTokenReturnsTrueForExisting() async throws {
        let token = PATToken(token: "token", organization: "org", createdAt: Date())
        await storage.save(pat: token)

        do { let value = await storage.hasToken(forOrganization: "org"); XCTAssertTrue(value) }
    }

    func testHasTokenReturnsFalseForNonexistent() async {
        do { let value = await storage.hasToken(forOrganization: "nonexistent"); XCTAssertFalse(value) }
    }

    func testHasTokenCaseInsensitive() async throws {
        let token = PATToken(token: "token", organization: "MyOrg", createdAt: Date())
        await storage.save(pat: token)

        do { let value = await storage.hasToken(forOrganization: "MYORG"); XCTAssertTrue(value) }
        do { let value = await storage.hasToken(forOrganization: "myorg"); XCTAssertTrue(value) }
    }

    func testHasTokenAfterDeletion() async throws {
        let token = PATToken(token: "token", organization: "org", createdAt: Date())
        await storage.save(pat: token)

        await storage.delete(forOrganization: "org")

        do { let value = await storage.hasToken(forOrganization: "org"); XCTAssertFalse(value) }
    }
}

// MARK: - PATToken Tests

final class PATTokenTests: XCTestCase {

    func testTokenInitialization() {
        let token = PATToken(
            token: "test-token",
            organization: "myorg",
            createdAt: Date(),
            expiresAt: nil
        )

        XCTAssertEqual(token.token, "test-token")
        XCTAssertEqual(token.organization, "myorg")
        XCTAssertNil(token.expiresAt)
    }

    func testTokenWithExpiration() {
        let expiration = Date().addingTimeInterval(86400)
        let token = PATToken(
            token: "test-token",
            organization: "myorg",
            createdAt: Date(),
            expiresAt: expiration
        )

        XCTAssertEqual(token.expiresAt, expiration)
    }

    func testTokenIsExpiredWithFutureDate() {
        let futureDate = Date().addingTimeInterval(3600)
        let token = PATToken(token: "t", organization: "o", createdAt: Date(), expiresAt: futureDate)

        XCTAssertFalse(token.isExpired)
    }

    func testTokenIsExpiredWithPastDate() {
        let pastDate = Date().addingTimeInterval(-3600)
        let token = PATToken(token: "t", organization: "o", createdAt: Date(), expiresAt: pastDate)

        XCTAssertTrue(token.isExpired)
    }

    func testTokenIsExpiredWithNilExpiration() {
        let token = PATToken(token: "t", organization: "o", createdAt: Date(), expiresAt: nil)

        XCTAssertFalse(token.isExpired)
    }

    func testTokenEquatable() {
        let date = Date()
        let token1 = PATToken(token: "t", organization: "o", createdAt: date, expiresAt: nil)
        let token2 = PATToken(token: "t", organization: "o", createdAt: date, expiresAt: nil)

        XCTAssertEqual(token1, token2)
    }

    func testTokenNotEquatableDifferentToken() {
        let date = Date()
        let token1 = PATToken(token: "t1", organization: "o", createdAt: date, expiresAt: nil)
        let token2 = PATToken(token: "t2", organization: "o", createdAt: date, expiresAt: nil)

        XCTAssertNotEqual(token1, token2)
    }

    func testTokenNotEquatableDifferentOrganization() {
        let date = Date()
        let token1 = PATToken(token: "t", organization: "o1", createdAt: date, expiresAt: nil)
        let token2 = PATToken(token: "t", organization: "o2", createdAt: date, expiresAt: nil)

        XCTAssertNotEqual(token1, token2)
    }
}

// MARK: - PATStoreError Tests

final class PATStoreErrorTests: XCTestCase {

    func testSaveFailedErrorDescription() {
        let error = PATStoreError.saveFailed
        XCTAssertEqual(error.localizedDescription, "Failed to save PAT to keychain")
    }

    func testLoadFailedErrorDescription() {
        let error = PATStoreError.loadFailed
        XCTAssertEqual(error.localizedDescription, "Failed to load PAT from keychain")
    }

    func testTokenNotFoundErrorDescription() {
        let error = PATStoreError.tokenNotFound
        XCTAssertEqual(error.localizedDescription, "PAT not found in keychain")
    }

    func testTokenExpiredErrorDescription() {
        let error = PATStoreError.tokenExpired
        XCTAssertEqual(error.localizedDescription, "PAT has expired")
    }

    func testInvalidTokenErrorDescription() {
        let error = PATStoreError.invalidToken
        XCTAssertEqual(error.localizedDescription, "PAT is invalid")
    }
}

// MARK: - PATToken Codable Tests

final class PATTokenCodableTests: XCTestCase {

    func testTokenEncodingAndDecoding() throws {
        let original = PATToken(
            token: "test-token-123",
            organization: "myorg",
            createdAt: Date(timeIntervalSince1970: 1705323000),
            expiresAt: Date(timeIntervalSince1970: 1705409400)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PATToken.self, from: data)

        XCTAssertEqual(decoded.token, original.token)
        XCTAssertEqual(decoded.organization, original.organization)
        XCTAssertEqual(decoded.createdAt, original.createdAt)
        XCTAssertEqual(decoded.expiresAt, original.expiresAt)
    }

    func testTokenEncodingAndDecodingWithoutExpiration() throws {
        let original = PATToken(
            token: "test-token",
            organization: "org",
            createdAt: Date(),
            expiresAt: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PATToken.self, from: data)

        XCTAssertEqual(decoded.token, original.token)
        XCTAssertEqual(decoded.organization, original.organization)
        XCTAssertNil(decoded.expiresAt)
    }
}

// MARK: - Thread Safety Tests

final class InMemoryPATStorageThreadSafetyTests: XCTestCase {

    // XCTest makes a fresh instance per test method, so each test gets its own storage.
    private var storage = InMemoryPATStorage()

    func testConcurrentSaveAndLoad() async throws {
        let storage = try XCTUnwrap(self.storage)
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    await storage.save(pat: PATToken(token: "token-\(index)", organization: "org-\(index % 5)", createdAt: Date()))
                }
            }
        }
        for org in 0..<5 {
            let loaded = try await storage.load(forOrganization: "org-\(org)")
            XCTAssertEqual(loaded.organization, "org-\(org)")
        }
    }

    func testConcurrentSaveAndList() async throws {
        let storage = try XCTUnwrap(self.storage)
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                group.addTask {
                    await storage.save(pat: PATToken(token: "token", organization: "org-\(index)", createdAt: Date()))
                }
            }
        }
        let organizations = await storage.listOrganizations()
        XCTAssertEqual(organizations.count, 50)
    }

    func testConcurrentSaveAndDelete() async throws {
        let storage = try XCTUnwrap(self.storage)
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    let org = "org-\(index % 10)"
                    if index % 2 == 0 {
                        await storage.save(pat: PATToken(token: "token", organization: org, createdAt: Date()))
                    } else {
                        await storage.delete(forOrganization: org)
                    }
                }
            }
        }
        // Even indices map to even orgs, odd to odd: odd orgs are only ever deleted.
        for org in stride(from: 1, to: 10, by: 2) {
            let has = await storage.hasToken(forOrganization: "org-\(org)")
            XCTAssertFalse(has)
        }
    }
}
