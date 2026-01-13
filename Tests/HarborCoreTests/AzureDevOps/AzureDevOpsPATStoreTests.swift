import Foundation
@testable import HarborCore
import XCTest

// MARK: - In-Memory PAT Storage Tests

final class InMemoryPATStorageTests: XCTestCase {

    var storage: InMemoryPATStorage!

    override func setUp() {
        super.setUp()
        storage = InMemoryPATStorage()
    }

    override func tearDown() {
        storage = nil
        super.tearDown()
    }

    // MARK: - Save and Load Tests

    func testSaveAndLoadToken() throws {
        let token = PATToken(
            token: "test-token-12345",
            organization: "myorg",
            createdAt: Date(),
            expiresAt: nil
        )

        storage.save(pat: token)

        let loaded = try storage.load(forOrganization: "myorg")

        XCTAssertEqual(loaded.token, token.token)
        XCTAssertEqual(loaded.organization, token.organization)
    }

    func testSaveAndLoadTokenWithExpiration() throws {
        let expiration = Date().addingTimeInterval(86400) // 24 hours from now
        let token = PATToken(
            token: "test-token-abc",
            organization: "acme",
            createdAt: Date(),
            expiresAt: expiration
        )

        storage.save(pat: token)

        let loaded = try storage.load(forOrganization: "acme")

        XCTAssertEqual(loaded.token, token.token)
        XCTAssertEqual(loaded.organization, token.organization)
        XCTAssertEqual(loaded.expiresAt, expiration)
    }

    func testLoadNonexistentTokenThrows() {
        XCTAssertThrowsError(try storage.load(forOrganization: "nonexistent")) { error in
            XCTAssertEqual(error as? PATStoreError, .tokenNotFound)
        }
    }

    func testLoadTokenCaseInsensitive() throws {
        let token = PATToken(
            token: "test-token",
            organization: "MyOrg",
            createdAt: Date(),
            expiresAt: nil
        )

        storage.save(pat: token)

        // Should find with different case
        let loaded = try storage.load(forOrganization: "MYORG")

        XCTAssertEqual(loaded.token, token.token)
    }

    // MARK: - Organization-Specific Storage Tests

    func testOrganizationSpecificStorage() throws {
        let token1 = PATToken(token: "token1", organization: "org1", createdAt: Date())
        let token2 = PATToken(token: "token2", organization: "org2", createdAt: Date())

        storage.save(pat: token1)
        storage.save(pat: token2)

        let loaded1 = try storage.load(forOrganization: "org1")
        let loaded2 = try storage.load(forOrganization: "org2")

        XCTAssertEqual(loaded1.token, "token1")
        XCTAssertEqual(loaded2.token, "token2")
    }

    func testOverwriteExistingToken() throws {
        let token1 = PATToken(token: "old-token", organization: "org", createdAt: Date())
        let token2 = PATToken(token: "new-token", organization: "org", createdAt: Date())

        storage.save(pat: token1)
        storage.save(pat: token2)

        let loaded = try storage.load(forOrganization: "org")

        XCTAssertEqual(loaded.token, "new-token")
    }

    func testMultipleOrganizationsRemainSeparate() throws {
        let tokens = [
            PATToken(token: "token-a", organization: "org-a", createdAt: Date()),
            PATToken(token: "token-b", organization: "org-b", createdAt: Date()),
            PATToken(token: "token-c", organization: "org-c", createdAt: Date())
        ]

        for token in tokens {
            storage.save(pat: token)
        }

        for token in tokens {
            let loaded = try storage.load(forOrganization: token.organization)
            XCTAssertEqual(loaded.token, token.token)
        }
    }

    // MARK: - Token Not Found Error Tests

    func testTokenNotFoundErrorForMissingOrganization() {
        XCTAssertThrowsError(try storage.load(forOrganization: "does-not-exist")) { error in
            XCTAssertEqual(error as? PATStoreError, PATStoreError.tokenNotFound)
        }
    }

