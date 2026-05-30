import Foundation

/// 右侧笔记编辑区的状态与持久化编排（`@MainActor`，UI 边界）。
///
/// 设计要点：
///  - 翻译结果只读、随采集更新（保持现状）；这里是**独立**的笔记草稿，
///    用户手敲，与 `results.jsonl` 分离，单独归档到 note-draft.md。
///  - 行内实时渲染：视图层挂 `MarkdownInlineEditorView`（WKWebView 内
///    TOAST UI Editor WYSIWYG），无编辑/预览分栏；`text` 仍是真理源
///    （Markdown 字符串），由编辑器经 JS 桥双向同步。
///  - 保存时机「两者都要」：手动 `save()` + 停止输入 1.5s 后防抖自动保存
///    （沿用本仓 TTS 设置的 `Task.sleep` 防抖模式，可取消重排）。
///  - 文本变更经 `text` 的 `didSet` 标脏并重排自动保存；保存后清脏。
@MainActor
final class NoteEditorViewModel: ObservableObject {

    /// 归档保存的可见状态，供 UI 顶栏显示「未保存 / 保存中 / 已保存 / 失败」。
    enum SaveStatus: Equatable {
        case clean              // 与磁盘一致
        case dirty              // 有未保存改动
        case saving
        case saved(Date)            // 内部草稿已落盘（防抖自动保存）
        case exported(URL)          // 用户「保存笔记」另存到所选位置
        case exportFailed
        case failed(AgentError.Category)
    }

    @Published var text: String = "" {
        didSet {
            guard text != oldValue else { return }
            // undo/redo 自身回写 text 时不再入撤销栈、不标脏触发新快照
            // （否则栈被自己污染、redo 立刻被清空）。但仍需落盘——撤销
            // 后的内容也是要持久化的状态，故 isApplyingHistory 只跳过
            // 入栈，scheduleAutosave 照走。
            if isApplyingHistory {
                saveStatus = .dirty
                scheduleAutosave()
                return
            }
            // 来自 load() 的首次灌入不算用户改动（loadingFromDisk 守门）。
            guard !loadingFromDisk else { return }
            saveStatus = .dirty
            scheduleAutosave()
            // 连续输入用防抖合并成「一段编辑」一个撤销点；程序化
            // insert() 走 commitUndoSnapshot() 立即落点（见下）。
            scheduleUndoSnapshot(from: oldValue)
        }
    }

    // MARK: - 撤销 / 重做（⌘Z / ⌘⇧Z + 顶栏 ← → 按钮）

    /// 撤销/重做基于**整段文本快照**栈（非字符级 diff）：实现简单、
    /// 对程序化 `insert` 与手敲都稳；连续手敲经防抖合并成一个撤销点，
    /// 避免一次退一个字母。栈深上限防长文档无限增长。
    private var undoStack: [String] = []
    private var redoStack: [String] = []
    private let historyLimit = 20
    /// true 期间 text 的写入来自 undo()/redo() 自身，didSet 跳过入栈。
    private var isApplyingHistory = false
    private var undoSnapshotTask: Task<Void, Never>?
    /// undo 栈里最后一个已记录的稳定状态（防抖期间的中间态不算）。
    private var lastSnapshot: String = ""

    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    /// 防抖落撤销点：停手 `undoCoalesceDelay` 后把 `from`（这段连续
    /// 编辑的**起点**）压栈。压的是起点而非当前值——撤销应回到「这段
    /// 编辑开始前」。被新输入打断则重排，于是整段连续编辑只留一个点。
    private let undoCoalesceDelay: Duration = .milliseconds(600)

