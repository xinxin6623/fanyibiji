import Foundation

/// 当配置/密钥缺失时的降级 provider：调用即抛预置 `AgentError`，
/// 让失败态在 UI 可见（避免静默卡死），真实配置 UI 属后续任务。
struct FailingLLMProvider: LLMProvider {
    let id = "unconfigured-llm"
    let error: AgentError
    func validate() throws { throw error }
    func complete(_ context: QueryContext) async throws -> AssistantResult {
        throw error
    }
}

/// 组合根：解析本地配置 + 密钥，组装垂直闭环依赖。
/// 不在仓库放 key；缺 key 时降级而非崩溃。
enum AppComposition {

    /// 默认 provider 配置（OpenAI-compatible）。真实可配置 UI 属后续任务。
    static let defaultConfig = ProviderConfig(
        baseUrl: "https://api.openai.com/v1",
        model: "gpt-4o-mini"
    )
    static let apiKeyRef = "llm.apiKey"

    static func resultsFileURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("com.james.personalagent", isDirectory: true)
            .appendingPathComponent("results.jsonl")
    }

    @MainActor
    static func makeViewModel() -> ContentQueryViewModel {
        let store = JSONLResultStore(fileURL: resultsFileURL())
        let configStore = ConfigStore(secrets: KeychainSecretStore())
        let provider: LLMProvider
        do {
            let resolved = try configStore.resolve(defaultConfig, apiKeyRef: apiKeyRef)
            provider = OpenAICompatibleLLMProvider(
                config: resolved, client: URLSessionLLMHTTPClient())
        } catch let error as AgentError {
            provider = FailingLLMProvider(error: error)
        } catch {
            provider = FailingLLMProvider(
                error: AgentError(category: .unknown,
                                  diagnosticMessage: "composition failed"))
        }
        return ContentQueryViewModel(provider: provider, store: store)
    }
}
