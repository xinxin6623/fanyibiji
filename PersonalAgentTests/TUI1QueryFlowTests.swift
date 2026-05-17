import XCTest
@testable import PersonalAgent

private struct StubLLMProvider: LLMProvider {
    let id = "stub-llm"
    let result: Result<AssistantResult, Error>
    func validate() throws {}
    func complete(_ context: QueryContext) async throws -> AssistantResult {
        try result.get()
    }
}

/// 不参与本套用例的占位翻译 provider（调用即失败，确保未误走翻译路径）。
struct NoopTranslateProvider: TranslateProvider {
    let id = "noop-translate"
    func validate() throws {}
    func translate(_ context: QueryContext) async throws -> TranslationResult {
        throw AgentError(category: .unknown, diagnosticMessage: "noop")
    }
}

/// 可注入剪贴板内容的共享桩（测试目标内复用）。
struct SharedStubPasteboard: PasteboardReading {
    let value: String?
    func readString() -> String? { value }
    var changeCount: Int { 0 }
    func writeString(_ value: String) {}
    func clearContents() {}
}

@MainActor
func makeTestViewModel(
    provider: LLMProvider,
    translateProvider: TranslateProvider = NoopTranslateProvider(),
    clipboard: ClipboardTextGrabber =
        ClipboardTextGrabber(pasteboard: SharedStubPasteboard(value: nil)),
    store: JSONLResultStore
) -> ContentQueryViewModel {
    ContentQueryViewModel(
        provider: provider,
        translateProvider: translateProvider,
        clipboard: clipboard,
        store: store)
}

@MainActor
final class TUI1QueryFlowTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tui1-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeVM(_ result: Result<AssistantResult, Error>,
                        store: JSONLResultStore? = nil) -> ContentQueryViewModel {
        makeTestViewModel(
            provider: StubLLMProvider(result: result),
            store: store ?? JSONLResultStore(
                fileURL: tempDir.appendingPathComponent("results.jsonl")))
    }

    func testSuccessPersistsAndExposesResult() async throws {
        let store = JSONLResultStore(fileURL: tempDir.appendingPathComponent("r.jsonl"))
        let vm = makeVM(.success(AssistantResult(text: "answer", model: "gpt-4o-mini")),
                        store: store)
        vm.inputText = "  hello  "
        await vm.runQuery()

        guard case let .success(model) = vm.state else {
            return XCTFail("expected success, got \(vm.state)")
        }
        XCTAssertEqual(model.content, .text("answer"))
        XCTAssertEqual(model.tags, ["model:gpt-4o-mini"])
        XCTAssertEqual(model.provider, "stub-llm")

        let persisted = try store.readAll()
        XCTAssertEqual(persisted.count, 1)
        XCTAssertEqual(persisted.first?.content, .text("answer"))
    }

    func testEmptyInputFailsWithoutCallingProvider() async {
        let vm = makeVM(.failure(AgentError(category: .network)))
        vm.inputText = "   "
        await vm.runQuery()
        XCTAssertEqual(vm.state, .failure(.invalidInput))
    }

    func testProviderAgentErrorMapsToFailureCategory() async {
        let vm = makeVM(.failure(AgentError(category: .timeout, isRetriable: true)))
        vm.inputText = "hi"
        await vm.runQuery()
        XCTAssertEqual(vm.state, .failure(.timeout))
    }

    func testProviderNonAgentErrorMapsToUnknown() async {
        struct Boom: Error {}
        let vm = makeVM(.failure(Boom()))
        vm.inputText = "hi"
        await vm.runQuery()
        XCTAssertEqual(vm.state, .failure(.unknown))
    }

    func testPersistenceFailureDoesNotBreakSuccess() async throws {
        // 父路径是普通文件 → 落盘必失败，但结果仍应展示。
        let blocker = tempDir.appendingPathComponent("blocker")
        FileManager.default.createFile(atPath: blocker.path, contents: Data())
        let store = JSONLResultStore(
            fileURL: blocker.appendingPathComponent("sub/r.jsonl"))
        let vm = makeVM(.success(AssistantResult(text: "ok", model: nil)),
                        store: store)
        vm.inputText = "hi"
        await vm.runQuery()

        guard case .success = vm.state else {
            return XCTFail("expected success despite persistence failure")
        }
        XCTAssertEqual(store.bufferedFailures.count, 1)
    }
}
