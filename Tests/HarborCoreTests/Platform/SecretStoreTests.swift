import Foundation
@testable import HarborCore
import Testing

/// Exercises the stores against `InMemorySecretStore`; tests never touch the real Keychain.
struct SecretStoreTests {
    @Test
    func patStoreListsEveryOrganization() throws {
        let store = AzureDevOpsPATStore(service: "test.ado", store: InMemorySecretStore())
        try store.save(token: "t1", forOrganization: "Contoso")
        try store.save(token: "t2", forOrganization: "fabrikam")
        #expect(try store.listOrganizations() == ["contoso", "fabrikam"])
        #expect(try store.token(forOrganization: "CONTOSO") == "t1")
        store.delete(forOrganization: "contoso")
        #expect(try store.listOrganizations() == ["fabrikam"])
        #expect(throws: PATStoreError.tokenNotFound) { try store.load(forOrganization: "contoso") }
    }

    @Test
    func expiredPATIsRefused() throws {
        let store = AzureDevOpsPATStore(service: "test.ado", store: InMemorySecretStore())
        try store.save(token: "old", forOrganization: "o", expiresAt: .distantPast)
        #expect(throws: PATStoreError.tokenExpired) { try store.load(forOrganization: "o") }
    }

    @Test
    func tokenStorageRoundTripsAndClears() throws {
        let storage = KeychainTokenStorage(service: "test.auth", store: InMemorySecretStore())
        let tokens = OAuthTokens(accessToken: "a", refreshToken: "r", expiresAt: nil)
        try storage.save(tokens: tokens)
        try storage.save(clientCredentials: OAuthClientCredentials(clientID: "id", clientSecret: "s"))
        #expect(try storage.load() == tokens)
        storage.clear()
        #expect(try storage.load() == nil)
        #expect(try storage.loadClientCredentials() == nil)
    }

    @Test
    func gitLabTokensArePerInstance() throws {
        let auth = GitLabAuth(store: InMemorySecretStore())
        try auth.saveToken("g1", for: "https://gitlab.com")
        try auth.saveToken("g2", for: "https://git.example.com:8443/")
        #expect(try auth.loadToken(for: "https://gitlab.com") == "g1")
        #expect(try auth.loadToken(for: "https://git.example.com:8443/") == "g2")
        auth.clearAllTokens()
        #expect(auth.hasToken(for: "https://gitlab.com") == false)
    }
}
