import Foundation

/// Runs blocking work (a `git` or `python3` process, a directory walk) on its own thread and
/// awaits the answer.
///
/// Swift's cooperative pool has one thread per core. Work that waits on a process there holds
/// that thread for the whole wait, so a few scans in parallel on a small machine starve every
/// other task in the app, the timeout timers included. A dedicated thread per call keeps the pool
/// free; the threads are few (one per repo in a pass) and short-lived.
public enum Blocking {
    /// `work` is `sending`, like a task group's child closure: ownership moves to the new thread
    /// and nothing else touches it, which is what makes the unchecked box below sound.
    public static func run<T: Sendable>(
        qos: QualityOfService = .userInitiated, _ work: sending @escaping () -> T
    ) async -> T {
        let box = TransferBox(work)
        return await withCheckedContinuation { continuation in
            let thread = Thread { continuation.resume(returning: box.work()) }
            thread.qualityOfService = qos
            thread.name = "harbor.blocking"
            thread.start()
        }
    }
}

/// Carries a `sending` closure onto the thread that runs it.
private final class TransferBox<T>: @unchecked Sendable {
    let work: () -> T
    init(_ work: @escaping () -> T) { self.work = work }
}
