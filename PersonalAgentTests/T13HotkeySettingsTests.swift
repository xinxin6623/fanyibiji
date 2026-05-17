import XCTest
import AppKit
@testable import PersonalAgent

final class T13HotkeySettingsTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("hk-\(UUID().uuidString)")
            .appendingPathComponent("hotkey-config.json")
    }

    func testSaveThenLoadRoundTrips() throws {
        let url = tempURL()
        let store = HotkeySettingsStore(fileURL: url)
        let cfg = HotkeyConfig(
            translateSelection: KeyBinding(keyCode: 17, modifiers:
                NSEvent.ModifierFlags([.command, .option]).rawValue),
            captureOCR: .defaultCaptureOCR)
        try store.save(cfg)
        XCTAssertEqual(store.load(), cfg)
    }

    func testMissingFileReturnsDefaults() {
        let store = HotkeySettingsStore(fileURL: tempURL())
        XCTAssertEqual(store.load(), HotkeyConfig())
    }

    func testCorruptFileReturnsDefaults() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)
        XCTAssertEqual(HotkeySettingsStore(fileURL: url).load(), HotkeyConfig())
    }

    func testInvalidBindingSanitizedToDefault() throws {
        let url = tempURL()
        let store = HotkeySettingsStore(fileURL: url)
        // 无修饰键的非法绑定（纯字母 'A'）应被夹回该项默认。
        let bad = HotkeyConfig(
            translateSelection: KeyBinding(keyCode: 0, modifiers: 0),
            captureOCR: .defaultCaptureOCR)
        try store.save(bad)
        let loaded = store.load()
        XCTAssertEqual(loaded.translateSelection, .defaultTranslateSelection)
        XCTAssertEqual(loaded.captureOCR, .defaultCaptureOCR)
    }

    func testKeyBindingDisplayString() {
        XCTAssertEqual(KeyBinding.defaultTranslateSelection.displayString, "⇧⌘C")
        XCTAssertEqual(KeyBinding.defaultCaptureOCR.displayString, "⇧⌘D")
    }

    func testKeyBindingValidityRequiresCommandOrControl() {
        XCTAssertTrue(KeyBinding.defaultCaptureOCR.isValid)
        XCTAssertFalse(KeyBinding(keyCode: 0, modifiers: 0).isValid)
        XCTAssertFalse(KeyBinding(keyCode: 0, modifiers:
            NSEvent.ModifierFlags.shift.rawValue).isValid)
    }
}
