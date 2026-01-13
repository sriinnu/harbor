import Foundation

enum AzureDevOpsRecentDecoders {
    // MARK: - Pull Requests

    static func decodeRecentPullRequests(from data: Data) throws -> [RepoPullRequestSummary] {
        let response = try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsPullRequest>.self, from: data)
        return response.value.map { pr in
            let isDraft = pr.isDraft ?? false
            let labels = (pr.labels ?? []).map { label in
                RepoIssueLabel(name: label.name, colorHex: "0078d4") // Azure DevOps blue
            }

            let sourceBranch = pr.sourceRefName?.replacingOccurrences(of: "refs/heads/", with: "")
            let targetBranch = pr.targetRefName?.replacingOccurrences(of: "refs/heads/", with: "")

            return RepoPullRequestSummary(
                number: pr.pullRequestId,
                title: pr.title,
                url: URL(string: pr.url ?? "")!,
                updatedAt: pr.creationDate ?? Date.distantPast,
                authorLogin: pr.createdBy?.uniqueName ?? pr.createdBy?.displayName,
                authorAvatarURL: pr.createdBy?.imageUrl.flatMap { URL(string: $0) },
                isDraft: isDraft,
                commentCount: 0, // Azure DevOps doesn't provide comment count in list
                reviewCommentCount: pr.reviewers?.count ?? 0,
                labels: labels,
                headRefName: sourceBranch,
                baseRefName: targetBranch
            )
        }
    }

    // MARK: - Work Items (Issues)

    static func decodeRecentWorkItems(from data: Data) throws -> [RepoIssueSummary] {
        let response = try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsWorkItem>.self, from: data)
        return response.value.compactMap { workItem in
            guard let fields = workItem.fields,
                  let title = fields.systemTitle,
                  let url = URL(string: workItem.url ?? "") else {
                return nil
            }

            let tags = fields.systemTags?.split(separator: ";").map { tag in
                RepoIssueLabel(name: String(tag.trimmingCharacters(in: .whitespaces)), colorHex: "0078d4")
            } ?? []

            let assignees = fields.systemAssignedTo.map { [$0.uniqueName ?? $0.displayName ?? ""] } ?? []

            return RepoIssueSummary(
                number: workItem.id,
                title: title,
                url: url,
                updatedAt: fields.systemChangedDate ?? Date.distantPast,
                authorLogin: fields.systemCreatedBy?.uniqueName ?? fields.systemCreatedBy?.displayName,
                authorAvatarURL: fields.systemCreatedBy?.imageUrl.flatMap { URL(string: $0) },
                assigneeLogins: assignees.compactMap { $0 },
                commentCount: 0, // Not available in basic work item query
                labels: tags
            )
        }
    }

    // MARK: - Pipeline Runs

    static func decodeRecentPipelineRuns(from data: Data) throws -> [RepoWorkflowRunSummary] {
        let response = try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsPipelineRun>.self, from: data)
        return response.value.compactMap { run -> RepoWorkflowRunSummary? in
            guard let urlString = run.url, let url = URL(string: urlString) else {
                return nil
            }

            let status = self.mapPipelineStatus(state: run.state, result: run.result)
            let branch = run.resources?.repositories?.values.first?.refName?
                .replacingOccurrences(of: "refs/heads/", with: "")

            let name = run.name ?? run.pipeline?.name ?? "Pipeline Run #\(run.id)"
            let updatedAt = run.finishedDate ?? run.createdDate ?? Date.distantPast

            return RepoWorkflowRunSummary(
                name: name,
                url: url,
                updatedAt: updatedAt,
                status: status,
                conclusion: run.result,
                branch: branch,
                event: nil, // Azure DevOps doesn't have a direct equivalent
                actorLogin: nil, // Not readily available in pipeline run response
                actorAvatarURL: nil,
                runNumber: run.id
            )
        }
    }

    // MARK: - Commits

    static func decodeRecentCommits(from data: Data) throws -> [RepoCommitSummary] {
        let response = try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsCommit>.self, from: data)
        return response.value.compactMap { commit in
            let message = commit.comment?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = message.split(whereSeparator: \.isNewline).first.map(String.init) ?? message

            guard let url = URL(string: commit.remoteUrl ?? commit.url ?? "") else {
                return nil
            }

            return RepoCommitSummary(
                sha: commit.commitId,
                message: title.isEmpty ? "Commit" : title,
                url: url,
                authoredAt: commit.author?.date ?? Date.distantPast,
                authorName: commit.author?.name,
                authorLogin: commit.author?.email,
                authorAvatarURL: nil
            )
        }
    }

    // MARK: - Branches

    static func decodeRecentBranches(from data: Data) throws -> [RepoBranchSummary] {
        let response = try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsBranch>.self, from: data)
        return response.value.map { branch in
            let branchName = branch.name.replacingOccurrences(of: "refs/heads/", with: "")
            return RepoBranchSummary(
                name: branchName,
                commitSHA: branch.objectId ?? "",
                isProtected: false // Would need separate API call to determine
            )
        }
    }

    // MARK: - Repositories

    static func decodeRepositories(from data: Data) throws -> [AzureDevOpsRepository] {
        let response = try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsRepository>.self, from: data)
        return response.value
    }

    // MARK: - Projects

    static func decodeProjects(from data: Data) throws -> [AzureDevOpsProject] {
        let response = try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsProject>.self, from: data)
        return response.value
    }

    // MARK: - Pushes (for activity tracking)

    static func decodeRecentPushes(from data: Data) throws -> [RepoCommitSummary] {
        let response = try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsPush>.self, from: data)
        return response.value.flatMap { push -> [RepoCommitSummary] in
            guard let commits = push.commits else { return [] }
            return commits.compactMap { commitRef in
                guard let url = URL(string: push.url ?? "") else { return nil }
                let message = commitRef.comment?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let title = message.split(whereSeparator: \.isNewline).first.map(String.init) ?? message

                return RepoCommitSummary(
                    sha: commitRef.commitId,
                    message: title.isEmpty ? "Commit" : title,
                    url: url,
                    authoredAt: push.date ?? Date.distantPast,
                    authorName: push.pushedBy?.displayName,
                    authorLogin: push.pushedBy?.uniqueName,
                    authorAvatarURL: push.pushedBy?.imageUrl.flatMap { URL(string: $0) }
                )
            }
        }
    }

    // MARK: - Helper Functions

    private static func mapPipelineStatus(state: String?, result: String?) -> CIStatus {
        guard let state = state?.lowercased() else {
            return .unknown
        }

        switch state {
        case "inprogress", "notstarted":
            return .pending
        case "canceling":
            return .pending
        case "completed":
            guard let result = result?.lowercased() else {
                return .unknown
            }
            switch result {
            case "succeeded":
                return .passing
            case "failed":
                return .failing
            case "canceled":
                return .failing
            case "partiallysucceeded":
                return .passing
            default:
                return .unknown
            }
        default:
            return .unknown
        }
    }

    private static func formatWorkItemType(_ type: String?) -> String {
        guard let type = type else { return "Work Item" }
        // Convert "Bug", "Task", "User Story" etc. to readable format
        return type
    }
}
