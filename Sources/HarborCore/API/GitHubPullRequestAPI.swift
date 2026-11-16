import Foundation

/// The GraphQL documents behind the pull request pane. Kept as plain strings so tests can
/// pin them exactly.
enum PullRequestGraphQL {
    static let readiness = """
    query PullReadiness($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        squashMergeAllowed
        mergeCommitAllowed
        rebaseMergeAllowed
        pullRequest(number: $number) {
          id
          number
          title
          url
          state
          isDraft
          author { login }
          baseRefName
          headRefName
          headRefOid
          isCrossRepository
          headRef { id }
          mergeable
          mergeStateStatus
          reviewDecision
          viewerCanUpdateBranch
          commits(last: 1) {
            nodes {
              commit {
                statusCheckRollup {
                  contexts(first: 50) {
                    totalCount
                    nodes {
                      __typename
                      ... on CheckRun { name status conclusion detailsUrl isRequired(pullRequestNumber: $number) }
                      ... on StatusContext { context state targetUrl isRequired(pullRequestNumber: $number) }
                    }
                  }
                }
              }
            }
          }
          reviewThreads(first: 50) {
            totalCount
            nodes {
              id
              isResolved
              isOutdated
              path
              line
              viewerCanResolve
              comments(first: 1) { nodes { author { login } bodyText url } }
            }
          }
        }
      }
    }
    """

    static let resolveThread = """
    mutation ResolveThread($id: ID!) {
      resolveReviewThread(input: { threadId: $id }) { thread { id isResolved } }
    }
    """

    static let updateBranch = """
    mutation UpdateBranch($id: ID!, $oid: GitObjectID!) {
      updatePullRequestBranch(input: { pullRequestId: $id, expectedHeadOid: $oid, updateMethod: MERGE }) {
        pullRequest { id }
      }
    }
    """

    static let merge = """
    mutation MergePull($id: ID!, $oid: GitObjectID!, $method: PullRequestMergeMethod!) {
      mergePullRequest(input: { pullRequestId: $id, expectedHeadOid: $oid, mergeMethod: $method }) {
        pullRequest { id state }
      }
    }
    """

    static let deleteBranch = """
    mutation DeleteBranch($id: ID!) {
      deleteRef(input: { refId: $id }) { clientMutationId }
    }
    """
}

// MARK: - Wire models

struct PullReadinessWire: Decodable {
    struct Login: Decodable { let login: String }
    struct Ref: Decodable { let id: String }
    struct Comment: Decodable {
        let author: Login?
        let bodyText: String
        let url: URL?
    }

    struct Thread: Decodable {
        let id: String
        let isResolved: Bool
        let isOutdated: Bool
        let path: String?
        let line: Int?
        let viewerCanResolve: Bool
        let comments: Nodes<Comment>
    }

    /// A check run or a commit status; the fields of the other kind are nil.
    struct Context: Decodable {
        let name: String?
        let status: String?
        let conclusion: String?
        let detailsUrl: URL?
        let context: String?
        let state: String?
        let targetUrl: URL?
        let isRequired: Bool?
    }

    struct Nodes<T: Decodable>: Decodable { let nodes: [T?]? }
    struct Counted<T: Decodable>: Decodable {
        let totalCount: Int?
        let nodes: [T?]?
    }

    struct Rollup: Decodable { let contexts: Counted<Context> }
    struct Commit: Decodable { let statusCheckRollup: Rollup? }
    struct CommitNode: Decodable { let commit: Commit }

    struct Pull: Decodable {
        let id: String
        let number: Int
        let title: String
        let url: URL?
        let state: String
        let isDraft: Bool
        let author: Login?
        let baseRefName: String
        let headRefName: String
        let headRefOid: String
        let isCrossRepository: Bool
        let headRef: Ref?
        let mergeable: String
        let mergeStateStatus: String
        let reviewDecision: String?
        let viewerCanUpdateBranch: Bool
        let commits: Nodes<CommitNode>
        let reviewThreads: Counted<Thread>
    }

    struct Repository: Decodable {
        let squashMergeAllowed: Bool
        let mergeCommitAllowed: Bool
        let rebaseMergeAllowed: Bool
        let pullRequest: Pull?
    }

    struct DataBody: Decodable { let repository: Repository? }
    let data: DataBody

