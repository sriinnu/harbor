import Foundation
@testable import HarborCore
import XCTest

// MARK: - Test Data Models

struct MockJSON {
    // MARK: - Pull Request JSON

    static let pullRequest = """
    {
        "pullRequestId": 123,
        "title": "Add new feature",
        "description": "This PR adds a new feature",
        "status": "active",
        "createdBy": {
            "id": "user123",
            "displayName": "Test User",
            "uniqueName": "testuser@example.com",
            "url": "https://dev.azure.com/org/_users/user123",
            "imageUrl": "https://dev.azure.com/org/_api/_avatar/123"
        },
        "creationDate": "2024-01-15T10:30:45.123456Z",
        "closedDate": null,
        "sourceRefName": "refs/heads/feature-branch",
        "targetRefName": "refs/heads/main",
        "mergeStatus": "succeeded",
        "isDraft": false,
        "url": "https://dev.azure.com/org/project/_git/repo/pullRequest/123",
        "repository": {
            "id": "repo123",
            "name": "my-repo"
        },
        "reviewers": [
            {
                "vote": 10,
                "isRequired": true,
                "reviewerUrl": "https://dev.azure.com/org/_users/reviewer123",
                "displayName": "Reviewer One",
                "uniqueName": "reviewer@example.com",
                "imageUrl": "https://dev.azure.com/org/_api/_avatar/reviewer"
            }
        ],
        "labels": [
            {
                "id": "label123",
                "name": "enhancement"
            }
        ]
    }
    """

    static let pullRequestMinimal = """
    {
        "pullRequestId": 456,
        "title": "Minimal PR",
        "status": "active"
    }
    """

    // MARK: - Repository JSON

    static let repository = """
    {
        "id": "repo-uuid-123",
        "name": "my-awesome-repo",
        "url": "https://dev.azure.com/myorg/myproject/_git/my-awesome-repo",
        "project": {
            "id": "project-uuid-456",
            "name": "MyProject"
        },
        "defaultBranch": "refs/heads/main",
        "size": 1024000,
        "remoteUrl": "https://myorg@dev.azure.com/myorg/MyProject/_git/my-awesome-repo",
        "sshUrl": "git@ssh.dev.azure.com:v3/myorg/MyProject/my-awesome-repo",
        "webUrl": "https://dev.azure.com/myorg/MyProject/_git/my-awesome-repo",
        "isDisabled": false
    }
    """

    static let repositoryMinimal = """
    {
        "id": "repo-uuid",
        "name": "minimal-repo"
    }
    """

    // MARK: - Pipeline Run JSON

    static let pipelineRun = """
    {
        "id": 789,
        "name": "Build and Test",
        "state": "completed",
        "result": "succeeded",
        "createdDate": "2024-01-15T08:00:00.000000Z",
        "finishedDate": "2024-01-15T08:05:30.000000Z",
        "url": "https://dev.azure.com/myorg/project/_build/results?buildId=789",
        "pipeline": {
            "id": 123,
            "name": "CI Pipeline",
            "folder": "\\\\"
        },
        "resources": {
            "repositories": {
                "self": {
                    "refName": "refs/heads/main",
                    "version": "abc123def456"
                }
            }
        }
    }
    """

    static let pipelineRunMinimal = """
    {
        "id": 100,
        "name": "Simple Build"
    }
    """

    // MARK: - Work Item JSON

    static let workItem = """
    {
        "id": 42,
        "rev": 5,
        "url": "https://dev.azure.com/myorg/_apis/wit/workItems/42",
        "fields": {
            "System.WorkItemType": "Bug",
            "System.Title": "Fix critical bug",
            "System.State": "Active",
            "System.AssignedTo": {
                "displayName": "John Doe",
                "uniqueName": "john.doe@example.com",
                "imageUrl": "https://dev.azure.com/org/_api/_avatar/user"
            },
            "System.CreatedDate": "2024-01-10T14:30:00.000000Z",
            "System.ChangedDate": "2024-01-15T09:15:00.000000Z",
            "System.CreatedBy": {
                "displayName": "Jane Smith",
                "uniqueName": "jane.smith@example.com",
                "imageUrl": "https://dev.azure.com/org/_api/_avatar/user2"
            },
            "System.Description": "This is a detailed description of the bug",
            "System.Tags": "bug;critical;release-blocker",
            "Microsoft.VSTS.Common.Priority": 1,
            "Microsoft.VSTS.Common.Severity": "1 - Critical"
        }
    }
    """

    static let workItemMinimal = """
    {
        "id": 100,
        "fields": {
            "System.Title": "Simple Task",
            "System.State": "New"
        }
    }
    """

