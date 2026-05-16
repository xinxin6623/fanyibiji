import XCTest
@testable import PersonalAgent

final class T11aJSONLStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("t11a-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeRecord(_ provider: String,
                            content: ResultContent = .text("answer")) -> ResultModel {
        ResultModel(
            contextId: UUID(),
            provider: provider,
            content: content,
            tags: ["llm"],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    // MARK: - 写入 + 读取

    func testAppendThenReadAllRoundTripsInOrder() throws {
        let url = tempDir.appendingPathComponent("results.jsonl")
        let store = JSONLResultStore(fileURL: url)
        let a = makeRecord("openai")
        let b = makeRecord("free-translate",
                           content: .translation(text: "你好",
                                                  sourceLang: "en", targetLang: "zh"))
        try store.append(a)
        try store.append(b)

        let read = try store.readAll()
        XCTAssertEqual(read, [a, b])
        XCTAssertTrue(store.bufferedFailures.isEmpty)
    }

    func testFileIsLineDelimitedSnakeCase() throws {
        let url = tempDir.appendingPathComponent("results.jsonl")
        let store = JSONLResultStore(fileURL: url)
        try store.append(makeRecord("openai"))
        try store.append(makeRecord("openai"))

        let raw = try String(contentsOf: url, encoding: .utf8)
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        // 两条记录 + 末尾换行后的空段。
        XCTAssertEqual(lines.filter { !$0.isEmpty }.count, 2)
        XCTAssertTrue(raw.contains("\"context_id\""))
        XCTAssertTrue(raw.contains("\"created_at\""))
        XCTAssertFalse(raw.contains("\"contextId\""))
    }

    func testCreatedAtPrecisionToSeconds() throws {
        let url = tempDir.appendingPathComponent("results.jsonl")
        let store = JSONLResultStore(fileURL: url)
        let record = makeRecord("openai")
        try store.append(record)
        let decoded = try XCTUnwrap(store.readAll().first)
        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970,
                       record.createdAt.timeIntervalSince1970, accuracy: 0.0001)
    }

    // MARK: - 读取边界

    func testReadAllOnMissingFileReturnsEmpty() throws {
        let store = JSONLResultStore(
            fileURL: tempDir.appendingPathComponent("nope.jsonl"))
        XCTAssertEqual(try store.readAll(), [])
    }

    func testReadAllOnEmptyFileReturnsEmpty() throws {
        let url = tempDir.appendingPathComponent("empty.jsonl")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        XCTAssertEqual(try JSONLResultStore(fileURL: url).readAll(), [])
    }

    func testReadAllThrowsPersistenceOnCorruptLine() throws {
        let url = tempDir.appendingPathComponent("results.jsonl")
        let store = JSONLResultStore(fileURL: url)
        try store.append(makeRecord("openai"))
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{not json}\n".utf8))
        try handle.close()

        XCTAssertThrowsError(try store.readAll()) { error in
            XCTAssertEqual((error as? AgentError)?.category, .persistence)
        }
    }

    // MARK: - 写入失败兜底

    func testAppendFailureBuffersRecordAndThrowsPersistence() throws {
        // 父路径是普通文件 → 无法在其下建目录，写入必失败。
        let blocker = tempDir.appendingPathComponent("blocker")
        FileManager.default.createFile(atPath: blocker.path, contents: Data())
        let store = JSONLResultStore(
            fileURL: blocker.appendingPathComponent("sub/results.jsonl"))
        let record = makeRecord("openai")

        XCTAssertThrowsError(try store.append(record)) { error in
            XCTAssertEqual((error as? AgentError)?.category, .persistence)
        }
        XCTAssertEqual(store.bufferedFailures, [record])
    }
}
