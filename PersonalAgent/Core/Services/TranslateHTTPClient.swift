import Foundation

/// 翻译 provider 的网络出口抽象：隔离 URLSession，便于单测注入桩。
/// 与 `LLMHTTPClient` 分开，避免翻译（可替换、可逆向）与 LLM 主路径
/// 私有耦合（AGENTS：逆向 Web API 不得成为核心依赖）。
protocol TranslateHTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// 生产实现：URLSession。错误不在此翻译，交 provider 映射 `AgentError`。
struct URLSessionTranslateHTTPClient: TranslateHTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AgentError(category: .network,
                             isRetriable: true,
                             diagnosticMessage: "non-http response")
        }
        return (data, http)
    }
}
