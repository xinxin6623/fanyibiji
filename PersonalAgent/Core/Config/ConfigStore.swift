import Foundation

/// 校验通过、可直接交给 provider 的配置。
///
/// 故意**不实现 `Codable`**：内含 `apiKey`，不允许被误序列化落盘或进仓库。
struct ResolvedProviderConfig: Sendable, Equatable {
    let baseUrl: URL
    let model: String
    let timeoutSeconds: Double
    let apiKey: String
}

/// 配置与密钥边界：把非敏感 `ProviderConfig` 与 `SecretStore` 中的 API key
/// 组合成 `ResolvedProviderConfig`，并对缺失/非法配置给出明确的
/// `AgentError`（统一 `.invalidInput`，UI 只按 category 分支）。
struct ConfigStore: Sendable {
    let secrets: SecretStore

    init(secrets: SecretStore) {
        self.secrets = secrets
    }

    /// - Parameter apiKeyRef: API key 在 `SecretStore` 中的键名。
    /// - Throws: 配置缺失/非法 → `AgentError(.invalidInput)`；
    ///           Keychain 底层失败 → `SecretStore` 抛出的 `.persistence` 原样透传。
    func resolve(_ config: ProviderConfig, apiKeyRef: String) throws -> ResolvedProviderConfig {
        let baseUrlString = config.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseUrlString.isEmpty else {
            throw ConfigStore.invalidInput("missing base_url")
        }
        guard let url = URL(string: baseUrlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            throw ConfigStore.invalidInput("invalid base_url")
        }

        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw ConfigStore.invalidInput("missing model")
        }

        guard config.timeoutSeconds > 0 else {
            throw ConfigStore.invalidInput("invalid timeout_seconds")
        }

        guard let rawKey = try secrets.secret(forKey: apiKeyRef) else {
            throw ConfigStore.invalidInput("missing api_key")
        }
        let apiKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw ConfigStore.invalidInput("missing api_key")
        }

        return ResolvedProviderConfig(
            baseUrl: url,
            model: model,
            timeoutSeconds: config.timeoutSeconds,
            apiKey: apiKey
        )
    }

    private static func invalidInput(_ message: String) -> AgentError {
        AgentError(category: .invalidInput,
                   isRetriable: false,
                   diagnosticMessage: message)
    }
}
