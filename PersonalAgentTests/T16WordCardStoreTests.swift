import XCTest
@testable import PersonalAgent

private struct StubAudioDownloader: AudioDownloading {
    func download(from url: URL, to destination: URL) async throws {
        // 单测里不走网络;写一个空文件证明被调用即可。
        try Data().write(to: destination)
    }
}

final class T16WordCardStoreTests: XCTestCase {

    private var tempRoot: URL!
    private var store: WordCardStore!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("word-card-tests-\(UUID().uuidString)")
        tempRoot = base
        store = WordCardStore(rootDirectory: base,
                              downloader: StubAudioDownloader())
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func entry(_ word: String,
                       us: String? = "ɡʊd",
                       uk: String? = "ɡʊd",
                       usAudio: String? = "https://x/u",
                       ukAudio: String? = "https://x/k") -> DictionaryEntry {
        DictionaryEntry(
            headword: word, summary: "好的",
            usIPA: us, ukIPA: uk,
            usAudioURL: usAudio, ukAudioURL: ukAudio,
            audioURL: nil,
            senses: [.init(partOfSpeech: "adj.", gloss: "优良的")],
            forms: [.init(name: "复数", words: ["goods"])],
            examTags: ["CET4"],
            source: "youdao-dict-web")
    }

    // MARK: - 基础写入

    func testFirstSaveCreatesFileWithFrontmatterAndBody() throws {
        let url = try store.save(entry("good"))
        XCTAssertEqual(url.lastPathComponent, "good.md")
        let raw = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(raw.hasPrefix("---\n"))
        XCTAssertTrue(raw.contains("word: good"))
        XCTAssertTrue(raw.contains("us_ipa: "))
        XCTAssertTrue(raw.contains("lookup_count: 1"))
        XCTAssertTrue(raw.contains("<!-- agent:body -->"))
        XCTAssertTrue(raw.contains("# good"))
        XCTAssertTrue(raw.contains("- **adj.** 优良的"))
        XCTAssertTrue(raw.contains("- 复数: goods"))
    }

    // MARK: - 文件名归一

    func testSlugLowercasesAndReplacesSpace() {
        XCTAssertEqual(WordCardStore.slug("Supervisor"), "supervisor")
        XCTAssertEqual(WordCardStore.slug("look up"), "look-up")
        XCTAssertEqual(WordCardStore.slug("good/bad"), "good-bad")
    }

    func testRepeatedSaveSameWordDoesNotDuplicate() throws {
        _ = try store.save(entry("Supervisor"))
        _ = try store.save(entry("supervisor"))
        let files = try FileManager.default.contentsOfDirectory(atPath: tempRoot.path)
        XCTAssertEqual(files.filter { $0.hasSuffix(".md") }.count, 1)
    }

    // MARK: - 合并:lookup_count 递增 & 用户改动保留

    func testSecondSaveIncrementsLookupCountAndPreservesUserBody() throws {
        let url = try store.save(entry("good"))

        // 用户改正文(在 agent:body 区间内插入笔记)。
        var raw = try String(contentsOf: url, encoding: .utf8)
        raw = raw.replacingOccurrences(
            of: "<!-- agent:body -->",
            with: "<!-- agent:body -->\n> 我的复习笔记: 想起 'all good'。")
        try raw.write(to: url, atomically: true, encoding: .utf8)

        // 二次保存。
        _ = try store.save(entry("good"))
        let after = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(after.contains("lookup_count: 2"))
        XCTAssertTrue(after.contains("我的复习笔记: 想起 'all good'。"),
                      "用户在 body 区间的改动应保留")
    }

    // MARK: - 音频路径

    func testAudioFilesScheduledNextToCard() throws {
        _ = try store.save(entry("good"))
        // 等 detached 任务跑完(轮询 1 秒上限)。
        let audioDir = tempRoot.appendingPathComponent("_audio")
        let us = audioDir.appendingPathComponent("good-us.mp3")
        let uk = audioDir.appendingPathComponent("good-uk.mp3")
        let expectation = XCTestExpectation(description: "audio created")
        Task {
            for _ in 0..<20 {
                if FileManager.default.fileExists(atPath: us.path)
                    && FileManager.default.fileExists(atPath: uk.path) {
                    expectation.fulfill(); return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: us.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: uk.path))
    }
}
