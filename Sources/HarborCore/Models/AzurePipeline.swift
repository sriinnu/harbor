import Foundation

/// Azure DevOps pipeline model conforming to ProviderPipeline
public struct AzurePipeline: ProviderPipeline {
    public let id: String
    public let name: String
    public var status: CIStatus
    public let runNumber: Int?
    public let createdAt: Date?
    public var updatedAt: Date?
    public let webURL: URL
    public let providerType: ProviderType

    // Additional Azure-specific properties
    public let azureStatus: AzurePipelineStatus
    public let result: String?
    public let queueTime: Date?
    public let finishTime: Date?
    public let branch: String?
    public let commitId: String?
    public let folder: String?
    public let uri: String?
    public let definitionId: Int?

    public init(
        id: String,
        name: String,
        status: CIStatus,
        runNumber: Int?,
        createdAt: Date?,
        updatedAt: Date?,
        webURL: URL,
        azureStatus: AzurePipelineStatus,
        result: String?,
        queueTime: Date?,
        finishTime: Date?,
        branch: String?,
        commitId: String?,
        folder: String?,
        uri: String?,
        definitionId: Int?
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.runNumber = runNumber
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.webURL = webURL
        self.providerType = .azureDevOps
        self.azureStatus = azureStatus
        self.result = result
        self.queueTime = queueTime
        self.finishTime = finishTime
        self.branch = branch
        self.commitId = commitId
        self.folder = folder
        self.uri = uri
        self.definitionId = definitionId
    }

    // MARK: - Computed Properties

    /// Whether the pipeline is currently running
    public var isRunning: Bool {
        azureStatus == .running
    }

    /// Whether the pipeline is pending
    public var isPending: Bool {
        azureStatus == .pending
    }

    /// Whether the pipeline succeeded
    public var isSucceeded: Bool {
        azureStatus == .succeeded
    }

    /// Whether the pipeline failed
    public var isFailed: Bool {
        azureStatus == .failed
    }

    /// Whether the pipeline was cancelled
    public var isCancelled: Bool {
        azureStatus == .cancelled
    }

    /// Duration in seconds (if completed)
    public var durationSeconds: TimeInterval? {
        guard let finish = finishTime, let start = createdAt ?? queueTime else { return nil }
        return finish.timeIntervalSince(start)
    }

    /// Duration formatted as a string (e.g., "2m 30s")
    public var durationDescription: String? {
        guard let duration = durationSeconds else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration)
    }

    // MARK: - Conversion to Domain Model

    /// Converts to the domain model
    public func toDomain() -> AzurePipelineDomain {
        AzurePipelineDomain(
            id: id,
            name: name,
            status: status,
            runNumber: runNumber,
            createdAt: createdAt,
            updatedAt: updatedAt,
            webURL: webURL,
            azureStatus: azureStatus,
            result: result,
            branch: branch,
            folder: folder
        )
    }

    /// Converts to the common RepoWorkflowRunSummary domain model
    public func toWorkflowRunSummary() -> RepoWorkflowRunSummary {
        toDomain().toWorkflowRunSummary()
    }

    // MARK: - Factory Methods

    /// Creates an AzurePipeline from an API model
    public static func from(apiModel: AzureDevOpsPipelineRun, project: String, organization: String) -> AzurePipeline {
        let azureStatus = AzurePipelineStatus(from: apiModel.state, result: apiModel.result)
        let status = azureStatus.toCIStatus
        let runNumber = apiModel.id

        let webURL: URL
        if let urlString = apiModel.url, let url = URL(string: urlString) {
            webURL = url
        } else {
            webURL = URL(string: "https://dev.azure.com/\(organization)/\(project)/_build/results?buildId=\(apiModel.id)")!
        }

        let branch = apiModel.resources?.repositories?["self"]?.refName?
            .replacingOccurrences(of: "refs/heads/", with: "")

        return AzurePipeline(
            id: "\(apiModel.id)",
            name: apiModel.name ?? "Pipeline #\(apiModel.id)",
            status: status,
            runNumber: runNumber,
            createdAt: apiModel.createdDate,
            updatedAt: apiModel.finishedDate ?? apiModel.createdDate,
            webURL: webURL,
            azureStatus: azureStatus,
            result: apiModel.result,
            queueTime: nil,
            finishTime: apiModel.finishedDate,
            branch: branch,
            commitId: nil,
            folder: apiModel.pipeline?.folder,
            uri: apiModel.url,
            definitionId: apiModel.pipeline?.id
        )
    }

    // MARK: - Equatable

    public static func == (lhs: AzurePipeline, rhs: AzurePipeline) -> Bool {
        lhs.id == rhs.id
    }
}

/// Azure DevOps pipeline definition
public struct AzurePipelineDefinition: Codable, Sendable {
    public let id: Int
    public let name: String
    public let folder: String?
    public let url: String?
    public let revision: Int?
    public let queueStatus: String?

    public init(
        id: Int,
        name: String,
        folder: String? = nil,
        url: String? = nil,
        revision: Int? = nil,
        queueStatus: String? = nil
    ) {
        self.id = id
        self.name = name
        self.folder = folder
        self.url = url
        self.revision = revision
        self.queueStatus = queueStatus
    }

    /// Whether the pipeline is enabled
    public var isEnabled: Bool {
        queueStatus?.lowercased() == "enabled"
    }
}

/// Azure DevOps pipeline reference
public struct AzurePipelineReference: Codable, Sendable {
    public let id: Int
    public let name: String?
    public let folder: String?

    public init(id: Int, name: String? = nil, folder: String? = nil) {
        self.id = id
        self.name = name
        self.folder = folder
    }
}

/// Azure DevOps build artifact
public struct AzureBuildArtifact: Codable, Sendable {
    public let id: Int
    public let name: String
    public let resource: ArtifactResource?

    public init(id: Int, name: String, resource: ArtifactResource? = nil) {
        self.id = id
        self.name = name
        self.resource = resource
    }

    public struct ArtifactResource: Codable, Sendable {
        public let data: String?
        public let url: URL?
        public let downloadUrl: URL?

        public init(data: String? = nil, url: URL? = nil, downloadUrl: URL? = nil) {
            self.data = data
            self.url = url
            self.downloadUrl = downloadUrl
        }
    }
}

/// Azure DevOps YAML pipeline approval
public struct AzurePipelineApproval: Codable, Sendable {
    public let id: Int
    public let type: String?
    public let status: String?
    public let requestedFor: AzureIdentity?
    public let createdOn: Date?
    public let approvalStep: ApprovalStep?

    public init(
        id: Int,
        type: String? = nil,
        status: String? = nil,
        requestedFor: AzureIdentity? = nil,
        createdOn: Date? = nil,
        approvalStep: ApprovalStep? = nil
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.requestedFor = requestedFor
        self.createdOn = createdOn
        self.approvalStep = approvalStep
    }

    public struct ApprovalStep: Codable, Sendable {
        public let id: Int
        public let name: String?
        public let order: Int?
        public let assignedTo: AzureIdentity?

        public init(id: Int, name: String? = nil, order: Int? = nil, assignedTo: AzureIdentity? = nil) {
            self.id = id
            self.name = name
            self.order = order
            self.assignedTo = assignedTo
        }
    }
}

/// Extension to AzureDevOpsPipelineRun for easier conversion
extension AzureDevOpsPipelineRun {
    /// Converts to an AzurePipeline domain model
    public func toPipeline(project: String, organization: String) -> AzurePipeline {
        AzurePipeline.from(apiModel: self, project: project, organization: organization)
    }
}
