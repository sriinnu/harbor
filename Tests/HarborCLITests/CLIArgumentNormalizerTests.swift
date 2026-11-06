@testable import HarborCLI
import Commander
import HarborCore
import Testing

struct CLIArgumentNormalizerTests {
    @Test
    func normalizesBinaryNameToRepobar() {
        let argv = CLIArgumentNormalizer.normalize(["/Applications/RepoBar.app/Contents/MacOS/repobarcli", "status"])
        #expect(argv.first == HarborRoot.commandName)
        #expect(argv.dropFirst().first == "status")
    }

    @Test
    @MainActor
    func normalizedArgsResolveToStatusCommand() throws {
        let argv = CLIArgumentNormalizer.normalize(["/Applications/RepoBar.app/Contents/MacOS/repobarcli", "status"])
        let program = Program(descriptors: [HarborRoot.descriptor()])
        let invocation = try program.resolve(argv: argv)
        #expect(invocation.path.last == StatusCommand.commandName)
    }

    @Test
    func normalizesLegacyAliases() {
        #expect(CLIArgumentNormalizer.normalize(["repobar", "list"]).dropFirst().first == "repos")
        #expect(CLIArgumentNormalizer.normalize(["repobar", "pr"]).dropFirst().first == "pulls")
        #expect(CLIArgumentNormalizer.normalize(["repobar", "prs"]).dropFirst().first == "pulls")
    }
}
