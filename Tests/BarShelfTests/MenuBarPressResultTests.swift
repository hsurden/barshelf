import ApplicationServices
import XCTest
@testable import BarShelf

final class MenuBarPressResultTests: XCTestCase {
    func testSuccessfulAcknowledgmentIsAccepted() {
        XCTAssertEqual(MenuBarPressResult(error: .success), .accepted)
    }

    func testTimeoutAndGenericFailureDoNotReportMenuFailure() {
        XCTAssertEqual(MenuBarPressResult(error: .cannotComplete), .unconfirmed)
        XCTAssertEqual(MenuBarPressResult(error: .failure), .unconfirmed)
    }

    func testExplicitlyUnavailableControlsRemainActionableFailures() {
        for error: AXError in [.invalidUIElement, .actionUnsupported, .apiDisabled,
                              .illegalArgument, .notImplemented] {
            XCTAssertEqual(MenuBarPressResult(error: error), .unavailable)
        }
    }
}
