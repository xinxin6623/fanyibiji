import XCTest
@testable import PersonalAgent

/// 笔记草稿持久化 + 编辑区编排单测。
/// 真机手验由 James 决定；这里覆盖纯逻辑：读写往返、空文件、原子覆盖、
/// 插入光标处、脏标记/保存状态流转。
final class TNoteEditorTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tnote-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeStore() -> NoteDraftStore {
        NoteDraftStore(
            notesDirectory: tempDir.appendingPathComponent("notes"))
    }

    /// 多草稿改造后:每个测试用固定 id 操作单草稿,等价旧单文件语义。
    private let did = UUID()

    @MainActor
    private func makeVM(_ store: NoteDraftStore) -> NoteEditorViewModel {
        NoteEditorViewModel(store: store, draftID: did)
    }

    // MARK: - NoteDraftStore

    func testLoadMissingFileReturnsEmpty() throws {
        XCTAssertEqual(try makeStore().load(id: did), "")
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = makeStore()
        let md = "# 标题\n\n正文 **加粗** 与 `code`。\n- 列表项"
        try store.save(id: did, text: md)
        XCTAssertEqual(try store.load(id: did), md)
    }

    func testSaveOverwritesAtomically() throws {
        let store = makeStore()
        try store.save(id: did, text: "first version")
        try store.save(id: did, text: "second version, longer content")
        XCTAssertEqual(try store.load(id: did), "second version, longer content")
    }

    func testSaveCreatesParentDirectory() throws {
        // notes/ 子目录此前不存在，save 应按需创建。
        let store = makeStore()
        try store.save(id: did, text: "x")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: tempDir.appendingPathComponent(
                "notes/draft-\(did.uuidString).md").path))
    }

    // MARK: - NoteEditorViewModel

    @MainActor
    func testInitLoadsExistingDraftAsClean() throws {
        let store = makeStore()
        try store.save(id: did, text: "已有草稿")
        let vm = makeVM(store)
        XCTAssertEqual(vm.text, "已有草稿")
        XCTAssertEqual(vm.saveStatus, .clean)
    }

    @MainActor
    func testUserEditMarksDirty() {
        let vm = makeVM(makeStore())
        XCTAssertEqual(vm.saveStatus, .clean)
        vm.text = "用户敲入"
        XCTAssertEqual(vm.saveStatus, .dirty)
    }

    @MainActor
    func testInsertAtEndAddsBlankLineSeparator() {
        let vm = makeVM(makeStore())
        vm.text = "已有内容"
        let cursor = vm.insert("译文片段")
        XCTAssertEqual(vm.text, "已有内容\n\n译文片段")
        XCTAssertEqual(cursor, vm.text.count)
        XCTAssertEqual(vm.saveStatus, .dirty)
    }

    @MainActor
    func testInsertIntoEmptyHasNoLeadingNewlines() {
        let vm = makeVM(makeStore())
        vm.insert("第一段")
        XCTAssertEqual(vm.text, "第一段")
    }

    @MainActor
    func testInsertAtOffsetSplitsExisting() {
        let vm = makeVM(makeStore())
        vm.text = "ABCDEF"
        let cursor = vm.insert("X", at: 3)
        // 偏移 3 前一字符是 'C'(非换行) → 前置空行衔接。
        XCTAssertEqual(vm.text, "ABC\n\nXDEF")
        XCTAssertEqual(cursor, 3 + 3)  // idx + "\n\nX".count
    }

    @MainActor
    func testManualSavePersistsAndMarksSaved() throws {
        let store = makeStore()
        let vm = makeVM(store)
        vm.text = "手动保存内容"
        vm.save()
        if case .saved = vm.saveStatus {} else {
            XCTFail("期望 .saved，实际 \(vm.saveStatus)")
        }
        // 新建一个 VM 从磁盘读回，确认确实落盘。
        let reread = makeVM(store)
        XCTAssertEqual(reread.text, "手动保存内容")
    }

    @MainActor
    func testMarkExportedReflectsTargetURL() {
        let vm = makeVM(makeStore())
        let url = URL(fileURLWithPath: "/tmp/note-x.md")
        vm.markExported(to: url)
        guard case let .exported(u) = vm.saveStatus else {
            return XCTFail("应为 .exported，实际 \(vm.saveStatus)")
        }
        XCTAssertEqual(u, url)
    }

    @MainActor
    func testMarkExportFailedSetsStatus() {
        let vm = makeVM(makeStore())
        vm.markExportFailed()
        XCTAssertEqual(vm.saveStatus, .exportFailed)
    }

    /// 手动 save 即使无改动也回显 .saved（给用户可见反馈，区别于自动
    /// 保存路径的静默 .clean），且不应误标可保存。
    @MainActor
    func testManualSaveWhenCleanGivesSavedFeedback() {
        let vm = makeVM(makeStore())
        vm.save()  // 无改动
        if case .saved = vm.saveStatus {} else {
            XCTFail("空操作手动保存应回显 .saved，实际 \(vm.saveStatus)")
        }
        XCTAssertFalse(vm.canSave)
    }

    /// 回归:自动保存把状态置 .saved 后,再编辑+手动保存必须真的写盘。
    /// 旧实现 persist() 见 .saved 即提前返回 → 手动保存无效。
    @MainActor
    func testManualSaveStillWorksAfterAutosaveMarkedSaved() throws {
        let store = makeStore()
        let vm = makeVM(store)
        vm.text = "第一次"
        vm.save()
        guard case .saved = vm.saveStatus else {
            return XCTFail("首存应为 .saved，实际 \(vm.saveStatus)")
        }
        XCTAssertFalse(vm.canSave)        // 落盘后无待存改动

        vm.text = "第二次内容"             // 继续编辑
        XCTAssertTrue(vm.canSave)         // 又有改动 → 按钮应可点
        vm.save()                         // 关键:此时不能被 .saved 短路
        XCTAssertEqual(
            makeVM(store).text, "第二次内容",
            "手动保存未把新内容落盘")
    }

    // MARK: - 源追 sidecar(原料包 A)

    @MainActor
    func testInsertWithSourceIDPersistsToSidecar() throws {
        let store = makeStore()
        let vm = makeVM(store)
        let rid = UUID()
        vm.insert("译文", sourceResultID: rid)
        XCTAssertTrue(vm.referencedResultIDs.contains(rid))
        // 新 VM 从 sidecar 读回 → 源追 id 持久化成功。
        XCTAssertTrue(makeVM(store).referencedResultIDs.contains(rid))
    }

    @MainActor
    func testInsertWithoutSourceIDKeepsRefsEmpty() {
        let vm = makeVM(makeStore())
        vm.insert("手敲译文")
        XCTAssertTrue(vm.referencedResultIDs.isEmpty)
    }

}

