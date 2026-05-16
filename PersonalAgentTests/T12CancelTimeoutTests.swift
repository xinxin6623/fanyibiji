import XCTest
@testable import PersonalAgent

/// T12-C 统一取消 + 超时恢复单测（§8-8）。
///
/// 取消时序用"挂起到被取消"的桩 provider 确定性验证：cancelCurrent()
/// 让状态回 idle、不落盘；超时由 provider 映射 `.timeout`（既有
/// T07a/T09 行为），此处验证编排层把 `.timeout` 透传并落失败记录。
@MainActor
final class T12CancelTimeoutTests: XCTestCase {

    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("t12c-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }
    private func store() -> JSONLResultStore {
        JSONLResultStore(fileURL: dir.appendingPathComponent("r.jsonl"))
    }

    /// 挂起直到任务被取消，然后抛 `.cancelled`（模拟可取消的网络请求）。
    private struct HangingLLM: LLMProvider {
        let id = "hang"
        func validate() throws {}
        func complete(_ c: QueryContext) async throws -> AssistantResult {
            while true {
                try Task.checkCancellation()
                try? await Task.sleep(nanoseconds: 2_000_000)
            }
        }
    }

    private struct TimeoutLLM: LLMProvider {
        let id = "to"
        func validate() throws {}
        func complete(_ c: QueryContext) async throws -> AssistantResult {
            throw AgentError(category: .timeout, isRetriable: true,
                             diagnosticMessage: "request timed out")
        }
    }

    func testCancelReturnsToIdleAndPersistsNothing() async throws {
        let s = store()
        let vm = makeTestViewModel(provider: HangingLLM(), store: s)

        vm.dispatch {
            await vm.runQuery(with: "hi", sourceKind: .manualInput,
                              action: .query)
        }
        // 等其进入 loading。
        for _ in 0..<200 where !vm.canCancel {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(vm.canCancel, "应进入可取消的 loading 态")

        vm.cancelCurrent()
        XCTAssertEqual(vm.state, .idle, "取消后回 idle")
        XCTAssertFalse(vm.canCancel)
        // 给传导一点时间，确认无落盘（取消非失败）。
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(try s.readAll().count, 0, "取消不落盘")
    }

    func testCanCancelOnlyDuringLoading() async {
        let vm = makeTestViewModel(provider: TimeoutLLM(), store: store())
        XCTAssertFalse(vm.canCancel, "idle 不可取消")
        await vm.runQuery(with: "hi", sourceKind: .manualInput, action: .query)
        XCTAssertFalse(vm.canCancel, "结束后（失败态）不可取消")
    }

    func testTimeoutMapsToTimeoutAndPersistsFailure() async throws {
        let s = store()
        let vm = makeTestViewModel(provider: TimeoutLLM(), store: s)
        await vm.runQuery(with: "hi", sourceKind: .manualInput, action: .query)

        XCTAssertEqual(vm.state, .failure(.timeout), "超时统一 .timeout")
        let rows = try s.readAll()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].error?.category, .timeout)
        XCTAssertTrue(vm.canRetry, "超时失败可重试")
    }

    func testDispatchIsSerialIgnoresSecondWhileRunning() async throws {
        let vm = makeTestViewModel(provider: HangingLLM(), store: store())
        vm.dispatch {
            await vm.runQuery(with: "a", sourceKind: .manualInput,
                              action: .query)
        }
        for _ in 0..<200 where !vm.canCancel {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        // 运行中再 dispatch 应被忽略（不叠任务）。
        var secondRan = false
        vm.dispatch { secondRan = true }
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertFalse(secondRan, "已有任务在跑，第二次 dispatch 被忽略")
        vm.cancelCurrent()
    }
}
