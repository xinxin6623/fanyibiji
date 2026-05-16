import XCTest
@testable import PersonalAgent

/// T-INT2 P2 整合编排层单测。
///
/// 只测可 headless 的 `P2IntegrationCoordinator` 链路与错误分类透传，
/// 以及 `ContentQueryViewModel` 对外部 OCR 文本/采集失败的接入。
/// GUI（overlay/热键/系统授权）按看板约定属真机手动验收，不在此造
/// 无法确定性断言的 UI 测试。
/// 闭包跨并发边界回写的线程安全标志（避免 Swift 6 捕获 var 告警）。
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

final class TINT2IntegrationTests: XCTestCase {

    // MARK: 桩

    private struct StubCapturer: ScreenCapturer {
        let result: Result<ScreenshotResult, Error>
        func capture(_ region: CaptureRegion) async throws -> ScreenshotResult {
            try result.get()
        }
    }

    private struct StubRecognizer: OCRRecognizing {
        let result: Result<[OCRLine], Error>
        func recognize(_ imageData: Data,
                        languageHints: [String]) async throws -> [OCRLine] {
            try result.get()
        }
    }

    private func makeRegion() -> CaptureRegion {
        CaptureRegion(rect: CGRect(x: 0, y: 0, width: 10, height: 10),
                      displayID: 1)!
    }

    private func makeShot() -> ScreenshotResult {
        ScreenshotResult(
            imageData: Data([0x1]),
            display: DisplayInfo(scaleFactor: 2,
                                 pixelSize: CGSize(width: 100, height: 100)))
    }

    private func makeCoordinator(
        screenAuthorized: Bool = true,
        capture: Result<ScreenshotResult, Error>,
        ocr: Result<[OCRLine], Error>
    ) -> P2IntegrationCoordinator {
        let screenAuth = StaticScreenCaptureAuthorizer(
            isAuthorized: screenAuthorized)
        return P2IntegrationCoordinator(
            screenAuth: screenAuth,
            capture: ScreenCaptureCoordinator(
                authorizer: screenAuth,
                capturer: StubCapturer(result: capture)),
            ocr: OCRCoordinator(recognizer: StubRecognizer(result: ocr)))
    }

    // MARK: 链路

    func testHappyPathProducesOCRText() async {
        let coord = makeCoordinator(
            capture: .success(makeShot()),
            ocr: .success([OCRLine(text: "hello world", confidence: 0.9,
                                   boundingBox: .zero)]))
        let out = await coord.captureText(selectRegion: {
            .selected(self.makeRegion())
        })
        guard case .success(let captured) = out else {
            return XCTFail("expected success, got \(out)")
        }
        XCTAssertEqual(captured.text, "hello world")
        XCTAssertEqual(captured.ocr.fullText, "hello world")
    }

    func testUnauthorizedScreenRecordingShortCircuitsBeforeSelection() async {
        // 未授权录屏：在区域选择前短路返回 .permission（不再依赖辅助
        // 功能门；截屏链只看录屏权限）。
        let coord = makeCoordinator(
            screenAuthorized: false,
            capture: .success(makeShot()),
            ocr: .success([OCRLine(text: "x", confidence: 1, boundingBox: .zero)]))
        let regionAsked = LockedFlag()
        let out = await coord.captureText(selectRegion: {
            regionAsked.set()
            return .selected(self.makeRegion())
        })
        guard case .failure(let err) = out else {
            return XCTFail("expected permission failure")
        }
        XCTAssertEqual(err.category, .permission)
        XCTAssertFalse(regionAsked.value, "录屏未授权应在区域选择前短路")
    }

    func testCancelledSelectionMapsToCancelled() async {
        let coord = makeCoordinator(
            capture: .success(makeShot()),
            ocr: .success([OCRLine(text: "x", confidence: 1, boundingBox: .zero)]))
        let out = await coord.captureText(selectRegion: { .cancelled })
        guard case .failure(let err) = out else {
            return XCTFail("expected cancelled")
        }
        XCTAssertEqual(err.category, .cancelled)
    }

