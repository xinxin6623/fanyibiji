import Foundation

/// TTS 引擎：两套讯飞接口，**同一套三件套密钥**（鉴权完全相同：
/// HMAC-SHA256 over host+date+request-line），仅 host/path 与请求/返回
/// JSON 结构不同。UI 可下拉切换，选择持久化。
enum TTSEngine: String, Codable, Sendable, CaseIterable {
    /// 普通在线语音合成 `wss://tts-api.xfyun.cn/v2/tts`（common/business/data）。
    case standard
    /// 超拟人语音合成 `wss://cbm01.cn-huabei-1.xf-yun.com/v1/private/mcd9m97e6`
    /// （header/parameter/payload，支持口语化）。
    case superHuman = "super"

    /// 该引擎的默认 WebSocket 地址。
    var defaultHost: String {
        switch self {
        case .standard:  return "wss://tts-api.xfyun.cn/v2/tts"
        case .superHuman: return "wss://cbm01.cn-huabei-1.xf-yun.com/v1/private/mcd9m97e6"
        }
    }

    /// 该引擎的默认发音人。
    var defaultVcn: String {
        switch self {
        case .standard:   return "xiaoyan"
        case .superHuman: return "x5_lingxiaoxuan_flow"
        }
    }
}

/// 超拟人口语化程度（仅 `superHuman` 引擎生效，standard 忽略）。
enum TTSOralLevel: String, Codable, Sendable, CaseIterable {
    case high, mid, low
}

/// 非敏感的 TTS provider 配置（纯值类型，可落 JSON）。
///
/// 编码契约与契约层一致：snake_case + `.iso8601`。三件套密钥
/// （appId/apiKey/apiSecret）不在此处，由 `SecretStore` 三个独立项保管，
/// 不进仓库、不落 JSON。命名用 `hostUrl`/`vcn` 等小写驼峰，避免
/// `.convertFromSnakeCase` 解码不对称（参考 `ProviderConfig` 注释）。
///
/// `engine` 决定走哪套接口；`hostUrl` 留作可覆盖项但默认随 engine。
/// 老配置文件无 `engine`/`oral_level` 字段时解码回退默认（见自定义
/// `init(from:)`），保证向后兼容不致读盘失败。
struct TTSConfig: Codable, Sendable, Equatable {
    let engine: TTSEngine
    /// WebSocket 接口地址；缺省随 `engine` 取 `defaultHost`。
    let hostUrl: String
    /// 发音人（需在讯飞控制台开通）。
    let vcn: String
    /// 语速 0–100。
    let speed: Int
    /// 音量 0–100。
    let volume: Int
    /// 音调 0–100。
    let pitch: Int
    /// 口语化程度，仅 `superHuman` 生效。
    let oralLevel: TTSOralLevel
    /// 单次握手到收完音频的整体超时（秒）。
    let timeoutSeconds: Double

    init(
        engine: TTSEngine = .superHuman,
        hostUrl: String? = nil,
        vcn: String? = nil,
        speed: Int = 50,
        volume: Int = 50,
        pitch: Int = 50,
        oralLevel: TTSOralLevel = .mid,
        timeoutSeconds: Double = 30
    ) {
        self.engine = engine
        self.hostUrl = hostUrl ?? engine.defaultHost
        self.vcn = vcn ?? engine.defaultVcn
        self.speed = speed
        self.volume = volume
        self.pitch = pitch
        self.oralLevel = oralLevel
        self.timeoutSeconds = timeoutSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case engine, hostUrl, vcn, speed, volume, pitch, oralLevel, timeoutSeconds
    }

    /// 容错解码：老配置无 `engine`/`oral_level`/`host_url` 时回默认，
    /// 不让一个新字段缺失导致整份偏好读盘失败（设置丢失只回默认）。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let engine = (try? c.decode(TTSEngine.self, forKey: .engine)) ?? .superHuman
        self.init(
            engine: engine,
            hostUrl: try? c.decodeIfPresent(String.self, forKey: .hostUrl),
            vcn: try? c.decodeIfPresent(String.self, forKey: .vcn),
            speed: (try? c.decodeIfPresent(Int.self, forKey: .speed)) ?? 50,
            volume: (try? c.decodeIfPresent(Int.self, forKey: .volume)) ?? 50,
            pitch: (try? c.decodeIfPresent(Int.self, forKey: .pitch)) ?? 50,
            oralLevel: (try? c.decode(TTSOralLevel.self, forKey: .oralLevel)) ?? .mid,
            timeoutSeconds: (try? c.decodeIfPresent(Double.self, forKey: .timeoutSeconds)) ?? 30
        )
    }
}

/// 校验通过、可直接交给讯飞 provider 的配置。
///
/// 故意**不实现 `Codable`**：内含三件套密钥，不允许被误序列化落盘
/// （与 `ResolvedProviderConfig` 同策略）。`engine`/`oralLevel` 一并
/// 携带，供组合根按引擎选择对应 provider。
struct ResolvedTTSConfig: Sendable, Equatable {
    let engine: TTSEngine
    let hostUrl: URL
    let vcn: String
    let speed: Int
    let volume: Int
    let pitch: Int
    let oralLevel: TTSOralLevel
    let timeoutSeconds: Double
    let appId: String
    let apiKey: String
    let apiSecret: String
}

/// TTS 配置与三件套密钥的边界：把非敏感 `TTSConfig` 与 `SecretStore`
/// 中的 appId/apiKey/apiSecret 组合成 `ResolvedTTSConfig`，对缺失/非法
/// 配置统一给出 `AgentError(.invalidInput)`（UI 只按 category 分支）。
///
/// **两个引擎共用同一套 Keychain key**（鉴权完全相同），切引擎无需
/// 重写密钥。
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
            engine: config.engine,
            hostUrl: url,
            vcn: vcn,
            speed: config.speed,
            volume: config.volume,
            pitch: config.pitch,
            oralLevel: config.oralLevel,
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
