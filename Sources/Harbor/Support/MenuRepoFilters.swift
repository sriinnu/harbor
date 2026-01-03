import HarborCore

enum MenuRepoSelection: String, CaseIterable, Hashable {
    case all
    case pinned
    case work

    var label: String {
        switch self {
        case .all: "All"
        case .pinned: "Pinned"
        case .work: "Work"
        }
    }

    var onlyWith: RepositoryOnlyWith {
        switch self {
        case .all:
            .none
        case .work:
            RepositoryOnlyWith(requireIssues: true, requirePRs: true)
        case .pinned:
            .none
        }
    }

    var isPinnedScope: Bool {
        self == .pinned
    }
}
