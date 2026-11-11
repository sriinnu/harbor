import Commander
import Darwin
import Foundation
import HarborCore

protocol CommanderRunnableCommand: ParsableCommand {
    static var commandName: String { get }
    mutating func bind(_ values: ParsedValues) throws
}

extension ParsableCommand {
    static func descriptor() -> CommandDescriptor {
        let description = Self.commandDescription
        let instance = Self()
        let signature = CommandSignature.describe(instance).flattened()
        let name = description.commandName ?? String(describing: Self.self).lowercased()
        let subcommands = description.subcommands.map { $0.descriptor() }
        let defaultName = description.defaultSubcommand?.commandDescription.commandName
            ?? description.defaultSubcommand.map { String(describing: $0).lowercased() }
        return CommandDescriptor(
            name: name,
            abstract: description.abstract,
            discussion: description.discussion,
            signature: signature,
            subcommands: subcommands,
            defaultSubcommandName: defaultName
        )
    }
}

extension ParsedValues {
    func flag(_ label: String) -> Bool {
        flags.contains(label)
    }

    func decodeOption<T: ExpressibleFromArgument>(_ label: String) throws -> T? {
        guard let raw = options[label]?.last else { return nil }
        guard let value = T(argument: raw) else {
            throw ValidationError("Invalid value for --\(label): \(raw)")
        }
        return value
    }
}

struct OutputOptions: CommanderParsable, Sendable {
    @Flag(
        names: [.customLong("json"), .customLong("json-output"), .short("j")],
        help: "Output JSON instead of the formatted table"
    )
    var jsonOutput: Bool = false

    @Flag(names: [.customLong("plain")], help: "Plain table output (no links, no colors, no URLs)")
    var plain: Bool = false

    @Flag(names: [.customLong("no-color")], help: "Disable color output")
    var noColor: Bool = false

    init() {}

    mutating func bind(_ values: ParsedValues) {
        self.jsonOutput = values.flag("jsonOutput")
        self.plain = values.flag("plain")
        self.noColor = values.flag("noColor")
    }

    var useColor: Bool {
        self.jsonOutput == false && self.plain == false && self.noColor == false && Ansi.supportsColor
    }
}

extension RepositorySortKey: ExpressibleFromArgument {
    public init?(argument: String) {
        switch argument.lowercased() {
        case "activity", "act", "date":
            self = .activity
        case "issues", "issue", "iss":
            self = .issues
        case "prs", "pr", "pulls", "pull":
            self = .pulls
        case "stars", "star":
            self = .stars
        case "repo", "name":
            self = .name
        case "event", "activity-line", "line":
            self = .event
        default:
            return nil
        }
    }
}

enum CLIError: Error {
    case notAuthenticated
    case openFailed
    case unknownCommand(String)

    var message: String {
        switch self {
        case .notAuthenticated:
            "No stored login. Run `harborcli login` first."
        case .openFailed:
            "Failed to open the browser."
        case let .unknownCommand(command):
            "Unknown command: \(command)"
        }
    }
}

enum Ansi {
    static let reset = "\u{001B}[0m"
    static let bold = Code("\u{001B}[1m")
    static let red = Code("\u{001B}[31m")
    static let yellow = Code("\u{001B}[33m")
    static let magenta = Code("\u{001B}[35m")
    static let cyan = Code("\u{001B}[36m")
    static let gray = Code("\u{001B}[90m")
    static let oscTerminator = "\u{001B}\\"

    static var supportsColor: Bool {
        guard isatty(fileno(stdout)) != 0 else { return false }
        return ProcessInfo.processInfo.environment["NO_COLOR"] == nil
    }

    static var supportsLinks: Bool {
        isatty(fileno(stdout)) != 0
    }

    struct Code {
        let value: String

        init(_ value: String) {
            self.value = value
        }

        func wrap(_ text: String) -> String {
            "\(self.value)\(text)\(Ansi.reset)"
        }
    }

