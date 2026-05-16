import XCTest
@testable import PersonalAgent

/// T08 取词 + T09 翻译 UI 动作分发单测（headless 编排层）。
///
/// 覆盖：剪贴板取词→LLM 问答、剪贴板取词→T09 翻译、取词失败（空/
/// 纯空白）不触发空查询、provider 失败分类透传、落盘 provider 字段
/// 可溯源走的是 LLM 还是翻译通道。GUI 按钮属真机，不在此造。
@MainActor
final class TClipboardDispatchTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func store() -> JSONLResultStore {
        JSONLResultStore(fileURL: dir.appendingPathComponent("r.jsonl"))
    }

    // MARK: 桩

    private struct OKLLM: LLMProvider {
        let id = "llm"
        func validate() throws {}
        func complete(_ c: QueryContext) async throws -> AssistantResult {
            XCTAssertEqual(c.sourceKind, .clipboard)
            XCTAssertEqual(c.userAction, .query)
            return AssistantResult(text: "ai:\(c.inputText)", model: "m")
        }
    }

    private struct OKTranslate: TranslateProvider {
        let id = "tr"
        func validate() throws {}
        func translate(_ c: QueryContext) async throws -> TranslationResult {
            XCTAssertEqual(c.sourceKind, .clipboard)
            XCTAssertEqual(c.userAction, .translate)
            // 取词翻译经 languageHints 传目标语言代码给 T09。
            XCTAssertEqual(c.languageHints.first, "zh")
            return TranslationResult(text: "译:\(c.inputText)",
                                     sourceLang: "en", targetLang: "zh")
        }
    }

    private struct FailTranslate: TranslateProvider {
        let id = "tr-fail"
        let err: AgentError
        func validate() throws {}
        func translate(_ c: QueryContext) async throws -> TranslationResult {
            throw err
        }
    }

    private func vm(clip: String?,
                    llm: LLMProvider = OKLLM(),
                    tr: TranslateProvider = OKTranslate()) -> ContentQueryViewModel {
        makeTestViewModel(
            provider: llm,
            translateProvider: tr,
            clipboard: ClipboardTextGrabber(
                pasteboard: SharedStubPasteboard(value: clip)),
            store: store())
    }

    // MARK: 取词查询（→LLM）

    func testQueryFromClipboardGoesToLLM() async {
        let s = store()
        let v = makeTestViewModel(
            provider: OKLLM(),
            clipboard: ClipboardTextGrabber(
                pasteboard: SharedStubPasteboard(value: "  hello  ")),
            store: s)
        await v.queryFromClipboard()
        guard case let .success(model) = v.state else {
            return XCTFail("expected success, got \(v.state)")
        }
        XCTAssertEqual(model.provider, "llm")
        XCTAssertEqual(model.content, .text("ai:hello"))
        XCTAssertEqual(try s.readAll().count, 1)
    }

    func testEmptyClipboardQueryFailsWithoutCallingProvider() async {
        let v = vm(clip: "   ")
        await v.queryFromClipboard()
        XCTAssertEqual(v.state, .failure(.invalidInput))
        XCTAssertEqual(v.inputText, "")
    }

    func testNilClipboardQueryFailsInvalidInput() async {
        let v = vm(clip: nil)
        await v.queryFromClipboard()
        XCTAssertEqual(v.state, .failure(.invalidInput))
    }

    // MARK: 取词翻译（→T09 TranslateProvider）

    func testTranslateFromClipboardGoesToTranslateProvider() async {
        let s = store()
        let v = makeTestViewModel(
            provider: OKLLM(),
            translateProvider: OKTranslate(),
            clipboard: ClipboardTextGrabber(
                pasteboard: SharedStubPasteboard(value: " 世界 ")),
            store: s)
        await v.translateFromClipboard()
        guard case let .success(model) = v.state else {
            return XCTFail("expected success, got \(v.state)")
        }
        // 落盘 provider 字段证明走的是翻译通道而非 LLM。
        XCTAssertEqual(model.provider, "tr")
        XCTAssertEqual(model.content, .text("译:世界"))
        XCTAssertEqual(model.tags, ["lang:en", "lang:zh"])
        XCTAssertEqual(try s.readAll().count, 1)
    }

    func testEmptyClipboardTranslateFailsWithoutCallingProvider() async {
        let v = vm(clip: "")
        await v.translateFromClipboard()
        XCTAssertEqual(v.state, .failure(.invalidInput))
        XCTAssertEqual(v.inputText, "")
    }

    func testTranslateProviderErrorMapsToFailureCategory() async {
        let v = vm(clip: "hi",
                   tr: FailTranslate(err: AgentError(category: .network,
                                                     isRetriable: true)))
        await v.translateFromClipboard()
        XCTAssertEqual(v.state, .failure(.network))
    }

    func testTranslateProviderNonAgentErrorMapsToUnknown() async {
        struct Boom: TranslateProvider {
            let id = "boom"
            func validate() throws {}
            func translate(_ c: QueryContext) async throws -> TranslationResult {
                struct E: Error {}
                throw E()
            }
        }
        let v = vm(clip: "hi", tr: Boom())
        await v.translateFromClipboard()
        XCTAssertEqual(v.state, .failure(.unknown))
    }
}
