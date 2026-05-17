import XCTest
@testable import PersonalAgent

/// 捕获发出的 URLRequest，断言 messages 是否含 system role。
private final class CapturingClient: LLMHTTPClient, @unchecked Sendable {
    private(set) var lastBody: [String: Any]?
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if let data = request.httpBody {
            lastBody = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        }
        // 回一个最小合法响应让 parse 不炸（断点在请求体，不关心返回）。
        let ok = #"{"choices":[{"message":{"content":"ok"}}]}"#
        let resp = HTTPURLResponse(
            url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: nil)!
        return (Data(ok.utf8), resp)
    }
}

final class T14SystemPromptInjectionTests: XCTestCase {

    private let cfg = ResolvedProviderConfig(
        baseUrl: URL(string: "https://api.example.com/v1")!,
        model: "gpt-4o-mini", timeoutSeconds: 30, apiKey: "sk-test")

    private func context() -> QueryContext {
        QueryContext(sourceKind: .clipboard,
                     inputText: "hello", userAction: .query)
    }

    private func messages(_ body: [String: Any]?) -> [[String: String]] {
        (body?["messages"] as? [[String: String]]) ?? []
    }

    func testSystemPromptInjectedAsFirstMessage() async throws {
        let client = CapturingClient()
        let provider = OpenAICompatibleLLMProvider(
            config: cfg, client: client, systemPrompt: "你是简洁助手。")
        _ = try await provider.complete(context())
        let msgs = messages(client.lastBody)
        XCTAssertEqual(msgs.first?["role"], "system")
        XCTAssertEqual(msgs.first?["content"], "你是简洁助手。")
        XCTAssertEqual(msgs.last?["role"], "user")
        XCTAssertEqual(msgs.count, 2)
    }

    func testEmptySystemPromptOmitsSystemMessage() async throws {
        let client = CapturingClient()
        let provider = OpenAICompatibleLLMProvider(
            config: cfg, client: client, systemPrompt: "   ")
        _ = try await provider.complete(context())
        let msgs = messages(client.lastBody)
        // 空白提示词退化为纯 user 单轮（向后兼容）。
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs.first?["role"], "user")
    }

    func testDefaultInitHasNoSystemMessage() async throws {
        let client = CapturingClient()
        // 不传 systemPrompt，默认 "" → 无 system（原行为）。
        let provider = OpenAICompatibleLLMProvider(
            config: cfg, client: client)
        _ = try await provider.complete(context())
        XCTAssertEqual(messages(client.lastBody).count, 1)
    }
}