    // MARK: - Commit JSON

    static let commit = """
    {
        "commitId": "abc123def456789",
        "comment": "Fix authentication bug in login flow",
        "author": {
            "name": "John Developer",
            "email": "john@example.com",
            "date": "2024-01-15T10:30:45.123456Z"
        },
        "committer": {
            "name": "John Developer",
            "email": "john@example.com",
            "date": "2024-01-15T10:30:45.123456Z"
        },
        "changeCounts": {
            "Add": 5,
            "Edit": 3,
            "Delete": 1
        },
        "url": "https://dev.azure.com/myorg/project/_git/repo/commit/abc123def456789",
        "remoteUrl": "https://myorg@dev.azure.com/myorg/project/_git/repo/commit/abc123def456789"
    }
    """

    static let commitMinimal = """
    {
        "commitId": "def456",
        "comment": "Quick fix"
    }
    """

    // MARK: - Branch JSON

    static let branch = """
    {
        "name": "refs/heads/feature/new-feature",
        "objectId": "abc123def456789012345678901234567890abcd",
        "creator": {
            "id": "user123",
            "displayName": "Feature Creator",
            "uniqueName": "creator@example.com",
            "url": "https://dev.azure.com/org/_users/user123",
            "imageUrl": "https://dev.azure.com/org/_api/_avatar/user",
            "descriptor": "aad.123"
        },
        "url": "https://dev.azure.com/myorg/project/_git/repo/branch/refs/heads/feature/new-feature",
        "isBaseVersion": false
    }
    """

    static let branchMinimal = """
    {
        "name": "refs/heads/main"
    }
    """

    // MARK: - List Response JSON

    static let pullRequestList = """
    {
        "count": 2,
        "value": [
            {
                "pullRequestId": 1,
                "title": "First PR",
                "status": "active"
            },
            {
                "pullRequestId": 2,
                "title": "Second PR",
                "status": "completed"
            }
        ]
    }
    """

    static let repositoryList = """
    {
        "count": 2,
        "value": [
            {
                "id": "repo1",
                "name": "repo-one"
            },
            {
                "id": "repo2",
                "name": "repo-two"
            }
        ]
    }
    """
}

// MARK: - Azure DevOps Pull Request Tests

final class AzureDevOpsPullRequestTests: XCTestCase {

    func testDecodingPullRequest() throws {
        let json = MockJSON.pullRequest.data(using: .utf8)!
        let pr = try AzureDevOpsDecoding.decode(AzureDevOpsPullRequest.self, from: json)

        XCTAssertEqual(pr.pullRequestId, 123)
        XCTAssertEqual(pr.title, "Add new feature")
        XCTAssertEqual(pr.description, "This PR adds a new feature")
        XCTAssertEqual(pr.status, "active")
        XCTAssertEqual(pr.sourceRefName, "refs/heads/feature-branch")
        XCTAssertEqual(pr.targetRefName, "refs/heads/main")
        XCTAssertEqual(pr.mergeStatus, "succeeded")
        XCTAssertFalse(pr.isDraft ?? true)
        XCTAssertNotNil(pr.createdBy)
        XCTAssertNotNil(pr.repository)
        XCTAssertEqual(pr.reviewers?.count, 1)
        XCTAssertEqual(pr.labels?.count, 1)
    }

    func testDecodingPullRequestMinimal() throws {
        let json = MockJSON.pullRequestMinimal.data(using: .utf8)!
        let pr = try AzureDevOpsDecoding.decode(AzureDevOpsPullRequest.self, from: json)

        XCTAssertEqual(pr.pullRequestId, 456)
        XCTAssertEqual(pr.title, "Minimal PR")
        XCTAssertEqual(pr.status, "active")
        XCTAssertNil(pr.createdBy)
        XCTAssertNil(pr.repository)
    }

    func testDecodingPullRequestReviewer() throws {
        let json = MockJSON.pullRequest.data(using: .utf8)!
        let pr = try AzureDevOpsDecoding.decode(AzureDevOpsPullRequest.self, from: json)

        guard let reviewer = pr.reviewers?.first else {
            XCTFail("Expected at least one reviewer")
            return
        }

        XCTAssertEqual(reviewer.vote, 10)
        XCTAssertTrue(reviewer.isRequired ?? false)
        XCTAssertEqual(reviewer.displayName, "Reviewer One")
        XCTAssertEqual(reviewer.uniqueName, "reviewer@example.com")
    }

