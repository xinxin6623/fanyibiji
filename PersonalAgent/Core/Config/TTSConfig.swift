import Foundation

/// 非敏感的 TTS provider 配置（纯值类型，可落 JSON）。
///
/// 编码契约与契约层一致：snake_case + `.iso8601`。三件套密钥
/// （appId/apiKey/apiSecret）不在此处，由 `SecretStore` 三个独立项保管，
/// 不进仓库、不落 JSON。命名用 `hostUrl`/`vcn` 等小写驼峰，避免
/// `.convertFromSnakeCase` 解码不对称（参考 `ProviderConfig` 注释）。
struct TTSConfig: Codable, Sendable, Equatable {
    /// WebSocket 接口地址，例：`wss://tts-api.xfyun.cn/v2/tts`。
    let hostUrl: String
    /// 发音人（需在讯飞控制台开通），例：`xiaoyan`。
    let vcn: String
    /// 语速 0–100。
    let speed: Int
    /// 音量 0–100。
    let volume: Int
    /// 音调 0–100。
    let pitch: Int
    /// 单次握手到收完音频的整体超时（秒）。
    let timeoutSeconds: Double

    init(
        hostUrl: String = "wss://tts-api.xfyun.cn/v2/tts",
        vcn: String = "xiaoyan",
        speed: Int = 50,
        volume: Int = 50,
        pitch: Int = 50,
        timeoutSeconds: Double = 30
    ) {
        self.hostUrl = hostUrl
        self.vcn = vcn
        self.speed = speed
        self.volume = volume
        self.pitch = pitch
        self.timeoutSeconds = timeoutSeconds
    }
}

/// 校验通过、可直接交给讯飞 provider 的配置。
///
/// 故意**不实现 `Codable`**：内含三件套密钥，不允许被误序列化落盘
/// （与 `ResolvedProviderConfig` 同策略）。
struct ResolvedTTSConfig: Sendable, Equatable {
    let hostUrl: URL
    let vcn: String
    let speed: Int
    let volume: Int
    let pitch: Int
    let timeoutSeconds: Double
    let appId: String
    let apiKey: String
    let apiSecret: String
}

/// TTS 配置与三件套密钥的边界：把非敏感 `TTSConfig` 与 `SecretStore`
/// 中的 appId/apiKey/apiSecret 组合成 `ResolvedTTSConfig`，对缺失/非法
/// 配置统一给出 `AgentError(.invalidInput)`（UI 只按 category 分支）。
struct TTSConfigStore: Sendable {
    let secrets: SecretStore

    /// Keychain 中三件套的键名（account）。service 仍是
    /// `com.james.personalagent`，三个独立项，写入用 `-A` 宽松 ACL。
    static let appIdRef = "tts.appId"
    static let apiKeyRef = "tts.apiKey"
    static let apiSecretRef = "tts.apiSecret"

    init(secrets: SecretStore) {
        self.secrets = secrets
    }

    /// - Throws: 配置缺失/非法 → `AgentError(.invalidInput)`；
    ///           Keychain 底层失败 → `SecretStore` 的 `.persistence` 原样透传。
    func resolve(_ config: TTSConfig) throws -> ResolvedTTSConfig {
        let hostString = config.hostUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hostString.isEmpty else {
            throw TTSConfigStore.invalidInput("missing host_url")
        }
        guard let url = URL(string: hostString),
              let scheme = url.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss",
              url.host != nil else {
            throw TTSConfigStore.invalidInput("invalid host_url")
        }

        let vcn = config.vcn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vcn.isEmpty else {
            throw TTSConfigStore.invalidInput("missing vcn")
        }

        for (value, name) in [(config.speed, "speed"),
                              (config.volume, "volume"),
                              (config.pitch, "pitch")] {
            guard (0...100).contains(value) else {
                throw TTSConfigStore.invalidInput("invalid \(name)")
            }
        }

        guard config.timeoutSeconds > 0 else {
            throw TTSConfigStore.invalidInput("invalid timeout_seconds")
        }

        let appId = try requireSecret(Self.appIdRef, "app_id")
        let apiKey = try requireSecret(Self.apiKeyRef, "api_key")
        let apiSecret = try requireSecret(Self.apiSecretRef, "api_secret")

        return ResolvedTTSConfig(
            hostUrl: url,
            vcn: vcn,
            speed: config.speed,
            volume: config.volume,
            pitch: config.pitch,
            timeoutSeconds: config.timeoutSeconds,
            appId: appId,
            apiKey: apiKey,
            apiSecret: apiSecret
        )
    }

    private func requireSecret(_ ref: String, _ label: String) throws -> String {
        guard let raw = try secrets.secret(forKey: ref) else {
            throw TTSConfigStore.invalidInput("missing \(label)")
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw TTSConfigStore.invalidInput("missing \(label)")
        }
        return value
    }

    private static func invalidInput(_ message: String) -> AgentError {
        AgentError(category: .invalidInput,
                   isRetriable: false,
                   diagnosticMessage: message)
    }
}
