import Foundation
import Security
import CryptoKit
import IOKit

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

/// 生产实现（现行默认）：AES-GCM 加密后落本地文件，**完全不碰
/// Keychain**，因此永不弹系统密码框。
///
/// 取舍（James 已知并接受）：根密钥派生自「本机硬件 UUID + App 固定
/// 盐」，不依赖 Keychain ACL，故开发期反复 rebuild（签名指纹漂移）
/// 不再触发授权框——这正是换掉 `KeychainSecretStore` 的目的。
/// 安全边界比 Keychain 弱：同机上能读到 enc 文件且知道本算法/盐的
/// 进程可解密；硬件 UUID 绑定使加密文件拷到**别的机器**无法直接解。
/// 对单用户本地开发工具，此强度换「不再每次启动弹好几次密码」值得。
///
/// 文件格式：JSON `{ "<account>": "<base64(AES.GCM.combined)>" }`，
/// combined = nonce‖ciphertext‖tag。原子写，失败转 `AgentError`。
final class FileSecretStore: SecretStore, @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    /// 派生根密钥用的 App 固定盐（换值会使旧密文全部失效，勿改）。
    private static let salt = Data("com.james.personalagent.secretbox.v1".utf8)

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// 一次性迁移：把旧 `KeychainSecretStore` 里仍存在、而本文件**还
    /// 没有**的 key 读出来加密落新文件。幂等——已迁移/新文件已有则
    /// 跳过该 key，故每次启动调都安全。读旧 Keychain 这一步可能弹一
    /// 次系统密码框（仅迁移当次；迁完后全部走文件，永不再弹）。
    /// 任何单个 key 迁移失败（旧库读不到/写盘错）只跳过它、不抛、不
    /// 阻断启动——缺的那项 UI 仍显示「未配置」引导重填。
    /// 返回实际迁移成功的 key 数（0 表示无需迁移或全失败，调用方仅
    /// 用于日志/无副作用）。
    @discardableResult
    func migrateFromKeychainIfNeeded(
        keys: [String],
        legacy: SecretStore) -> Int {
        var migrated = 0
        for key in keys {
            // 新文件已有 → 视为已迁移，跳过（幂等）。
            if (try? secret(forKey: key)) ?? nil != nil { continue }
            guard let old = (try? legacy.secret(forKey: key)) ?? nil,
                  !old.isEmpty else { continue }
            do {
                try setSecret(old, forKey: key)
                migrated += 1
            } catch {
                continue   // 单项失败不阻断其它 key 与启动
            }
        }
        return migrated
    }

    func secret(forKey key: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        let map = try load()
        guard let b64 = map[key], let blob = Data(base64Encoded: b64) else {
            return nil
        }
        do {
            let box = try AES.GCM.SealedBox(combined: blob)
            let opened = try AES.GCM.open(box, using: Self.rootKey())
            return String(decoding: opened, as: UTF8.self)
        } catch {
            // 密文损坏 / 换机解不开：当作「无此项」而非崩溃，UI 据此
            // 显示「未配置」引导用户重填，比抛错阻断体验好。
            return nil
        }
    }

    func setSecret(_ value: String, forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        var map = try load()
        do {
            let sealed = try AES.GCM.seal(Data(value.utf8),
                                          using: Self.rootKey())
            guard let combined = sealed.combined else {
                throw AgentError(category: .persistence,
                                 diagnosticMessage: "GCM combined nil")
            }
            map[key] = combined.base64EncodedString()
        } catch let e as AgentError {
            throw e
        } catch {
            throw AgentError(category: .persistence,
                             diagnosticMessage: "secret encrypt failed")
        }
        try persist(map)
    }

    func deleteSecret(forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        var map = try load()
        guard map.removeValue(forKey: key) != nil else { return }
        try persist(map)
    }

    // MARK: - 内部

    private func load() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }
        do {
            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else { return [:] }
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            throw AgentError(category: .persistence,
                             diagnosticMessage: "secret file read/parse failed")
        }
    }

    private func persist(_ map: [String: String]) throws {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(map)
            try data.write(to: fileURL, options: [.atomic])
            // 仅属主可读写（0600），缩小同机其它用户读取面。
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch let e as AgentError {
            throw e
        } catch {
            throw AgentError(category: .persistence,
                             diagnosticMessage: "secret file write failed")
        }
    }

    /// 根密钥 = HKDF-SHA256(本机硬件 UUID, salt)。硬件 UUID 取不到
    /// （理论上罕见）时退回固定串——届时退化为「同算法即可解」，仍
    /// 不弹框、不崩，属可接受降级。
    private static func rootKey() -> SymmetricKey {
        let machine = hardwareUUID() ?? "personalagent-fallback-machine-id"
        let ikm = SymmetricKey(data: Data(machine.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm,
            salt: salt,
            info: Data("secretbox".utf8),
            outputByteCount: 32)
    }

    private static func hardwareUUID() -> String? {
        let dict = IOServiceMatching("IOPlatformExpertDevice")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, dict)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let cf = IORegistryEntryCreateCFProperty(
            service, kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault, 0)?.takeRetainedValue() as? String else {
            return nil
        }
        return cf
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
