import XCTest
@testable import PersonalAgent

final class TCContractsTests: XCTestCase {

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - AgentError

    func testAgentErrorRoundTripsForEveryCategory() throws {
        let encoder = makeEncoder()
        let decoder = makeDecoder()
        let categories: [AgentError.Category] = [
            .permission, .network, .timeout, .cancelled,
            .invalidInput, .persistence, .providerRejected, .unknown
        ]
        for category in categories {
            let error = AgentError(
                category: category,
                isRetriable: true,
                diagnosticMessage: "diag",
                providerErrorCode: "E_42"
            )
            let decoded = try decoder.decode(AgentError.self, from: try encoder.encode(error))
            XCTAssertEqual(decoded, error)
        }
    }

    func testAgentErrorUsesSnakeCaseKeys() throws {
        let error = AgentError(category: .network, isRetriable: true,
                               diagnosticMessage: "x", providerErrorCode: "y")
        let object = try jsonObject(try makeEncoder().encode(error))
        XCTAssertNotNil(object["is_retriable"])
        XCTAssertNotNil(object["diagnostic_message"])
        XCTAssertNotNil(object["provider_error_code"])
        XCTAssertNil(object["isRetriable"])
    }

    func testAgentErrorOptionalsOmittedWhenNil() throws {
        let error = AgentError(category: .cancelled)
        let object = try jsonObject(try makeEncoder().encode(error))
        XCTAssertNil(object["diagnostic_message"])
        XCTAssertNil(object["provider_error_code"])
        XCTAssertEqual(object["is_retriable"] as? Bool, false)
    }

    // MARK: - InputSource

    func testInputSourceKindMapping() {
        let display = DisplayInfo(scaleFactor: 2.0, pixelSize: CGSize(width: 100, height: 50))
        XCTAssertEqual(InputSource.screenshot(image: Data([0x1]), display: display).kind, .screenshot)
        XCTAssertEqual(InputSource.selectedText("a").kind, .selectedText)
        XCTAssertEqual(InputSource.clipboard("b").kind, .clipboard)
        XCTAssertEqual(InputSource.manualInput("c").kind, .manualInput)
    }

    // MARK: - QueryContext

    func testQueryContextRoundTripAndEncoding() throws {
        let context = QueryContext(
            id: UUID(),
            sourceKind: .clipboard,
            inputText: "hello",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            languageHints: ["en", "zh"],
            userAction: .query
        )
        let data = try makeEncoder().encode(context)
        let object = try jsonObject(data)
        XCTAssertNotNil(object["source_kind"])
        XCTAssertNotNil(object["input_text"])
        XCTAssertNotNil(object["language_hints"])
        XCTAssertNotNil(object["user_action"])
        let createdAt = try XCTUnwrap(object["created_at"] as? String)
        XCTAssertNotNil(ISO8601DateFormatter().date(from: createdAt))

        let decoded = try makeDecoder().decode(QueryContext.self, from: data)
        XCTAssertEqual(decoded, context)
    }

    // MARK: - OCRResult

    func testOCRResultRoundTrip() throws {
        let result = OCRResult(
            fullText: "line1\nline2",
            overallConfidence: 0.91,
            blocks: [
                OCRBlock(text: "line1",
                         boundingBox: CGRect(x: 0, y: 0, width: 10, height: 4),
                         confidence: 0.95)
            ],
            languageHints: ["en"],
            sourceImageRef: "img-1"
        )
        let decoded = try makeDecoder().decode(
            OCRResult.self, from: try makeEncoder().encode(result))
        XCTAssertEqual(decoded, result)
    }

    // MARK: - ResultModel / ResultContent

    func testResultModelRoundTripWithError() throws {
        let model = ResultModel(
            contextId: UUID(),
            provider: "openai",
            content: .text("answer"),
            tags: ["llm"],
            error: AgentError(category: .timeout, isRetriable: true),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let decoded = try makeDecoder().decode(
            ResultModel.self, from: try makeEncoder().encode(model))
        XCTAssertEqual(decoded, model)
    }

    func testResultModelRoundTripWithoutError() throws {
        let model = ResultModel(
            contextId: UUID(),
            provider: "free-translate",
            content: .translation(text: "你好", sourceLang: "en", targetLang: "zh"),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let decoded = try makeDecoder().decode(
            ResultModel.self, from: try makeEncoder().encode(model))
        XCTAssertEqual(decoded, model)
        XCTAssertNil(decoded.error)
    }

    func testResultContentDiscriminatorAndAudioCarriesRefNotBytes() throws {
        let cases: [ResultContent] = [
            .text("t"),
            .translation(text: "x", sourceLang: nil, targetLang: "zh"),
            .audio(ref: "audio-1", format: "mp3", durationMs: 1234)
        ]
        let expectedType = ["text", "translation", "audio"]
        for (content, type) in zip(cases, expectedType) {
            let data = try makeEncoder().encode(content)
            let object = try jsonObject(data)
            XCTAssertEqual(object["type"] as? String, type)
            let decoded = try makeDecoder().decode(ResultContent.self, from: data)
            XCTAssertEqual(decoded, content)
        }

        let audioData = try makeEncoder().encode(ResultContent.audio(
            ref: "audio-1", format: "wav", durationMs: nil))
        let audioObject = try jsonObject(audioData)
        XCTAssertEqual(audioObject["ref"] as? String, "audio-1")
        XCTAssertNil(audioObject["data"])
        XCTAssertNil(audioObject["duration_ms"])
    }
}
