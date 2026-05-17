import XCTest
import AppKit
@testable import PersonalAgent

private final class StubHotkeyMonitor: HotkeyMonitoring {
    var onTranslateSelection: (() -> Void)?
    var onCaptureOCR: (() -> Void)?
    var onSelectionToNote: (() -> Void)?
    var startError: AgentError?
    private(set) var started = false
    private(set) var lastConfig: HotkeyConfig?

    func start() throws {
        if let startError { throw startError }
        started = true
    }
    func stop() { started = false }
    func update(_ config: HotkeyConfig) { lastConfig = config }
    func fireCapture() { onCaptureOCR?() }
    func fireSelection() { onTranslateSelection?() }
    func fireSelectionToNote() { onSelectionToNote?() }
}

final class T04InputRoutingTests: XCTestCase {

    // MARK: - InputEntry 映射

    func testInputEntrySourceKindMapping() {
        XCTAssertEqual(InputEntry.screenshot.sourceKind, .screenshot)
        XCTAssertEqual(InputEntry.selection.sourceKind, .selectedText)
        XCTAssertEqual(InputEntry.manualInput.sourceKind, .manualInput)
        XCTAssertFalse(InputEntry.manualInput.requiresAuthorization)
        XCTAssertTrue(InputEntry.screenshot.requiresAuthorization)
        XCTAssertTrue(InputEntry.selection.requiresAuthorization)
    }

    // MARK: - 路由 + 授权门

    func testManualInputAlwaysRoutesEvenWhenUnauthorized() {
        let router = InputRouter(
            authorizer: StaticAccessibilityAuthorizer(isTrusted: false))
        XCTAssertEqual(try router.route(.manualInput).get(), .manualInput)
    }

    func testAuthorizedEntriesRouteWhenTrusted() {
        let router = InputRouter(
            authorizer: StaticAccessibilityAuthorizer(isTrusted: true))
        XCTAssertEqual(try router.route(.screenshot).get(), .screenshot)
        XCTAssertEqual(try router.route(.selection).get(), .selectedText)
    }

    func testAuthorizedEntriesFailWithPermissionWhenUntrusted() {
        let router = InputRouter(
            authorizer: StaticAccessibilityAuthorizer(isTrusted: false))
        for entry in [InputEntry.screenshot, .selection] {
            switch router.route(entry) {
            case .success:
                XCTFail("\(entry) should require authorization")
            case let .failure(error):
                XCTAssertEqual(error.category, .permission)
            }
        }
    }

    // MARK: - 热键监听契约

    func testHotkeyTriggerInvokesCallback() throws {
        let monitor = StubHotkeyMonitor()
        var capture = 0
        var selection = 0
        monitor.onCaptureOCR = { capture += 1 }
        monitor.onTranslateSelection = { selection += 1 }
        try monitor.start()
        XCTAssertTrue(monitor.started)
        monitor.fireCapture()
        monitor.fireCapture()
        monitor.fireSelection()
        XCTAssertEqual(capture, 2)
        XCTAssertEqual(selection, 1)
    }

    func testHotkeyUpdatePropagatesConfig() {
        let monitor = StubHotkeyMonitor()
        let cfg = HotkeyConfig(
            translateSelection: KeyBinding(keyCode: 17, modifiers:
                NSEvent.ModifierFlags([.command, .option]).rawValue),
            captureOCR: .defaultCaptureOCR)
        monitor.update(cfg)
        XCTAssertEqual(monitor.lastConfig, cfg)
    }

    func testHotkeyStartThrowsPermissionWhenUnauthorized() {
        let monitor = StubHotkeyMonitor()
        monitor.startError = AgentError(category: .permission)
        XCTAssertThrowsError(try monitor.start()) {
            XCTAssertEqual(($0 as? AgentError)?.category, .permission)
        }
    }
}
