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

    /// 历史记录（最近在前），UI 历史面板消费。`historyError` 非 nil 时
    /// 表示读取失败的分类（损坏行/IO），UI 显示对应本地化文案。
    @Published private(set) var history: [ResultModel] = []
    @Published private(set) var historyError: AgentError.Category?

    private let provider: LLMProvider
    private let translateProvider: TranslateProvider
    private let clipboard: ClipboardTextGrabber
    private let store: JSONLResultStore

    /// 上次尝试的原始参数，供 `retryLast()` 复用（§8-4 允许重试）。
    private struct LastAttempt {
        enum Kind: Equatable {
            case llm(action: UserAction)
            case translate
        }
        let rawText: String
        let sourceKind: InputSourceKind
        let kind: Kind
    }
    private var lastAttempt: LastAttempt?

    /// UI 据此决定是否显示「重试」按钮：仅当处于失败态且有可重试记录。
    var canRetry: Bool {
        if case .failure = state { return lastAttempt != nil }
        return false
    }

    /// 运行中的查询/翻译任务，供取消（§8-8）。同一时刻至多一个。
    private var runningTask: Task<Void, Never>?

    /// UI 据此显示「取消」按钮：仅 loading 且有在跑的任务。
    var canCancel: Bool {
        if case .loading = state { return runningTask != nil }
        return false
    }

    /// 取消进行中的查询/翻译。取消会传导到 provider（其内部
    /// `Task.checkCancellation()` / `URLError.cancelled` → `.cancelled`），
    /// 状态回 idle、不报错、不落盘（取消属用户主动，复用 T12-B 语义）。
    func cancelCurrent() {
        runningTask?.cancel()
        runningTask = nil
        state = .idle
    }

    /// 在受管任务中跑一段查询/翻译逻辑：串行（已有在跑则忽略，避免叠
    /// 请求），完成清理任务句柄。UI 统一经此触发，便于取消与状态归位。
    func dispatch(_ body: @escaping () async -> Void) {
        guard runningTask == nil else { return }
        runningTask = Task { @MainActor in
            await body()
            runningTask = nil
        }
    }

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

        // 记住本次尝试供 retryLast() 复用（失败后可一键重试同一输入）。
        lastAttempt = .init(rawText: text, sourceKind: sourceKind,
                            kind: .llm(action: action))

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
            // 取消由 cancelCurrent() 负责把状态归位到 idle；在途请求随后
            // 抛出的 .cancelled / Task 取消不应回写状态、不落盘，否则与
            // 取消语义打架（§8-8）。
            if error.category == .cancelled || Task.isCancelled { return }
            persistFailure(context: context, provider: provider.id, error: error)
            state = .failure(error.category)
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            let e = AgentError(category: .unknown,
                               diagnosticMessage: "non-AgentError")
            persistFailure(context: context, provider: provider.id, error: e)
            state = .failure(.unknown)
        }
    }

    /// 采集链（截屏/OCR）尚未进入 LLM 就失败时，由编排层把分类透传到
    /// UI 状态。取消属用户主动行为，回到 idle 不显示错误横幅；其余分类
    /// （如 `.permission`）显示对应本地化文案，引导用户处理。
    func reportCaptureFailure(_ category: AgentError.Category) {
        state = category == .cancelled ? .idle : .failure(category)
    }

    // MARK: - T12-B 失败落盘 + 重试（§8-4）

    /// 失败也写一条带 `error` 的 `ResultModel`（content 留空文本占位），
    /// 让历史可追溯失败、且每次查询至少一条记录（PRD §10）。取消属
    /// 用户主动放弃、非失败，不落盘。落盘本身失败按既有非阻断降级
    /// （`try?`，内存缓冲已由 store 兜底）。
    private func persistFailure(context: QueryContext,
                                provider: String,
                                error: AgentError) {
        guard error.category != .cancelled else { return }
        let model = ResultModel(
            contextId: context.id,
            provider: provider,
            content: .text(""),
            tags: ["failed"],
            error: error)
        try? store.append(model)
    }

    /// 重试上一次尝试（同输入、同通道）。无记录则无操作。UI 仅在
    /// `canRetry` 为真时暴露按钮。重试复用原始文本，重新组装 context
    /// （新 id），与首次走完全相同的失败落盘/分类语义。
    func retryLast() async {
        guard let a = lastAttempt else { return }
        switch a.kind {
        case let .llm(action):
            await runQuery(with: a.rawText,
                           sourceKind: a.sourceKind, action: action)
        case .translate:
            await runTranslate(a.rawText, sourceKind: a.sourceKind)
        }
    }

    // MARK: - T12-D 历史读取

    /// 读取本地 JSONL 历史（最近在前，最多 `limit` 条）。读取失败
    /// （损坏行/IO，T11a 约定抛 `.persistence`）记 `historyError` 供 UI
    /// 提示，不崩溃；缺失/空文件按 T11a 返回空列表（非错误）。
    func loadHistory(limit: Int = 200) {
        do {
            let all = try store.readAll()
            history = Array(all.reversed().prefix(limit))
            historyError = nil
        } catch let error as AgentError {
            history = []
            historyError = error.category
        } catch {
            history = []
            historyError = .persistence
        }
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
        lastAttempt = .init(rawText: text, sourceKind: sourceKind,
                            kind: .translate)

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
            if error.category == .cancelled || Task.isCancelled { return }
            persistFailure(context: context,
                           provider: translateProvider.id, error: error)
            state = .failure(error.category)
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            let e = AgentError(category: .unknown,
                               diagnosticMessage: "non-AgentError")
            persistFailure(context: context,
                           provider: translateProvider.id, error: e)
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
