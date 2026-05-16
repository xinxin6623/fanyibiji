import XCTest
@testable import PersonalAgent

/// T12-D 历史读取接口单测。
///
/// 覆盖：最近在前、limit 截断、空/缺失文件→空列表无错、损坏行→
/// historyError=.persistence 不崩溃、失败记录也在历史里。本地化完整性
/// 由构建期 xcstrings 全键 en+zh-Hans 保证，不在此造运行时断言。
@MainActor
final class T12HistoryTests: XCTestCase {

    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("t12d-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func vm(_ url: URL) -> ContentQueryViewModel {
        makeTestViewModel(
            provider: NoopLLM(),
            store: JSONLResultStore(fileURL: url))
    }
    private struct NoopLLM: LLMProvider {
        let id = "noop"
        func validate() throws {}
        func complete(_ c: QueryContext) async throws -> AssistantResult {
            AssistantResult(text: "", model: nil)
        }
    }

    func testMissingFileGivesEmptyHistoryNoError() {
        let v = vm(dir.appendingPathComponent("nope.jsonl"))
        v.loadHistory()
        XCTAssertTrue(v.history.isEmpty)
        XCTAssertNil(v.historyError)
    }

    func testRecentFirstAndLimit() throws {
        let url = dir.appendingPathComponent("r.jsonl")
        let store = JSONLResultStore(fileURL: url)
        for i in 0..<5 {
            try store.append(ResultModel(
                contextId: UUID(), provider: "p\(i)",
                content: .text("m\(i)")))
        }
        let v = vm(url)
        v.loadHistory(limit: 3)
        XCTAssertEqual(v.history.count, 3, "limit 截断")
        // 最近写入的 m4 应在最前。
        XCTAssertEqual(v.history.first?.content, .text("m4"))
        XCTAssertEqual(v.history.last?.content, .text("m2"))
        XCTAssertNil(v.historyError)
    }

    func testFailedRecordsAppearInHistory() async throws {
        let url = dir.appendingPathComponent("r.jsonl")
        let s = JSONLResultStore(fileURL: url)
        // 借 ViewModel 失败落盘路径写一条失败记录。
        struct FailLLM: LLMProvider {
            let id = "f"
            func validate() throws {}
            func complete(_ c: QueryContext) async throws -> AssistantResult {
                throw AgentError(category: .network, isRetriable: true)
            }
        }
        let writer = makeTestViewModel(provider: FailLLM(), store: s)
        await writer.runQuery(with: "hi", sourceKind: .manualInput,
                              action: .query)

        let v = vm(url)
        v.loadHistory()
        XCTAssertEqual(v.history.count, 1)
        XCTAssertEqual(v.history[0].error?.category, .network)
        XCTAssertEqual(v.history[0].tags, ["failed"])
    }

    func testCorruptLineSetsPersistenceError() throws {
        let url = dir.appendingPathComponent("r.jsonl")
        try "{not valid json\n".data(using: .utf8)!.write(to: url)
        let v = vm(url)
        v.loadHistory()
        XCTAssertTrue(v.history.isEmpty)
        XCTAssertEqual(v.historyError, .persistence,
                       "损坏行映射 .persistence，不崩溃（T11a 约定）")
    }
}
