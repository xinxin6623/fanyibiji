import XCTest
@testable import PersonalAgent

private actor CallCounter {
    private(set) var count = 0
    func bump() -> Int { count += 1; return count }
}

private struct ScriptedLLM: LLMProvider {
    let id = "scripted-llm"
    let counter: CallCounter
    /// 前 `failFirst` 次抛 `error`，之后返回成功。
    let failFirst: Int
    let error: AgentError

    func validate() throws {}
    func complete(_ context: QueryContext) async throws -> AssistantResult {
        let n = await counter.bump()
        if n <= failFirst { throw error }
        return AssistantResult(text: "ok-\(n)", model: "m")
    }
}

final class T07bRetryTests: XCTestCase {

    private let ctx = QueryContext(sourceKind: .clipboard,
                                   inputText: "hi", userAction: .query)
    private let noSleep: @Sendable (UInt64) async -> Void = { _ in }

    func testRetriesThenSucceeds() async throws {
        let counter = CallCounter()
        let provider = RetryingLLMProvider(
            wrapping: ScriptedLLM(
                counter: counter, failFirst: 2,
                error: AgentError(category: .network, isRetriable: true)),
            maxAttempts: 3, sleep: noSleep)

        let result = try await provider.complete(ctx)
        XCTAssertEqual(result.text, "ok-3")
        let total = await counter.count
        XCTAssertEqual(total, 3)
    }

    func testExhaustsAndThrowsLastError() async {
        let counter = CallCounter()
        let provider = RetryingLLMProvider(
            wrapping: ScriptedLLM(
                counter: counter, failFirst: 99,
                error: AgentError(category: .timeout, isRetriable: true)),
            maxAttempts: 3, sleep: noSleep)

        do {
            _ = try await provider.complete(ctx)
            XCTFail("expected throw")
        } catch let e as AgentError {
            XCTAssertEqual(e.category, .timeout)
        } catch { XCTFail("expected AgentError") }
        let total = await counter.count
        XCTAssertEqual(total, 3)
    }

    func testNonRetriableErrorNotRetried() async {
        let counter = CallCounter()
        let provider = RetryingLLMProvider(
            wrapping: ScriptedLLM(
                counter: counter, failFirst: 99,
                error: AgentError(category: .providerRejected, isRetriable: false)),
            maxAttempts: 5, sleep: noSleep)

        do {
            _ = try await provider.complete(ctx)
            XCTFail("expected throw")
        } catch let e as AgentError {
            XCTAssertEqual(e.category, .providerRejected)
        } catch { XCTFail("expected AgentError") }
        let total = await counter.count
        XCTAssertEqual(total, 1)
    }

    func testCancelledNotRetriedEvenIfMarkedRetriable() async {
        let counter = CallCounter()
        let provider = RetryingLLMProvider(
            wrapping: ScriptedLLM(
                counter: counter, failFirst: 99,
                error: AgentError(category: .cancelled, isRetriable: true)),
            maxAttempts: 5, sleep: noSleep)

        do {
            _ = try await provider.complete(ctx)
            XCTFail("expected throw")
        } catch let e as AgentError {
            XCTAssertEqual(e.category, .cancelled)
        } catch { XCTFail("expected AgentError") }
        let total = await counter.count
        XCTAssertEqual(total, 1)
    }

    func testIdAndValidateDelegate() throws {
        let provider = RetryingLLMProvider(
            wrapping: ScriptedLLM(counter: CallCounter(), failFirst: 0,
                                  error: AgentError(category: .unknown)),
            sleep: noSleep)
        XCTAssertEqual(provider.id, "scripted-llm")
        XCTAssertNoThrow(try provider.validate())
    }
}
