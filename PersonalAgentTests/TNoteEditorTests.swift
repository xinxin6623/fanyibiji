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
            fileURL: tempDir.appendingPathComponent("notes/note-draft.md"))
    }

    // MARK: - NoteDraftStore

    func testLoadMissingFileReturnsEmpty() throws {
        XCTAssertEqual(try makeStore().load(), "")
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = makeStore()
        let md = "# 标题\n\n正文 **加粗** 与 `code`。\n- 列表项"
        try store.save(md)
        XCTAssertEqual(try store.load(), md)
    }

    func testSaveOverwritesAtomically() throws {
        let store = makeStore()
        try store.save("first version")
        try store.save("second version, longer content")
        XCTAssertEqual(try store.load(), "second version, longer content")
    }

    func testSaveCreatesParentDirectory() throws {
        // notes/ 子目录此前不存在，save 应按需创建。
        let store = makeStore()
        try store.save("x")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: tempDir.appendingPathComponent("notes/note-draft.md").path))
    }

    // MARK: - NoteEditorViewModel

    @MainActor
    func testInitLoadsExistingDraftAsClean() throws {
        let store = makeStore()
        try store.save("已有草稿")
        let vm = NoteEditorViewModel(store: store)
        XCTAssertEqual(vm.text, "已有草稿")
        XCTAssertEqual(vm.saveStatus, .clean)
    }

    @MainActor
    func testUserEditMarksDirty() {
        let vm = NoteEditorViewModel(store: makeStore())
        XCTAssertEqual(vm.saveStatus, .clean)
        vm.text = "用户敲入"
        XCTAssertEqual(vm.saveStatus, .dirty)
    }

    @MainActor
    func testInsertAtEndAddsBlankLineSeparator() {
        let vm = NoteEditorViewModel(store: makeStore())
        vm.text = "已有内容"
        let cursor = vm.insert("译文片段")
        XCTAssertEqual(vm.text, "已有内容\n\n译文片段")
        XCTAssertEqual(cursor, vm.text.count)
        XCTAssertEqual(vm.saveStatus, .dirty)
    }

    @MainActor
    func testInsertIntoEmptyHasNoLeadingNewlines() {
        let vm = NoteEditorViewModel(store: makeStore())
        vm.insert("第一段")
        XCTAssertEqual(vm.text, "第一段")
    }

    @MainActor
    func testInsertAtOffsetSplitsExisting() {
        let vm = NoteEditorViewModel(store: makeStore())
        vm.text = "ABCDEF"
        let cursor = vm.insert("X", at: 3)
        // 偏移 3 前一字符是 'C'(非换行) → 前置空行衔接。
        XCTAssertEqual(vm.text, "ABC\n\nXDEF")
        XCTAssertEqual(cursor, 3 + 3)  // idx + "\n\nX".count
    }

    @MainActor
    func testManualSavePersistsAndMarksSaved() throws {
        let store = makeStore()
        let vm = NoteEditorViewModel(store: store)
        vm.text = "手动保存内容"
        vm.save()
        if case .saved = vm.saveStatus {} else {
            XCTFail("期望 .saved，实际 \(vm.saveStatus)")
        }
        // 新建一个 VM 从磁盘读回，确认确实落盘。
        let reread = NoteEditorViewModel(store: store)
        XCTAssertEqual(reread.text, "手动保存内容")
    }

    @MainActor
    func testMarkExportedReflectsTargetURL() {
        let vm = NoteEditorViewModel(store: makeStore())
        let url = URL(fileURLWithPath: "/tmp/note-x.md")
        vm.markExported(to: url)
        guard case let .exported(u) = vm.saveStatus else {
            return XCTFail("应为 .exported，实际 \(vm.saveStatus)")
        }
        XCTAssertEqual(u, url)
    }

    @MainActor
    func testMarkExportFailedSetsStatus() {
        let vm = NoteEditorViewModel(store: makeStore())
        vm.markExportFailed()
        XCTAssertEqual(vm.saveStatus, .exportFailed)
    }

    /// 手动 save 即使无改动也回显 .saved（给用户可见反馈，区别于自动
    /// 保存路径的静默 .clean），且不应误标可保存。
    @MainActor
    func testManualSaveWhenCleanGivesSavedFeedback() {
        let vm = NoteEditorViewModel(store: makeStore())
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
        let vm = NoteEditorViewModel(store: store)
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
            NoteEditorViewModel(store: store).text, "第二次内容",
            "手动保存未把新内容落盘")
    }
}
