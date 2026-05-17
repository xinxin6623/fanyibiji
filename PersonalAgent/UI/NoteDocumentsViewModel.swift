import Foundation
import Combine

/// 多草稿 / Tab 编排层(@MainActor,UI 边界)。
///
/// 设计:**不动** `NoteEditorViewModel` 内部逻辑——它从「全局唯一」
/// 变为「每 Tab 一个实例」。所有已修过的坑(状态机短路 / 空操作反馈 /
/// 保存语义)在每个 Tab 各自成立。
///
/// 关闭 Tab = 仅从 `documents` 移除,**草稿文件留盘**(James 明确
/// 不怕丢,全量留存)。被关闭的草稿可经「历史草稿」列表重新打开。
@MainActor
final class NoteDocumentsViewModel: ObservableObject {

    /// 一个打开的草稿 Tab。
    final class Tab: Identifiable, ObservableObject {
        let id: UUID
        let editor: NoteEditorViewModel
        /// Tab 显示名(草稿首行,空 → "未命名");随输入刷新。
        @Published var title: String

        init(id: UUID, editor: NoteEditorViewModel, title: String) {
            self.id = id
            self.editor = editor
            self.title = title
        }
    }

    /// 历史草稿列表项(notes/ 里存在但未在 Tab 打开的)。
    struct HistoryItem: Identifiable, Equatable {
        let id: UUID
        let title: String
    }

    @Published private(set) var tabs: [Tab] = []
    @Published var selectedID: UUID?

    private let store: NoteDraftStore
    private var cancellables: Set<AnyCancellable> = []

    init(store: NoteDraftStore) {
        self.store = store
        restore()
    }

    /// 当前选中 Tab(导出原料包/插入均作用于它)。
    var selected: Tab? {
        tabs.first { $0.id == selectedID } ?? tabs.first
    }

    // MARK: - 启动恢复

    private func restore() {
        let manifest = store.loadManifest()
        if manifest.entries.isEmpty {
            newDocument()                 // 首次运行:开一个空草稿
            return
        }
        tabs = manifest.entries.map { makeTab(id: $0.id) }
        selectedID = manifest.selectedID ?? tabs.first?.id
        persistManifest()
    }

    // MARK: - Tab 操作

    func newDocument() {
        let id = UUID()
        let tab = makeTab(id: id)
        tabs.append(tab)
        selectedID = id
        persistManifest()
    }

    /// 关闭 Tab:只从列表移除,**不删文件**(留存,可经历史重开)。
    func closeDocument(_ id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: idx)
        if selectedID == id {
            selectedID = tabs[safe: idx]?.id ?? tabs.last?.id
        }
        persistManifest()
    }

    func select(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedID = id
        persistManifest()
    }

    /// 历史草稿 = 磁盘有、但当前未在 Tab 打开的草稿。
    func history() -> [HistoryItem] {
        let open = Set(tabs.map(\.id))
        return store.allDraftIDs()
            .filter { open.contains($0) == false }
            .map { id in
                let first = (try? store.load(id: id))?
                    .split(separator: "\n").first.map(String.init) ?? ""
                return HistoryItem(id: id, title: displayTitle(first))
            }
    }

    /// 从历史重新打开一个已关闭的草稿(回到 Tab)。
    func openFromHistory(_ id: UUID) {
        if tabs.contains(where: { $0.id == id }) { selectedID = id; return }
        let tab = makeTab(id: id)
        tabs.append(tab)
        selectedID = id
        persistManifest()
    }

    // MARK: - 内部

    private func makeTab(id: UUID) -> Tab {
        let editor = NoteEditorViewModel(store: store, draftID: id)
        let tab = Tab(id: id,
                      editor: editor,
                      title: displayTitle(firstLine(of: editor.text)))
        // 草稿首行变 → Tab 标题刷新 + manifest 缓存(避免每次读文件)。
        editor.$text
            .map { [weak self] in self?.displayTitle(self?.firstLine(of: $0) ?? "") ?? "" }
            .removeDuplicates()
            .sink { [weak self, weak tab] newTitle in
                tab?.title = newTitle
                self?.persistManifest()
            }
            .store(in: &cancellables)
        return tab
    }

    private func firstLine(of text: String) -> String {
        text.split(separator: "\n").first.map(String.init) ?? ""
    }

    private func displayTitle(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "未命名" : String(t.prefix(40))
    }

    private func persistManifest() {
        let entries = tabs.map {
            NoteDraftStore.Entry(id: $0.id, title: $0.title)
        }
        try? store.saveManifest(
            .init(entries: entries, selectedID: selectedID))
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}