    func testDecodingPullRequestLabel() throws {
        let json = MockJSON.pullRequest.data(using: .utf8)!
        let pr = try AzureDevOpsDecoding.decode(AzureDevOpsPullRequest.self, from: json)

        guard let label = pr.labels?.first else {
            XCTFail("Expected at least one label")
            return
        }

        XCTAssertEqual(label.id, "label123")
        XCTAssertEqual(label.name, "enhancement")
    }
}

// MARK: - Azure DevOps Repository Tests

final class AzureDevOpsRepositoryTests: XCTestCase {

    func testDecodingRepository() throws {
        let json = MockJSON.repository.data(using: .utf8)!
        let repo = try AzureDevOpsDecoding.decode(AzureDevOpsRepository.self, from: json)

        XCTAssertEqual(repo.id, "repo-uuid-123")
        XCTAssertEqual(repo.name, "my-awesome-repo")
        XCTAssertEqual(repo.defaultBranch, "refs/heads/main")
        XCTAssertEqual(repo.size, 1024000)
        XCTAssertEqual(repo.isDisabled, false)
        XCTAssertNotNil(repo.project)
        XCTAssertEqual(repo.project?.name, "MyProject")
    }

    func testDecodingRepositoryMinimal() throws {
        let json = MockJSON.repositoryMinimal.data(using: .utf8)!
        let repo = try AzureDevOpsDecoding.decode(AzureDevOpsRepository.self, from: json)

        XCTAssertEqual(repo.id, "repo-uuid")
        XCTAssertEqual(repo.name, "minimal-repo")
        XCTAssertNil(repo.project)
        XCTAssertNil(repo.defaultBranch)
    }

    func testDecodingRepositoryProjectReference() throws {
        let json = MockJSON.repository.data(using: .utf8)!
        let repo = try AzureDevOpsDecoding.decode(AzureDevOpsRepository.self, from: json)

        guard let project = repo.project else {
            XCTFail("Expected project reference")
            return
        }

        XCTAssertEqual(project.id, "project-uuid-456")
        XCTAssertEqual(project.name, "MyProject")
    }
}

// MARK: - Azure DevOps Pipeline Run Tests

final class AzureDevOpsPipelineRunTests: XCTestCase {

    func testDecodingPipelineRun() throws {
        let json = MockJSON.pipelineRun.data(using: .utf8)!
        let run = try AzureDevOpsDecoding.decode(AzureDevOpsPipelineRun.self, from: json)

        XCTAssertEqual(run.id, 789)
        XCTAssertEqual(run.name, "Build and Test")
        XCTAssertEqual(run.state, "completed")
        XCTAssertEqual(run.result, "succeeded")
        XCTAssertNotNil(run.createdDate)
        XCTAssertNotNil(run.finishedDate)
        XCTAssertNotNil(run.pipeline)
    }

    func testDecodingPipelineRunMinimal() throws {
        let json = MockJSON.pipelineRunMinimal.data(using: .utf8)!
        let run = try AzureDevOpsDecoding.decode(AzureDevOpsPipelineRun.self, from: json)

        XCTAssertEqual(run.id, 100)
        XCTAssertEqual(run.name, "Simple Build")
        XCTAssertNil(run.state)
        XCTAssertNil(run.result)
    }

    func testDecodingPipelineReference() throws {
        let json = MockJSON.pipelineRun.data(using: .utf8)!
        let run = try AzureDevOpsDecoding.decode(AzureDevOpsPipelineRun.self, from: json)

        guard let pipeline = run.pipeline else {
            XCTFail("Expected pipeline reference")
            return
        }

        XCTAssertEqual(pipeline.id, 123)
        XCTAssertEqual(pipeline.name, "CI Pipeline")
        XCTAssertEqual(pipeline.folder, "\\\\")
    }

    func testDecodingPipelineResources() throws {
        let json = MockJSON.pipelineRun.data(using: .utf8)!
        let run = try AzureDevOpsDecoding.decode(AzureDevOpsPipelineRun.self, from: json)

        guard let resources = run.resources,
              let repo = resources.repositories?["self"] else {
            XCTFail("Expected resources")
            return
        }

        XCTAssertEqual(repo.refName, "refs/heads/main")
        XCTAssertEqual(repo.version, "abc123def456")
    }
}

// MARK: - Azure DevOps Work Item Tests

final class AzureDevOpsWorkItemTests: XCTestCase {

    func testDecodingWorkItem() throws {
        let json = MockJSON.workItem.data(using: .utf8)!
        let workItem = try AzureDevOpsDecoding.decode(AzureDevOpsWorkItem.self, from: json)

        XCTAssertEqual(workItem.id, 42)
        XCTAssertEqual(workItem.rev, 5)
        XCTAssertNotNil(workItem.fields)
        XCTAssertNotNil(workItem.url)
    }

