import XCTest
import AppKit
@testable import PersonalAgent

/// 可变剪贴板桩：合成 ⌘C 时按预设决定是否"产生新内容"
/// （changeCount 是否自增），并记录写回/清空以验证还原。
private final class MutablePasteboard: PasteboardReading, @unchecked Sendable {
    private let lock = NSLock()
    private var _value: String?
    private var _count: Int
    /// 合成复制后注入的"选中文字"；nil 表示无选中（changeCount 不动）。
    private let copyProduces: String?
    private(set) var writes: [String] = []
    private(set) var cleared = false

    init(initial: String?, copyProduces: String?) {
        self._value = initial
        self._count = 0
        self.copyProduces = copyProduces
    }

    func readString() -> String? { lock.lock(); defer { lock.unlock() }; return _value }
    var changeCount: Int { lock.lock(); defer { lock.unlock() }; return _count }

    func writeString(_ value: String) {
        lock.lock(); defer { lock.unlock() }
        _value = value; _count += 1; writes.append(value)
    }
    func clearContents() {
        lock.lock(); defer { lock.unlock() }
        _value = nil; _count += 1; cleared = true
    }

    /// 由 keystroke 桩调用：模拟前台 App 响应 ⌘C 把选中文字写进剪贴板。
    func simulateCopyEffect() {
        guard let t = copyProduces else { return } // 无选中：剪贴板不动
        lock.lock(); defer { lock.unlock() }
        _value = t; _count += 1
    }
}

private struct StubKeystroke: CopyKeystrokeSending {
    let pasteboard: MutablePasteboard
    func sendCopyKeystroke() { pasteboard.simulateCopyEffect() }
}

final class T13SelectionGrabTests: XCTestCase {

    private func makeGrabber(_ pb: MutablePasteboard) -> SelectionTextGrabber {
        SelectionTextGrabber(
            pasteboard: pb,
            keystroke: StubKeystroke(pasteboard: pb),
            timeout: .milliseconds(200),
            pollInterval: .milliseconds(1),
            sleep: { _ in })   // 注入空 sleep，单测不真实等待
    }

    func testGrabsSelectedTextAndTrims() async {
        let pb = MutablePasteboard(initial: "old", copyProduces: "  hi there \n")
        let r = await makeGrabber(pb).grab()
        XCTAssertEqual(try? r.get(), "hi there")
    }

    func testRestoresOriginalClipboardAfterGrab() async {
        let pb = MutablePasteboard(initial: "ORIGINAL", copyProduces: "picked")
        _ = await makeGrabber(pb).grab()
        // 取词后用户原剪贴板必须被还原（AGENTS 硬约束）。
        XCTAssertEqual(pb.writes.last, "ORIGINAL")
        XCTAssertEqual(pb.readString(), "ORIGINAL")
    }

    func testRestoresEmptyClipboardByClearing() async {
        let pb = MutablePasteboard(initial: nil, copyProduces: "picked")
        _ = await makeGrabber(pb).grab()
        XCTAssertTrue(pb.cleared)
    }

    func testNoSelectionFailsInvalidInputSilently() async {
        // copyProduces nil → changeCount 不变 → 超时 → 静默失败
        let pb = MutablePasteboard(initial: "keep", copyProduces: nil)
        let r = await makeGrabber(pb).grab()
        assertInvalidInput(r)
        // 没选中时不应动用户剪贴板。
        XCTAssertEqual(pb.readString(), "keep")
        XCTAssertTrue(pb.writes.isEmpty)
        XCTAssertFalse(pb.cleared)
    }

    func testBlankSelectionFailsInvalidInput() async {
        let pb = MutablePasteboard(initial: "x", copyProduces: "   \n\t ")
        assertInvalidInput(await makeGrabber(pb).grab())
    }

    private func assertInvalidInput(_ r: Result<String, AgentError>,
                                    file: StaticString = #filePath,
                                    line: UInt = #line) {
        switch r {
        case .success:
            XCTFail("expected failure", file: file, line: line)
        case .failure(let e):
            XCTAssertEqual(e.category, .invalidInput, file: file, line: line)
        }
    }
}