// MARK: - NotePackComposer(原料包 A∪B 去重 + 清洗)

final class TNotePackTests: XCTestCase {

    private func r(_ id: UUID, src: String, tr: String,
                   error: AgentError? = nil,
                   audio: Bool = false) -> ResultModel {
        ResultModel(
            id: id, contextId: UUID(), provider: "p",
            content: audio ? .audio(ref: "a", format: "mp3", durationMs: nil)
                           : .text(tr),
            tags: [], error: error, createdAt: Date(),
            sourceText: src)
    }

    func testAHitBySourceTracking() {
        let id = UUID()
        let pairs = NotePackComposer.relevantPairs(
            draft: "草稿没提到译文",
            referencedResultIDs: [id],
            allResults: [r(id, src: "hello", tr: "你好")])
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs[0].source, "hello")
        XCTAssertEqual(pairs[0].translation, "你好")
        XCTAssertTrue(pairs[0].viaSourceTracking)
    }

    func testBHitByTextContainmentWhenNoSourceID() {
        let id = UUID()
        let pairs = NotePackComposer.relevantPairs(
            draft: "笔记里贴了 世界 这段译文",
            referencedResultIDs: [],
            allResults: [r(id, src: "world", tr: "世界")])
        XCTAssertEqual(pairs.count, 1)
        XCTAssertFalse(pairs[0].viaSourceTracking)
    }

    func testAUnionBDedupSameResultOnce() {
        let id = UUID()
        // 既被源追、又文本命中 → 只出一次,标 A。
        let pairs = NotePackComposer.relevantPairs(
            draft: "含 你好 文本",
            referencedResultIDs: [id],
            allResults: [r(id, src: "hi", tr: "你好")])
        XCTAssertEqual(pairs.count, 1)
        XCTAssertTrue(pairs[0].viaSourceTracking)
    }

    func testFailedAndAudioExcluded() {
        let f = UUID(), a = UUID()
        let pairs = NotePackComposer.relevantPairs(
            draft: "x",
            referencedResultIDs: [f, a],
            allResults: [
                r(f, src: "s", tr: "t",
                  error: AgentError(category: .unknown,
                                    diagnosticMessage: "x")),
                r(a, src: "s2", tr: "", audio: true)])
        XCTAssertTrue(pairs.isEmpty)
    }

    func testNoSourceTextEntrySkipped() {
        let id = UUID()
        let m = ResultModel(
            id: id, contextId: UUID(), provider: "p",
            content: .text("译文"), tags: [], error: nil,
            createdAt: Date(), sourceText: nil)   // 旧 jsonl 行
        let pairs = NotePackComposer.relevantPairs(
            draft: "", referencedResultIDs: [id], allResults: [m])
        XCTAssertTrue(pairs.isEmpty)
    }

    func testComposeEmptyHistoryStillEmitsDraft() {
        let md = NotePackComposer.compose(
            draft: "我的草稿", referencedResultIDs: [], allResults: [],
            now: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(md.contains("我的草稿"))
        XCTAssertTrue(md.contains("无相关翻译历史"))
    }

    func testComposeEmptyDraftPlaceholder() {
        let md = NotePackComposer.compose(
            draft: "", referencedResultIDs: [], allResults: [],
            now: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(md.contains("(空草稿)"))
    }
}

// MARK: - NoteDocumentsViewModel(多草稿 Tab)

final class TNoteDocumentsTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tdocs-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }
    private func makeStore() -> NoteDraftStore {
        NoteDraftStore(notesDirectory: tempDir.appendingPathComponent("n"))
    }

    @MainActor
    func testFreshStartOpensOneEmptyDraft() {
        let vm = NoteDocumentsViewModel(store: makeStore())
        XCTAssertEqual(vm.tabs.count, 1)
        XCTAssertNotNil(vm.selected)
    }

    @MainActor
    func testNewDocumentAddsAndSelects() {
        let vm = NoteDocumentsViewModel(store: makeStore())
        let first = vm.selectedID
        vm.newDocument()
        XCTAssertEqual(vm.tabs.count, 2)
        XCTAssertNotEqual(vm.selectedID, first)
    }

    @MainActor
    func testCloseKeepsFileOnDisk() throws {
        let store = makeStore()
        let vm = NoteDocumentsViewModel(store: store)
        let id = vm.selected!.id
        vm.selected!.editor.text = "留存内容"
        vm.selected!.editor.save()
        vm.closeDocument(id)
        XCTAssertFalse(vm.tabs.contains { $0.id == id })
        // 文件仍在磁盘(全量留存)。
        XCTAssertEqual(try store.load(id: id), "留存内容")
    }

    @MainActor
    func testHistoryListsClosedAndReopen() {
        let store = makeStore()
        let vm = NoteDocumentsViewModel(store: store)
        let id = vm.selected!.id
        vm.selected!.editor.text = "历史标题行\n正文"
        vm.selected!.editor.save()
        vm.newDocument()                 // 保证关闭后还有 Tab
        vm.closeDocument(id)
        let hist = vm.history()
        XCTAssertTrue(hist.contains { $0.id == id })
        vm.openFromHistory(id)
        XCTAssertTrue(vm.tabs.contains { $0.id == id })
    }

    @MainActor
    func testTabsIsolateText() {
        let vm = NoteDocumentsViewModel(store: makeStore())
        let a = vm.selected!
        vm.newDocument()
        let b = vm.selected!
        a.editor.text = "A 内容"
        b.editor.text = "B 内容"
        XCTAssertEqual(a.editor.text, "A 内容")
        XCTAssertEqual(b.editor.text, "B 内容")
        XCTAssertNotEqual(a.id, b.id)
    }

    @MainActor
    func testCrossTabSourceMapNotLeaked() {
        let vm = NoteDocumentsViewModel(store: makeStore())
        let a = vm.selected!
        let ridA = UUID()
        a.editor.insert("A译文", sourceResultID: ridA)
        vm.newDocument()
        let b = vm.selected!
        let ridB = UUID()
        b.editor.insert("B译文", sourceResultID: ridB)
        // 关键:各 Tab sourceMap 互不串。
        XCTAssertTrue(a.editor.referencedResultIDs.contains(ridA))
        XCTAssertFalse(a.editor.referencedResultIDs.contains(ridB))
        XCTAssertTrue(b.editor.referencedResultIDs.contains(ridB))
        XCTAssertFalse(b.editor.referencedResultIDs.contains(ridA))
    }

    @MainActor
    func testManifestCorruptDegradesToDiskScan() throws {
        let store = makeStore()
        let vm0 = NoteDocumentsViewModel(store: store)
        let id = vm0.selected!.id
        vm0.selected!.editor.text = "草稿X"
        vm0.selected!.editor.save()
        // 写坏 manifest.json。
        let mURL = tempDir.appendingPathComponent("n/manifest.json")
        try "{ broken".data(using: .utf8)!.write(to: mURL)
        // 新 VM 应降级扫目录重建,仍能看到草稿。
        let vm1 = NoteDocumentsViewModel(store: store)
        XCTAssertTrue(vm1.tabs.contains { $0.id == id }
                      || vm1.history().contains { $0.id == id })
    }
}
