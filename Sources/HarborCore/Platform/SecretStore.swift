import Foundation

/// The one place Harbor keeps secrets: OAuth tokens, OAuth client credentials,
/// Azure DevOps PATs, GitLab tokens, and any future API key (Jev, Laya).
/// Nothing secret goes to UserDefaults, settings files or logs.
///
/// Per platform:
/// - macOS: the login Keychain (`KeychainSecretStore`). It is local to the Mac and
///   never syncs to iCloud (items aren't marked synchronizable).
/// - iOS: the same code; there the items are also "after first unlock, this device
///   only", so background refresh can read them and backups can't move them.
/// - Windows (harbor-windows, Tauri): Windows Credential Manager through the Rust
///   `keyring` crate.
/// - Linux (harbor-linux, Tauri): the Secret Service (GNOME Keyring / KWallet).
/// - Android (none yet): Android Keystore. Keys stay in the Keystore and data is
///   encrypted with them; never plain SharedPreferences.
public protocol SecretStore: Sendable {
    func data(service: String, account: String) throws -> Data?
    func set(_ data: Data, service: String, account: String, label: String?) throws
    func remove(service: String, account: String) throws
    /// Every account stored under `service`.
    func accounts(service: String) throws -> [String]
}

public extension SecretStore {
    func set(_ data: Data, service: String, account: String) throws {
        try self.set(data, service: service, account: account, label: nil)
    }

    func removeAll(service: String) throws {
        for account in try self.accounts(service: service) {
            try self.remove(service: service, account: account)
        }
    }

    func value<T: Decodable>(_: T.Type, service: String, account: String) throws -> T? {
        guard let data = try self.data(service: service, account: account) else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func setValue(_ value: some Encodable, service: String, account: String, label: String? = nil) throws {
        try self.set(JSONEncoder().encode(value), service: service, account: account, label: label)
    }
}

public struct SecretStoreError: Error, LocalizedError, Equatable {
    public let operation: String
    public let status: Int32

    public var errorDescription: String? {
        "Keychain \(self.operation) failed (\(self.status))"
    }
}

#if canImport(Security)
import Security

public struct KeychainSecretStore: SecretStore {
    public static let shared = KeychainSecretStore()

    public init() {}

    private func baseQuery(service: String, account: String? = nil) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service
        ]
        if let account { query[kSecAttrAccount] = account }
        return query
    }

    public func data(service: String, account: String) throws -> Data? {
        var query = self.baseQuery(service: service, account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecretStoreError(operation: "read", status: status) }
        return item as? Data
    }

    /// Update in place, or add: never delete first, so a failed write can't lose the old secret.
    public func set(_ data: Data, service: String, account: String, label: String?) throws {
        var attributes: [CFString: Any] = [
            kSecValueData: data,
            // Applies on iOS (data-protection keychain); the macOS login keychain
            // ignores it and is local anyway. Never kSecAttrSynchronizable.
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        if let label { attributes[kSecAttrLabel] = label }

        let query = self.baseQuery(service: service, account: account)
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw SecretStoreError(operation: "update", status: update) }

        let add = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        guard add == errSecSuccess else { throw SecretStoreError(operation: "add", status: add) }
    }

    public func remove(service: String, account: String) throws {
        let status = SecItemDelete(self.baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError(operation: "delete", status: status)
        }
    }

    public func accounts(service: String) throws -> [String] {
        var query = self.baseQuery(service: service)
        query[kSecReturnAttributes] = true
        query[kSecMatchLimit] = kSecMatchLimitAll // without it the Keychain returns one item, not a list
        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw SecretStoreError(operation: "list", status: status) }
        let list = (items as? [[CFString: Any]]) ?? []
        return list.compactMap { $0[kSecAttrAccount] as? String }.sorted()
    }
}
#endif

/// Process memory only: tests and previews. Never shipped as a real store.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: [String: Data]] = [:]

    public init() {}

    public func data(service: String, account: String) throws -> Data? {
        self.lock.withLock { self.items[service]?[account] }
    }

    public func set(_ data: Data, service: String, account: String, label _: String?) throws {
        self.lock.withLock { self.items[service, default: [:]][account] = data }
    }

    public func remove(service: String, account: String) throws {
        _ = self.lock.withLock { self.items[service]?.removeValue(forKey: account) }
    }

    public func accounts(service: String) throws -> [String] {
        self.lock.withLock { (self.items[service].map { Array($0.keys) } ?? []).sorted() }
    }
}
