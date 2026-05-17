import Foundation

/// 右侧笔记编辑区的状态与持久化编排（`@MainActor`，UI 边界）。
///
/// 设计要点：
///  - 翻译结果只读、随采集更新（保持现状）；这里是**独立**的笔记草稿，
///    用户手敲，与 `results.jsonl` 分离，单独归档到 note-draft.md。
///  - 编辑/预览双模式：`mode` 切换；编辑态前端用 `TextEditor` 改 Markdown
///    源码，预览态用 SwiftUI 原生 Markdown 渲染（视图层负责）。
///  - 保存时机「两者都要」：手动 `save()` + 停止输入 1.5s 后防抖自动保存
///    （沿用本仓 TTS 设置的 `Task.sleep` 防抖模式，可取消重排）。
///  - 文本变更经 `text` 的 `didSet` 标脏并重排自动保存；保存后清脏。
@MainActor
final class NoteEditorViewModel: ObservableObject {

    enum Mode: Equatable { case edit, preview }

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
            // 来自 load() 的首次灌入不算用户改动（loadingFromDisk 守门）。
            guard !loadingFromDisk else { return }
            saveStatus = .dirty
            scheduleAutosave()
        }
    }

    @Published var mode: Mode = .edit
    @Published private(set) var saveStatus: SaveStatus = .clean

    private let store: NoteDraftStore
    private var autosaveTask: Task<Void, Never>?
    private var loadingFromDisk = false

    /// 上次成功落盘的内容快照。判定「是否需要写」只看它与当前 `text`
    /// 是否一致——而非 `saveStatus` 枚举（旧实现按 `.saved` 提前返回，
    /// 导致自动保存后手动保存无效）。
    private var lastPersistedText: String = ""

    /// 自动保存防抖窗口（停止输入后多久落盘）。
    private let autosaveDelay: Duration = .milliseconds(1500)

    init(store: NoteDraftStore) {
        self.store = store
        loadDraft()
    }

    /// 启动读回草稿。读失败不清空已有内容、只反馈状态（避免覆盖用户
    /// 可能仍在内存里的文字）；缺失/空文件按 store 语义返回空串。
    func loadDraft() {
        loadingFromDisk = true
        defer { loadingFromDisk = false }
        do {
            let loaded = try store.load()
            text = loaded
            lastPersistedText = loaded
            saveStatus = .clean
        } catch let error as AgentError {
            saveStatus = .failed(error.category)
        } catch {
            saveStatus = .failed(.persistence)
        }
    }

    /// 把给定文本插入到当前内容尾部（视图层无法回传光标位置时的兜底）。
    /// 视图传 `at:` 时按字符偏移插入到光标处。插入算用户改动 → 触发
    /// 防抖自动保存。返回插入后光标应落的字符偏移，供视图回设选区。
    @discardableResult
    func insert(_ snippet: String, at offset: Int? = nil) -> Int {
        guard !snippet.isEmpty else { return offset ?? text.count }
        // 衔接处补换行：尾部插入且已有内容不以换行结尾时，前置空行。
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
            try store.save(text)
            lastPersistedText = text
            saveStatus = .saved(Date())
        } catch let error as AgentError {
            saveStatus = .failed(error.category)
        } catch {
            saveStatus = .failed(.persistence)
        }
    }
}