    func testDecodingWorkItemMinimal() throws {
        let json = MockJSON.workItemMinimal.data(using: .utf8)!
        let workItem = try AzureDevOpsDecoding.decode(AzureDevOpsWorkItem.self, from: json)

        XCTAssertEqual(workItem.id, 100)
        XCTAssertNil(workItem.rev)
        XCTAssertNotNil(workItem.fields)
    }

    func testDecodingWorkItemFields() throws {
        let json = MockJSON.workItem.data(using: .utf8)!
        let workItem = try AzureDevOpsDecoding.decode(AzureDevOpsWorkItem.self, from: json)

        guard let fields = workItem.fields else {
            XCTFail("Expected work item fields")
            return
        }

        XCTAssertEqual(fields.systemWorkItemType, "Bug")
        XCTAssertEqual(fields.systemTitle, "Fix critical bug")
        XCTAssertEqual(fields.systemState, "Active")
        XCTAssertEqual(fields.systemTags, "bug;critical;release-blocker")
        XCTAssertEqual(fields.microsoftVSTSCommonPriority, 1)
    }

    func testDecodingWorkItemAssignedTo() throws {
        let json = MockJSON.workItem.data(using: .utf8)!
        let workItem = try AzureDevOpsDecoding.decode(AzureDevOpsWorkItem.self, from: json)

        guard let fields = workItem.fields,
              let assignedTo = fields.systemAssignedTo else {
            XCTFail("Expected assignedTo")
            return
        }

        XCTAssertEqual(assignedTo.displayName, "John Doe")
        XCTAssertEqual(assignedTo.uniqueName, "john.doe@example.com")
    }

    func testDecodingWorkItemCreatedBy() throws {
        let json = MockJSON.workItem.data(using: .utf8)!
        let workItem = try AzureDevOpsDecoding.decode(AzureDevOpsWorkItem.self, from: json)

        guard let fields = workItem.fields,
              let createdBy = fields.systemCreatedBy else {
            XCTFail("Expected createdBy")
            return
        }

        XCTAssertEqual(createdBy.displayName, "Jane Smith")
        XCTAssertEqual(createdBy.uniqueName, "jane.smith@example.com")
    }
}

// MARK: - Azure DevOps Commit Tests

final class AzureDevOpsCommitTests: XCTestCase {

    func testDecodingCommit() throws {
        let json = MockJSON.commit.data(using: .utf8)!
        let commit = try AzureDevOpsDecoding.decode(AzureDevOpsCommit.self, from: json)

        XCTAssertEqual(commit.commitId, "abc123def456789")
        XCTAssertEqual(commit.comment, "Fix authentication bug in login flow")
        XCTAssertNotNil(commit.author)
        XCTAssertNotNil(commit.committer)
        XCTAssertNotNil(commit.changeCounts)
    }

    func testDecodingCommitMinimal() throws {
        let json = MockJSON.commitMinimal.data(using: .utf8)!
        let commit = try AzureDevOpsDecoding.decode(AzureDevOpsCommit.self, from: json)

        XCTAssertEqual(commit.commitId, "def456")
        XCTAssertEqual(commit.comment, "Quick fix")
        XCTAssertNil(commit.author)
        XCTAssertNil(commit.committer)
    }

    func testDecodingCommitAuthor() throws {
        let json = MockJSON.commit.data(using: .utf8)!
        let commit = try AzureDevOpsDecoding.decode(AzureDevOpsCommit.self, from: json)

        guard let author = commit.author else {
            XCTFail("Expected author")
            return
        }

        XCTAssertEqual(author.name, "John Developer")
        XCTAssertEqual(author.email, "john@example.com")
        XCTAssertNotNil(author.date)
    }

    func testDecodingCommitCommitter() throws {
        let json = MockJSON.commit.data(using: .utf8)!
        let commit = try AzureDevOpsDecoding.decode(AzureDevOpsCommit.self, from: json)

        guard let committer = commit.committer else {
            XCTFail("Expected committer")
            return
        }

        XCTAssertEqual(committer.name, "John Developer")
        XCTAssertEqual(committer.email, "john@example.com")
    }

    func testDecodingCommitChangeCounts() throws {
        let json = MockJSON.commit.data(using: .utf8)!
        let commit = try AzureDevOpsDecoding.decode(AzureDevOpsCommit.self, from: json)

        guard let changeCounts = commit.changeCounts else {
            XCTFail("Expected changeCounts")
            return
        }

        XCTAssertEqual(changeCounts.add, 5)
        XCTAssertEqual(changeCounts.edit, 3)
        XCTAssertEqual(changeCounts.delete, 1)
    }
}

