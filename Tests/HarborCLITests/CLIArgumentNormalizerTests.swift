@testable import HarborCLI
import Commander
import HarborCore
import Testing

struct CLIArgumentNormalizerTests {
    @Test
    func normalizesBinaryNameToHarborcli() {
        let argv = CLIArgumentNormalizer.normalize(["/opt/homebrew/bin/harborcli-link", "status"])
        #expect(argv.first == "harborcli")
        #expect(argv.dropFirst().first == "status")
    }

    @Test
    @MainActor
    func normalizedArgsResolveToStatusCommand() throws {
        let argv = CLIArgumentNormalizer.normalize(["/Applications/Harbor.app/Contents/Helpers/harborcli", "status"])
        let program = Program(descriptors: [HarborRoot.descriptor()])
        let invocation = try program.resolve(argv: argv)
        #expect(invocation.path.last == StatusCommand.commandName)
    }

    @Test
    func normalizesLegacyAliases() {
        #expect(CLIArgumentNormalizer.normalize(["harborcli", "list"]).dropFirst().first == "repos")
        #expect(CLIArgumentNormalizer.normalize(["harborcli", "pr"]).dropFirst().first == "pulls")
        #expect(CLIArgumentNormalizer.normalize(["harborcli", "prs"]).dropFirst().first == "pulls")
    }
}
