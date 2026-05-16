import Foundation

/// 垂直闭环的可测编排层（无 SwiftUI 依赖，可 headless 单测）：
/// 文本 → `QueryContext` → `LLMProvider` → `ResultModel` → JSONL 落盘。
///
/// UI 只消费 `state`，失败仅暴露 `AgentError.Category`（不拼接 provider
/// 私有错误，文案在 View 层本地化）。
@MainActor
final class ContentQueryViewModel: ObservableObject {

    enum State: Equatable {
        case idle
        case loading
        case success(ResultModel)
        case failure(AgentError.Category)
    }

    @Published private(set) var state: State = .idle
    @Published var inputText: String = ""

    private let provider: LLMProvider
    private let store: JSONLResultStore

    init(provider: LLMProvider, store: JSONLResultStore) {
        self.provider = provider
        self.store = store
    }

    /// 运行一次查询。落盘失败不丢结果：结果仍展示，state 仍为 success
    /// （记录已进 store 的内存缓冲），持久化错误属非阻断降级。
    func runQuery() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .failure(.invalidInput)
            return
        }

        state = .loading
        let context = QueryContext(
            sourceKind: .clipboard,
            inputText: trimmed,
            userAction: .query
        )

        do {
            let assistant = try await provider.complete(context)
            let model = ResultModel(
                contextId: context.id,
                provider: provider.id,
                content: .text(assistant.text),
                tags: assistant.model.map { ["model:\($0)"] } ?? []
            )
            try? store.append(model)
            state = .success(model)
        } catch let error as AgentError {
            state = .failure(error.category)
        } catch {
            state = .failure(.unknown)
        }
    }
}
