import Foundation
import HarborCore
import Observation

/// One of a repo's lists (issues, pull requests, releases, runs, branches), loaded with a
/// single GraphQL query when its pane opens and thrown away when it closes. In memory only.
@MainActor
@Observable
final class RepoListModel {
    enum State: Equatable {
        case loading
        case loaded(RepoListPage)
        case failed(String)
    }

    let kind: RepoListKind
    let owner: String
    let name: String
    private(set) var state = State.loading

    init(kind: RepoListKind, fullName: String) {
        self.kind = kind
        let parts = fullName.split(separator: "/", maxSplits: 1).map(String.init)
        self.owner = parts.first ?? ""
        self.name = parts.count == 2 ? parts[1] : ""
    }

    /// Debug snapshots only: a model that shows fixed rows and never touches GitHub.
    static func preview(kind: RepoListKind, page: RepoListPage) -> RepoListModel {
        let model = RepoListModel(kind: kind, fullName: "sriinnu/harbor")
        model.state = .loaded(page)
        model.isPreview = true
        return model
    }

    private var isPreview = false

    func load() async {
        guard !self.isPreview else { return }
        guard let client = RepoHealthService.client else {
            self.state = .failed("Sign in to GitHub to see \(self.kind.title.lowercased()).")
            return
        }
        guard !self.owner.isEmpty, !self.name.isEmpty else {
            self.state = .failed("This repository has no owner/name.")
            return
        }
        self.state = .loading
        do {
            let page = try await client.repoList(kind: self.kind, owner: self.owner, name: self.name)
            guard !Task.isCancelled else { return }
            self.state = .loaded(page)
        } catch {
            guard !Task.isCancelled, let message = error.reportableMessage else { return }
            self.state = .failed(message)
        }
    }
}
