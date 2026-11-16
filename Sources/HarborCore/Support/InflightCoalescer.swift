import Foundation

/// Joins identical requests that are in flight at the same moment onto one piece of work.
///
/// This is coalescing, not caching: the entry is removed the instant the work finishes, before
/// any caller sees the value, so a call that arrives afterwards always starts fresh work.
actor InflightCoalescer<Key: Hashable & Sendable, Value: Sendable> {
    private struct Entry {
        let id: UUID
        let task: Task<Value, Error>
    }

    private var inflight: [Key: Entry] = [:]

    func run(key: Key, work: @escaping @Sendable () async throws -> Value) async throws -> Value {
        if let entry = self.inflight[key] { return try await entry.task.value }
        let id = UUID()
        let task = Task<Value, Error> {
            do {
                let value = try await work()
                self.finish(key: key, id: id)
                return value
            } catch {
                self.finish(key: key, id: id)
                throw error
            }
        }
        self.inflight[key] = Entry(id: id, task: task)
        return try await task.value
    }

    /// Requests currently being waited on. Exposed for tests.
    var activeCount: Int { self.inflight.count }

    private func finish(key: Key, id: UUID) {
        if self.inflight[key]?.id == id { self.inflight[key] = nil }
    }
}
