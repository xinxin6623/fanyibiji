import Foundation

/// 非敏感的 provider 配置（纯值类型，可落 JSON）。
///
/// 编码契约与 TC 契约层一致：`JSONEncoder` snake_case + `.iso8601`。
/// 本类型只承载非敏感字段；API key 不在此处，由 `SecretStore` 单独保管，
/// 不进入仓库、不落 JSON。字段范围保持最小（baseUrl / model /
/// timeoutSeconds），T07a OpenAI-compatible 直接消费，后续按需扩展。
///
/// 命名用 `baseUrl` 而非 `baseURL`：`.convertFromSnakeCase` 会把
/// `base_url` 解回 `baseUrl`，与 `baseURL` 不对称会导致解码失败。
struct ProviderConfig: Codable, Sendable, Equatable {
    let baseUrl: String
    let model: String
    let timeoutSeconds: Double

    init(baseUrl: String, model: String, timeoutSeconds: Double = 30) {
        self.baseUrl = baseUrl
        self.model = model
        self.timeoutSeconds = timeoutSeconds
    }
}
