import Commander
import Foundation
import HarborCore
import Synchronization

/// `harborcli timing`: times one cold refresh the way the menu bar app runs it (repo list with
/// per-repo counts, then details for the top repos) and reports how much rate limit it spent.
/// Prints phase timings only. No tokens, no repository names.
@MainActor
struct TimingCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "timing"

    @OptionGroup
    var output: OutputOptions

    static var commandDescription: CommandDescription {
        CommandDescription(
            commandName: commandName,
            abstract: "Time one cold refresh and show the rate limit it used"
        )
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
    }

    mutating func run() async throws {
        guard (try? TokenStore.shared.load()) != nil else { throw CLIError.notAuthenticated }
        let keychain = KeychainTokenStorage()
        let endpoint = CLIEndpoint.resolve(storage: keychain, settings: SettingsStore().load())
        let client = await endpoint.makeClient(storage: keychain)

        _ = try await client.currentUser() // primes the rate-limit headers; not timed
        _ = await RequestTally.shared.drain()
        let clock = ContinuousClock()
        let startedAt = clock.now

        let listed = try await client.listRepositories(limit: nil)
        let listTime = clock.now - startedAt

        let enrichStart = clock.now
        let firstBatch = Mutex<Duration?>(nil)
        let counted = Mutex(0)
        await client.enrich(listed) { batch in
            firstBatch.withLock { if $0 == nil { $0 = clock.now - enrichStart } }
            counted.withLock { $0 += batch.count }
        }
        let enrichTime = clock.now - enrichStart
        let refreshTotal = clock.now - startedAt
        let refreshTally = await RequestTally.shared.drain()

        // One repo detail, as when its pane opens.
        var detailTime: Duration?
        var detailTally = RequestTally.Snapshot()
        if let first = RepositorySort.sorted(listed).first {
            let detailStart = clock.now
            _ = await client.loadDetails(for: first)
            detailTime = clock.now - detailStart
            detailTally = await RequestTally.shared.drain()
        }

        let after = await client.diagnostics()
        func seconds(_ duration: Duration) -> String {
            String(format: "%.2fs", Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
        }
        print("repos listed:         \(listed.count) (counts filled for \(counted.withLock { $0 }))")
        print("list phase:           \(seconds(listTime))")
        print("first batch at:       \(firstBatch.withLock { $0 }.map(seconds) ?? "n/a") after list")
        print("enrich phase:         \(seconds(enrichTime))")
        print("total cold refresh:   \(seconds(refreshTotal))")
        print("refresh calls:        REST \(refreshTally.restTotal), GraphQL \(refreshTally.graphQLTotal)")
        print("  \(RequestTally.summary(refreshTally))")
        if let detailTime {
            print("one detail opening:   \(seconds(detailTime)), REST \(detailTally.restTotal), GraphQL \(detailTally.graphQLTotal)")
        }
        print("rest remaining:       \(after.restRateLimit?.remaining.map(String.init) ?? "?")")
        print("graphql remaining:    \(after.graphQLRateLimit?.remaining.map(String.init) ?? "?")")
    }
}
