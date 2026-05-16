import XCTest
@testable import PersonalAgent

/// T12-B 失败落盘 + 重试单测（§8-4 / PRD §10「每次查询至少一条记录」）。
@MainActor
final class T12FailurePersistRetryTests: XCTestCase {

    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("t12b-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }
    private func store() -> JSONLResultStore {
        JSONLResultStore(fileURL: dir.appendingPathComponent("r.jsonl"))
    }

    /// 可切换成功/失败的 LLM 桩（重试场景用）。
    private final class FlakyLLM: LLMProvider {
        let id = "flaky"
        var failuresLeft: Int
        let err: AgentError
        init(failuresLeft: Int,
             err: AgentError = AgentError(category: .network, isRetriable: true)) {
            self.failuresLeft = failuresLeft; self.err = err
        }
        func validate() throws {}
        func complete(_ c: QueryContext) async throws -> AssistantResult {
            if failuresLeft > 0 { failuresLeft -= 1; throw err }
            return AssistantResult(text: "ok", model: "m")
        }
    }

    private struct AlwaysFailTranslate: TranslateProvider {
        let id = "tr-fail"
        func validate() throws {}
        func translate(_ c: QueryContext) async throws -> TranslationResult {
            throw AgentError(category: .timeout, isRetriable: true)
        }
    }

    // MARK: 失败落盘

    func testLLMFailurePersistsFailedResultModel() async throws {
        let s = store()
        let vm = makeTestViewModel(
            provider: FlakyLLM(failuresLeft: 99), store: s)
        await vm.runQuery(with: "hi", sourceKind: .manualInput, action: .query)

        guard case .failure(.network) = vm.state else {
            return XCTFail("expected network failure, got \(vm.state)")
        }
        let rows = try s.readAll()
        XCTAssertEqual(rows.count, 1, "失败也应落一条记录")
        XCTAssertEqual(rows[0].provider, "flaky")
        XCTAssertEqual(rows[0].tags, ["failed"])
        XCTAssertEqual(rows[0].error?.category, .network)
        XCTAssertEqual(rows[0].content, .text(""))
    }

    func testTranslateFailurePersistsFailedResultModel() async throws {
        let s = store()
        let vm = makeTestViewModel(
            provider: FlakyLLM(failuresLeft: 0),
            translateProvider: AlwaysFailTranslate(), store: s)
        await vm.runTranslate("世界", sourceKind: .clipboard)

        guard case .failure(.timeout) = vm.state else {
            return XCTFail("expected timeout, got \(vm.state)")
        }
        let rows = try s.readAll()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].provider, "tr-fail")
        XCTAssertEqual(rows[0].error?.category, .timeout)
    }

    func testCancelledDoesNotPersist() async throws {
        let s = store()
        struct CancelLLM: LLMProvider {
            let id = "c"
            func validate() throws {}
            func complete(_ c: QueryContext) async throws -> AssistantResult {
                throw AgentError(category: .cancelled)
            }
        }
        let vm = makeTestViewModel(provider: CancelLLM(), store: s)
        await vm.runQuery(with: "hi", sourceKind: .manualInput, action: .query)

        // T12-C 语义：取消不回写状态（由 cancelCurrent() 归位 idle），
        // 不弹错误横幅、不落盘。此处未经 cancelCurrent 直接 provider 抛
        // .cancelled，run 方法应早退、状态停在 loading（不变为 failure），
        // 关键断言是「不落盘」。
        if case .failure = vm.state {
            XCTFail("取消不应进入 failure 态，got \(vm.state)")
        }
        XCTAssertEqual(try s.readAll().count, 0, "取消属用户主动，不落盘")
    }

    // MARK: 重试

    func testCanRetryOnlyInFailureWithRecord() async {
        let vm = makeTestViewModel(
            provider: FlakyLLM(failuresLeft: 1), store: store())
        XCTAssertFalse(vm.canRetry, "idle 无记录不可重试")
        await vm.runQuery(with: "hi", sourceKind: .manualInput, action: .query)
        XCTAssertTrue(vm.canRetry, "失败且有记录可重试")
    }

    func testRetryLastSucceedsAfterTransientFailure() async throws {
        let s = store()
        let llm = FlakyLLM(failuresLeft: 1)   // 首次失败，重试成功
        let vm = makeTestViewModel(provider: llm, store: s)

        await vm.runQuery(with: "hi", sourceKind: .manualInput, action: .query)
        XCTAssertEqual(vm.state, .failure(.network))

        await vm.retryLast()
        guard case let .success(model) = vm.state else {
            return XCTFail("retry should succeed, got \(vm.state)")
        }
        XCTAssertEqual(model.content, .text("ok"))
        // 一条失败 + 一条成功，均落盘。
        let rows = try s.readAll()
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].tags, ["failed"])
        XCTAssertEqual(rows[1].content, .text("ok"))
    }

    func testRetryLastNoopWhenNoAttempt() async {
        let vm = makeTestViewModel(
            provider: FlakyLLM(failuresLeft: 0), store: store())
        await vm.retryLast()          // 无记录
        XCTAssertEqual(vm.state, .idle)
    }

    func testRetryTranslatePathReusesTranslateProvider() async throws {
        let s = store()
        let vm = makeTestViewModel(
            provider: FlakyLLM(failuresLeft: 0),
            translateProvider: AlwaysFailTranslate(), store: s)
        await vm.runTranslate("hi", sourceKind: .clipboard)
        XCTAssertEqual(vm.state, .failure(.timeout))
        await vm.retryLast()
        // 仍走翻译 provider（失败），证明重试复用的是翻译通道而非 LLM。
        XCTAssertEqual(vm.state, .failure(.timeout))
        XCTAssertEqual(try s.readAll().count, 2)
        XCTAssertTrue(try s.readAll().allSatisfy { $0.provider == "tr-fail" })
    }
}
