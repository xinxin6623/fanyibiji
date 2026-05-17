import Foundation

/// `PromptConfig` 的单文件 JSON 持久化（用户在设置里改的系统提示词，
/// 下次开 App 保留）。
///
/// 与 `HotkeySettingsStore` 同构：显式 CodingKeys 已是 snake_case
/// 字面量，故**不设** key 转换策略（叠加会二次转换 + 解码不对称）。
/// 容错优先：文件缺失/损坏/空串一律回 `PromptConfig()` 默认——
/// 提示词丢失只回默认，不应让 LLM 退化成无约束闲聊。
///
/// 路径由调用方注入（生产 Application Support，单测临时目录）。
final class PromptSettingsStore: @unchecked Sendable {
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

    /// 读取已保存配置；文件缺失/损坏/空提示词一律回默认。
    func load() -> PromptConfig {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL),
              !data.isEmpty,
              let decoded = try? JSONDecoder()
                .decode(PromptConfig.self, from: data) else {
            return PromptConfig()
        }
        return PromptSettingsStore.sanitized(decoded)
    }

    /// 覆盖写入。失败抛 `AgentError(.persistence)`（调用方可忽略：
    /// 存盘失败只丢失本次偏好持久化，不中断当前会话）。
    func save(_ config: PromptConfig) throws {
        lock.lock(); defer { lock.unlock() }
        do {
            let data = try PromptSettingsStore.makeEncoder()
                .encode(PromptSettingsStore.sanitized(config))
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw AgentError(category: .persistence,
                             isRetriable: true,
                             diagnosticMessage: "prompt settings write failed")
        }
    }

    /// 空白提示词回默认（避免存出空 system 让 LLM 失约束）。
    private static func sanitized(_ c: PromptConfig) -> PromptConfig {
        let trimmed = c.systemPrompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return PromptConfig(
            systemPrompt: trimmed.isEmpty
                ? PromptConfig.defaultSystemPrompt : trimmed)
    }
}