    func testTokenNotFoundAfterDeletion() throws {
        let token = PATToken(token: "token", organization: "org", createdAt: Date())
        storage.save(pat: token)

        storage.delete(forOrganization: "org")

        XCTAssertThrowsError(try storage.load(forOrganization: "org")) { error in
            XCTAssertEqual(error as? PATStoreError, PATStoreError.tokenNotFound)
        }
    }

    // MARK: - Token Expiration Check Tests

    func testNonExpiredToken() throws {
        let futureDate = Date().addingTimeInterval(3600) // 1 hour from now
        let token = PATToken(
            token: "valid-token",
            organization: "org",
            createdAt: Date(),
            expiresAt: futureDate
        )

        storage.save(pat: token)

        let loaded = try storage.load(forOrganization: "org")

        XCTAssertFalse(loaded.isExpired)
    }

    func testExpiredToken() throws {
        let pastDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let token = PATToken(
            token: "expired-token",
            organization: "org",
            createdAt: Date(),
            expiresAt: pastDate
        )

        storage.save(pat: token)

        let loaded = try storage.load(forOrganization: "org")

        XCTAssertTrue(loaded.isExpired)
    }

    func testTokenWithoutExpirationNeverExpires() throws {
        let token = PATToken(
            token: "eternal-token",
            organization: "org",
            createdAt: Date(),
            expiresAt: nil
        )

        storage.save(pat: token)

        let loaded = try storage.load(forOrganization: "org")

        XCTAssertFalse(loaded.isExpired)
    }

    // MARK: - List Organizations Tests

    func testListEmptyOrganizations() throws {
        let organizations = storage.listOrganizations()

        XCTAssertTrue(organizations.isEmpty)
    }

    func testListSingleOrganization() throws {
        let token = PATToken(token: "token", organization: "myorg", createdAt: Date())
        storage.save(pat: token)

        let organizations = storage.listOrganizations()

        XCTAssertEqual(organizations.count, 1)
        XCTAssertTrue(organizations.contains("myorg"))
    }

    func testListMultipleOrganizations() throws {
        let tokens = [
            PATToken(token: "t1", organization: "org-a", createdAt: Date()),
            PATToken(token: "t2", organization: "org-b", createdAt: Date()),
            PATToken(token: "t3", organization: "org-c", createdAt: Date())
        ]

        for token in tokens {
            storage.save(pat: token)
        }

        let organizations = storage.listOrganizations()

        XCTAssertEqual(organizations.count, 3)
        XCTAssertTrue(organizations.contains("org-a"))
        XCTAssertTrue(organizations.contains("org-b"))
        XCTAssertTrue(organizations.contains("org-c"))
    }

    func testListOrganizationsCaseInsensitive() throws {
        let token = PATToken(token: "token", organization: "MixedCase", createdAt: Date())
        storage.save(pat: token)

        let organizations = storage.listOrganizations()

        XCTAssertEqual(organizations.count, 1)
        XCTAssertTrue(organizations.contains("mixedcase"))
    }

    // MARK: - Delete Organization Token Tests

    func testDeleteOrganizationToken() throws {
        let token = PATToken(token: "token", organization: "org", createdAt: Date())
        storage.save(pat: token)

        storage.delete(forOrganization: "org")

        XCTAssertFalse(storage.hasToken(forOrganization: "org"))
    }

    func testDeleteNonexistentOrganizationDoesNotThrow() {
        // Should not throw even if organization doesn't exist
        storage.delete(forOrganization: "nonexistent")
    }

    func testDeleteMaintainsOtherOrganizations() throws {
        let tokens = [
            PATToken(token: "t1", organization: "org-a", createdAt: Date()),
            PATToken(token: "t2", organization: "org-b", createdAt: Date())
        ]

        for token in tokens {
            storage.save(pat: token)
        }

        storage.delete(forOrganization: "org-a")

        XCTAssertFalse(storage.hasToken(forOrganization: "org-a"))
        XCTAssertTrue(storage.hasToken(forOrganization: "org-b"))
    }

