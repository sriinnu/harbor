import Commander
@testable import HarborCLI
import Testing

@MainActor
struct CLIRepoFlagTests {
    @Test
    func repoFlagsReachTheCommand() throws {
        let signature = RepoCommand.descriptor().signature
        let values = try CommandParser(signature: signature)
            .parse(arguments: ["sriinnu/harbor", "--traffic", "--security", "--heatmap", "--release"])
        var command = RepoCommand()
        try command.bind(values)
        #expect(command.includeTraffic)
        #expect(command.includeSecurity)
        #expect(command.includeHeatmap)
        #expect(command.includeRelease)
    }
}
