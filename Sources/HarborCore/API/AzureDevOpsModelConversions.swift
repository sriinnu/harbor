import Foundation

// MARK: - AzurePullRequest Conversion

extension AzurePullRequest {
    static func from(api: AzureDevOpsPullRequest, organization: String, project: String, repository: String) -> AzurePullRequest {
        let status = AzurePullRequestStatus(rawValue: api.status.lowercased()) ?? .notSet
        let mergeStatus = AzureMergeStatus(rawValue: api.mergeStatus?.lowercased() ?? "notset") ?? .notSet

        let createdBy = AzureIdentity(
            id: api.createdBy?.id,
            displayName: api.createdBy?.displayName ?? "Unknown",
            uniqueName: api.createdBy?.uniqueName,
            imageURL: api.createdBy?.imageUrl.flatMap { URL(string: $0) },
            descriptor: api.createdBy?.descriptor
        )

        let repoRef = AzureRepositoryRef(
            id: api.repository?.id ?? "",
            name: api.repository?.name ?? repository,
            url: nil
        )

        let reviewers = (api.reviewers ?? []).map { reviewer in
            AzureReviewer(
                id: reviewer.reviewerUrl ?? UUID().uuidString,
                displayName: reviewer.displayName ?? "Unknown",
                uniqueName: reviewer.uniqueName,
                imageURL: reviewer.imageUrl.flatMap { URL(string: $0) },
                vote: reviewer.vote ?? 0,
                isRequired: reviewer.isRequired ?? false,
                isFlagged: false
            )
        }

        let labels = (api.labels ?? []).map { label in
            AzureLabel(id: label.id ?? UUID().uuidString, name: label.name, active: true)
        }

        let webURL = URL(string: "https://dev.azure.com/\(organization)/\(project)/_git/\(repository)/pullrequest/\(api.pullRequestId)")!

        return AzurePullRequest(
            id: "\(api.pullRequestId)",
            pullRequestId: api.pullRequestId,
            title: api.title,
            description: api.description,
            status: status,
            mergeStatus: mergeStatus,
            createdBy: createdBy,
            creationDate: api.creationDate ?? Date(),
            closedDate: api.closedDate,
            sourceRefName: api.sourceRefName ?? "",
            targetRefName: api.targetRefName ?? "",
            repository: repoRef,
            url: webURL,
            isDraft: api.isDraft ?? false,
            reviewers: reviewers,
            labels: labels,
            workItemRefs: []
        )
    }
}

// MARK: - AzureRepository Conversion

extension AzureRepository {
    static func from(apiRepo: AzureDevOpsRepository, organization: String, stats: AzureRepositoryStats? = nil) -> AzureRepository {
        let webURL: URL
        if let webUrlString = apiRepo.webUrl, let url = URL(string: webUrlString) {
            webURL = url
        } else {
            let projectName = apiRepo.project?.name ?? ""
            webURL = URL(string: "https://dev.azure.com/\(organization)/\(projectName)/_git/\(apiRepo.name)")!
        }

        return AzureRepository(
            id: apiRepo.id,
            name: apiRepo.name,
            project: apiRepo.project?.name ?? "",
            organization: organization,
            defaultBranch: apiRepo.defaultBranch?.replacingOccurrences(of: "refs/heads/", with: ""),
            size: apiRepo.size,
            isDisabled: apiRepo.isDisabled ?? false,
            webURL: webURL,
            remoteURL: apiRepo.remoteUrl.flatMap { URL(string: $0) }
        )
    }

    static func from(
        apiRepo: AzureDevOpsRepository,
        organization: String,
        stats: AzureRepositoryStats?,
        openPulls: Int = 0,
        latestActivity: RepoCommitSummary? = nil,
        error: String? = nil,
        rateLimitedUntil: Date? = nil
    ) -> AzureRepository {
        var repo = self.from(apiRepo: apiRepo, organization: organization)
        return repo
    }
}
