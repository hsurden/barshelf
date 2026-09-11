import XCTest
@testable import BarShelf

final class MenuBarWindowTests: XCTestCase {
    let button = CGRect(x: -4016, y: 4.5, width: 40, height: 24)
    let hosted = MenuBarWindow(id: 10, ownerPID: 636,
                               frame: CGRect(x: -4015, y: 0, width: 38, height: 33))

    func testMatchesTahoeHostedOffscreenButton() {
        XCTAssertEqual(MenuBarWindow.match(frame: button, ownerPID: 698, hostPID: 636,
                                            windows: [hosted]), hosted)
    }

    func testRejectsOtherProcessEvenWithIdenticalBounds() {
        XCTAssertNil(MenuBarWindow.match(frame: button, ownerPID: 698, hostPID: 900, windows: [hosted]))
    }

    func testRejectsAmbiguousWindows() {
        let duplicate = MenuBarWindow(id: 11, ownerPID: 636, frame: hosted.frame)
        XCTAssertNil(MenuBarWindow.match(frame: button, ownerPID: 698, hostPID: 636,
                                        windows: [hosted, duplicate]))
    }

    func testRejectsStalePositionAndWrongMenuBar() {
        XCTAssertNil(MenuBarWindow.match(frame: button.offsetBy(dx: 30, dy: 0), ownerPID: 698,
                                        hostPID: 636, windows: [hosted]))
        XCTAssertNil(MenuBarWindow.match(frame: button.offsetBy(dx: 0, dy: 800), ownerPID: 698,
                                        hostPID: 636, windows: [hosted]))
        XCTAssertNil(MenuBarWindow.match(frame: .zero, ownerPID: 698, hostPID: 636, windows: [hosted]))
    }

    func testMatchesDirectlyOwnedWindowWithoutSharedHost() {
        XCTAssertEqual(MenuBarWindow.match(frame: button, ownerPID: 636, hostPID: nil,
                                            windows: [hosted]), hosted)
    }

    func testDestinationUsesFreshWindowEdgeIncludingOffscreenReturn() {
        XCTAssertEqual(WindowMoveEdge.left.point(on: hosted.frame), CGPoint(x: -4015, y: 16.5))
        XCTAssertEqual(WindowMoveEdge.right.point(on: hosted.frame), CGPoint(x: -3977, y: 16.5))
    }
    func testInsertionCoordinatesAccountForWidthWhenMovingOutAndBack() {
        let visible = CGRect(x: 1302, y: 0, width: 25, height: 33)
        let outward = WindowMoveEdge.left.movePoints(source: hosted.frame, destination: visible)
        XCTAssertEqual(outward.start, CGPoint(x: 1302, y: 0))
        XCTAssertEqual(outward.end, CGPoint(x: 1264, y: 0))
        let returned = WindowMoveEdge.left.movePoints(source: visible, destination: hosted.frame)
        XCTAssertEqual(returned.start, CGPoint(x: -4016, y: 0))
        XCTAssertEqual(returned.end, CGPoint(x: -4005.5, y: 0))
        let right = WindowMoveEdge.right.movePoints(source: visible, destination: hosted.frame)
        XCTAssertEqual(right.start, CGPoint(x: -3976, y: 0))
        XCTAssertEqual(right.end, CGPoint(x: -3986.5, y: 0))
    }

    func testLeftwardReturnReleasesBeforeNarrowNeighborMidpoint() {
        // Live calibration, 2026-09-10, NSStatusItemSpacing 3: a 24-point
        // Rectangle window returning before a 19-point neighbor landed
        // correctly at 0, 0.25, and 0.5 of the neighbor width, and one slot
        // too far at 0.75 and 1.0.
        let rectangle = CGRect(x: 1120, y: 0, width: 24, height: 33)
        let neighbor = CGRect(x: -3927, y: 0, width: 19, height: 33)
        let end = WindowMoveEdge.left.movePoints(source: rectangle, destination: neighbor).end.x
        XCTAssertEqual(end, neighbor.minX + 4.75)
        XCTAssertLessThan(end, neighbor.midX)
    }

    func testWideWeatherReturnDoesNotOvershootNarrowNeighbor() {
        // Live failure: Weather (66pt) was released past Claude (40pt)
        // and landed to its right instead of between the saved neighbors.
        let weather = CGRect(x: 1431, y: 0, width: 66, height: 33)
        for width: CGFloat in [38, 40] {
            let neighbor = CGRect(x: -4603, y: 0, width: width, height: 33)
            let points = WindowMoveEdge.left.movePoints(source: weather, destination: neighbor)
            XCTAssertEqual(points.end.x, neighbor.minX + width / 4)
            XCTAssertLessThan(points.end.x, neighbor.midX)
        }
        // The wide closed boundary still uses the selected icon's width.
        let divider = CGRect(x: -4387, y: 0, width: 5016, height: 33)
        XCTAssertEqual(WindowMoveEdge.left.movePoints(source: weather, destination: divider).end.x,
                       divider.minX + weather.width)
    }

}
