import Foundation
@testable import HarborCLI
import HarborCore
import Testing

struct CLIEndpointTests {
    private func storage(active: String?) throws -> InMemoryTokenStorage {
        let storage = InMemoryTokenStorage()
        if let active { try storage.setActiveAccount(active) }
        return storage
    }

    @Test
    func anEnterpriseAccountSendsItsTokenToItsOwnHostNotTheSettingsHost() throws {
        let storage = try storage(active: GitHubAccountKey.make(login: "Alice", host: "ghe.example.com"))
        let settings = UserSettings() // the CLI last signed in to github.com
        let endpoint = CLIEndpoint.resolve(storage: storage, settings: settings)
        #expect(endpoint.host.absoluteString == "https://ghe.example.com")
        #expect(endpoint.apiHost.absoluteString == "https://ghe.example.com/api/v3")
        #expect(endpoint.accountKey == "github:alice@ghe.example.com")
    }

    @Test
    func aGitHubDotComAccountIgnoresAnEnterpriseHostLeftInSettings() throws {
        let storage = try storage(active: GitHubAccountKey.make(login: "bob", host: "github.com"))
        var settings = UserSettings()
        settings.enterpriseHost = URL(string: "https://ghe.example.com")
        let endpoint = CLIEndpoint.resolve(storage: storage, settings: settings)
        #expect(endpoint.host.absoluteString == "https://github.com")
        #expect(endpoint.apiHost == HarborAuthDefaults.apiHost)
    }

    @Test
    func withNoActivePointerTheSettingsStillNameTheHost() throws {
        var settings = UserSettings()
        settings.enterpriseHost = URL(string: "https://ghe.example.com")
        let endpoint = CLIEndpoint.resolve(storage: try storage(active: nil), settings: settings)
        #expect(endpoint.host.absoluteString == "https://ghe.example.com")
        #expect(endpoint.apiHost.absoluteString == "https://ghe.example.com/api/v3")
        #expect(endpoint.accountKey == nil)
    }
}
