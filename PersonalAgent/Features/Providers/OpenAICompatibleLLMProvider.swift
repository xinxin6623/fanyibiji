import Foundation

/// OpenAI-compatible `/chat/completions` 的最小 LLM provider。
///
/// 消费 `ConfigStore.resolve` 产出的 `ResolvedProviderConfig`（不自读
/// Keychain）。`validate()` 仅形状检查、零网络。所有失败统一映射
/// `AgentError`，UI 只按 `category` 分支，不暴露 provider 私有错误。
struct OpenAICompatibleLLMProvider: LLMProvider {
    let id = "openai-compatible-llm"

    private let config: ResolvedProviderConfig
    private let client: LLMHTTPClient

    init(config: ResolvedProviderConfig, client: LLMHTTPClient) {
        self.config = config
        self.client = client
    }

    /// 仅形状检查，零网络（契约层约定）。
    func validate() throws {
        guard config.baseUrl.scheme?.hasPrefix("http") == true,
              config.baseUrl.host != nil else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "invalid base_url")
        }
        guard !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "missing model")
        }
        guard !config.apiKey.isEmpty else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "missing api_key")
        }
    }

    func complete(_ context: QueryContext) async throws -> AssistantResult {
        try validate()

        let trimmed = context.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "empty input text")
        }

        let request = try makeRequest(prompt: trimmed)

        let data: Data
        let response: HTTPURLResponse
        do {
            try Task.checkCancellation()
            (data, response) = try await client.send(request)
            try Task.checkCancellation()
        } catch let error as AgentError {
            throw error
        } catch is CancellationError {
            throw AgentError(category: .cancelled, diagnosticMessage: "request cancelled")
        } catch let urlError as URLError {
            throw OpenAICompatibleLLMProvider.mapURLError(urlError)
        } catch {
            throw AgentError(category: .network,
                             isRetriable: true,
                             diagnosticMessage: "transport failure")
        }

        guard (200..<300).contains(response.statusCode) else {
            throw OpenAICompatibleLLMProvider.mapHTTPStatus(response.statusCode)
        }

        return try OpenAICompatibleLLMProvider.parse(data, fallbackModel: config.model)
    }

    // MARK: - Request

    private func makeRequest(prompt: String) throws -> URLRequest {
        let url = config.baseUrl.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = config.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": config.model,
            "messages": [["role": "user", "content": prompt]]
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "failed to encode request body")
        }
        return request
    }

    // MARK: - Failure mapping

    private static func mapURLError(_ error: URLError) -> AgentError {
        switch error.code {
        case .cancelled:
            return AgentError(category: .cancelled, diagnosticMessage: "request cancelled")
        case .timedOut:
            return AgentError(category: .timeout, isRetriable: true,
                              diagnosticMessage: "request timed out")
        default:
            return AgentError(category: .network, isRetriable: true,
                              diagnosticMessage: "network failure",
                              providerErrorCode: "URLError_\(error.code.rawValue)")
        }
    }

    private static func mapHTTPStatus(_ status: Int) -> AgentError {
        let retriable = status >= 500
        return AgentError(category: .providerRejected,
                          isRetriable: retriable,
                          diagnosticMessage: "provider returned http \(status)",
                          providerErrorCode: "HTTP_\(status)")
    }

    private static func parse(_ data: Data, fallbackModel: String) throws -> AssistantResult {
        guard
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String,
            !content.isEmpty
        else {
            throw AgentError(category: .providerRejected,
                             diagnosticMessage: "invalid response shape")
        }
        let model = (root["model"] as? String) ?? fallbackModel
        return AssistantResult(text: content, model: model)
    }
}
