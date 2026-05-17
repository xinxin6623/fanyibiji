import XCTest
@testable import PersonalAgent

final class T14PromptConfigTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pc-\(UUID().uuidString)")
            .appendingPathComponent("prompt-config.json")
    }

    func testDefaultIsNonEmpty() {
        XCTAssertFalse(PromptConfig().systemPrompt
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testSaveLoadRoundTrips() throws {
        let store = PromptSettingsStore(fileURL: tempURL())
        let cfg = PromptConfig(systemPrompt: "只回答事实，不要解释。")
        try store.save(cfg)
        XCTAssertEqual(store.load(), cfg)
    }

    func testMissingFileReturnsDefault() {
        XCTAssertEqual(PromptSettingsStore(fileURL: tempURL()).load(),
                       PromptConfig())
    }

    func testCorruptFileReturnsDefault() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data("garbage{".utf8).write(to: url)
        XCTAssertEqual(PromptSettingsStore(fileURL: url).load(),
                       PromptConfig())
    }

    func testBlankPromptSanitizedToDefault() throws {
        let url = tempURL()
        let store = PromptSettingsStore(fileURL: url)
        try store.save(PromptConfig(systemPrompt: "   \n\t "))
        XCTAssertEqual(store.load().systemPrompt,
                       PromptConfig.defaultSystemPrompt)
    }

    func testSnakeCaseCodingKeyRoundTrips() throws {
        // system_prompt 字面量 CodingKey，避免 convertFromSnakeCase 坑。
        let cfg = PromptConfig(systemPrompt: "abc")
        let data = try JSONEncoder().encode(cfg)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("system_prompt"))
        XCTAssertEqual(try JSONDecoder()
            .decode(PromptConfig.self, from: data), cfg)
    }
}
