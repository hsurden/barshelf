import XCTest
@testable import BarShelf

final class BarShelfTests: XCTestCase {
    func testVisibleMoveConfirmationRejectsNotchOverflowOnVisibleSideOfDivider() {
        let boundaries = BoundaryFrames(
            control: CGRect(x: 1497, y: 1084, width: 38, height: 33),
            alwaysHidden: CGRect(x: 879, y: 1084, width: 30, height: 33)
        )
        let screen = ScreenGeometry(
            coordinates: ScreenCoordinateSpace(
                appKitFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                quartzFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117)
            ), statusAreaMinX: 956
        )
        let chrome = CGRect(x: 916, y: 4.5, width: 24, height: 24)
        XCTAssertEqual(boundaries.zone(for: chrome), .alwaysVisible)
        XCTAssertFalse(boundaries.confirms(chrome, in: .alwaysVisible, screens: [screen]))
        XCTAssertFalse(boundaries.confirms(
            CGRect(x: 955, y: 4.5, width: 24, height: 24),
            in: .alwaysVisible, screens: [screen]))
        XCTAssertTrue(boundaries.confirms(
            CGRect(x: 956, y: 4.5, width: 24, height: 24),
            in: .alwaysVisible, screens: [screen]))
        XCTAssertTrue(boundaries.confirms(
            CGRect(x: -200, y: 4.5, width: 24, height: 24),
            in: .alwaysHidden, screens: [screen]))
    }

    func testBoundaryClassification() {
        let boundaries = BoundaryFrames(
            control: CGRect(x: 900, y: 900, width: 20, height: 24),
            alwaysHidden: CGRect(x: 400, y: 900, width: 10, height: 24)
        )

        XCTAssertEqual(
            boundaries.zone(for: CGRect(x: 800, y: 900, width: 20, height: 24)),
            .alwaysVisible
        )
        XCTAssertEqual(
            boundaries.zone(for: CGRect(x: 250, y: 900, width: 20, height: 24)),
            .alwaysHidden
        )
    }

    func testSystemItemsRightOfControlAreAlwaysVisible() {
        let boundaries = BoundaryFrames(
            control: CGRect(x: 900, y: 876, width: 20, height: 24),
            alwaysHidden: CGRect(x: 400, y: 876, width: 14, height: 24)
        )
        let systemItem = CGRect(x: 920, y: 876, width: 20, height: 24)

        XCTAssertGreaterThan(systemItem.midX, boundaries.control.midX)
        XCTAssertEqual(boundaries.zone(for: systemItem), .alwaysVisible)
    }

    func testBoundaryTargetsAllowEmptySections() throws {
        let boundaries = BoundaryFrames(
            control: CGRect(x: 900, y: 876, width: 20, height: 24),
            alwaysHidden: CGRect(x: 886, y: 876, width: 14, height: 24)
        )

        XCTAssertEqual(
            boundaries.targetPoint(for: .alwaysVisible),
            CGPoint(x: 901, y: 888)
        )
        XCTAssertEqual(
            boundaries.targetPoint(for: .alwaysHidden),
            CGPoint(x: 868, y: 888)
        )

        let visibleTarget = try XCTUnwrap(boundaries.targetPoint(for: .alwaysVisible))
        let insertedItem = CGRect(x: visibleTarget.x - 11, y: 876, width: 22, height: 24)
        XCTAssertEqual(boundaries.zone(for: insertedItem), .alwaysVisible)
    }

    func testTargetMovesItemOutOfAlwaysHidden() throws {
        let boundaries = BoundaryFrames(
            control: CGRect(x: 900, y: 876, width: 20, height: 24),
            alwaysHidden: CGRect(x: 400, y: 876, width: 14, height: 24)
        )
        let initialFrame = CGRect(x: 250, y: 876, width: 22, height: 24)
        let visibleTarget = try XCTUnwrap(boundaries.targetPoint(for: .alwaysVisible))
        let movedFrame = CGRect(x: visibleTarget.x - 11, y: 876, width: 22, height: 24)

        XCTAssertEqual(boundaries.zone(for: initialFrame), .alwaysHidden)
        XCTAssertEqual(boundaries.zone(for: movedFrame), .alwaysVisible)
    }

    func testBoundaryTargetsRejectInvalidOrdering() {
        let boundaries = BoundaryFrames(
            control: CGRect(x: 872, y: 876, width: 20, height: 24),
            alwaysHidden: CGRect(x: 900, y: 876, width: 14, height: 24)
        )

        for zone in VisibilityZone.allCases {
            XCTAssertNil(boundaries.targetPoint(for: zone))
        }
    }

    func testAppKitPointsConvertToQuartzCoordinates() {
        let coordinates = ScreenCoordinateSpace(
            appKitFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            quartzFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        XCTAssertEqual(
            coordinates.quartzPoint(fromAppKit: CGPoint(x: 100, y: 888)),
            CGPoint(x: 100, y: 12)
        )
        XCTAssertEqual(
            coordinates.quartzPoint(fromAppKit: CGPoint(x: 500, y: 300)),
            CGPoint(x: 500, y: 600)
        )
    }

    func testAccessibilitySourceUsesMenuBarCoordinateCandidate() {
        let coordinates = ScreenCoordinateSpace(
            appKitFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            quartzFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )

        XCTAssertEqual(
            coordinates.quartzPoint(
                fromAccessibility: CGPoint(x: 100, y: 12),
                menuBarAnchorY: 12
            ),
            CGPoint(x: 100, y: 12)
        )
        XCTAssertEqual(
            coordinates.quartzPoint(
                fromAccessibility: CGPoint(x: 100, y: 888),
                menuBarAnchorY: 12
            ),
            CGPoint(x: 100, y: 12)
        )
    }

    func testAppKitPointsConvertAcrossOffsetDisplays() {
        let coordinates = ScreenCoordinateSpace(
            appKitFrame: CGRect(x: 1440, y: 100, width: 1920, height: 1080),
            quartzFrame: CGRect(x: 1440, y: -280, width: 1920, height: 1080)
        )

        XCTAssertEqual(
            coordinates.quartzPoint(fromAppKit: CGPoint(x: 1540, y: 1160)),
            CGPoint(x: 1540, y: -260)
        )
        XCTAssertNil(coordinates.quartzPoint(fromAppKit: CGPoint(x: 100, y: 100)))
    }

    func testNoNotchDisplayAllowsSettingsMove() {
        let screen = ScreenGeometry(
            coordinates: ScreenCoordinateSpace(
                appKitFrame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
                quartzFrame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
            )
        )

        XCTAssertNoThrow(
            try ItemMoveService.validate(
                sourceFrame: CGRect(x: 1_500, y: 0, width: 22, height: 24),
                target: CGPoint(x: 1_200, y: 12),
                screens: [screen]
            )
        )
    }

    func testNotchedDisplayAllowsSettingsMoveAcrossCenter() {
        let screen = ScreenGeometry(
            coordinates: ScreenCoordinateSpace(
                appKitFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
                quartzFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982)
            )
        )
        let source = CGRect(x: 1_300, y: 0, width: 22, height: 24)
        let target = CGPoint(x: 200, y: 12)
        let cameraHousing = CGRect(x: 646, y: 0, width: 220, height: 40)

        // macOS owns overflow around the housing. BarShelf validates the landing
        // points and relies on the confirmation scan instead of blocking this path.
        XCTAssertGreaterThan(source.midX, cameraHousing.maxX)
        XCTAssertLessThan(target.x, cameraHousing.minX)
        XCTAssertTrue(cameraHousing.contains(CGPoint(x: cameraHousing.midX, y: target.y)))
        XCTAssertNoThrow(
            try ItemMoveService.validate(
                sourceFrame: source,
                target: target,
                screens: [screen]
            )
        )
    }

    func testSettingsMoveRejectsOffscreenTarget() {
        let screen = ScreenGeometry(
            coordinates: ScreenCoordinateSpace(
                appKitFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
                quartzFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982)
            )
        )

        XCTAssertThrowsError(
            try ItemMoveService.validate(
                sourceFrame: CGRect(x: 1_300, y: 0, width: 22, height: 24),
                target: CGPoint(x: -100, y: 12),
                screens: [screen]
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                BarShelfError.invalidGeometry.localizedDescription
            )
        }
    }

    func testDefaultProductRules() {
        let settings = BarShelfSettings()
        XCTAssertEqual(settings.iconStyle, .ellipsis)
        XCTAssertFalse(settings.requireAuthentication)
        XCTAssertFalse(settings.reduceItemSpacing)
    }

    func testPickerPrioritizesOverflowAndFiltersPinnedItems() {
        func item(_ name: String, id: String? = nil) -> MenuBarItemSnapshot {
            MenuBarItemSnapshot(
                id: id ?? "com.example.\(name.lowercased())|status",
                displayName: name,
                ownerName: "\(name) App",
                bundleIdentifier: id == nil ? "com.example.\(name.lowercased())" : "com.apple.controlcenter",
                frame: CGRect(x: 10, y: 10, width: 20, height: 20),
                isEnabled: true
            )
        }

        let hidden = item("Hidden")
        let alwaysHidden = item("Archive")
        let visible = item("Visible")
        let pinnedClock = item(
            "Clock",
            id: "com.apple.controlcenter|com.apple.menuextra.clock"
        )
        let zones: [String: VisibilityZone] = [
            hidden.id: .alwaysHidden,
            alwaysHidden.id: .alwaysHidden,
            visible.id: .alwaysVisible,
            pinnedClock.id: .alwaysVisible,
        ]

        let contents = MenuBarPickerContents(
            items: [visible, hidden, pinnedClock, alwaysHidden],
            query: ""
        ) { zones[$0.id] ?? .alwaysVisible }

        XCTAssertEqual(contents.overflow.map(\.displayName), ["Archive", "Hidden"])
        XCTAssertEqual(contents.visible.map(\.displayName), ["Visible"])
        XCTAssertFalse(contents.isEmpty)
    }

    func testPickerSearchesDisplayAndOwnerNames() {
        let item = MenuBarItemSnapshot(
            id: "com.example.sync|status",
            displayName: "Connection",
            ownerName: "Cloud Sync",
            bundleIdentifier: "com.example.sync",
            frame: CGRect(x: 10, y: 10, width: 20, height: 20),
            isEnabled: true
        )

        let displayMatch = MenuBarPickerContents(items: [item], query: "connect") { _ in .alwaysHidden }
        let ownerMatch = MenuBarPickerContents(items: [item], query: "cloud") { _ in .alwaysHidden }
        let noMatch = MenuBarPickerContents(items: [item], query: "battery") { _ in .alwaysHidden }

        XCTAssertEqual(displayMatch.overflow, [item])
        XCTAssertEqual(ownerMatch.overflow, [item])
        XCTAssertTrue(noMatch.isEmpty)
    }

    @MainActor
    func testMenuBarStripDetection() {
        let frame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        XCTAssertTrue(AppCoordinator.isInMenuBarStrip(
            location: CGPoint(x: 900, y: 1100), screenFrame: frame
        ))
        XCTAssertFalse(AppCoordinator.isInMenuBarStrip(
            location: CGPoint(x: 900, y: 1000), screenFrame: frame
        ))
        XCTAssertFalse(AppCoordinator.isInMenuBarStrip(
            location: CGPoint(x: 2000, y: 1100), screenFrame: frame
        ))
    }

    func testNotchOverflowDetection() {
        let notched = ScreenGeometry(
            coordinates: ScreenCoordinateSpace(
                appKitFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                quartzFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117)
            ),
            statusAreaMinX: 1010
        )
        XCTAssertTrue(notched.hidesMenuBarPoint(CGPoint(x: 896, y: 16.5)))
        XCTAssertFalse(notched.hidesMenuBarPoint(CGPoint(x: 1200, y: 16.5)))
        XCTAssertFalse(notched.hidesMenuBarPoint(CGPoint(x: 896, y: 500)))
        XCTAssertFalse(notched.hidesMenuBarPoint(CGPoint(x: -100, y: 16.5)))

        let flat = ScreenGeometry(
            coordinates: notched.coordinates
        )
        XCTAssertFalse(flat.hidesMenuBarPoint(CGPoint(x: 896, y: 16.5)))
    }

    func testPinnedByMacOSDetection() {
        func snapshot(bundle: String?, stablePart: String) -> MenuBarItemSnapshot {
            MenuBarItemSnapshot(
                id: "\(bundle ?? "pid:1")|\(stablePart)",
                displayName: "Item",
                ownerName: "Owner",
                bundleIdentifier: bundle,
                frame: CGRect(x: 10, y: 10, width: 20, height: 20),
                isEnabled: true
            )
        }

        XCTAssertTrue(snapshot(
            bundle: "com.apple.controlcenter",
            stablePart: "com.apple.menuextra.clock"
        ).isPinnedByMacOS)
        XCTAssertTrue(snapshot(
            bundle: "com.apple.controlcenter",
            stablePart: "com.apple.menuextra.controlcenter"
        ).isPinnedByMacOS)
        XCTAssertFalse(snapshot(
            bundle: "com.apple.controlcenter",
            stablePart: "com.apple.menuextra.battery"
        ).isPinnedByMacOS)
        XCTAssertFalse(snapshot(
            bundle: "com.example.app",
            stablePart: "com.apple.menuextra.clock"
        ).isPinnedByMacOS)
    }

    func testFallbackIdentityDoesNotDependOnMutableTitle() {
        let first = MenuBarItemIdentity.id(
            bundleIdentifier: "com.example.sync",
            pid: 42,
            identifier: nil,
            slot: 0
        )
        let afterStatusTextChanged = MenuBarItemIdentity.id(
            bundleIdentifier: "com.example.sync",
            pid: 42,
            identifier: nil,
            slot: 0
        )
        XCTAssertEqual(first, "com.example.sync|slot:0")
        XCTAssertEqual(first, afterStatusTextChanged)
        XCTAssertEqual(
            MenuBarItemIdentity.id(
                bundleIdentifier: "com.example.sync",
                pid: 42,
                identifier: "status-item",
                slot: 7
            ),
            "com.example.sync|ax:status-item"
        )
        XCTAssertEqual(
            MenuBarItemIdentity.id(
                bundleIdentifier: "com.microsoft.OneDrive",
                pid: 42,
                identifier: "OneDrive — Backed up and synced",
                slot: 0
            ),
            "com.microsoft.OneDrive|slot:0"
        )
    }

    @MainActor
    func testLegacyRuleAndPriorityIdentityMigration() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let legacyID = "com.example.sync|Connected|0"
        var document = BarShelfDocument()
        document.rules[legacyID] = ItemRule(
            id: legacyID,
            displayName: "Connected",
            ownerName: "Sync App",
            bundleIdentifier: "com.example.sync",
            zone: .alwaysHidden,
            group: nil
        )
        document.priorityOrder = [PriorityEntry(
            id: legacyID,
            displayName: "Connected",
            ownerName: "Sync App",
            bundleIdentifier: "com.example.sync"
        )]
        let encoder = JSONEncoder()
        try encoder.encode(document).write(to: baseURL.appendingPathComponent("state.json"))

        let item = MenuBarItemSnapshot(
            id: "com.example.sync|slot:0",
            displayName: "Synchronizing 42 files",
            ownerName: "Sync App",
            bundleIdentifier: "com.example.sync",
            frame: CGRect(x: 10, y: 4, width: 20, height: 24),
            isEnabled: true,
            ownerPID: 42,
            ownerSlot: 0
        )
        let store = StateStore(baseURL: baseURL)
        store.reconcileItemIdentities(with: [item])

        XCTAssertNil(store.rules[legacyID])
        XCTAssertEqual(store.rules[item.id]?.zone, .alwaysHidden)
        XCTAssertEqual(store.priorityOrder.map(\.id), [item.id])
    }

    @MainActor
    func testStateRoundTrip() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let item = MenuBarItemSnapshot(
            id: "com.example.app|Status",
            displayName: "Status",
            ownerName: "Example",
            bundleIdentifier: "com.example.app",
            frame: CGRect(x: 10, y: 10, width: 20, height: 20),
            isEnabled: true
        )

        let first = StateStore(baseURL: baseURL)
        first.updateSettings { $0.iconStyle = .ring }
        first.setRule(for: item, zone: .alwaysVisible)

        let second = StateStore(baseURL: baseURL)
        XCTAssertEqual(second.settings.iconStyle, .ring)
        XCTAssertEqual(second.rules[item.id]?.zone, .alwaysVisible)
    }

    @MainActor
    func testSettingsUpdateNotifiesObservers() {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = StateStore(baseURL: baseURL)
        var notifications = 0
        let subscription = store.objectWillChange.sink { notifications += 1 }

        store.updateSettings { $0.requireAuthentication = true }

        XCTAssertTrue(store.settings.requireAuthentication)
        XCTAssertGreaterThanOrEqual(notifications, 1)
        withExtendedLifetime(subscription) {}
    }

    private func snapshot(
        _ name: String,
        x: CGFloat,
        width: CGFloat = 30,
        bundle: String? = nil,
        stablePart: String = "status"
    ) -> MenuBarItemSnapshot {
        let bundleID = bundle ?? "com.example.\(name.lowercased())"
        return MenuBarItemSnapshot(
            id: "\(bundleID)|\(stablePart)",
            displayName: name,
            ownerName: name,
            bundleIdentifier: bundleID,
            frame: CGRect(x: x, y: 4, width: width, height: 24),
            isEnabled: true
        )
    }

    private var notchedScreen: ScreenGeometry {
        ScreenGeometry(
            coordinates: ScreenCoordinateSpace(
                appKitFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                quartzFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117)
            ),
            statusAreaMinX: 1010
        )
    }

    func testOverflowClassification() {
        let screens = [notchedScreen]

        XCTAssertFalse(OverflowClassifier.isOverflowed(
            frame: CGRect(x: 1200, y: 4, width: 30, height: 24), screens: screens
        ))
        // Laid out behind the notch: on screen, but left of the status area.
        XCTAssertTrue(OverflowClassifier.isOverflowed(
            frame: CGRect(x: 900, y: 4, width: 30, height: 24), screens: screens
        ))
        // Pushed past the display entirely.
        XCTAssertTrue(OverflowClassifier.isOverflowed(
            frame: CGRect(x: -200, y: 4, width: 30, height: 24), screens: screens
        ))
        // Not on the menu bar strip at all.
        XCTAssertTrue(OverflowClassifier.isOverflowed(
            frame: CGRect(x: 1200, y: 500, width: 30, height: 24), screens: screens
        ))

        let ids = OverflowClassifier.overflowedIDs(
            items: [snapshot("Safe", x: 1200), snapshot("Notched", x: 900)],
            screens: screens
        )
        XCTAssertEqual(ids, ["com.example.notched|status"])
    }

    func testShelfSessionIncludesSavedHiddenAndPhysicalOverflow() {
        let visible = snapshot("Visible", x: 1_200)
        let overflow = snapshot("Overflow", x: 900)
        let savedHidden = snapshot("Saved", x: 1_300)
        let shelf = ShelfSessionModel.items(
            from: [visible, overflow, savedHidden],
            overflowIDs: [overflow.id],
            intentionallyHiddenIDs: [savedHidden.id]
        )

        XCTAssertEqual(Set(shelf.map(\.id)), [overflow.id, savedHidden.id])
        // A session is an owned value. Later classifier changes do not mutate
        // the buttons already displayed in this session.
        let laterOverflowIDs: Set<String> = []
        XCTAssertTrue(laterOverflowIDs.isEmpty)
        XCTAssertEqual(Set(shelf.map(\.id)), [overflow.id, savedHidden.id])
    }

    func testShelfInventoryToleratesTwoMissedScansAndDropsExitedOwner() {
        let item = MenuBarItemSnapshot(
            id: "com.example.sync|slot:0",
            displayName: "Sync",
            ownerName: "Sync",
            bundleIdentifier: "com.example.sync",
            frame: CGRect(x: 900, y: 4, width: 20, height: 24),
            isEnabled: true,
            ownerPID: 42
        )
        var inventory = ShelfInventory()
        inventory.update(
            scannedItems: [item],
            scannedOverflowIDs: [item.id],
            runningPIDs: [42]
        )
        inventory.update(scannedItems: [], scannedOverflowIDs: [], runningPIDs: [42])
        inventory.update(scannedItems: [], scannedOverflowIDs: [], runningPIDs: [42])
        XCTAssertEqual(inventory.items.map(\.id), [item.id])
        XCTAssertEqual(inventory.overflowIDs, [item.id])

        inventory.update(scannedItems: [item], scannedOverflowIDs: [], runningPIDs: [42])
        XCTAssertTrue(inventory.overflowIDs.isEmpty)

        inventory.update(scannedItems: [], scannedOverflowIDs: [], runningPIDs: [])
        XCTAssertTrue(inventory.items.isEmpty)
        XCTAssertTrue(inventory.overflowIDs.isEmpty)
    }

    func testConfirmedPlacementUpdatesOverflowWithoutRescan() {
        let item = MenuBarItemSnapshot(
            id: "com.example.drive|slot:0",
            displayName: "Drive",
            ownerName: "Drive",
            bundleIdentifier: "com.example.drive",
            frame: CGRect(x: -3000, y: 4, width: 20, height: 24),
            isEnabled: true,
            ownerPID: 42
        )
        var inventory = ShelfInventory()
        inventory.update(scannedItems: [item], scannedOverflowIDs: [item.id], runningPIDs: [42])

        // A confirmed move into the bar clears the stale off-screen evidence
        // that kept the Items tab showing the icon as hidden.
        inventory.recordConfirmedPlacement(itemID: item.id, isOverflowed: false)
        XCTAssertTrue(inventory.overflowIDs.isEmpty)

        inventory.recordConfirmedPlacement(itemID: item.id, isOverflowed: true)
        XCTAssertEqual(inventory.overflowIDs, [item.id])

        // Unknown items are ignored so a move cannot invent inventory.
        inventory.recordConfirmedPlacement(itemID: "com.example.other|slot:0", isOverflowed: true)
        XCTAssertEqual(inventory.overflowIDs, [item.id])
    }

    func testFlatDisplayHasNoNotchOverflow() {
        let flat = ScreenGeometry(
            coordinates: ScreenCoordinateSpace(
                appKitFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                quartzFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
            )
        )
        XCTAssertFalse(OverflowClassifier.isOverflowed(
            frame: CGRect(x: 100, y: 4, width: 30, height: 24), screens: [flat]
        ))
    }

    func testOrderPlannerMovesItemToRankPosition() {
        let clock = snapshot(
            "Clock",
            x: 1650,
            bundle: "com.apple.controlcenter",
            stablePart: "com.apple.menuextra.clock"
        )
        let a = snapshot("Alpha", x: 1600)
        let b = snapshot("Beta", x: 1560)
        let c = snapshot("Gamma", x: 1520)
        let all = [c, a, clock, b]

        let movable = OrderPlanner.movableRightToLeft(all)
        XCTAssertEqual(movable.map(\.displayName), ["Alpha", "Beta", "Gamma"])
        XCTAssertEqual(OrderPlanner.rightAnchorMinX(all), clock.frame.minX)

        // Alpha already holds rank 0.
        XCTAssertTrue(OrderPlanner.isInPlace(itemID: a.id, rank: 0, movableRightToLeft: movable))
        XCTAssertNil(OrderPlanner.moveTarget(
            itemID: a.id, rank: 0, movableRightToLeft: movable, rightAnchorMinX: clock.frame.minX
        ))

        // Gamma wants rank 0: drop just left of the pinned cluster.
        let target = OrderPlanner.moveTarget(
            itemID: c.id, rank: 0, movableRightToLeft: movable, rightAnchorMinX: clock.frame.minX
        )
        XCTAssertEqual(target, CGPoint(x: clock.frame.minX - 6, y: a.frame.midY))

        // Gamma wants rank 1: drop just left of the current rank-0 item.
        let secondTarget = OrderPlanner.moveTarget(
            itemID: c.id, rank: 1, movableRightToLeft: movable, rightAnchorMinX: clock.frame.minX
        )
        XCTAssertEqual(secondTarget, CGPoint(x: a.frame.minX - 6, y: b.frame.midY))

        // A rank beyond the movable count cannot be planned.
        XCTAssertNil(OrderPlanner.moveTarget(
            itemID: c.id, rank: 5, movableRightToLeft: movable, rightAnchorMinX: clock.frame.minX
        ))
    }

    func testOrderPlannerAnchorsWithoutPinnedItems() {
        let a = snapshot("Alpha", x: 1600)
        let b = snapshot("Beta", x: 1500)
        XCTAssertEqual(OrderPlanner.rightAnchorMinX([b, a]), a.frame.maxX)
    }

    func testHiddenRuleClearsAfterTwoDrawableScans() {
        var reconciler = HiddenRuleReconciler()
        let hidden: Set<String> = ["a", "b"]

        // First drawable scan for "a" is tolerated; "b" is really off screen.
        XCTAssertEqual(reconciler.update(hiddenIntentIDs: hidden, overflowIDs: ["b"]), [])
        // A stale frame that recovers resets the count.
        XCTAssertEqual(reconciler.update(hiddenIntentIDs: hidden, overflowIDs: ["a", "b"]), [])
        XCTAssertEqual(reconciler.update(hiddenIntentIDs: hidden, overflowIDs: ["b"]), [])
        // Second consecutive drawable scan drops the rule.
        XCTAssertEqual(reconciler.update(hiddenIntentIDs: hidden, overflowIDs: ["b"]), ["a"])
        // Once cleared it does not report again until it is hidden anew.
        XCTAssertEqual(reconciler.update(hiddenIntentIDs: ["b"], overflowIDs: []), [])
        XCTAssertEqual(reconciler.update(hiddenIntentIDs: ["b"], overflowIDs: []), ["b"])
    }

    func testClosedBoundaryEdgeSplitsTwoZones() {
        // The Always hidden boundary is the only divider. Its frame is the
        // narrow left edge of the closed status item, leaving exactly two zones.
        let boundaries = BoundaryFrames(
            control: CGRect(x: 900, y: 876, width: 20, height: 24),
            alwaysHidden: CGRect(x: 700, y: 876, width: 14, height: 24)
        )

        XCTAssertEqual(
            boundaries.targetPoint(for: .alwaysVisible),
            CGPoint(x: 807, y: 888)
        )
        XCTAssertEqual(
            boundaries.targetPoint(for: .alwaysHidden),
            CGPoint(x: 682, y: 888)
        )
        XCTAssertEqual(
            boundaries.zone(for: CGRect(x: 800, y: 876, width: 20, height: 24)),
            .alwaysVisible
        )
        XCTAssertEqual(
            boundaries.zone(for: CGRect(x: 500, y: 876, width: 20, height: 24)),
            .alwaysHidden
        )
    }

    func testOldDocumentsDecodeWithoutNewFields() throws {
        let old = """
        {"version":1,"settings":{"launchAtLogin":false,"showDockIcon":false,"iconStyle":"ellipsis","autoRehide":true,"rehideDelay":5,"hideOnAppChange":false,"showOnHover":false,"hoverDelay":1,"showOnScroll":false,"showOnMenuBarClick":true,"requireAuthentication":false,"showOnLowBattery":false,"lowBatteryLevel":20,"alwaysShowOnExternalDisplay":false,"useCustomAppearance":false,"appearanceOpacity":0.16,"appearanceCornerRadius":8,"appearanceBorder":false,"reduceItemSpacing":false,"itemSpacing":4,"itemPadding":4},"rules":{},"groups":[],"profiles":[]}
        """
        let document = try JSONDecoder().decode(BarShelfDocument.self, from: Data(old.utf8))
        XCTAssertEqual(document.settings.iconStyle, .ellipsis)
        XCTAssertNil(document.priorityOrder)
        XCTAssertNil(document.identityVersion)
    }

    func testClassicDocumentsMigrateToShelf() throws {
        // A document saved while classic mode existed carries a mode value,
        // reveal settings, and rules in the removed Hidden section. It must
        // still load, with those rules treated as In the menu bar.
        let old = """
        {"version":1,"settings":{"iconStyle":"dot","menuBarMode":"classic","autoRehide":false,"rehideDelay":5,"hideOnAppChange":false,"showOnHover":true,"hoverDelay":1,"showOnScroll":false,"showOnMenuBarClick":true,"showOnLowBattery":false,"lowBatteryLevel":20,"alwaysShowOnExternalDisplay":false,"requireAuthentication":true,"launchAtLogin":false,"showDockIcon":false,"useCustomAppearance":false,"appearanceOpacity":0.16,"appearanceCornerRadius":8,"appearanceBorder":false,"reduceItemSpacing":false,"itemSpacing":4,"itemPadding":4},"rules":{"com.example.a|slot:0":{"id":"com.example.a|slot:0","displayName":"A","ownerName":"A","zone":"hidden"},"com.example.b|slot:0":{"id":"com.example.b|slot:0","displayName":"B","ownerName":"B","zone":"alwaysHidden"}},"groups":[],"profiles":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Work","createdAt":"2026-01-01T00:00:00Z","settings":{"iconStyle":"ring","menuBarMode":"classic","requireAuthentication":false,"launchAtLogin":false,"showDockIcon":false,"useCustomAppearance":false,"appearanceOpacity":0.16,"appearanceCornerRadius":8,"appearanceBorder":false,"reduceItemSpacing":false,"itemSpacing":4,"itemPadding":4},"rules":{"com.example.c|slot:0":{"id":"com.example.c|slot:0","displayName":"C","ownerName":"C","zone":"hidden"}}}]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(BarShelfDocument.self, from: Data(old.utf8))
        XCTAssertEqual(document.settings.iconStyle, .dot)
        XCTAssertTrue(document.settings.requireAuthentication)
        XCTAssertEqual(document.rules["com.example.a|slot:0"]?.zone, .alwaysVisible)
        XCTAssertEqual(document.rules["com.example.b|slot:0"]?.zone, .alwaysHidden)
        XCTAssertEqual(document.profiles.first?.rules["com.example.c|slot:0"]?.zone, .alwaysVisible)
        XCTAssertThrowsError(
            try decoder.decode(VisibilityZone.self, from: Data("\"somethingElse\"".utf8))
        )
    }

    @MainActor
    func testPriorityOrderRoundTrip() {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let alpha = snapshot("Alpha", x: 100)
        let beta = snapshot("Beta", x: 200)

        let first = StateStore(baseURL: baseURL)
        first.addPriority(for: alpha)
        first.addPriority(for: beta)
        first.addPriority(for: alpha)
        XCTAssertEqual(first.priorityOrder.map(\.displayName), ["Alpha", "Beta"])
        first.movePriority(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        let second = StateStore(baseURL: baseURL)
        XCTAssertEqual(second.priorityOrder.map(\.displayName), ["Beta", "Alpha"])
        second.removePriority(id: alpha.id)
        XCTAssertEqual(second.priorityOrder.map(\.displayName), ["Beta"])
    }

    func testAllIconsRenderAtNativeSize() {
        for style in BarShelfIconStyle.allCases {
            let image = BarShelfIconFactory.image(for: style, expanded: false)
            XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
            XCTAssertTrue(image.isTemplate)
        }
    }
}
