import XCTest
@testable import PersonalAgent

final class T15LanguageConfigTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("lc-\(UUID().uuidString)")
            .appendingPathComponent("language-config.json")
    }

    func testDefaultIsChinese() {
        XCTAssertEqual(LanguageConfig().target, .chinese)
    }

    func testTargetLanguageCodesStableForProvider() {
        // code 必须与原写死值兼容(zh)，否则翻译 tl 参数变化破坏行为。
        XCTAssertEqual(TargetLanguage.chinese.code, "zh")
        XCTAssertEqual(TargetLanguage.chinese.naturalName, "中文")
        XCTAssertEqual(TargetLanguage.english.code, "en")
    }

    func testSaveLoadRoundTrips() throws {
        let store = LanguageSettingsStore(fileURL: tempURL())
        let cfg = LanguageConfig(target: .japanese)
        try store.save(cfg)
        XCTAssertEqual(store.load(), cfg)
    }

    func testMissingFileReturnsDefault() {
        XCTAssertEqual(LanguageSettingsStore(fileURL: tempURL()).load(),
                       LanguageConfig())
    }

    func testCorruptFileReturnsDefault() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        XCTAssertEqual(LanguageSettingsStore(fileURL: url).load(),
                       LanguageConfig())
    }

    func testInvalidEnumReturnsDefault() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data(#"{"target":"klingon"}"#.utf8).write(to: url)
        XCTAssertEqual(LanguageSettingsStore(fileURL: url).load(),
                       LanguageConfig())
    }

    func testAllCasesHaveFlagAndDisplayKey() {
        for lang in TargetLanguage.allCases {
            XCTAssertFalse(lang.flag.isEmpty)
            XCTAssertTrue(lang.displayNameKey.hasPrefix("lang."))
        }
    }
}