    func testDeleteCaseInsensitive() throws {
        let token = PATToken(token: "token", organization: "MyOrg", createdAt: Date())
        storage.save(pat: token)

        storage.delete(forOrganization: "myorg")

        XCTAssertFalse(storage.hasToken(forOrganization: "myorg"))
    }

    // MARK: - Clear All Tests

    func testClearAll() throws {
        let tokens = [
            PATToken(token: "t1", organization: "org-a", createdAt: Date()),
            PATToken(token: "t2", organization: "org-b", createdAt: Date()),
            PATToken(token: "t3", organization: "org-c", createdAt: Date())
        ]

        for token in tokens {
            storage.save(pat: token)
        }

        storage.clearAll()

        XCTAssertTrue(storage.listOrganizations().isEmpty)
        XCTAssertFalse(storage.hasToken(forOrganization: "org-a"))
        XCTAssertFalse(storage.hasToken(forOrganization: "org-b"))
        XCTAssertFalse(storage.hasToken(forOrganization: "org-c"))
    }

    // MARK: - Has Token Tests

    func testHasTokenReturnsTrueForExisting() throws {
        let token = PATToken(token: "token", organization: "org", createdAt: Date())
        storage.save(pat: token)

        XCTAssertTrue(storage.hasToken(forOrganization: "org"))
    }

    func testHasTokenReturnsFalseForNonexistent() {
        XCTAssertFalse(storage.hasToken(forOrganization: "nonexistent"))
    }

    func testHasTokenCaseInsensitive() throws {
        let token = PATToken(token: "token", organization: "MyOrg", createdAt: Date())
        storage.save(pat: token)

        XCTAssertTrue(storage.hasToken(forOrganization: "MYORG"))
        XCTAssertTrue(storage.hasToken(forOrganization: "myorg"))
    }

    func testHasTokenAfterDeletion() throws {
        let token = PATToken(token: "token", organization: "org", createdAt: Date())
        storage.save(pat: token)

        storage.delete(forOrganization: "org")

        XCTAssertFalse(storage.hasToken(forOrganization: "org"))
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

    var storage: InMemoryPATStorage!

    override func setUp() {
        super.setUp()
        storage = InMemoryPATStorage()
    }

    override func tearDown() {
        storage = nil
        super.tearDown()
    }

    func testConcurrentSaveAndLoad() {
        let expectation = XCTestExpectation(description: "Concurrent operations complete")
        let iterations = 100

        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            let org = "org-\(index % 5)"
            let token = PATToken(token: "token-\(index)", organization: org, createdAt: Date())
            storage.save(pat: token)
        }

        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            let org = "org-\(index % 5)"
            _ = storage.load(forOrganization: org)
        }

        expectation.fulfill()
        wait(for: [expectation], timeout: 10)
    }

    func testConcurrentSaveAndList() {
        let expectation = XCTestExpectation(description: "Concurrent save and list complete")
        let iterations = 50

        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            let org = "org-\(index)"
            let token = PATToken(token: "token", organization: org, createdAt: Date())
            storage.save(pat: token)
        }

        let _ = storage.listOrganizations()

        expectation.fulfill()
        wait(for: [expectation], timeout: 10)
    }

    func testConcurrentSaveAndDelete() {
        let expectation = XCTestExpectation(description: "Concurrent save and delete complete")
        let iterations = 100

        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            let org = "org-\(index % 10)"
            if index % 2 == 0 {
                let token = PATToken(token: "token", organization: org, createdAt: Date())
                storage.save(pat: token)
            } else {
                storage.delete(forOrganization: org)
            }
        }

        expectation.fulfill()
        wait(for: [expectation], timeout: 10)
    }
}
