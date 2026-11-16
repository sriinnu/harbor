@testable import Harbor
import Testing

@MainActor
struct AzureTokenPageTests {
    @Test
    func buildsTheOrganizationsTokenPageFromAnyForm() {
        let expected = "https://dev.azure.com/contoso/_usersSettings/tokens"
        #expect(AccountSettingsView.azureTokenPage(organization: "contoso").absoluteString == expected)
        #expect(AccountSettingsView.azureTokenPage(organization: " https://dev.azure.com/contoso/Project ").absoluteString == expected)
        #expect(AccountSettingsView.azureTokenPage(organization: "contoso.visualstudio.com").absoluteString == expected)
    }

    @Test
    func fallsBackToTheHomeWhenTheOrganizationIsEmptyOrOdd() {
        #expect(AccountSettingsView.azureTokenPage(organization: "").absoluteString == "https://dev.azure.com/")
        #expect(AccountSettingsView.azureTokenPage(organization: "a b?c").absoluteString == "https://dev.azure.com/")
    }
}
