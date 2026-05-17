import Foundation

/// `LanguageConfig` 的单文件 JSON 持久化（用户选的翻译目标语言，
/// 下次开 App 保留）。
///
/// 与 HotkeySettingsStore/PromptSettingsStore 同构：显式 CodingKeys
/// 已是 snake_case，故**不设** key 转换策略。容错优先：文件缺失/
/// 损坏/非法枚举一律回 `LanguageConfig()` 默认（中文）。
///
/// 路径由调用方注入（生产 Application Support，单测临时目录）。
final class LanguageSettingsStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    /// 读取已保存配置；缺失/损坏/非法枚举值一律回默认。
    func load() -> LanguageConfig {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL),
              !data.isEmpty,
              let decoded = try? JSONDecoder()
                .decode(LanguageConfig.self, from: data) else {
            return LanguageConfig()
        }
        return decoded
    }

    /// 覆盖写入。失败抛 `AgentError(.persistence)`（调用方可忽略：
    /// 存盘失败只丢失本次偏好持久化，不中断当前会话）。
    func save(_ config: LanguageConfig) throws {
        lock.lock(); defer { lock.unlock() }
        do {
            let data = try LanguageSettingsStore.makeEncoder().encode(config)
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw AgentError(category: .persistence,
                             isRetriable: true,
                             diagnosticMessage: "language settings write failed")
        }
    }
}
