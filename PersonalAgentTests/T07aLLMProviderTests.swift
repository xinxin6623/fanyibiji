import XCTest
@testable import PersonalAgent

private struct StubClient: LLMHTTPClient {
    let result: Result<(Data, HTTPURLResponse), Error>
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try result.get()
    }
}

final class T07aLLMProviderTests: XCTestCase {

    private let baseUrl = URL(string: "https://api.example.com/v1")!

    private func config(baseUrl: URL? = nil,
                        model: String = "gpt-4o-mini",
                        apiKey: String = "sk-test") -> ResolvedProviderConfig {
        ResolvedProviderConfig(baseUrl: baseUrl ?? self.baseUrl,
                               model: model,
                               timeoutSeconds: 30,
                               apiKey: apiKey)
    }

    private func http(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: baseUrl, statusCode: status,
                        httpVersion: nil, headerFields: nil)!
    }

    private func context(_ text: String) -> QueryContext {
        QueryContext(sourceKind: .clipboard, inputText: text, userAction: .query)
    }

    private func provider(_ result: Result<(Data, HTTPURLResponse), Error>,
                          config cfg: ResolvedProviderConfig? = nil)
        -> OpenAICompatibleLLMProvider {
        OpenAICompatibleLLMProvider(config: cfg ?? config(),
                                    client: StubClient(result: result))
    }

    private func assertCategory(_ expected: AgentError.Category,
                                _ block: () async throws -> Void,
                                file: StaticString = #filePath,
                                line: UInt = #line) async {
        do {
            try await block()
            XCTFail("expected throw", file: file, line: line)
        } catch let error as AgentError {
            XCTAssertEqual(error.category, expected, file: file, line: line)
        } catch {
            XCTFail("expected AgentError, got \(error)", file: file, line: line)
        }
    }

    // MARK: - validate（仅形状，零网络）

    func testValidatePassesOnGoodConfig() throws {
        try provider(.success((Data(), http(200)))).validate()
    }

    func testValidateFailsOnEmptyModel() {
        let p = provider(.success((Data(), http(200))),
                         config: config(model: " "))
        XCTAssertThrowsError(try p.validate()) {
            XCTAssertEqual(($0 as? AgentError)?.category, .invalidInput)
        }
    }

    // MARK: - 成功

    func testCompleteSuccess() async throws {
        let json = """
        {"model":"gpt-4o-mini","choices":[{"message":{"role":"assistant","content":"hi"}}]}
        """
        let p = provider(.success((Data(json.utf8), http(200))))
        let result = try await p.complete(context("hello"))
        XCTAssertEqual(result.text, "hi")
        XCTAssertEqual(result.model, "gpt-4o-mini")
    }

    // MARK: - 输入无效

    func testEmptyInputRejected() async {
        let p = provider(.success((Data(), http(200))))
        await assertCategory(.invalidInput) { _ = try await p.complete(self.context("  ")) }
    }

    // MARK: - 鉴权 / HTTP 状态

    func testHTTP401MapsToProviderRejected() async {
        let p = provider(.success((Data(), http(401))))
        await assertCategory(.providerRejected) {
            _ = try await p.complete(self.context("x"))
        }
    }

    func testHTTP500IsRetriableProviderRejected() async throws {
        let p = provider(.success((Data(), http(500))))
        do {
            _ = try await p.complete(context("x"))
            XCTFail("expected throw")
        } catch let e as AgentError {
            XCTAssertEqual(e.category, .providerRejected)
            XCTAssertTrue(e.isRetriable)
            XCTAssertEqual(e.providerErrorCode, "HTTP_500")
        }
    }

    // MARK: - 网络 / 超时 / 取消

    func testTimeoutMapsToTimeout() async {
        let p = provider(.failure(URLError(.timedOut)))
        await assertCategory(.timeout) { _ = try await p.complete(self.context("x")) }
    }

    func testCancelledURLErrorMapsToCancelled() async {
        let p = provider(.failure(URLError(.cancelled)))
        await assertCategory(.cancelled) { _ = try await p.complete(self.context("x")) }
    }

    func testCancellationErrorMapsToCancelled() async {
        let p = provider(.failure(CancellationError()))
        await assertCategory(.cancelled) { _ = try await p.complete(self.context("x")) }
    }

    func testGenericURLErrorMapsToNetwork() async {
        let p = provider(.failure(URLError(.notConnectedToInternet)))
        await assertCategory(.network) { _ = try await p.complete(self.context("x")) }
    }

    // MARK: - 响应畸形

    func testMalformedJSONMapsToProviderRejected() async {
        let p = provider(.success((Data("{not json}".utf8), http(200))))
        await assertCategory(.providerRejected) {
            _ = try await p.complete(self.context("x"))
        }
    }

    func testEmptyChoicesMapsToProviderRejected() async {
        let p = provider(.success((Data("{\"choices\":[]}".utf8), http(200))))
        await assertCategory(.providerRejected) {
            _ = try await p.complete(self.context("x"))
        }
    }
}
