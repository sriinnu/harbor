import Foundation

/// The whole ledger folded into memory, then kept current by a file watch. Nothing is stored:
/// the byte offset is a cursor into the file, the state is rebuilt from the file at every launch.
public final class LedgerTail: @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "harbor.ledger-tail")
    private var replayer = LedgerReplayer()
    private var offset: UInt64 = 0
    private var source: DispatchSourceFileSystemObject?
    private var onChange: (@Sendable () -> Void)?
    /// Bumped by `start` and `stop` so a pending reattach from an earlier run does nothing.
    private var generation = 0
    /// Waits between attempts to attach to a missing file, doubling up to `maxRetryDelay`.
    private let firstRetryDelay: TimeInterval
    private let maxRetryDelay: TimeInterval

    public init(
        url: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".agents/ledger/events.jsonl"),
        firstRetryDelay: TimeInterval = 0.2, maxRetryDelay: TimeInterval = 5
    ) {
        self.url = url
        self.firstRetryDelay = firstRetryDelay
        self.maxRetryDelay = maxRetryDelay
    }

    deinit { self.source?.cancel() }

    /// The folded state right now.
    public func snapshot() -> [String: LedgerWorktree] {
        self.queue.sync { self.replayer.state }
    }

    /// The offset up to which the file has been folded.
    public var cursor: UInt64 { self.queue.sync { self.offset } }

    /// Replays the file from the start (streaming), then watches it. `onChange` runs on a
    /// private queue after every append that added state.
    public func start(onChange: @escaping @Sendable () -> Void) {
        self.queue.sync {
            self.onChange = onChange
            self.generation += 1
            self.source?.cancel()
            self.source = nil
            self.resetAndReplay()
            self.attach()
        }
    }

    public func stop() {
        self.queue.sync {
            self.source?.cancel()
            self.source = nil
            self.onChange = nil
            self.generation += 1
        }
    }

    // MARK: - queue-confined

    private func resetAndReplay() {
        var fresh = LedgerReplayer()
        self.offset = AgentLedger.replay(file: self.url, into: &fresh) ?? 0
        self.replayer = fresh
    }

    /// Watches the file. When it is missing (not created yet, or between a delete and a
    /// recreate) tries again after a short backoff, replaying from the start once it appears.
    private func attach(retryDelay: TimeInterval? = nil) {
        let descriptor = open(self.url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            let delay = retryDelay ?? self.firstRetryDelay
            let generation = self.generation
            self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.generation == generation, self.onChange != nil, self.source == nil else { return }
                guard FileManager.default.fileExists(atPath: self.url.path) else {
                    self.attach(retryDelay: min(delay * 2, self.maxRetryDelay))
                    return
                }
                // It exists now: fold what it holds, then watch it.
                self.resetAndReplay()
                self.attach(retryDelay: min(delay * 2, self.maxRetryDelay))
                self.onChange?()
            }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.extend, .write, .delete, .rename], queue: self.queue
        )
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            if !source.data.isDisjoint(with: [.delete, .rename]) {
                // The file was replaced: drop the watch on the old inode and start over.
                source.cancel()
                self.source = nil
                self.resetAndReplay()
                self.attach()
            } else {
                self.readAppended()
            }
            self.onChange?()
        }
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.resume()
    }

    private func readAppended() {
        let size = (try? FileManager.default.attributesOfItem(atPath: self.url.path)[.size] as? UInt64) ?? 0
        if size < self.offset {
            // Truncated in place.
            self.resetAndReplay()
            return
        }
        guard size > self.offset else { return }
        if let end = AgentLedger.replay(file: self.url, from: self.offset, into: &self.replayer) { self.offset = end }
    }
}