// MARK: - Azure DevOps Branch Tests

final class AzureDevOpsBranchTests: XCTestCase {

    func testDecodingBranch() throws {
        let json = MockJSON.branch.data(using: .utf8)!
        let branch = try AzureDevOpsDecoding.decode(AzureDevOpsBranch.self, from: json)

        XCTAssertEqual(branch.name, "refs/heads/feature/new-feature")
        XCTAssertEqual(branch.objectId, "abc123def456789012345678901234567890abcd")
        XCTAssertEqual(branch.isBaseVersion, false)
        XCTAssertNotNil(branch.creator)
    }

    func testDecodingBranchMinimal() throws {
        let json = MockJSON.branchMinimal.data(using: .utf8)!
        let branch = try AzureDevOpsDecoding.decode(AzureDevOpsBranch.self, from: json)

        XCTAssertEqual(branch.name, "refs/heads/main")
        XCTAssertNil(branch.objectId)
        XCTAssertNil(branch.creator)
    }

    func testDecodingBranchCreator() throws {
        let json = MockJSON.branch.data(using: .utf8)!
        let branch = try AzureDevOpsDecoding.decode(AzureDevOpsBranch.self, from: json)

        guard let creator = branch.creator else {
            XCTFail("Expected creator")
            return
        }

        XCTAssertEqual(creator.id, "user123")
        XCTAssertEqual(creator.displayName, "Feature Creator")
        XCTAssertEqual(creator.uniqueName, "creator@example.com")
        XCTAssertEqual(creator.descriptor, "aad.123")
    }
}

// MARK: - Azure DevOps List Response Tests

final class AzureDevOpsListResponseTests: XCTestCase {

    func testDecodingPullRequestListResponse() throws {
        let json = MockJSON.pullRequestList.data(using: .utf8)!
        let response = try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsPullRequest>.self, from: json)

        XCTAssertEqual(response.count, 2)
        XCTAssertEqual(response.value.count, 2)
        XCTAssertEqual(response.value[0].pullRequestId, 1)
        XCTAssertEqual(response.value[1].pullRequestId, 2)
    }

    func testDecodingRepositoryListResponse() throws {
        let json = MockJSON.repositoryList.data(using: .utf8)!
        let response = try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsRepository>.self, from: json)

        XCTAssertEqual(response.count, 2)
        XCTAssertEqual(response.value.count, 2)
        XCTAssertEqual(response.value[0].name, "repo-one")
        XCTAssertEqual(response.value[1].name, "repo-two")
    }
}

// MARK: - Azure DevOps Identity Ref Tests

final class AzureDevOpsIdentityRefTests: XCTestCase {

    func testDecodingIdentityRef() throws {
        let json = """
        {
            "id": "user123",
            "displayName": "Test User",
            "uniqueName": "test@example.com",
            "url": "https://dev.azure.com/org/_users/user123",
            "imageUrl": "https://dev.azure.com/org/_api/_avatar/user",
            "descriptor": "aad.456"
        }
        """.data(using: .utf8)!

        let identity = try AzureDevOpsDecoding.decode(IdentityRef.self, from: json)

        XCTAssertEqual(identity.id, "user123")
        XCTAssertEqual(identity.displayName, "Test User")
        XCTAssertEqual(identity.uniqueName, "test@example.com")
        XCTAssertEqual(identity.descriptor, "aad.456")
    }
}

// MARK: - Azure DevOps Project Tests

final class AzureDevOpsProjectTests: XCTestCase {

    func testDecodingProject() throws {
        let json = """
        {
            "id": "project-uuid-123",
            "name": "MyProject",
            "description": "A test project",
            "url": "https://dev.azure.com/org/_apis/projects/project-uuid-123",
            "state": "wellFormed",
            "visibility": "private",
            "lastUpdateTime": "2024-01-15T10:30:45.123456Z"
        }
        """.data(using: .utf8)!

        let project = try AzureDevOpsDecoding.decode(AzureDevOpsProject.self, from: json)

        XCTAssertEqual(project.id, "project-uuid-123")
        XCTAssertEqual(project.name, "MyProject")
        XCTAssertEqual(project.description, "A test project")
        XCTAssertEqual(project.state, "wellFormed")
        XCTAssertEqual(project.visibility, "private")
        XCTAssertNotNil(project.lastUpdateTime)
    }
}