    private func scheduleUndoSnapshot(from previous: String) {
        undoSnapshotTask?.cancel()
        undoSnapshotTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.undoCoalesceDelay)
            guard !Task.isCancelled else { return }
            self.pushUndo(previous)
        }
    }

    /// 立即落一个撤销点（值=`snapshot`，应为这次动作**前**的内容）。
    /// 程序化 `insert()` 用它：插入是一次明确动作，整体应可一步撤销，
    /// 不该被防抖合并进随后的手敲。
    private func commitUndoSnapshot(_ snapshot: String) {
        undoSnapshotTask?.cancel()
        undoSnapshotTask = nil
        pushUndo(snapshot)
    }

    private func pushUndo(_ value: String) {
        guard value != lastSnapshot else { return }
        undoStack.append(value)
        if undoStack.count > historyLimit { undoStack.removeFirst() }
        lastSnapshot = value
        redoStack.removeAll()   // 新的改动让 redo 失效（标准编辑器语义）
        refreshHistoryFlags()
    }

    private func refreshHistoryFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    /// 撤销：当前内容入 redo 栈，恢复上一个快照。无快照则无操作。
    func undo() {
        undoSnapshotTask?.cancel()
        undoSnapshotTask = nil
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(text)
        if redoStack.count > historyLimit { redoStack.removeFirst() }
        applyHistory(previous)
        refreshHistoryFlags()
    }

    /// 重做：当前内容入 undo 栈，恢复被撤销的状态。无记录则无操作。
    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(text)
        if undoStack.count > historyLimit { undoStack.removeFirst() }
        applyHistory(next)
        refreshHistoryFlags()
    }

    /// 把历史值写回 text，期间置 isApplyingHistory 让 didSet 不再入栈。
    /// lastSnapshot 同步到该值，避免下次防抖把它当「新起点」重复压栈。
    private func applyHistory(_ value: String) {
        isApplyingHistory = true
        text = value
        lastSnapshot = value
        isApplyingHistory = false
    }

    @Published private(set) var saveStatus: SaveStatus = .clean

    /// 行内编辑器的协调器（弱引用，由 View 在 makeCoordinator 时回调注入）。
    /// 程序化 `insert(_:)` 走它的 `insertAtCursor` 在光标处插入，避免覆盖
    /// 整段 markdown 导致光标位置丢失。
    private weak var editorCoordinator: MarkdownInlineEditorView.Coordinator?

    /// SwiftUI 视图层在 makeCoordinator 完成时回调本方法注入引用。
    func attachEditorCoordinator(_ coord: MarkdownInlineEditorView.Coordinator) {
        self.editorCoordinator = coord
    }

    private let store: NoteDraftStore
    /// 本草稿在 notes/ 下的 id(决定读写哪个文件 + sidecar)。
    let draftID: UUID
    /// 本草稿「插入到编辑区」记录过的来源 result id(原料包 A 源追)。
    /// D1-b:只记 id 集合,不记字符区间——编辑不影响,导出本就给下游
    /// 再加工,不需字符级精确。变更即随 sidecar 持久化。
    private(set) var referencedResultIDs: Set<UUID> = []

    private var autosaveTask: Task<Void, Never>?
    private var loadingFromDisk = false

    /// 上次成功落盘的内容快照。判定「是否需要写」只看它与当前 `text`
    /// 是否一致——而非 `saveStatus` 枚举（旧实现按 `.saved` 提前返回，
    /// 导致自动保存后手动保存无效）。
    private var lastPersistedText: String = ""

    /// 自动保存防抖窗口（停止输入后多久落盘）。
    private let autosaveDelay: Duration = .milliseconds(1500)

    init(store: NoteDraftStore, draftID: UUID) {
        self.store = store
        self.draftID = draftID
        self.referencedResultIDs = store.loadSourceIDs(id: draftID)
        loadDraft()
    }

    /// 启动读回草稿。读失败不清空已有内容、只反馈状态（避免覆盖用户
    /// 可能仍在内存里的文字）；缺失/空文件按 store 语义返回空串。
    func loadDraft() {
        loadingFromDisk = true
        defer { loadingFromDisk = false }
        do {
            let loaded = try store.load(id: draftID)
            text = loaded
            lastPersistedText = loaded
            // 载入的内容是撤销基线：第一次编辑应能一路退回到它，
            // 但它本身不进 undo 栈（没有「比初始更早」的状态可退）。
            lastSnapshot = loaded
            saveStatus = .clean
        } catch let error as AgentError {
            saveStatus = .failed(error.category)
        } catch {
            saveStatus = .failed(.persistence)
        }
    }

    /// 把给定文本插入到笔记中。优先走 inline editor 的「光标处插入」
    /// （保住光标位置 + 让用户能直接 ⌘Z 撤回这次插入）；编辑器未就绪
    /// 或不可用时退回旧行为：追加到尾部、补空行衔接。
    /// `at:` 参数仅在 fallback 路径用；编辑器路径下光标由 WYSIWYG 自管。
    /// 返回值在 fallback 路径下表示插入后光标应落的字符偏移；编辑器路径
    /// 下返回当前 text 的字符数（视图层用不上具体值，保留兼容签名）。
    @discardableResult
    func insert(_ snippet: String,
                at offset: Int? = nil,
                sourceResultID: UUID? = nil) -> Int {
        // 记来源 id（原料包 A 源追）。即便 snippet 为空也先登记——
        // 用户点了「插入」即视为引用该结果。集合变更立即写 sidecar。
        if let sid = sourceResultID, referencedResultIDs.contains(sid) == false {
            referencedResultIDs.insert(sid)
            try? store.saveSourceIDs(id: draftID, ids: referencedResultIDs)
        }
        guard !snippet.isEmpty else { return offset ?? text.count }

        // 程序化插入是一次明确动作：插入**前**的内容立即落一个 ViewModel
        // 撤销点，这样 UI 顶栏的 ← 按钮能一步撤掉刚插入的片段，不被随后
        // 的手敲防抖合并。inline editor 自身的 ⌘Z 仍可分步退（更细粒度）。
        commitUndoSnapshot(text)

        // 优先走编辑器光标处插入：JS 内 `editor.insertText(text)` 会在
        // 当前光标位置插入，保住用户的光标/选区；之后 change 事件回弹
        // 同步回 `text`，不需要这里手动改 text。
        if let coord = editorCoordinator {
            coord.insertAtCursor(snippet)
            return text.count
        }

        // Fallback：编辑器还没 ready（如刚开 App 首屏），按旧行为补换行
        // 追加到尾部。下一帧编辑器 ready 后通过 setMarkdown 推回 JS。
        let chars = Array(text)
        let idx = min(max(offset ?? chars.count, 0), chars.count)
        var piece = snippet
        if idx > 0, chars[idx - 1] != "\n" {
            piece = "\n\n" + piece
        }
        let inserted = Array(piece)
        var next = chars
        next.insert(contentsOf: inserted, at: idx)
        text = String(next)
        return idx + inserted.count
    }

    /// 用户「保存笔记」另存成功（View 弹 NSSavePanel 并写文件后回调）。
    /// 顶栏据此回显导出目标，明确告知已导出到所选位置。
    func markExported(to url: URL) {
        saveStatus = .exported(url)
    }

    /// 另存写文件失败（权限/磁盘）时回调，顶栏给可见错误反馈。
    func markExportFailed() {
        saveStatus = .exportFailed
    }

    /// 内部草稿手动落盘（保留给可能的程序化调用；UI 顶栏现走另存导出，
    /// 草稿仍由防抖自动保存兜底防丢）。空操作也回显「已保存」。
    func save() {
        autosaveTask?.cancel()
        autosaveTask = nil
        if text == lastPersistedText {
            saveStatus = .saved(Date())   // 空操作也回显，明确告知已是最新
            return
        }
        persist()
    }

    /// 停止输入后防抖自动保存：重排定时器，到点未被新输入打断则落盘。
    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.autosaveDelay)
            guard !Task.isCancelled else { return }
            self.persist()
        }
    }

    /// UI 据此决定手动保存按钮是否可点：当前内容与上次落盘不一致即可
    /// 保存（含失败后重试；不依赖 `saveStatus`，避免自动保存后误禁用）。
    var canSave: Bool { text != lastPersistedText }

    /// 实际落盘。内容与上次落盘一致则跳过（真正的幂等判据），否则写盘
    /// 并刷新快照。失败保留 `lastPersistedText` 不变，便于下次重试。
    private func persist() {
        guard text != lastPersistedText else {
            saveStatus = .clean
            return
        }
        saveStatus = .saving
        do {
            try store.save(id: draftID, text: text)
            lastPersistedText = text
            saveStatus = .saved(Date())
        } catch let error as AgentError {
            saveStatus = .failed(error.category)
        } catch {
            saveStatus = .failed(.persistence)
        }
    }
}
