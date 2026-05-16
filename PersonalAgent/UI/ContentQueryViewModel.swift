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

    /// 运行一次查询（手动输入框，来源记为 `.manualInput`）。
    func runQuery() async {
        await runQuery(with: inputText, sourceKind: .manualInput)
    }

    /// 用外部采集到的文本运行查询（截屏 OCR / 剪贴板取词注入）。
    /// 把文本回填输入框便于用户查看与二次编辑，再走同一条管线，
    /// 保留真实 `sourceKind` 供 `ResultModel` 溯源。
    func runQuery(with text: String, sourceKind: InputSourceKind) async {
        inputText = text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .failure(.invalidInput)
            return
        }

        state = .loading
        let context = QueryContext(
            sourceKind: sourceKind,
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

    /// 采集链（截屏/OCR）尚未进入 LLM 就失败时，由编排层把分类透传到
    /// UI 状态。取消属用户主动行为，回到 idle 不显示错误横幅；其余分类
    /// （如 `.permission`）显示对应本地化文案，引导用户处理。
    func reportCaptureFailure(_ category: AgentError.Category) {
        state = category == .cancelled ? .idle : .failure(category)
    }
}
