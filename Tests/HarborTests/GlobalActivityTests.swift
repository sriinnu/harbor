import Foundation
@testable import HarborCore
import Testing

struct GlobalActivityTests {
    @Test
    func repoEventActivityEventFromRepo_buildsEvent() throws {
        let data = Data("""
        {
          "type": "PushEvent",
          "actor": { "login": "steipete", "avatar_url": "https://example.com/avatar.png" },
          "repo": { "name": "steipete/RepoBar", "url": "https://api.github.com/repos/steipete/RepoBar" },
          "payload": { "head": "abc123" },
          "created_at": "2024-01-01T00:00:00Z"
        }
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(RepoEvent.self, from: data)

        let activity = event.activityEventFromRepo()

        #expect(activity != nil)
        #expect(activity?.actor == "steipete")
        #expect(activity?.eventType == "PushEvent")
        #expect(activity?.url.absoluteString.contains("https://github.com/steipete/RepoBar/commit/abc123") == true)
    }

    @Test
    func repoEventActivityEventFromRepo_rejectsInvalidRepoName() throws {
        let data = Data("""
        {
          "type": "PushEvent",
          "actor": { "login": "steipete", "avatar_url": "https://example.com/avatar.png" },
          "repo": { "name": "RepoBar", "url": "https://api.github.com/repos/steipete/RepoBar" },
          "payload": { "head": "abc123" },
          "created_at": "2024-01-01T00:00:00Z"
        }
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(RepoEvent.self, from: data)

        #expect(event.activityEventFromRepo() == nil)
    }

    @Test
    func globalActivityScope_labels() {
        #expect(GlobalActivityScope.allActivity.label == "All activity")
        #expect(GlobalActivityScope.myActivity.label == "My activity")
    }
}
