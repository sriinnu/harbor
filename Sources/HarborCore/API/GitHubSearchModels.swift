import Foundation

struct SearchResponse: Decodable {
    let items: [RepoItem]
}

struct RepoItem: Decodable {
    let id: Int
    let name: String
    let fullName: String
    let fork: Bool
    let archived: Bool
    let openIssuesCount: Int
    let stargazersCount: Int
    let forksCount: Int
    let pushedAt: Date?
    let owner: Owner

    struct Owner: Decodable { let login: String }

    enum CodingKeys: String, CodingKey {
        case id, name
        case fullName = "full_name"
        case fork
        case archived
        case openIssuesCount = "open_issues_count"
        case stargazersCount = "stargazers_count"
        case forksCount = "forks_count"
        case pushedAt = "pushed_at"
        case owner
    }
}

struct SearchIssuesResponse: Decodable {
    let totalCount: Int

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
    }
}

struct PullRequestListItem: Decodable {
    let id: Int
}
