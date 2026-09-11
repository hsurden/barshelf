import XCTest
@testable import BarShelf

final class TemporaryItemPlacementTests: XCTestCase {
    func testAccessFallsBackToControlWhenLeftmostSlotCrossesNotch() {
        let screen = ScreenGeometry(coordinates: ScreenCoordinateSpace(
            appKitFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            quartzFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117)
        ), statusAreaMinX: 956)
        let item = TemporaryItemPlacement.Anchor(id: "chrome",
            frame: CGRect(x: -100, y: 4.5, width: 24, height: 24))
        let control = anchor(TemporaryItemPlacement.controlID, 1497)
        XCTAssertEqual(TemporaryItemPlacement.accessAnchor(
            for: item, in: [item, anchor("wifi", 979), control], screens: [screen])?.id,
            TemporaryItemPlacement.controlID)
        XCTAssertEqual(TemporaryItemPlacement.accessAnchor(
            for: item, in: [item, anchor("wifi", 980), control], screens: [screen])?.id,
            "wifi")
        XCTAssertNil(TemporaryItemPlacement.accessAnchor(
            for: item, in: [item, anchor("wifi", 979)], screens: [screen]))
        XCTAssertNil(TemporaryItemPlacement.accessAnchor(
            for: item, in: [item, anchor(TemporaryItemPlacement.controlID, 970)],
            screens: [screen]))
    }

    func testFullBarUsesLeftmostSlotThatClearsNotchInsteadOfControl() {
        let screen = ScreenGeometry(coordinates: ScreenCoordinateSpace(
            appKitFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            quartzFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117)
        ), statusAreaMinX: 956)
        let item = TemporaryItemPlacement.Anchor(id: "chrome",
            frame: CGRect(x: -4000, y: 4.5, width: 24, height: 24))
        let control = anchor(TemporaryItemPlacement.controlID, 1497)
        // Wi-Fi's slot would cross the notch; Bluetooth's clears it. macOS then
        // pushes Wi-Fi behind the notch until the item returns.
        let anchors = [item, anchor("wifi", 960), anchor("bluetooth", 982), anchor("sound", 1004), control]
        XCTAssertEqual(TemporaryItemPlacement.accessAnchor(for: item, in: anchors, screens: [screen])?.id,
                       "bluetooth")
        XCTAssertEqual(TemporaryItemPlacement.accessCandidates(for: item, in: anchors, screens: [screen]).map(\.id),
                       ["bluetooth", "sound", TemporaryItemPlacement.controlID])
    }

    func testAccessSkipsLiveActivitiesAndItemsRightOfControl() {
        let screen = ScreenGeometry(coordinates: ScreenCoordinateSpace(
            appKitFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            quartzFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)
        ), statusAreaMinX: 848)
        let item = TemporaryItemPlacement.Anchor(id: "antigravity",
            frame: CGRect(x: -4055, y: 4.5, width: 27, height: 24))
        let pill = TemporaryItemPlacement.Anchor(id: "united.liveActivity",
            frame: CGRect(x: 983, y: 4.5, width: 135, height: 24))
        let control = anchor(TemporaryItemPlacement.controlID, 1303)
        let anchors = [item, pill, anchor("bluetooth", 1145), control, anchor("clock", 1376)]
        XCTAssertEqual(TemporaryItemPlacement.accessAnchor(
            for: item, in: anchors, excluding: [pill.id], screens: [screen])?.id, "bluetooth")
        XCTAssertFalse(TemporaryItemPlacement.accessCandidates(
            for: item, in: anchors, excluding: [pill.id], screens: [screen]).contains { $0.id == "clock" })
    }

    func testLiveActivityIdentityIsRecognized() {
        let pill = MenuBarItemSnapshot(
            id: "com.apple.controlcenter|ax:com.united.UnitedCustomerFacingIPhone.liveActivity",
            displayName: "United", ownerName: "Control Center",
            bundleIdentifier: "com.apple.controlcenter",
            frame: CGRect(x: 983, y: 4.5, width: 135, height: 24), isEnabled: true)
        let wifi = MenuBarItemSnapshot(
            id: "com.apple.controlcenter|ax:com.apple.menuextra.wifi",
            displayName: "Wi-Fi", ownerName: "Control Center",
            bundleIdentifier: "com.apple.controlcenter",
            frame: CGRect(x: 1163, y: 4.5, width: 22, height: 24), isEnabled: true)
        XCTAssertTrue(pill.isLiveActivity)
        XCTAssertFalse(wifi.isLiveActivity)
    }

    func testOverflowReturnDistinguishesWrongOrderFromSystemDisabledIcon() throws {
        let screen = ScreenGeometry(coordinates: .init(
            appKitFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            quartzFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117)
        ), statusAreaMinX: 956)
        let control = CGRect(x: 1504, y: 4.5, width: 24, height: 24)
        XCTAssertTrue(TemporaryItemPlacement.isInOverflow(
            CGRect(x: 714, y: 4.5, width: 24, height: 24), reference: control, screens: [screen]))
        XCTAssertFalse(TemporaryItemPlacement.isInOverflow(
            CGRect(x: -1, y: 1116, width: 24, height: 24), reference: control, screens: [screen]))
        XCTAssertFalse(TemporaryItemPlacement.isInOverflow(
            CGRect(x: 1466, y: 4.5, width: 24, height: 24), reference: control, screens: [screen]))
        let address = try XCTUnwrap(TemporaryItemPlacement(itemID: "tailscale", anchors: [
            anchor("playing", 715), anchor("tailscale", 747), anchor("telegram", 777)
        ]))
        XCTAssertFalse(address.isRestored(in: [anchor("tailscale", 714),
            anchor("playing", 753), anchor("telegram", 777)]))
    }

    func testAccessInventoryKeepsHiddenAndNotchItemsButExcludesUnavailableIcons() {
        let control = CGRect(x: 1504, y: 4.5, width: 24, height: 24)
        for x: CGFloat in [-4600, 714, 1466] {
            XCTAssertTrue(TemporaryItemPlacement.isAvailableForAccess(
                CGRect(x: x, y: 4.5, width: 24, height: 24), reference: control))
        }
        XCTAssertFalse(TemporaryItemPlacement.isAvailableForAccess(
            CGRect(x: -1, y: 1116, width: 40, height: 24), reference: control))
        XCTAssertFalse(TemporaryItemPlacement.isAvailableForAccess(
            CGRect(x: 714, y: 16.5, width: 0, height: 0), reference: control))
        // Re-enabling the same app restores an ordinary row frame; it is
        // eligible on the next refresh, with no sticky exclusion by identity.
        XCTAssertTrue(TemporaryItemPlacement.isAvailableForAccess(
            CGRect(x: -4600, y: 4.5, width: 40, height: 24), reference: control))
    }

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
    func testAccessUsesLeftmostDrawableNeighborRatherThanBarShelf() {
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

    @MainActor
    func testParkedItemsAndClosedBoundaryAreNotReadyForMoves() {
        // Captured on Jon's 1728x1117 MacBook Pro on macOS 26.5.2. Tahoe
        // reports deeply overflowed children on a sentinel row at the bottom
        // of the display even though ordinary menu-bar children use y=4...30.
        let control = CGRect(x: 1506, y: 0, width: 38, height: 33)
        let nordParked = CGRect(x: -1, y: 1116, width: 36, height: 24)
        let nordRematerialized = CGRect(x: 980, y: 4, width: 36, height: 24)

        XCTAssertFalse(TemporaryItemPlacement.isOnMenuBarRow(nordParked, reference: control))
        XCTAssertTrue(TemporaryItemPlacement.isOnMenuBarRow(nordRematerialized, reference: control))
        // The failed Chrome move read this closed native boundary and calculated
        // an off-display target at x=-1314. Trimming its width hid the stale size.
        XCTAssertFalse(StatusBarEngine.isCompactBoundaryFrame(
            CGRect(x: -4146, y: 1084, width: 5002, height: 33)))
        XCTAssertTrue(StatusBarEngine.isCompactBoundaryFrame(
            CGRect(x: 979, y: 1084, width: 28, height: 33)))
        XCTAssertFalse(StatusBarEngine.isCompactBoundaryFrame(.zero))
    }

    func testMacBookAXFixturePreservesRealOverflowSplit() {
        let screen = ScreenGeometry(
            coordinates: ScreenCoordinateSpace(
                appKitFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                quartzFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117)
            ),
            statusAreaMinX: 956
        )
        let rows: [(String, CGRect)] = [
            ("Now Playing", CGRect(x: -3998, y: 4, width: 17, height: 26)),
            ("Google Drive", CGRect(x: -3974, y: 4, width: 34, height: 26)),
            ("Rectangle", CGRect(x: -3942, y: 4, width: 40, height: 26)),
            ("1Password", CGRect(x: -1, y: 1115, width: 34, height: 26)),
            ("nordMenuBarItem", CGRect(x: -1, y: 1115, width: 36, height: 26)),
            ("Google Chrome", CGRect(x: 7, y: 1115, width: 24, height: 26)),
            ("Antigravity", CGRect(x: -1, y: 1115, width: 40, height: 26)),
            ("Gemini status menu", CGRect(x: 7, y: 1115, width: 24, height: 26)),
            ("ChatGPT", CGRect(x: 7, y: 1115, width: 24, height: 26)),
            ("Telegram", CGRect(x: -1, y: 1115, width: 42, height: 26)),
            ("Creative Cloud", CGRect(x: 7, y: 1115, width: 26, height: 26)),
            ("Claude", CGRect(x: -1, y: 1115, width: 42, height: 26)),
            ("Citrix Workspace", CGRect(x: 1104, y: 4, width: 24, height: 26)),
            ("ChatGPTHelper", CGRect(x: 1134, y: 4, width: 36, height: 26)),
            ("SwiftBar Camera", CGRect(x: 1168, y: 4, width: 45, height: 26)),
            ("Tailscale", CGRect(x: 1219, y: 4, width: 24, height: 26)),
            ("SwiftBar Location", CGRect(x: 1249, y: 4, width: 73, height: 26)),
            ("Wi-Fi", CGRect(x: 1329, y: 4, width: 22, height: 26)),
            ("SwiftBar", CGRect(x: 1358, y: 4, width: 40, height: 26)),
            ("Battery", CGRect(x: 1405, y: 4, width: 26, height: 26)),
            ("SystemUIServer", CGRect(x: 1409, y: 4, width: 22, height: 26)),
            ("Spotlight", CGRect(x: 1476, y: 4, width: 34, height: 26)),
            ("jon", CGRect(x: 1517, y: 4, width: 18, height: 26)),
            ("Control Center", CGRect(x: 1552, y: 4, width: 26, height: 26)),
            ("Clock", CGRect(x: 1594, y: 4, width: 127, height: 26)),
        ]
        let overflowed = rows.filter { OverflowClassifier.isOverflowed(frame: $0.1, screens: [screen]) }
        XCTAssertEqual(rows.count, 25)
        XCTAssertEqual(overflowed.count, 12)
        XCTAssertTrue(overflowed.map(\.0).contains("nordMenuBarItem"))
    }
}