    func testEmptyOCRMapsToInvalidInput() async {
        let coord = makeCoordinator(
            capture: .success(makeShot()),
            ocr: .success([OCRLine(text: "   ", confidence: 0.5,
                                   boundingBox: .zero)]))
        let out = await coord.captureText(selectRegion: {
            .selected(self.makeRegion())
        })
        guard case .failure(let err) = out else {
            return XCTFail("expected invalidInput")
        }
        XCTAssertEqual(err.category, .invalidInput)
    }

    func testCaptureFailurePropagatesAgentError() async {
        let coord = makeCoordinator(
            capture: .failure(AgentError(category: .timeout, isRetriable: true)),
            ocr: .success([OCRLine(text: "x", confidence: 1, boundingBox: .zero)]))
        let out = await coord.captureText(selectRegion: {
            .selected(self.makeRegion())
        })
        guard case .failure(let err) = out else {
            return XCTFail("expected timeout")
        }
        XCTAssertEqual(err.category, .timeout)
    }

    // MARK: ViewModel 接入

    @MainActor
    func testOCRTextDefaultsToTranslateWithPromptWrapped() async {
        // 截屏 OCR 文本默认走翻译：发给 provider 的应是包了翻译指令的
        // prompt（含原文），userAction=.translate，sourceKind=.screenshot；
        // 输入框回填原始 OCR 文本（便于用户查看/二次编辑）。
        struct StubLLM: LLMProvider {
            let id = "stub"
            func validate() throws {}
            func complete(_ c: QueryContext) async throws -> AssistantResult {
                XCTAssertEqual(c.sourceKind, .screenshot)
                XCTAssertEqual(c.userAction, .translate)
                XCTAssertTrue(c.inputText.contains("ocr text"),
                              "prompt 应含原文")
                XCTAssertTrue(c.inputText.contains("翻译"),
                              "prompt 应含翻译指令")
                XCTAssertNotEqual(c.inputText, "ocr text",
                                  "翻译路径不应直发裸文本")
                return AssistantResult(text: "译文", model: "m")
            }
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        let vm = ContentQueryViewModel(
            provider: StubLLM(),
            store: JSONLResultStore(
                fileURL: dir.appendingPathComponent("r.jsonl")))
        await vm.runQuery(with: "  ocr text  ", sourceKind: .screenshot)
        guard case .success = vm.state else {
            return XCTFail("expected success, got \(vm.state)")
        }
        XCTAssertEqual(vm.inputText, "  ocr text  ", "输入框回填原始文本")
    }

    func testPromptBuilderShapes() {
        let t = ContentQueryViewModel.prompt(
            for: .translate, text: "hello", targetLanguage: "中文")
        XCTAssertTrue(t.contains("hello"))
        XCTAssertTrue(t.contains("中文"))
        XCTAssertTrue(t.contains("翻译"))

        // 问答/朗读直发原文，不包装。
        XCTAssertEqual(
            ContentQueryViewModel.prompt(
                for: .query, text: "hi", targetLanguage: "中文"), "hi")
        XCTAssertEqual(
            ContentQueryViewModel.prompt(
                for: .speak, text: "hi", targetLanguage: "中文"), "hi")
    }

    @MainActor
    func testReportCaptureFailureCancelledGoesIdleOthersFailure() {
        struct StubLLM: LLMProvider {
            let id = "s"
            func validate() throws {}
            func complete(_ c: QueryContext) async throws -> AssistantResult {
                AssistantResult(text: "", model: nil)
            }
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        let vm = ContentQueryViewModel(
            provider: StubLLM(),
            store: JSONLResultStore(
                fileURL: dir.appendingPathComponent("r.jsonl")))

        vm.reportCaptureFailure(.cancelled)
        XCTAssertEqual(vm.state, .idle)

        vm.reportCaptureFailure(.permission)
        XCTAssertEqual(vm.state, .failure(.permission))
    }
}
