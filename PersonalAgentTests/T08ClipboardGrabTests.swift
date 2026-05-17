import XCTest
@testable import PersonalAgent

private struct StubPasteboard: PasteboardReading {
    let value: String?
    func readString() -> String? { value }
    var changeCount: Int { 0 }
    func writeString(_ value: String) {}
    func clearContents() {}
}

final class T08ClipboardGrabTests: XCTestCase {

    private func grab(_ value: String?) -> Result<String, AgentError> {
        ClipboardTextGrabber(pasteboard: StubPasteboard(value: value)).grab()
    }

    func testGrabReturnsTrimmedText() {
        XCTAssertEqual(try grab("  hello world  ").get(), "hello world")
    }

    func testGrabPreservesInnerNewlines() {
        XCTAssertEqual(try grab("a\nb").get(), "a\nb")
    }

    func testNilClipboardFailsInvalidInput() {
        assertInvalidInput(grab(nil))
    }

    func testEmptyClipboardFailsInvalidInput() {
        assertInvalidInput(grab(""))
    }

    func testWhitespaceOnlyClipboardFailsInvalidInput() {
        assertInvalidInput(grab("   \n\t "))
    }

    private func assertInvalidInput(_ result: Result<String, AgentError>,
                                    file: StaticString = #filePath,
                                    line: UInt = #line) {
        switch result {
        case .success:
            XCTFail("expected failure", file: file, line: line)
        case let .failure(error):
            XCTAssertEqual(error.category, .invalidInput, file: file, line: line)
        }
    }
}
