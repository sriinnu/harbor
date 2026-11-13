import Foundation

/// The reads and deletes behind "Clean up old runs". Needs the `repo` scope Harbor already
/// asks for, and write access to the repo; without it GitHub answers 403.
extension GitHubRestAPI {
    private static let runPageSize = 100
    /// A safety stop: 50 pages of 100 is 5,000 items, far past any sane cleanup.
    private static let maxRunPages = 50

    func listWorkflows(owner: String, name: String) async throws -> [WorkflowInfo] {
        let pages = try await self.pages(owner: owner, name: name, path: "actions/workflows")
        return try pages.flatMap { try GitHubDecoding.decode(WorkflowsResponse.self, from: $0).workflows }
            .map { WorkflowInfo(id: $0.id, state: $0.state) }
    }

    func listWorkflowRuns(owner: String, name: String) async throws -> [WorkflowRunInfo] {
        let pages = try await self.pages(owner: owner, name: name, path: "actions/runs")
        return try pages.flatMap { try GitHubDecoding.decode(RunsResponse.self, from: $0).workflowRuns }
            .map { WorkflowRunInfo(id: $0.id, workflowID: $0.workflowID, status: $0.status ?? "", createdAt: $0.createdAt) }
    }

    func deleteWorkflowRun(owner: String, name: String, id: Int) async throws {
        let token = try await self.tokenProvider()
        let url = await self.apiHost().appending(path: "/repos/\(owner)/\(name)/actions/runs/\(id)")
        try await self.requestRunner.delete(url: url, token: token)
    }

    /// Every page of a list endpoint, following the `next` link GitHub returns.
    private func pages(owner: String, name: String, path: String) async throws -> [Data] {
        let token = try await self.tokenProvider()
        let base = await self.apiHost().appending(path: "/repos/\(owner)/\(name)/\(path)")
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        components.queryItems = [URLQueryItem(name: "per_page", value: String(Self.runPageSize))]
        var next = components.url
        var pages: [Data] = []
        while let url = next, pages.count < Self.maxRunPages {
            let (data, response) = try await self.authorizedGet(url: url, token: token)
            pages.append(data)
            next = GitHubPagination.nextURL(from: response.value(forHTTPHeaderField: "Link") ?? "")
        }
        return pages
    }
}

private struct WorkflowsResponse: Decodable {
    struct Workflow: Decodable {
        let id: Int
        let state: String
    }

    let workflows: [Workflow]
}

private struct RunsResponse: Decodable {
    struct Run: Decodable {
        let id: Int
        let workflowID: Int
        let status: String?
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id, status
            case workflowID = "workflow_id"
            case createdAt = "created_at"
        }
    }

    let workflowRuns: [Run]

    enum CodingKeys: String, CodingKey { case workflowRuns = "workflow_runs" }
}
