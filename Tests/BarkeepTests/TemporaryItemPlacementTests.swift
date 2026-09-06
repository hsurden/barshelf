import XCTest
@testable import Barkeep

final class TemporaryItemPlacementTests: XCTestCase {
    private func anchor(_ id: String, _ x: CGFloat) -> TemporaryItemPlacement.Anchor {
        .init(id: id, frame: CGRect(x: x, y: 0, width: 22, height: 24))
    }

    func testReturnUsesFreshNeighborGeometryAfterOtherItemsResize() throws {
        let address = try XCTUnwrap(TemporaryItemPlacement(itemID: "selected", anchors: [
            anchor("left", 100), anchor("selected", 124), anchor("right", 148)
        ]))
        let live = [anchor("left", 200), anchor("right", 224), anchor("selected", 500)]
        XCTAssertEqual(address.returnTarget(in: live), CGPoint(x: 222, y: 12))
        XCTAssertFalse(address.isRestored(in: live))
        XCTAssertTrue(address.isRestored(in: [anchor("left", 200), anchor("selected", 224), anchor("right", 248)]))
    }

    func testReturnFallsBackWhenRightNeighborExitsButDoesNotGuessWhenBothExit() throws {
        let address = try XCTUnwrap(TemporaryItemPlacement(itemID: "selected", anchors: [
            anchor("left", 100), anchor("selected", 124), anchor("right", 148)
        ]))
        XCTAssertEqual(address.returnTarget(in: [anchor("left", 200)]), CGPoint(x: 224, y: 12))
        XCTAssertNil(address.returnTarget(in: [anchor("selected", 500)]))
        XCTAssertFalse(address.isRestored(in: [anchor("selected", 500)]))
    }

    func testReturnRejectsInterveningItemAndWrongSideOfDivider() throws {
        let divider = TemporaryItemPlacement.boundaryID
        let address = try XCTUnwrap(TemporaryItemPlacement(itemID: "selected", anchors: [
            anchor("selected", 100), anchor(divider, 124)
        ]))
        XCTAssertTrue(address.isRestored(in: [anchor("selected", 200), anchor(divider, 224)]))
        XCTAssertFalse(address.isRestored(in: [anchor(divider, 200), anchor("selected", 224)]))
        XCTAssertFalse(address.isRestored(in: [anchor("selected", 200), anchor("other", 224), anchor(divider, 248)]))
    }

    func testBothExitedNeighborsFallBackToOriginalSectionBoundary() throws {
        let divider = TemporaryItemPlacement.boundaryID
        let address = try XCTUnwrap(TemporaryItemPlacement(itemID: "selected", anchors: [
            anchor("left", 100), anchor("selected", 124), anchor("right", 148), anchor(divider, 172)
        ]))
        XCTAssertEqual(address.returnTarget(in: [anchor(divider, 300), anchor("selected", 500)]),
                       CGPoint(x: 298, y: 12))
        XCTAssertTrue(address.isRestored(in: [anchor("selected", 276), anchor(divider, 300)]))
        XCTAssertFalse(address.isRestored(in: [anchor(divider, 300), anchor("selected", 324)]))
    }

    func testSlotRequiresWholeIconOutsideNotchAndImmediatelyBeforeNeighbor() {
        let screen = ScreenGeometry(coordinates: .init(
            appKitFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            quartzFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        ), statusAreaMinX: 550)
        XCTAssertFalse(TemporaryItemPlacement.isDrawable(CGRect(x: 540, y: 0, width: 24, height: 24), screens: [screen]))
        XCTAssertTrue(TemporaryItemPlacement.isDrawable(CGRect(x: 550, y: 0, width: 24, height: 24), screens: [screen]))
        let control = anchor("control", 900).frame
        XCTAssertTrue(TemporaryItemPlacement.isImmediatelyBefore(item: anchor("selected", 878).frame, neighbor: control, otherItems: []))
        XCTAssertFalse(TemporaryItemPlacement.isImmediatelyBefore(item: anchor("selected", 850).frame, neighbor: control, otherItems: [anchor("other", 876).frame]))
        XCTAssertFalse(TemporaryItemPlacement.isImmediatelyBefore(item: anchor("selected", 924).frame, neighbor: control, otherItems: []))
    }
    func testAccessUsesLeftmostDrawableNeighborRatherThanBarkeep() {
        let screen = ScreenGeometry(coordinates: .init(
            appKitFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            quartzFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)
        ), statusAreaMinX: 850)
        let anchors = [anchor("overflow", -4000), anchor("notch", 700),
                       anchor("wifi", 1053), anchor("volume", 1196),
                       anchor(TemporaryItemPlacement.controlID, 1302)]
        XCTAssertEqual(TemporaryItemPlacement.leadingVisibleAnchor(
            in: anchors, excluding: "overflow", screens: [screen])?.id, "wifi")
        XCTAssertEqual(TemporaryItemPlacement.leadingVisibleAnchor(
            in: [anchor("selected", 1015), anchor("wifi", 1053)],
            excluding: "selected", screens: [screen])?.id, "wifi")
        XCTAssertNil(TemporaryItemPlacement.leadingVisibleAnchor(
            in: [anchor("notch", 700)], excluding: "selected", screens: [screen]))
    }

}
