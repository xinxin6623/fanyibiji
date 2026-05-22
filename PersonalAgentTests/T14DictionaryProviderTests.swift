import XCTest
@testable import PersonalAgent

private struct StubDictClient: TranslateHTTPClient {
    let result: Result<(Data, HTTPURLResponse), Error>
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try result.get()
    }
}

final class T14DictionaryProviderTests: XCTestCase {

    private let url = URL(string: "https://d.example.com/x")!

    private func http(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status,
                        httpVersion: nil, headerFields: nil)!
    }

    private func ctx(_ text: String) -> QueryContext {
        QueryContext(sourceKind: .manualInput, inputText: text,
                     userAction: .query)
    }

    private func provider(_ result: Result<(Data, HTTPURLResponse), Error>)
        -> YoudaoDictProvider {
        YoudaoDictProvider(client: StubDictClient(result: result),
                           endpoint: url)
    }

    /// 同目录 fixture (good_v4.json) 加载。无法找到时 fail 而不是返回空,
    /// 防止悄悄跳过解析校验。
    private func fixture(_ name: String) throws -> Data {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let f = here.appendingPathComponent(name)
        return try Data(contentsOf: f)
    }

    // MARK: - 真实 fixture(good_v4.json)→ DictionaryEntry

    func testParsesGoodFixtureECBranch() async throws {
        let data = try fixture("youdao_good_v4.json")
        let entry = try YoudaoDictProvider.parse(
            data, headword: "good", source: "youdao-dict-web")
        XCTAssertEqual(entry.headword, "good")
        XCTAssertEqual(entry.usIPA, "ɡʊd")
        XCTAssertEqual(entry.ukIPA, "ɡʊd")
        XCTAssertNotNil(entry.usAudioURL)
        XCTAssertNotNil(entry.ukAudioURL)
        // 美音 URL 应包含 dictvoice + 编码后的 audio query 参数。
        XCTAssertTrue(entry.usAudioURL?.contains("dict.youdao.com/dictvoice") == true)
        // good 至少有 adj./n./adv. 三个词性 + 1 个人名条目。
        XCTAssertGreaterThanOrEqual(entry.senses.count, 3)
        XCTAssertTrue(entry.senses.contains { $0.partOfSpeech == "adj." })
        // 变形:复数/比较级/最高级。
        XCTAssertEqual(entry.forms.count, 3)
        XCTAssertTrue(entry.forms.contains { $0.name == "复数" && $0.words == ["goods"] })
    }

    // MARK: - 失败/边界

    func testEmptyResponseMapsToProviderRejected() async {
        let p = provider(.success((Data("{}".utf8), http(200))))
        do {
            _ = try await p.lookup(ctx("nonword"))
            XCTFail("expected throw")
        } catch let e as AgentError {
            XCTAssertEqual(e.category, .providerRejected)
            XCTAssertEqual(e.providerErrorCode, "NO_ENTRY")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testHTTP500MapsToProviderRejectedRetriable() async {
        let p = provider(.success((Data("{}".utf8), http(500))))
        do {
            _ = try await p.lookup(ctx("good"))
            XCTFail("expected throw")
        } catch let e as AgentError {
            XCTAssertEqual(e.category, .providerRejected)
            XCTAssertTrue(e.isRetriable)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testEmptyInputMapsToInvalidInput() async {
        let p = provider(.success((Data("{}".utf8), http(200))))
        do {
            _ = try await p.lookup(ctx("   "))
            XCTFail("expected throw")
        } catch let e as AgentError {
            XCTAssertEqual(e.category, .invalidInput)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    // MARK: - 语言检测

    func testLanguageDetectionEnglishAndChinese() {
        XCTAssertEqual(YoudaoDictProvider.detectForeignLang("hello"), "eng")
        XCTAssertEqual(YoudaoDictProvider.detectForeignLang("supervisor"), "eng")
        XCTAssertEqual(YoudaoDictProvider.detectForeignLang("你好"), "eng")
        XCTAssertNil(YoudaoDictProvider.detectForeignLang("123 !@#"))
    }

    // MARK: - ResultContent.dictionary 编解码往返

    func testResultContentDictionaryRoundTrip() throws {
        let entry = DictionaryEntry(
            headword: "good", summary: "好",
            usIPA: "ɡʊd", ukIPA: "ɡʊd",
            usAudioURL: "https://x/u", ukAudioURL: "https://x/k",
            audioURL: nil,
            senses: [.init(partOfSpeech: "adj.", gloss: "优良的")],
            forms: [.init(name: "复数", words: ["goods"])],
            examTags: ["CET4"], source: "youdao-dict-web")
        let content = ResultContent.dictionary(entry)
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(ResultContent.self, from: data)
        guard case let .dictionary(roundtripped) = decoded else {
            return XCTFail("expected .dictionary case")
        }
        XCTAssertEqual(roundtripped, entry)
    }
}
