import Foundation

/// `TTSConfig` 的单文件 JSON 持久化（发音人/语速/音量/音调可在 UI 改，
/// 下次开 App 保留）。
///
/// 编码契约与 TC 契约层一致：snake_case。整文件覆盖写、整文件读取
/// （单对象，非 JSONL）。**容错优先**：文件缺失/损坏/字段非法一律
/// 回落到 `TTSConfig()` 默认值而不抛错——设置项丢失只是回默认，不应
/// 阻断 TTS 功能（与 JSONLResultStore「不静默跳过损坏行」相反，因为
/// 这里损坏只损失偏好、无数据完整性风险）。
///
/// 路径由调用方注入（生产 Application Support，单测临时目录）。
final class TTSSettingsStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// 读取已保存配置；文件缺失/损坏/越界一律回 `TTSConfig()` 默认。
    func load() -> TTSConfig {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL),
              !data.isEmpty,
              let decoded = try? TTSSettingsStore.makeDecoder()
                .decode(TTSConfig.self, from: data) else {
            return TTSConfig()
        }
        return TTSSettingsStore.sanitized(decoded)
    }

    /// 覆盖写入。失败抛 `AgentError(.persistence)`（调用方可选择忽略：
    /// 存盘失败不应中断正在进行的合成，仅丢失本次偏好持久化）。
    func save(_ config: TTSConfig) throws {
        lock.lock(); defer { lock.unlock() }
        do {
            let data = try TTSSettingsStore.makeEncoder()
                .encode(TTSSettingsStore.sanitized(config))
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw AgentError(category: .persistence,
                             isRetriable: true,
                             diagnosticMessage: "tts settings write failed")
        }
    }

    /// 把可能越界的值夹回合法范围，host/vcn 空则回**该引擎**默认。
    /// 确保读到的配置不会让后续 `TTSConfigStore.resolve` 因脏数据失败。
    private static func sanitized(_ c: TTSConfig) -> TTSConfig {
        let host = c.hostUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let vcn = c.vcn.trimmingCharacters(in: .whitespacesAndNewlines)
        func clamp(_ v: Int) -> Int { min(max(v, 0), 100) }
        return TTSConfig(
            engine: c.engine,
            hostUrl: host.isEmpty ? c.engine.defaultHost : host,
            vcn: vcn.isEmpty ? c.engine.defaultVcn : vcn,
            speed: clamp(c.speed),
            volume: clamp(c.volume),
            pitch: clamp(c.pitch),
            oralLevel: c.oralLevel,
            timeoutSeconds: c.timeoutSeconds > 0 ? c.timeoutSeconds : 30)
    }
}
