import Foundation
@testable import HarborCore
import Testing

struct HarborURLSessionTests {
    @Test
    func configuration_hasNoURLCache_andIgnoresLocalCacheData() {
        let config = HarborURLSession.configuration()
        #expect(config.urlCache == nil)
        #expect(config.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(HarborURLSession.shared.configuration.urlCache == nil)
    }

    @Test
    func coalescingKey_separatesStatusesAndURLs() {
        let url = URL(string: "https://api.github.com/repos/o/r/pulls?per_page=1")!
        let fingerprint = GitHubRequestRunner.accountFingerprint("token-a")
        #expect(GitHubRequestRunner.coalescingKey(url: url, allowedStatuses: [404, 200], token: "token-a")
            == "200,404 \(fingerprint) https://api.github.com/repos/o/r/pulls?per_page=1")
        #expect(GitHubRequestRunner.coalescingKey(url: url, allowedStatuses: [200], token: "token-a")
            != GitHubRequestRunner.coalescingKey(url: url, allowedStatuses: [200, 404], token: "token-a"))
    }
}
