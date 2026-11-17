import Foundation
import HarborCore

struct RepoWebURLBuilder {
    let host: URL

    /// GitHub addresses only: an Azure DevOps key (`azure:…`) has none here.
    func repoURL(fullName: String) -> URL? {
        guard case let .github(owner, name) = RepoKey(fullName) else { return nil }
        return self.repoPathURL(components: [owner, name])
    }

    func repoPathURL(fullName: String, path: String) -> URL? {
        let components = path.split(separator: "/").map(String.init)
        return self.repoPathURL(fullName: fullName, components: components)
    }

    func issuesURL(fullName: String) -> URL? {
        self.repoPathURL(fullName: fullName, components: ["issues"])
    }

    func pullsURL(fullName: String) -> URL? {
        self.repoPathURL(fullName: fullName, components: ["pulls"])
    }

    func actionsURL(fullName: String) -> URL? {
        self.repoPathURL(fullName: fullName, components: ["actions"])
    }

    func discussionsURL(fullName: String) -> URL? {
        self.repoPathURL(fullName: fullName, components: ["discussions"])
    }

    func tagsURL(fullName: String) -> URL? {
        self.repoPathURL(fullName: fullName, components: ["tags"])
    }

    func branchesURL(fullName: String) -> URL? {
        self.repoPathURL(fullName: fullName, components: ["branches"])
    }

    func contributorsURL(fullName: String) -> URL? {
        self.repoPathURL(fullName: fullName, components: ["graphs", "contributors"])
    }

    func releasesURL(fullName: String) -> URL? {
        self.repoPathURL(fullName: fullName, components: ["releases"])
    }

    func tagURL(fullName: String, tag: String) -> URL? {
        self.repoPathURL(fullName: fullName, components: ["tree"] + tag.split(separator: "/").map(String.init))
    }

    func branchURL(fullName: String, branch: String) -> URL? {
        self.repoPathURL(fullName: fullName, components: ["tree"] + branch.split(separator: "/").map(String.init))
    }

    private func repoPathURL(fullName: String, components: [String]) -> URL? {
        guard var url = self.repoURL(fullName: fullName) else { return nil }
        for component in components where component.isEmpty == false {
            url.appendPathComponent(component)
        }
        return url
    }

    private func repoPathURL(components: [String]) -> URL {
        var url = self.host
        for component in components where component.isEmpty == false {
            url.appendPathComponent(component)
        }
        return url
    }
}