    static func link(_ label: String, url: URL, enabled: Bool) -> String {
        guard enabled else { return "\(label) \(url.absoluteString)" }
        let start = "\u{001B}]8;;\(url.absoluteString)\(Ansi.oscTerminator)"
        let end = "\u{001B}]8;;\(Ansi.oscTerminator)"
        return "\(start)\(label)\(end)"
    }
}

extension String {
    var singleLine: String {
        let noNewlines = self.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .joined(separator: " ")
        return noNewlines.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

func printError(_ message: String) {
    if Ansi.supportsColor {
        print(Ansi.red.wrap("Error: \(message)"))
    } else {
        print("Error: \(message)")
    }
}

func openURL(_ url: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [url.absoluteString]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CLIError.openFailed }
}

func parseHost(_ raw: String) throws -> URL {
    do {
        return try OAuthLoginFlow.normalizeHost(raw)
    } catch {
        throw ValidationError("Invalid host: \(raw) (expected an https host, like ghe.example.com)")
    }
}

enum HelpTarget: String {
    case root
    case repos
    case repo
    case issues
    case pulls
    case local
    case refresh
    case contributions
    case login
    case logout
    case status

    static func from(argv: [String]) -> HelpTarget? {
        guard !argv.isEmpty else { return .root }

        if argv.count > 1, argv[1] == "help" {
            let target = argv.dropFirst(2).first
            return HelpTarget.from(token: target)
        }

        guard argv.contains("--help") || argv.contains("-h") else { return nil }
        let target = argv.dropFirst().first(where: { !$0.hasPrefix("-") })
        return HelpTarget.from(token: target)
    }

