import Foundation

/// LLM provider 的网络出口抽象：隔离 URLSession，便于单测注入桩，
/// 覆盖成功与超时/取消/鉴权/网络各失败分支，不依赖真实网络。
protocol LLMHTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// 生产实现：URLSession。超时由 `URLRequest.timeoutInterval` 承载；
/// Swift Task 取消会自动取消底层 data task。错误不在此处翻译，统一交
/// provider 映射成 `AgentError`，保持网络层无业务语义。
struct URLSessionLLMHTTPClient: LLMHTTPClient {
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
