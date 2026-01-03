import Foundation
@testable import HarborCore
import Testing

struct RecentRepoItemsDecodingTests {
    @Test
    func issuesEndpointFiltersOutPullRequests() throws {
        let json = """
        [
          {
            "number": 1,
            "title": "Issue one",
            "html_url": "https://github.com/acme/widget/issues/1",
            "updated_at": "2025-12-28T10:00:00Z",
            "comments": 3,
            "labels": [
              { "name": "bug", "color": "d73a4a" },
              { "name": "good first issue", "color": "7057ff" }
            ],
            "assignees": [
              { "login": "steipete", "avatar_url": "https://avatars.githubusercontent.com/u/583?v=4" }
            ],
            "user": { "login": "alice", "avatar_url": "https://avatars.githubusercontent.com/u/1?v=4" }
          },
          {
            "number": 2,
            "title": "PR (should not appear as issue)",
            "html_url": "https://github.com/acme/widget/pull/2",
            "updated_at": "2025-12-28T12:00:00Z",
            "comments": 0,
            "labels": [],
            "user": { "login": "bob", "avatar_url": "https://avatars.githubusercontent.com/u/2?v=4" },
            "pull_request": {}
          }
        ]
        """

        let items = try GitHubClient.decodeRecentIssues(from: Data(json.utf8))
        #expect(items.count == 1)
        #expect(items.first?.number == 1)
        #expect(items.first?.authorLogin == "alice")
        #expect(items.first?.authorAvatarURL != nil)
        #expect(items.first?.commentCount == 3)
        #expect(items.first?.labels.count == 2)
        #expect(items.first?.assigneeLogins == ["steipete"])
    }

    @Test
    func pullsEndpointMapsDraftAndAuthor() throws {
        let json = """
        [
          {
            "number": 42,
            "title": "Add repo submenu items",
            "html_url": "https://github.com/acme/widget/pull/42",
            "updated_at": "2025-12-27T09:30:00Z",
            "draft": true,
            "comments": 2,
            "review_comments": 5,
            "labels": [
              { "name": "bug", "color": "d73a4a" }
            ],
            "head": { "ref": "feature/menu-rows" },
            "base": { "ref": "main" },
            "user": { "login": "steipete", "avatar_url": "https://avatars.githubusercontent.com/u/583?v=4" }
          }
        ]
        """

        let items = try GitHubClient.decodeRecentPullRequests(from: Data(json.utf8))
        #expect(items.count == 1)
        #expect(items.first?.number == 42)
        #expect(items.first?.isDraft == true)
        #expect(items.first?.authorLogin == "steipete")
        #expect(items.first?.authorAvatarURL != nil)
        #expect(items.first?.commentCount == 2)
        #expect(items.first?.reviewCommentCount == 5)
        #expect(items.first?.labels.first?.name == "bug")
        #expect(items.first?.headRefName == "feature/menu-rows")
        #expect(items.first?.baseRefName == "main")
    }

    @Test
    func releasesEndpointSkipsDraftAndAggregatesAssets() throws {
        let json = """
        [
          {
            "name": "v1.2.3",
            "tag_name": "v1.2.3",
            "html_url": "https://github.com/acme/widget/releases/tag/v1.2.3",
            "published_at": "2025-12-28T10:00:00Z",
            "created_at": "2025-12-28T09:50:00Z",
            "draft": false,
            "prerelease": true,
            "author": { "login": "alice", "avatar_url": "https://avatars.githubusercontent.com/u/1?v=4" },
            "assets": [
              { "download_count": 10 },
              { "download_count": 5 }
            ]
          },
          {
            "name": "Draft release",
            "tag_name": "v1.2.4",
            "html_url": "https://github.com/acme/widget/releases/tag/v1.2.4",
            "draft": true
          }
        ]
        """

        let items = try GitHubClient.decodeRecentReleases(from: Data(json.utf8))
        #expect(items.count == 1)
        #expect(items.first?.tag == "v1.2.3")
        #expect(items.first?.name == "v1.2.3")
        #expect(items.first?.isPrerelease == true)
        #expect(items.first?.authorLogin == "alice")
        #expect(items.first?.authorAvatarURL != nil)
        #expect(items.first?.assetCount == 2)
        #expect(items.first?.downloadCount == 15)
    }
}
