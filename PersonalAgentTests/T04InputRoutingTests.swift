import XCTest
@testable import PersonalAgent

private final class StubHotkeyMonitor: HotkeyMonitoring {
    var onTrigger: (() -> Void)?
    var startError: AgentError?
    private(set) var started = false

    func start() throws {
        if let startError { throw startError }
        started = true
    }
    func stop() { started = false }
    func fire() { onTrigger?() }
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
        var fired = 0
        monitor.onTrigger = { fired += 1 }
        try monitor.start()
        XCTAssertTrue(monitor.started)
        monitor.fire()
        monitor.fire()
        XCTAssertEqual(fired, 2)
    }

    func testHotkeyStartThrowsPermissionWhenUnauthorized() {
        let monitor = StubHotkeyMonitor()
        monitor.startError = AgentError(category: .permission)
        XCTAssertThrowsError(try monitor.start()) {
            XCTAssertEqual(($0 as? AgentError)?.category, .permission)
        }
    }
}
