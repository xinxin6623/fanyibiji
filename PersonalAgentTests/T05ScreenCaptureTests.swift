import XCTest
@testable import PersonalAgent

private struct StubCapturer: ScreenCapturer {
    let result: Result<ScreenshotResult, Error>
    func capture(_ region: CaptureRegion) async throws -> ScreenshotResult {
        try result.get()
    }
}

final class T05ScreenCaptureTests: XCTestCase {

    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let sample = ScreenshotResult(
        imageData: Data([0x89, 0x50]),
        display: DisplayInfo(scaleFactor: 2.0,
                             pixelSize: CGSize(width: 200, height: 100)))

    // MARK: - CaptureRegion 几何

    func testFromDragNormalizesReversedPoints() {
        let region = CaptureRegion.fromDrag(
            start: CGPoint(x: 300, y: 250),
            end: CGPoint(x: 100, y: 50),
            displayID: 1, displayBounds: bounds)
        XCTAssertEqual(region?.rect, CGRect(x: 100, y: 50, width: 200, height: 200))
    }

    func testFromDragClipsToDisplayBounds() {
        let region = CaptureRegion.fromDrag(
            start: CGPoint(x: 900, y: 700),
            end: CGPoint(x: 1200, y: 1000),
            displayID: 1, displayBounds: bounds)
        XCTAssertEqual(region?.rect, CGRect(x: 900, y: 700, width: 100, height: 100))
    }

    func testFromDragDegenerateReturnsNil() {
        XCTAssertNil(CaptureRegion.fromDrag(
            start: CGPoint(x: 10, y: 10), end: CGPoint(x: 10, y: 10),
            displayID: 1, displayBounds: bounds))
        XCTAssertNil(CaptureRegion.fromDrag(
            start: CGPoint(x: 5000, y: 5000), end: CGPoint(x: 5001, y: 5001),
            displayID: 1, displayBounds: bounds))
    }

    func testInitRejectsSubpixel() {
        XCTAssertNil(CaptureRegion(rect: CGRect(x: 0, y: 0, width: 0.4, height: 10),
                                   displayID: 1))
        XCTAssertNotNil(CaptureRegion(rect: CGRect(x: 0, y: 0, width: 1, height: 1),
                                      displayID: 1))
    }

    // MARK: - 协调器：授权 / 取消 / 成功 / 失败

    private func coordinator(authorized: Bool,
                             _ result: Result<ScreenshotResult, Error>)
        -> ScreenCaptureCoordinator {
        ScreenCaptureCoordinator(
            authorizer: StaticScreenCaptureAuthorizer(isAuthorized: authorized),
            capturer: StubCapturer(result: result))
    }

    private func region() -> CaptureRegion {
        CaptureRegion(rect: CGRect(x: 0, y: 0, width: 10, height: 10), displayID: 1)!
    }

    func testUnauthorizedReturnsPermission() async {
        let r = await coordinator(authorized: false, .success(sample))
            .capture(.selected(region()))
        assertFailure(r, .permission)
    }

    func testCancelledSelectionReturnsCancelled() async {
        let r = await coordinator(authorized: true, .success(sample))
            .capture(.cancelled)
        assertFailure(r, .cancelled)
    }

    func testSuccessReturnsScreenshot() async {
        let r = await coordinator(authorized: true, .success(sample))
            .capture(.selected(region()))
        guard case let .success(value) = r else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, sample)
    }

    func testCapturerAgentErrorPropagates() async {
        let r = await coordinator(authorized: true,
                                  .failure(AgentError(category: .unknown)))
            .capture(.selected(region()))
        assertFailure(r, .unknown)
    }

    func testCapturerGenericErrorMapsToUnknown() async {
        struct Boom: Error {}
        let r = await coordinator(authorized: true, .failure(Boom()))
            .capture(.selected(region()))
        assertFailure(r, .unknown)
    }

    // MARK: - Helper

    private func assertFailure(_ result: Result<ScreenshotResult, AgentError>,
                               _ expected: AgentError.Category,
                               file: StaticString = #filePath,
                               line: UInt = #line) {
        switch result {
        case .success:
            XCTFail("expected failure", file: file, line: line)
        case let .failure(error):
            XCTAssertEqual(error.category, expected, file: file, line: line)
        }
    }
}
