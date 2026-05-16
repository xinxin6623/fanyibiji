import XCTest
@testable import PersonalAgent

private struct StubRecognizer: OCRRecognizing {
    let result: Result<[OCRLine], Error>
    func recognize(_ imageData: Data,
                   languageHints: [String]) async throws -> [OCRLine] {
        try result.get()
    }
}

final class T06OCRTests: XCTestCase {

    private func line(_ text: String, _ conf: Double) -> OCRLine {
        OCRLine(text: text, confidence: conf,
                boundingBox: CGRect(x: 0, y: 0, width: 1, height: 0.1))
    }

    // MARK: - OCRAssembler 纯逻辑

    func testAssembleJoinsTextAndAveragesConfidence() {
        let result = OCRAssembler.assemble(
            [line("hello", 0.9), line("world", 0.7)],
            languageHints: ["en"], sourceImageRef: "img-1")
        XCTAssertEqual(result.fullText, "hello\nworld")
        XCTAssertEqual(result.overallConfidence, 0.8, accuracy: 0.0001)
        XCTAssertEqual(result.blocks.count, 2)
        XCTAssertEqual(result.languageHints, ["en"])
        XCTAssertEqual(result.sourceImageRef, "img-1")
    }

    func testAssembleEmptyIsZeroConfidence() {
        let result = OCRAssembler.assemble([], languageHints: [], sourceImageRef: nil)
        XCTAssertEqual(result.fullText, "")
        XCTAssertEqual(result.overallConfidence, 0)
        XCTAssertTrue(result.blocks.isEmpty)
    }

    // MARK: - OCRCoordinator 编排

    private func coordinator(_ result: Result<[OCRLine], Error>) -> OCRCoordinator {
        OCRCoordinator(recognizer: StubRecognizer(result: result))
    }

    func testSuccessReturnsAssembledResult() async {
        let r = await coordinator(.success([line("abc", 0.95)]))
            .recognize(imageData: Data([0x1]), languageHints: ["en"],
                       sourceImageRef: "ref")
        guard case let .success(ocr) = r else { return XCTFail("expected success") }
        XCTAssertEqual(ocr.fullText, "abc")
        XCTAssertEqual(ocr.sourceImageRef, "ref")
    }

    func testLowConfidenceStillSucceeds() async {
        let r = await coordinator(.success([line("blurry", 0.05)]))
            .recognize(imageData: Data([0x1]))
        guard case let .success(ocr) = r else { return XCTFail("expected success") }
        XCTAssertEqual(ocr.overallConfidence, 0.05, accuracy: 0.0001)
    }

    func testEmptyAndBlankOnlyMapsToInvalidInput() async {
        for lines in [[OCRLine](), [line("   ", 0.9)]] {
            let r = await coordinator(.success(lines)).recognize(imageData: Data())
            assertFailure(r, .invalidInput)
        }
    }

    func testRecognizerAgentErrorPropagates() async {
        let r = await coordinator(.failure(AgentError(category: .invalidInput)))
            .recognize(imageData: Data())
        assertFailure(r, .invalidInput)
    }

    func testRecognizerGenericErrorMapsToUnknown() async {
        struct Boom: Error {}
        let r = await coordinator(.failure(Boom())).recognize(imageData: Data())
        assertFailure(r, .unknown)
    }

    func testCancellationMapsToCancelled() async {
        let r = await coordinator(.failure(CancellationError()))
            .recognize(imageData: Data())
        assertFailure(r, .cancelled)
    }

    private func assertFailure(_ result: Result<OCRResult, AgentError>,
                               _ expected: AgentError.Category,
                               file: StaticString = #filePath,
                               line: UInt = #line) {
        switch result {
        case .success:
            XCTFail("expected failure", file: file, line: line)
        case let .failure(error):
            XCTAssertEqual(error.category, expected, file: file, line: line)
        }
    }
}