    private static func from(token: String?) -> HelpTarget {
        guard let token else { return .root }
        switch token {
        case ReposCommand.commandName:
            return .repos
        case RepoCommand.commandName:
            return .repo
        case IssuesCommand.commandName:
            return .issues
        case PullsCommand.commandName:
            return .pulls
        case LocalProjectsCommand.commandName:
            return .local
        case RefreshCommand.commandName:
            return .refresh
        case ContributionsCommand.commandName:
            return .contributions
        case LoginCommand.commandName:
            return .login
        case LogoutCommand.commandName:
            return .logout
        case StatusCommand.commandName:
            return .status
        default:
            return .root
        }
    }
}

func printHelp(_ target: HelpTarget) {
    let text = switch target {
    case .root:
        """
        harborcli - Harbor from the command line: repositories, PRs, issues, local Git

        Usage:
          harborcli [repos] [--limit N] [--age DAYS] [--release] [--event] [--forks] [--archived] [--scope VAL] [--filter VAL] [--pinned-only] [--only-with VAL] [--json] [--plain] [--sort KEY]
          harborcli repo <owner/name> [--traffic] [--security] [--heatmap] [--release] [--json] [--plain]
          harborcli issues <owner/name> [--limit N] [--json] [--plain]
          harborcli pulls <owner/name> [--limit N] [--json] [--plain]
          harborcli local [--root PATH] [--depth N] [--sync] [--limit N] [--json] [--plain]
          harborcli refresh [--json] [--plain]
          harborcli contributions [--login USER] [--json] [--plain]
          harborcli login [--host URL] [--client-id ID] [--client-secret SECRET] [--loopback-port PORT]   (no secret: one-time code on github.com)
          harborcli logout
          harborcli status [--json]

        Options:
          --limit N    Max repositories to fetch (default: all accessible)
          --age DAYS   Only show repos with activity in the last N days (default: 365)
          --release    Include latest release tag and date
          --event      Show activity event column (hidden by default)
          --forks      Include forked repositories (hidden by default)
          --archived   Include archived repositories (hidden by default)
          --scope      Scope repositories (values: all, pinned, hidden)
          --filter     Filter repositories (values: all, work, issues, prs)
          --pinned-only  Only list pinned repositories from settings (alias for --scope pinned)
          --only-with  Only show repos that have issues and/or PRs (values: work, issues, prs)
          --json       Output JSON instead of formatted table
          --plain      Plain table output (no links, no colors, no URLs)
          --sort KEY   Sort by activity, issues, prs, stars, repo, or event
          --no-color   Disable color output
          -h, --help   Show help
        """
    case .repos:
        """
        harborcli repos - list repositories

        Usage:
          harborcli repos [--limit N] [--age DAYS] [--release] [--event] [--forks] [--archived] [--scope VAL] [--filter VAL] [--pinned-only] [--only-with VAL] [--json] [--plain] [--sort KEY]

        Options:
          --limit N    Max repositories to fetch (default: all accessible)
          --age DAYS   Only show repos with activity in the last N days (default: 365)
          --release    Include latest release tag and date
          --event      Show activity event column (hidden by default)
          --forks      Include forked repositories (hidden by default)
          --archived   Include archived repositories (hidden by default)
          --scope      Scope repositories (values: all, pinned, hidden)
          --filter     Filter repositories (values: all, work, issues, prs)
          --pinned-only  Only list pinned repositories from settings (alias for --scope pinned)
          --only-with  Only show repos that have issues and/or PRs (values: work, issues, prs)
          --json       Output JSON instead of formatted table
          --plain      Plain table output (no links, no colors, no URLs)
          --sort KEY   Sort by activity, issues, prs, stars, repo, or event
          --no-color   Disable color output
        """
    case .repo:
        """
        harborcli repo - fetch a repository summary

        Usage:
          harborcli repo <owner/name> [--traffic] [--security] [--heatmap] [--release] [--json] [--plain]

        Options:
          --traffic   Include traffic stats
          --security  Include open security alerts
          --heatmap   Include commit activity heatmap
          --release   Include latest release data
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .issues:
        """
        harborcli issues - list open issues

        Usage:
          harborcli issues <owner/name> [--limit N] [--json] [--plain]

        Options:
          --limit N   Max issues to fetch (default: 20)
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .pulls:
        """
        harborcli pulls - list open pull requests

        Usage:
          harborcli pulls <owner/name> [--limit N] [--json] [--plain]

        Options:
          --limit N   Max PRs to fetch (default: 20)
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .local:
        """
        harborcli local - scan local projects

        Usage:
          harborcli local [--root PATH] [--depth N] [--sync] [--limit N] [--json] [--plain]

        Options:
          --root PATH  Project folder to scan (defaults to settings value, then ~/Projects)
          --depth N    Max scan depth (default: 2)
          --sync       Fast-forward pull clean repos that are behind
          --limit N    Limit processed repos (default: all)
          --json       Output JSON instead of formatted table
          --plain      Plain table output (no links, no colors, no URLs)
          --no-color   Disable color output
        """
    case .refresh:
        """
        harborcli refresh - refresh pinned repositories

        Usage:
          harborcli refresh [--json] [--plain]

        Options:
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .contributions:
        """
        harborcli contributions - fetch contribution heatmap

        Usage:
          harborcli contributions [--login USER] [--json] [--plain]

        Options:
          --login USER  GitHub login (defaults to current user)
          --json        Output JSON instead of formatted text
          --plain       Plain output (no links, no colors)
          --no-color    Disable color output
        """
    case .login:
        """
        harborcli login - sign in to GitHub (one-time code; with --client-secret, your own OAuth app via the browser)

        Usage:
          harborcli login [--host URL] [--client-id ID] [--client-secret SECRET] [--loopback-port PORT]   (no secret: one-time code on github.com)
        """
    case .logout:
        """
        harborcli logout - clear stored credentials

        Usage:
          harborcli logout
        """
    case .status:
        """
        harborcli status - show login state

        Usage:
          harborcli status [--json]
        """
    }
    print(text)
}
