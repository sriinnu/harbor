import Foundation
import HarborCore

enum CLIArgumentNormalizer {
    static func normalize(_ args: [String]) -> [String] {
        guard !args.isEmpty else { return [HarborRoot.commandName] }

        var normalized = args
        let invokedName = URL(fileURLWithPath: args[0]).lastPathComponent

        // Commander expects argv[0] to be the command name used in help/usage. Our binary name can vary
        // (e.g. `harborcli` when bundled inside the app), but the public interface stays `harbor`.
        if invokedName != HarborRoot.commandName {
            normalized[0] = HarborRoot.commandName
        } else {
            normalized[0] = invokedName
        }

        if normalized.count > 1, normalized[1] == "list" {
            normalized[1] = "repos"
        }
        if normalized.count > 1, ["pr", "prs"].contains(normalized[1]) {
            normalized[1] = "pulls"
        }

        return normalized
    }
}
