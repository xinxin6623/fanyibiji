import Foundation

/// `HotkeyConfig` 的单文件 JSON 持久化（用户在设置里改的快捷键，
/// 下次开 App 保留）。
///
/// 与 `TTSSettingsStore` 同构：snake_case、整文件覆盖写/读取、
/// **容错优先**——文件缺失/损坏/绑定非法一律回 `HotkeyConfig()`
/// 默认值而不抛错（设置项丢失只回默认，不应阻断热键功能）。
///
/// 路径由调用方注入（生产 Application Support，单测临时目录）。
final class HotkeySettingsStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// 不设 key 转换策略：`HotkeyConfig`/`KeyBinding` 已用显式
    /// snake_case `CodingKeys`，再叠 `.convertToSnakeCase` 会对
    /// 字面量二次转换、且解码侧 `.convertFromSnakeCase` 对缩写
    /// 不对称（这正是本类型 bug 根因）。CodingKeys 自带契约即可。
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    /// 读取已保存配置；文件缺失/损坏/绑定非法一律回默认。
    func load() -> HotkeyConfig {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL),
              !data.isEmpty,
              let decoded = try? HotkeySettingsStore.makeDecoder()
                .decode(HotkeyConfig.self, from: data) else {
            return HotkeyConfig()
        }
        return HotkeySettingsStore.sanitized(decoded)
    }

    /// 覆盖写入。失败抛 `AgentError(.persistence)`（调用方可选择忽略：
    /// 存盘失败不应中断当前会话，仅丢失本次偏好持久化）。
    func save(_ config: HotkeyConfig) throws {
        lock.lock(); defer { lock.unlock() }
        do {
            let data = try HotkeySettingsStore.makeEncoder()
                .encode(HotkeySettingsStore.sanitized(config))
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw AgentError(category: .persistence,
                             isRetriable: true,
                             diagnosticMessage: "hotkey settings write failed")
        }
    }

    /// 非法绑定（无 ⌘/⌃ 修饰）回退到该项默认，避免存出会误触发的
    /// 纯字母热键，或解码到脏数据后装不上监听。
    private static func sanitized(_ c: HotkeyConfig) -> HotkeyConfig {
        HotkeyConfig(
            translateSelection: c.translateSelection.isValid
                ? c.translateSelection : .defaultTranslateSelection,
            captureOCR: c.captureOCR.isValid
                ? c.captureOCR : .defaultCaptureOCR)
    }
}
