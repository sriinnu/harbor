import Foundation
@testable import HarborCore
import Testing

/// Azure DevOps Connect: the PAT is checked against `{org}/_apis/connectionData`, and it is
/// stored only when Azure accepts it. The token is a made-up string; the in-memory store
/// stands in for the Keychain.
struct AzureDevOpsConnectTests {
    private static let pat = "azure-test-pat-0001"

    private func auth(_ host: String, _ route: @escaping StubURLProtocol.Route) -> (AzureDevOpsAuth, AzureDevOpsPATStore) {
        StubURLProtocol.register(host: host, route: route)
        let store = AzureDevOpsPATStore(service: "test.ado", store: InMemorySecretStore())
        let auth = AzureDevOpsAuth(patStore: store, host: URL(string: "https://\(host)")!, session: StubURLProtocol.session())
        return (auth, store)
    }

    private func failure(_ auth: AzureDevOpsAuth, org: String = "acme") async -> String? {
        do {
            _ = try await auth.connect(pat: Self.pat, organization: org)
            return nil
        } catch { return (error as? AzureDevOpsAuthError)?.errorDescription }
    }

    @Test
    func anAcceptedTokenIsCheckedAtConnectionDataAndStored() async throws {
        let host = "ado-ok.stub.test"
        let (auth, store) = self.auth(host) { seen in
            guard seen.path == "/acme/_apis/connectionData" else { return .init(status: 404) }
            return .init(body: #"""
            {"authenticatedUser":{"id":"u-1","providerDisplayName":"Sri",
             "properties":{"Account":{"$type":"System.String","$value":"sri@example.com"}}}}
            """#)
        }
        let result = try await auth.connect(pat: Self.pat, organization: "acme")
        #expect(result.user == AzureDevOpsUser(id: "u-1", displayName: "Sri", uniqueName: "sri@example.com", emailAddress: "sri@example.com"))
        #expect(result.organization == "acme")
        let basic = "Basic " + Data(":\(Self.pat)".utf8).base64EncodedString()
        #expect(StubURLProtocol.requests(host: host) == [.init(path: "/acme/_apis/connectionData", query: nil, authorization: basic)])
        #expect(try store.token(forOrganization: "acme") == Self.pat)
    }

    @Test
    func aRejectedTokenIsNamedAndNotStored() async {
        let (auth, store) = self.auth("ado-401.stub.test") { _ in .init(status: 401) }
        #expect(await self.failure(auth) == "Azure DevOps rejected this token. Check it hasn't expired and was made for this organization.")
        #expect(store.hasToken(forOrganization: "acme") == false)
    }

    @Test
    func theSignInPageAnswerCountsAsRejected() async {
        let (auth, store) = self.auth("ado-203.stub.test") { _ in .init(status: 203, body: "<html>sign in</html>") }
        #expect(await self.failure(auth) == "Azure DevOps rejected this token. Check it hasn't expired and was made for this organization.")
        #expect(store.hasToken(forOrganization: "acme") == false)
    }

    @Test
    func anUnknownOrganizationIsNamedAndNotStored() async {
        let (auth, store) = self.auth("ado-404.stub.test") { _ in .init(status: 404) }
        #expect(await self.failure(auth, org: "nope") == #"No organization named "nope" on Azure DevOps. Use the name from dev.azure.com/{name}."#)
        #expect(store.hasToken(forOrganization: "nope") == false)
    }
}
