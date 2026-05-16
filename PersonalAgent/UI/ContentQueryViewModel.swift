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
    private let translateProvider: TranslateProvider
    private let clipboard: ClipboardTextGrabber
    private let store: JSONLResultStore

    init(provider: LLMProvider,
         translateProvider: TranslateProvider,
         clipboard: ClipboardTextGrabber,
         store: JSONLResultStore) {
        self.provider = provider
        self.translateProvider = translateProvider
        self.clipboard = clipboard
        self.store = store
    }

    /// 默认翻译目标语言。MVP 固定中文，可配置 UI 属后续任务。
    /// `translateTargetLanguage`：LLM prompt 用的自然语言名（截屏路径）。
    /// `translateTargetLangCode`：T09 provider 的 `tl` 语言代码（取词
    /// 翻译路径，经 `languageHints` 传入）。
    private let translateTargetLanguage = "中文"
    nonisolated static let translateTargetLangCode = "zh"

    /// 运行一次查询（手动输入框，来源记为 `.manualInput`，问答语义）。
    func runQuery() async {
        await runQuery(with: inputText, sourceKind: .manualInput, action: .query)
    }

    /// 用外部采集到的文本运行（截屏 OCR / 剪贴板取词注入）。
    ///
    /// 经 James 确认对齐 Easydict：OCR 文本默认走**翻译**（`action`
    /// 缺省 `.translate`）。把文本回填输入框便于查看/二次编辑，再走
    /// 同一条管线，保留真实 `sourceKind`/`userAction` 供 `ResultModel`
    /// 溯源。翻译指令在本编排层组装（provider 保持纯通道，不感知动作），
    /// 失败分类与落盘行为与问答路径一致。
    func runQuery(with text: String,
                  sourceKind: InputSourceKind,
                  action: UserAction = .translate) async {
        inputText = text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .failure(.invalidInput)
            return
        }

        state = .loading
        let prompt = Self.prompt(for: action,
                                 text: trimmed,
                                 targetLanguage: translateTargetLanguage)
        let context = QueryContext(
            sourceKind: sourceKind,
            inputText: prompt,
            userAction: action
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

    // MARK: - T08 取词动作分发

    /// 剪贴板取词 → LLM 问答（`.query`）。取词失败（空/纯空白）按
    /// `ClipboardTextGrabber` 语义直接 `.invalidInput`，不触发空查询。
    func queryFromClipboard() async {
        switch clipboard.grab() {
        case .success(let text):
            await runQuery(with: text, sourceKind: .clipboard, action: .query)
        case .failure(let error):
            inputText = ""
            state = .failure(error.category)
        }
    }

    /// 剪贴板取词 → 翻译（走 T09 `TranslateProvider`，主翻译通道、
    /// 免 key）。与截屏的"LLM+翻译 prompt"路径有意区分：取词翻译用
    /// 专用翻译 provider，落盘 `provider` 字段据此可溯源走的是哪条。
    func translateFromClipboard() async {
        switch clipboard.grab() {
        case .success(let text):
            await runTranslate(text, sourceKind: .clipboard)
        case .failure(let error):
            inputText = ""
            state = .failure(error.category)
        }
    }

    /// 经 `TranslateProvider` 翻译并落盘。失败分类与 LLM 路径一致语义，
    /// 落盘失败不丢结果（与 `runQuery` 一致的非阻断降级）。
    func runTranslate(_ text: String, sourceKind: InputSourceKind) async {
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
            languageHints: [Self.translateTargetLangCode],
            userAction: .translate
        )

        do {
            let result = try await translateProvider.translate(context)
            let model = ResultModel(
                contextId: context.id,
                provider: translateProvider.id,
                content: .text(result.text),
                tags: [result.sourceLang, result.targetLang]
                    .compactMap { $0 }.map { "lang:\($0)" }
            )
            try? store.append(model)
            state = .success(model)
        } catch let error as AgentError {
            state = .failure(error.category)
        } catch {
            state = .failure(.unknown)
        }
    }

    /// 按动作组装发给 LLM 的提示词。翻译套固定指令（要求只回译文，
    /// 不加解释，原文照抄非目标语言部分以适配 OCR 噪声）；问答/朗读
    /// 直发原文。纯函数，便于单测断言提示词形状。
    nonisolated static func prompt(for action: UserAction,
                                   text: String,
                                   targetLanguage: String) -> String {
        switch action {
        case .translate:
            return """
            请把下面的文本翻译成\(targetLanguage)，只输出译文，不要解释、\
            不要附加原文。若文本已是\(targetLanguage)则原样返回：

            \(text)
            """
        case .query, .speak:
            return text
        }
    }
}
