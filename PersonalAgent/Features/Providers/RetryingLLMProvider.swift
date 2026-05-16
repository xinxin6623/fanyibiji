import Foundation

/// 给任意 `LLMProvider` 叠加有界重试的装饰器。
///
/// 用装饰器而非改 `OpenAICompatibleLLMProvider`：T07a 已验证的最小闭环
/// 零改动、零回归（AGENTS：新增能力不破坏 P1 回归）。只对
/// `AgentError.isRetriable` 重试；`.cancelled` 立即停止；耗尽次数抛最后
/// 一次错误。多模型由 `ResolvedProviderConfig.model` 承载，无需额外代码；
/// 流式按 AGENTS「不提前造系统」推迟到确有需求。
struct RetryingLLMProvider: LLMProvider {
    let id: String

    private let wrapped: LLMProvider
    private let maxAttempts: Int
    private let sleep: @Sendable (UInt64) async -> Void

    init(wrapping provider: LLMProvider,
         maxAttempts: Int = 3,
         sleep: @escaping @Sendable (UInt64) async -> Void = {
             try? await Task.sleep(nanoseconds: $0)
         }) {
        self.wrapped = provider
        self.maxAttempts = max(1, maxAttempts)
        self.sleep = sleep
        self.id = provider.id
    }

    func validate() throws { try wrapped.validate() }

    func complete(_ context: QueryContext) async throws -> AssistantResult {
        var attempt = 0
        while true {
            attempt += 1
            do {
                return try await wrapped.complete(context)
            } catch let error as AgentError {
                let canRetry = error.isRetriable
                    && error.category != .cancelled
                    && attempt < maxAttempts
                guard canRetry else { throw error }
                // 指数退避：100ms, 200ms, 400ms…（首个失败后才等待）。
                await sleep(UInt64(100_000_000) << (attempt - 1))
            }
        }
    }
}
