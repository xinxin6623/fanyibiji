import XCTest
@testable import PersonalAgent

final class T03ConfigTests: XCTestCase {

    private let validConfig = ProviderConfig(
        baseUrl: "https://api.example.com/v1",
        model: "gpt-4o-mini",
        timeoutSeconds: 30
    )

    // MARK: - ProviderConfig 编码契约

    func testProviderConfigSnakeCaseRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let data = try encoder.encode(validConfig)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["base_url"])
        XCTAssertNotNil(object["timeout_seconds"])
        XCTAssertNil(object["baseUrl"])

        XCTAssertEqual(try decoder.decode(ProviderConfig.self, from: data), validConfig)
    }

    // MARK: - 有 key

    func testResolveSucceedsWithKey() throws {
        let store = ConfigStore(secrets: InMemorySecretStore(["llm.apiKey": "sk-test"]))
        let resolved = try store.resolve(validConfig, apiKeyRef: "llm.apiKey")
        XCTAssertEqual(resolved.apiKey, "sk-test")
        XCTAssertEqual(resolved.model, "gpt-4o-mini")
        XCTAssertEqual(resolved.baseUrl.absoluteString, "https://api.example.com/v1")
        XCTAssertEqual(resolved.timeoutSeconds, 30)
    }

    func testResolveTrimsWhitespaceKey() throws {
        let store = ConfigStore(secrets: InMemorySecretStore(["llm.apiKey": "  sk-x  "]))
        XCTAssertEqual(try store.resolve(validConfig, apiKeyRef: "llm.apiKey").apiKey, "sk-x")
    }

    // MARK: - 无 key

    func testResolveFailsWhenKeyMissing() {
        let store = ConfigStore(secrets: InMemorySecretStore())
        assertInvalidInput("missing api_key") {
            try store.resolve(validConfig, apiKeyRef: "llm.apiKey")
        }
    }

    func testResolveFailsWhenKeyBlank() {
        let store = ConfigStore(secrets: InMemorySecretStore(["llm.apiKey": "   "]))
        assertInvalidInput("missing api_key") {
            try store.resolve(validConfig, apiKeyRef: "llm.apiKey")
        }
    }

    // MARK: - 非法配置

    func testResolveFailsOnEmptyBaseURL() {
        let store = ConfigStore(secrets: InMemorySecretStore(["k": "sk"]))
        assertInvalidInput("missing base_url") {
            try store.resolve(ProviderConfig(baseUrl: "  ", model: "m"), apiKeyRef: "k")
        }
    }

    func testResolveFailsOnNonHTTPBaseURL() {
        let store = ConfigStore(secrets: InMemorySecretStore(["k": "sk"]))
        assertInvalidInput("invalid base_url") {
            try store.resolve(ProviderConfig(baseUrl: "ftp://x.com", model: "m"),
                              apiKeyRef: "k")
        }
    }

    func testResolveFailsOnEmptyModel() {
        let store = ConfigStore(secrets: InMemorySecretStore(["k": "sk"]))
        assertInvalidInput("missing model") {
            try store.resolve(ProviderConfig(baseUrl: "https://a.com", model: " "),
                              apiKeyRef: "k")
        }
    }

    func testResolveFailsOnNonPositiveTimeout() {
        let store = ConfigStore(secrets: InMemorySecretStore(["k": "sk"]))
        assertInvalidInput("invalid timeout_seconds") {
            try store.resolve(
                ProviderConfig(baseUrl: "https://a.com", model: "m", timeoutSeconds: 0),
                apiKeyRef: "k")
        }
    }

    // MARK: - SecretStore 失败透传

    func testResolvePropagatesSecretStoreFailureAsPersistence() {
        let store = ConfigStore(secrets: FailingSecretStore())
        XCTAssertThrowsError(try store.resolve(validConfig, apiKeyRef: "k")) { error in
            let agentError = error as? AgentError
            XCTAssertEqual(agentError?.category, .persistence)
        }
    }

    // MARK: - InMemorySecretStore set/delete

    func testInMemorySecretStoreSetAndDelete() throws {
        let store = InMemorySecretStore()
        XCTAssertNil(try store.secret(forKey: "k"))
        try store.setSecret("v", forKey: "k")
        XCTAssertEqual(try store.secret(forKey: "k"), "v")
        try store.deleteSecret(forKey: "k")
        XCTAssertNil(try store.secret(forKey: "k"))
    }

    // MARK: - Helpers

    private func assertInvalidInput(_ expectedMessage: String,
                                    _ block: () throws -> Void,
                                    file: StaticString = #filePath,
                                    line: UInt = #line) {
        XCTAssertThrowsError(try block(), file: file, line: line) { error in
            guard let agentError = error as? AgentError else {
                return XCTFail("expected AgentError, got \(error)", file: file, line: line)
            }
            XCTAssertEqual(agentError.category, .invalidInput, file: file, line: line)
            XCTAssertEqual(agentError.diagnosticMessage, expectedMessage,
                           file: file, line: line)
        }
    }
}
