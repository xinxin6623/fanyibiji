import XCTest
@testable import PersonalAgent

private struct StubTranslateClient: TranslateHTTPClient {
    let result: Result<(Data, HTTPURLResponse), Error>
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try result.get()
    }
}

private struct StubLLM: LLMProvider {
    let id = "stub-llm"
    func validate() throws {}
    func complete(_ context: QueryContext) async throws -> AssistantResult {
        AssistantResult(text: "llm-ok", model: "m")
    }
}

final class T09TranslateProviderTests: XCTestCase {

    private let url = URL(string: "https://t.example.com/x")!

    private func http(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status,
                        httpVersion: nil, headerFields: nil)!
    }

    private func ctx(_ text: String, hints: [String] = []) -> QueryContext {
        QueryContext(sourceKind: .clipboard, inputText: text,
                     languageHints: hints, userAction: .translate)
    }

    private func provider(_ result: Result<(Data, HTTPURLResponse), Error>)
        -> FreeWebTranslateProvider {
        FreeWebTranslateProvider(client: StubTranslateClient(result: result),
                                 endpoint: url, defaultTargetLang: "zh")
    }

    private func assertCategory(_ expected: AgentError.Category,
                                _ block: () async throws -> Void,
                                file: StaticString = #filePath,
                                line: UInt = #line) async {
        do {
            try await block()
            XCTFail("expected throw", file: file, line: line)
        } catch let e as AgentError {
            XCTAssertEqual(e.category, expected, file: file, line: line)
        } catch {
            XCTFail("expected AgentError, got \(error)", file: file, line: line)
        }
    }

    func testSuccessParsesGoogleFormat() async throws {
        let json = "[[[\"你好\",\"hello\",null,null,10],[\"世界\",\" world\"]],null,\"en\"]"
        let p = provider(.success((Data(json.utf8), http(200))))
        let r = try await p.translate(ctx("hello world", hints: ["zh"]))
        XCTAssertEqual(r.text, "你好世界")
        XCTAssertEqual(r.sourceLang, "en")
        XCTAssertEqual(r.targetLang, "zh")
    }

    func testTargetFromHintsOverridesDefault() async throws {
        let json = "[[[\"bonjour\",\"hello\"]],null,\"en\"]"
        let p = provider(.success((Data(json.utf8), http(200))))
        let r = try await p.translate(ctx("hello", hints: ["fr"]))
        XCTAssertEqual(r.targetLang, "fr")
    }

    func testEmptyInputRejected() async {
        let p = provider(.success((Data("[[]]".utf8), http(200))))
        await assertCategory(.invalidInput) { _ = try await p.translate(self.ctx("  ")) }
    }

    func testHTTP500RetriableProviderRejected() async {
        let p = provider(.success((Data(), http(500))))
        do {
            _ = try await p.translate(ctx("x"))
            XCTFail("expected throw")
        } catch let e as AgentError {
            XCTAssertEqual(e.category, .providerRejected)
            XCTAssertTrue(e.isRetriable)
        } catch {
            XCTFail("expected AgentError, got \(error)")
        }
    }

    func testTimeoutMapsToTimeout() async {
        let p = provider(.failure(URLError(.timedOut)))
        await assertCategory(.timeout) { _ = try await p.translate(self.ctx("x")) }
    }

    func testCancelledMapsToCancelled() async {
        let p = provider(.failure(URLError(.cancelled)))
        await assertCategory(.cancelled) { _ = try await p.translate(self.ctx("x")) }
    }

    func testGenericNetworkMapsToNetwork() async {
        let p = provider(.failure(URLError(.cannotConnectToHost)))
        await assertCategory(.network) { _ = try await p.translate(self.ctx("x")) }
    }

    func testMalformedResponseRejected() async {
        let p = provider(.success((Data("not-json".utf8), http(200))))
        await assertCategory(.providerRejected) {
            _ = try await p.translate(self.ctx("x"))
        }
    }

    func testEmptyTranslationRejected() async {
        let p = provider(.success((Data("[null,null,\"en\"]".utf8), http(200))))
        await assertCategory(.providerRejected) {
            _ = try await p.translate(self.ctx("x"))
        }
    }

    /// 隔离性：翻译 provider 失败不影响 LLM 主路径（无共享状态）。
    func testTranslateFailureDoesNotAffectLLM() async throws {
        let failing = provider(.failure(URLError(.timedOut)))
        let llm = StubLLM()
        await assertCategory(.timeout) {
            _ = try await failing.translate(self.ctx("x"))
        }
        let llmResult = try await llm.complete(ctx("hi"))
        XCTAssertEqual(llmResult.text, "llm-ok")
    }
}
