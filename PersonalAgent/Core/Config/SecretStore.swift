import Foundation
import Security

/// 敏感信息（API key 等）的存取边界。
///
/// 通过协议隔离，便于单测用内存桩，不触碰真实 Keychain（测试宿主下
/// Keychain 不可靠）。底层失败统一转 `AgentError`，不暴露 OSStatus。
protocol SecretStore: Sendable {
    /// 不存在返回 `nil`；底层失败抛 `AgentError(.persistence)`。
    func secret(forKey key: String) throws -> String?
    func setSecret(_ value: String, forKey key: String) throws
    func deleteSecret(forKey key: String) throws
}

/// 生产实现：`kSecClassGenericPassword`，service 限本 App。
/// 不在此处做配置校验，只负责安全读写；校验在 `ConfigStore`。
struct KeychainSecretStore: SecretStore {
    let service: String

    init(service: String = "com.james.personalagent") {
        self.service = service
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    func secret(forKey key: String) throws -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainSecretStore.persistenceError(status)
        }
        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw AgentError(category: .persistence,
                             diagnosticMessage: "keychain item is not utf8 string")
        }
        return value
    }

    func setSecret(_ value: String, forKey key: String) throws {
        let data = Data(value.utf8)
        let deleteStatus = SecItemDelete(baseQuery(key) as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw KeychainSecretStore.persistenceError(deleteStatus)
        }
        var attributes = baseQuery(key)
        attributes[kSecValueData as String] = data
        // 关键：只在写入(SecItemAdd)时设可访问性，不能进 baseQuery
        // ——它同时用于读/删查询，带 kSecAttrAccessible 会匹配不到。
        // AfterFirstUnlock：开机首次解锁后本进程免密访问，不再每个
        // key 项各弹一次系统密码框（开发期 rebuild 后 ACL 失效的根因）。
        attributes[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainSecretStore.persistenceError(addStatus)
        }
    }

    func deleteSecret(forKey key: String) throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSecretStore.persistenceError(status)
        }
    }

    private static func persistenceError(_ status: OSStatus) -> AgentError {
        AgentError(category: .persistence,
                   isRetriable: false,
                   diagnosticMessage: "keychain operation failed",
                   providerErrorCode: "OSStatus_\(status)")
    }
}

/// 单测桩：纯内存，线程安全，不接触 Keychain。
final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String]

    init(_ initial: [String: String] = [:]) {
        self.storage = initial
    }

    func secret(forKey key: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    func setSecret(_ value: String, forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = value
    }

    func deleteSecret(forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = nil
    }
}

/// 单测桩：每次操作都抛指定的 `AgentError`，用于验证错误透传。
struct FailingSecretStore: SecretStore {
    let error: AgentError

    init(error: AgentError = AgentError(category: .persistence,
                                        diagnosticMessage: "stub failure")) {
        self.error = error
    }

    func secret(forKey key: String) throws -> String? { throw error }
    func setSecret(_ value: String, forKey key: String) throws { throw error }
    func deleteSecret(forKey key: String) throws { throw error }
}