    /// nil when the repository or the pull request does not exist.
    func detail() -> PullRequestDetail? {
        guard let repo = data.repository, let pull = repo.pullRequest else { return nil }
        let contexts = (pull.commits.nodes?.first??.commit.statusCheckRollup?.contexts.nodes ?? []).compactMap { $0 }
        let threads = (pull.reviewThreads.nodes ?? []).compactMap { $0 }.map { thread -> PullReviewThread in
            let first = thread.comments.nodes?.compactMap { $0 }.first
            return PullReviewThread(
                id: thread.id, isResolved: thread.isResolved, isOutdated: thread.isOutdated,
                path: thread.path, line: thread.line, viewerCanResolve: thread.viewerCanResolve,
                authorLogin: first?.author?.login, excerpt: PullReviewThread.excerpt(from: first?.bodyText ?? ""),
                url: first?.url
            )
        }
        return PullRequestDetail(
            id: pull.id, number: pull.number, title: pull.title, url: pull.url,
            state: PullRequestDetail.State(rawValue: pull.state) ?? .open, isDraft: pull.isDraft,
            authorLogin: pull.author?.login, baseRef: pull.baseRefName, headRef: pull.headRefName,
            headOid: pull.headRefOid, isCrossRepository: pull.isCrossRepository, headRefID: pull.headRef?.id,
            mergeable: pull.mergeable, mergeStateStatus: pull.mergeStateStatus, reviewDecision: pull.reviewDecision,
            viewerCanUpdateBranch: pull.viewerCanUpdateBranch,
            checks: contexts.compactMap(Self.check), threads: threads,
            squashMergeAllowed: repo.squashMergeAllowed, mergeCommitAllowed: repo.mergeCommitAllowed,
            rebaseMergeAllowed: repo.rebaseMergeAllowed,
            checksTotal: pull.commits.nodes?.first??.commit.statusCheckRollup?.contexts.totalCount,
            threadsTotal: pull.reviewThreads.totalCount
        )
    }

    private static func check(_ context: Context) -> PullCheck? {
        let required = context.isRequired ?? false
        if let name = context.name {
            let state: PullCheckState
            if context.status != "COMPLETED" {
                state = .pending
            } else {
                switch context.conclusion {
                case "SUCCESS", "NEUTRAL", "SKIPPED": state = .passed
                default: state = .failed
                }
            }
            return PullCheck(name: name, state: state, isRequired: required, url: context.detailsUrl)
        }
        guard let name = context.context else { return nil }
        let state: PullCheckState = switch context.state {
        case "SUCCESS": .passed
        case "PENDING": .pending
        case "EXPECTED": .expected
        default: .failed
        }
        return PullCheck(name: name, state: state, isRequired: required, url: context.targetUrl)
    }
}

/// GraphQL answers 200 with an `errors` array when a mutation is refused; that message is
/// what the user needs to read, so it is passed on as written.
enum GraphQLFailure {
    static func message(in data: Data) -> String? {
        struct Body: Decodable {
            struct Failure: Decodable { let message: String }
            let errors: [Failure]?
            let message: String?
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else { return nil }
        if let first = body.errors?.first { return first.message }
        return body.message
    }
}

// MARK: - Client

public extension GitHubClient {
    func pullRequestDetail(owner: String, name: String, number: Int) async throws -> PullRequestDetail {
        let data = try await self.graphQL.execute(
            query: PullRequestGraphQL.readiness,
            variables: ["owner": .string(owner), "name": .string(name), "number": .int(number)],
            label: "PullReadiness"
        )
        guard let detail = try JSONDecoder().decode(PullReadinessWire.self, from: data).detail() else {
            throw GitHubAPIError.badStatus(code: 404, message: "Pull request #\(number) was not found in \(owner)/\(name).")
        }
        return detail
    }

    func resolveReviewThread(id: String) async throws {
        _ = try await self.graphQL.execute(
            query: PullRequestGraphQL.resolveThread, variables: ["id": .string(id)], label: "ResolveThread"
        )
    }

    /// Merges the base branch into the head; GitHub makes (and signs) the commit.
    func updatePullRequestBranch(_ pull: PullRequestDetail) async throws {
        _ = try await self.graphQL.execute(
            query: PullRequestGraphQL.updateBranch,
            variables: ["id": .string(pull.id), "oid": .string(pull.headOid)],
            label: "UpdateBranch"
        )
    }

    func mergePullRequest(_ pull: PullRequestDetail, method: PullMergeMethod) async throws {
        _ = try await self.graphQL.execute(
            query: PullRequestGraphQL.merge,
            variables: ["id": .string(pull.id), "oid": .string(pull.headOid), "method": .string(method.rawValue)],
            label: "MergePull"
        )
    }

    func deleteBranch(refID: String) async throws {
        _ = try await self.graphQL.execute(
            query: PullRequestGraphQL.deleteBranch, variables: ["id": .string(refID)], label: "DeleteBranch"
        )
    }
}
