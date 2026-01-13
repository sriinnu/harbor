import Foundation
@testable import HarborCore
import XCTest

// MARK: - Test Helper Types

private struct TestDateModel: Decodable {
    let date: Date
}

// MARK: - Azure DevOps Decoding Tests

final class AzureDevOpsDecodingTests: XCTestCase {

    // MARK: - ISO 8601 Date Formats

    // MARK: - Microseconds Format Tests

    func testDecodingDateWithMicroseconds() throws {
        let json = """
        {
            "date": "2024-01-15T10:30:45.123456Z"
        }
        """.data(using: .utf8)!

        let model = try AzureDevOpsDecoding.decode(TestDateModel.self, from: json)

        XCTAssertNotNil(model.date)
        let calendar = Calendar.current
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: model.date)
        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 15)
        XCTAssertEqual(components.hour, 10)
        XCTAssertEqual(components.minute, 30)
        XCTAssertEqual(components.second, 45)
    }

    func testDecodingDateWith6DigitMicroseconds() throws {
        let json = """
        {
            "date": "2024-06-20T14:25:30.999999Z"
        }
        """.data(using: .utf8)!

        let model = try AzureDevOpsDecoding.decode(TestDateModel.self, from: json)

        XCTAssertNotNil(model.date)
        let calendar = Calendar.current
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: model.date)
        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.day, 20)
        XCTAssertEqual(components.second, 30)
    }

    // MARK: - Milliseconds Format Tests

    func testDecodingDateWithMilliseconds() throws {
        let json = """
        {
            "date": "2024-01-15T10:30:45.123Z"
        }
        """.data(using: .utf8)!

        let model = try AzureDevOpsDecoding.decode(TestDateModel.self, from: json)

        XCTAssertNotNil(model.date)
        let calendar = Calendar.current
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: model.date)
        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 15)
    }

    func testDecodingDateWith3DigitMilliseconds() throws {
        let json = """
        {
            "date": "2024-12-31T23:59:59.999Z"
        }
        """.data(using: .utf8)!

        let model = try AzureDevOpsDecoding.decode(TestDateModel.self, from: json)

        XCTAssertNotNil(model.date)
    }

    // MARK: - Standard Format Tests

    func testDecodingDateStandardFormat() throws {
        let json = """
        {
            "date": "2024-01-15T10:30:45Z"
        }
        """.data(using: .utf8)!

        let model = try AzureDevOpsDecoding.decode(TestDateModel.self, from: json)

        XCTAssertNotNil(model.date)
        let calendar = Calendar.current
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: model.date)
        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 15)
        XCTAssertEqual(components.hour, 10)
        XCTAssertEqual(components.minute, 30)
        XCTAssertEqual(components.second, 45)
    }

    func testDecodingDateWithTimezoneOffset() throws {
        // Note: Azure DevOps typically uses UTC (Z), but some APIs may return offsets
        let json = """
        {
            "date": "2024-01-15T10:30:45+00:00"
        }
        """.data(using: .utf8)!

        let model = try AzureDevOpsDecoding.decode(TestDateModel.self, from: json)

        XCTAssertNotNil(model.date)
    }

    // MARK: - Snake Case to CamelCase Key Conversion Tests

    func testSnakeCaseDecodingSimple() throws {
        let json = """
        {
            "pull_request_id": 123,
            "title": "Test PR",
            "created_date": "2024-01-15T10:30:45Z"
        }
        """.data(using: .utf8)!

        struct PRModel: Decodable {
            let pullRequestId: Int
            let title: String
            let createdDate: Date
        }

        let model = try AzureDevOpsDecoding.decode(PRModel.self, from: json)

        XCTAssertEqual(model.pullRequestId, 123)
        XCTAssertEqual(model.title, "Test PR")
        XCTAssertNotNil(model.createdDate)
    }

    func testSnakeCaseDecodingNested() throws {
        let json = """
        {
            "repository": {
                "id": "repo-123",
                "default_branch": "main",
                "created_date": "2024-01-15T10:30:45Z"
            }
        }
        """.data(using: .utf8)!

        struct RepoModel: Decodable {
            let repository: InnerRepo

            struct InnerRepo: Decodable {
                let id: String
                let defaultBranch: String
                let createdDate: Date
            }
        }

        let model = try AzureDevOpsDecoding.decode(RepoModel.self, from: json)

        XCTAssertEqual(model.repository.id, "repo-123")
        XCTAssertEqual(model.repository.defaultBranch, "main")
        XCTAssertNotNil(model.repository.createdDate)
    }

    func testSnakeCaseDecodingWithBoolean() throws {
        let json = """
        {
            "is_draft": true,
            "is_disabled": false
        }
        """.data(using: .utf8)!

        struct BoolModel: Decodable {
            let isDraft: Bool
            let isDisabled: Bool
        }

        let model = try AzureDevOpsDecoding.decode(BoolModel.self, from: json)

        XCTAssertTrue(model.isDraft)
        XCTAssertFalse(model.isDisabled)
    }

    func testSnakeCaseDecodingWithOptional() throws {
        let json = """
        {
            "title": "Test",
            "description": null,
            "created_date": "2024-01-15T10:30:45Z"
        }
        """.data(using: .utf8)!

        struct OptionalModel: Decodable {
            let title: String
            let description: String?
            let createdDate: Date
        }

        let model = try AzureDevOpsDecoding.decode(OptionalModel.self, from: json)

        XCTAssertEqual(model.title, "Test")
        XCTAssertNil(model.description)
        XCTAssertNotNil(model.createdDate)
    }

    // MARK: - Complex Model Decoding Tests

    func testDecodingPullRequestWithAllFields() throws {
        let json = """
        {
            "pull_request_id": 123,
            "title": "Test PR",
            "description": "A test description",
            "status": "active",
            "is_draft": false,
            "source_ref_name": "refs/heads/feature",
            "target_ref_name": "refs/heads/main",
            "creation_date": "2024-01-15T10:30:45.123456Z",
            "closed_date": null,
            "created_by": {
                "id": "user-123",
                "display_name": "Test User",
                "unique_name": "test@example.com"
            }
        }
        """.data(using: .utf8)!

        struct PRModel: Decodable {
            let pullRequestId: Int
            let title: String
            let description: String?
            let status: String
            let isDraft: Bool?
            let sourceRefName: String?
            let targetRefName: String?
            let creationDate: Date?
            let closedDate: Date?
            let createdBy: IdentityRef?
        }

        let model = try AzureDevOpsDecoding.decode(PRModel.self, from: json)

        XCTAssertEqual(model.pullRequestId, 123)
        XCTAssertEqual(model.title, "Test PR")
        XCTAssertEqual(model.status, "active")
        XCTAssertFalse(model.isDraft ?? true)
        XCTAssertNotNil(model.creationDate)
        XCTAssertNotNil(model.createdBy)
    }

    func testDecodingWorkItemWithSnakeCaseFields() throws {
        let json = """
        {
            "id": 42,
            "rev": 5,
            "fields": {
                "system_work_item_type": "Bug",
                "system_title": "Fix bug",
                "system_state": "Active",
                "system_assigned_to": {
                    "display_name": "John Doe",
                    "unique_name": "john@example.com"
                },
                "system_created_date": "2024-01-15T10:30:45.123456Z",
                "system_changed_date": "2024-01-15T11:00:00.000000Z"
            }
        }
        """.data(using: .utf8)!

        struct WorkItemModel: Decodable {
            let id: Int
            let rev: Int?
            let fields: Fields

            struct Fields: Decodable {
                let systemWorkItemType: String?
                let systemTitle: String?
                let systemState: String?
                let systemAssignedTo: AssignedTo?
                let systemCreatedDate: Date?
                let systemChangedDate: Date?

                struct AssignedTo: Decodable {
                    let displayName: String?
                    let uniqueName: String?
                }
            }
        }

        let model = try AzureDevOpsDecoding.decode(WorkItemModel.self, from: json)

        XCTAssertEqual(model.id, 42)
        XCTAssertEqual(model.fields.systemWorkItemType, "Bug")
        XCTAssertEqual(model.fields.systemTitle, "Fix bug")
        XCTAssertEqual(model.fields.systemState, "Active")
        XCTAssertNotNil(model.fields.systemCreatedDate)
        XCTAssertNotNil(model.fields.systemAssignedTo)
    }

    // MARK: - Error Handling Tests

    func testDecodingInvalidDateFormat() throws {
        let json = """
        {
            "date": "not-a-date"
        }
        """.data(using: .utf8)!

        do {
            _ = try AzureDevOpsDecoding.decode(TestDateModel.self, from: json)
            XCTFail("Expected decoding error for invalid date")
        } catch {
            // Expected error
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testDecodingNullDate() throws {
        let json = """
        {
            "date": null
        }
        """.data(using: .utf8)!

        struct NullableDateModel: Decodable {
            let date: Date?
        }

        let model = try AzureDevOpsDecoding.decode(NullableDateModel.self, from: json)

        XCTAssertNil(model.date)
    }

    func testDecodingMissingDate() throws {
        let json = """
        {
            "other_field": "value"
        }
        """.data(using: .utf8)!

        do {
            _ = try AzureDevOpsDecoding.decode(TestDateModel.self, from: json)
            XCTFail("Expected decoding error for missing date")
        } catch {
            // Expected error
            XCTAssertTrue(error is DecodingError)
        }
    }

    // MARK: - Pipeline Run Date Decoding Tests

    func testDecodingPipelineRunDates() throws {
        let json = """
        {
            "id": 789,
            "name": "Build Pipeline",
            "state": "completed",
            "result": "succeeded",
            "created_date": "2024-01-15T08:00:00.000000Z",
            "finished_date": "2024-01-15T08:05:30.000000Z"
        }
        """.data(using: .utf8)!

        struct PipelineRunModel: Decodable {
            let id: Int
            let name: String
            let state: String?
            let result: String?
            let createdDate: Date?
            let finishedDate: Date?
        }

        let model = try AzureDevOpsDecoding.decode(PipelineRunModel.self, from: json)

        XCTAssertEqual(model.id, 789)
        XCTAssertEqual(model.name, "Build Pipeline")
        XCTAssertNotNil(model.createdDate)
        XCTAssertNotNil(model.finishedDate)
    }

    // MARK: - Commit Date Decoding Tests

    func testDecodingCommitDates() throws {
        let json = """
        {
            "commit_id": "abc123",
            "comment": "Fix bug",
            "author": {
                "name": "Developer",
                "email": "dev@example.com",
                "date": "2024-01-15T10:30:45.123456Z"
            },
            "committer": {
                "name": "Developer",
                "email": "dev@example.com",
                "date": "2024-01-15T10:30:45.123456Z"
            }
        }
        """.data(using: .utf8)!

        struct CommitModel: Decodable {
            let commitId: String
            let comment: String?
            let author: Author?
            let committer: Committer?

            struct Author: Decodable {
                let name: String?
                let email: String?
                let date: Date?
            }

            struct Committer: Decodable {
                let name: String?
                let email: String?
                let date: Date?
            }
        }

        let model = try AzureDevOpsDecoding.decode(CommitModel.self, from: json)

        XCTAssertEqual(model.commitId, "abc123")
        XCTAssertNotNil(model.author?.date)
        XCTAssertNotNil(model.committer?.date)
    }

    // MARK: - Integer Decoding Tests

    func testDecodingIntegerValues() throws {
        let json = """
        {
            "id": 123,
            "priority": 1,
            "is_active": true
        }
        """.data(using: .utf8)!

        struct IntModel: Decodable {
            let id: Int
            let priority: Int
            let isActive: Bool
        }

        let model = try AzureDevOpsDecoding.decode(IntModel.self, from: json)

        XCTAssertEqual(model.id, 123)
        XCTAssertEqual(model.priority, 1)
        XCTAssertTrue(model.isActive)
    }

    // MARK: - Array Decoding Tests

    func testDecodingArrayWithSnakeCase() throws {
        let json = """
        {
            "items": [
                {
                    "item_id": 1,
                    "item_name": "First",
                    "created_date": "2024-01-15T10:30:45Z"
                },
                {
                    "item_id": 2,
                    "item_name": "Second",
                    "created_date": "2024-01-16T10:30:45Z"
                }
            ]
        }
        """.data(using: .utf8)!

        struct ArrayModel: Decodable {
            let items: [Item]

            struct Item: Decodable {
                let itemId: Int
                let itemName: String
                let createdDate: Date
            }
        }

        let model = try AzureDevOpsDecoding.decode(ArrayModel.self, from: json)

        XCTAssertEqual(model.items.count, 2)
        XCTAssertEqual(model.items[0].itemId, 1)
        XCTAssertEqual(model.items[0].itemName, "First")
        XCTAssertEqual(model.items[1].itemId, 2)
        XCTAssertEqual(model.items[1].itemName, "Second")
    }

    // MARK: - Dictionary Decoding Tests

    func testDecodingDictionaryWithSnakeCase() throws {
        let json = """
        {
            "metadata": {
                "total_count": 100,
                "page_size": 25,
                "current_page": 1
            }
        }
        """.data(using: .utf8)!

        struct DictModel: Decodable {
            let metadata: [String: Int]
        }

        let model = try AzureDevOpsDecoding.decode(DictModel.self, from: json)

        XCTAssertEqual(model.metadata["total_count"], 100)
        XCTAssertEqual(model.metadata["page_size"], 25)
        XCTAssertEqual(model.metadata["current_page"], 1)
    }
}

// MARK: - ISO8601DateFormatter Tests

final class AzureDevOpsISO8601FormatterTests: XCTestCase {

    func testMicrosecondsFormatter() {
        let formatter = ISO8601DateFormatter.azureDevOpsWithMicroseconds
        let dateString = "2024-01-15T10:30:45.123456Z"
        let date = formatter.date(from: dateString)

        XCTAssertNotNil(date)
    }

    func testMillisecondsFormatter() {
        let formatter = ISO8601DateFormatter.azureDevOpsWithMilliseconds
        let dateString = "2024-01-15T10:30:45.123Z"
        let date = formatter.date(from: dateString)

        XCTAssertNotNil(date)
    }

    func testStandardFormatter() {
        let formatter = ISO8601DateFormatter.azureDevOpsStandard
        let dateString = "2024-01-15T10:30:45Z"
        let date = formatter.date(from: dateString)

        XCTAssertNotNil(date)
    }

    func testFormatterFormatOptions() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dateString = "2024-01-15T10:30:45.123456Z"
        let date = formatter.date(from: dateString)

        XCTAssertNotNil(date)
    }
}
