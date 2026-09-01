import CoreGraphics
import Foundation

/// Pure geometry for the overflow-shelf mode. An item is "overflowed" when its
/// scanned frame is not on any screen's drawable menu bar strip: macOS laid it
/// out behind the camera notch or pushed it past the edge of the display.
enum OverflowClassifier {
    /// Item frames come from the Accessibility scan and are temporary evidence,
    /// valid only for the scan they came from.
    static func isOverflowed(frame: CGRect, screens: [ScreenGeometry]) -> Bool {
        let mid = CGPoint(x: frame.midX, y: frame.midY)
        let onDrawableStrip = screens.contains { screen in
            screen.frame.insetBy(dx: -2, dy: -2).contains(mid) &&
            mid.y <= screen.frame.minY + 40 &&
            !screen.hidesMenuBarPoint(mid)
        }
        return !onDrawableStrip
    }

    static func overflowedIDs(
        items: [MenuBarItemSnapshot],
        screens: [ScreenGeometry]
    ) -> Set<String> {
        Set(items.filter { isOverflowed(frame: $0.frame, screens: screens) }.map(\.id))
    }
}

enum ShelfSessionModel {
    /// A shelf session is a snapshot, not a live projection of moving menu-bar
    /// geometry. Deliberately hidden items remain present even when macOS
    /// reports a stale drawable frame, and physically overflowed items remain
    /// present until the user closes and reopens the shelf.
    static func items(
        from items: [MenuBarItemSnapshot],
        overflowIDs: Set<String>,
        intentionallyHiddenIDs: Set<String>
    ) -> [MenuBarItemSnapshot] {
        items.filter {
            !$0.isPinnedByMacOS &&
            (overflowIDs.contains($0.id) || intentionallyHiddenIDs.contains($0.id))
        }
        .sorted { lhs, rhs in
            let lhsHidden = intentionallyHiddenIDs.contains(lhs.id)
            let rhsHidden = intentionallyHiddenIDs.contains(rhs.id)
            if lhsHidden != rhsHidden { return lhsHidden }
            return lhs.frame.midX < rhs.frame.midX
        }
    }
}

struct ShelfInventory {
    private(set) var itemsByID: [String: MenuBarItemSnapshot] = [:]
    private(set) var overflowIDs: Set<String> = []
    private var missedScans: [String: Int] = [:]

    var items: [MenuBarItemSnapshot] { Array(itemsByID.values) }

    /// Accessibility occasionally omits a status item for one scan while its
    /// owner is busy. Keep the last reliable evidence through two misses, but
    /// remove it immediately when the owning application exits.
    mutating func update(
        scannedItems: [MenuBarItemSnapshot],
        scannedOverflowIDs: Set<String>,
        runningPIDs: Set<pid_t>
    ) {
        let scannedIDs = Set(scannedItems.map(\.id))
        let earlierOverflow = overflowIDs

        for item in scannedItems {
            itemsByID[item.id] = item
            missedScans[item.id] = 0
        }

        for (id, item) in itemsByID where !scannedIDs.contains(id) {
            if item.ownerPID != 0 && !runningPIDs.contains(item.ownerPID) {
                itemsByID[id] = nil
                missedScans[id] = nil
                continue
            }
            let misses = (missedScans[id] ?? 0) + 1
            if misses >= 3 {
                itemsByID[id] = nil
                missedScans[id] = nil
            } else {
                missedScans[id] = misses
            }
        }

        let retainedMissingIDs = Set(itemsByID.keys).subtracting(scannedIDs)
        overflowIDs = scannedOverflowIDs.union(
            earlierOverflow.intersection(retainedMissingIDs)
        )
    }
}

extension ScreenGeometry {
    /// Every display's menu bar mirrors the same items packed from its right
    /// edge with identical widths, so a bar point maps between displays by
    /// its distance from the right edge.
    func remapMenuBarPoint(_ point: CGPoint, to other: ScreenGeometry) -> CGPoint {
        CGPoint(
            x: other.frame.maxX - (frame.maxX - point.x),
            y: other.frame.minY + (point.y - frame.minY)
        )
    }
}

/// Plans the explicit "Apply Order Now" moves. Ranks are rightmost-first:
/// rank 0 sits immediately left of the immovable macOS cluster (Clock and
/// Control Center), rank 1 immediately left of rank 0, and so on. The planner
/// works on one fresh scan at a time; the coordinator rescans after every move.
enum OrderPlanner {
    /// Movable items sorted right-to-left by midX, pinned macOS items excluded.
    static func movableRightToLeft(_ items: [MenuBarItemSnapshot]) -> [MenuBarItemSnapshot] {
        items.filter { !$0.isPinnedByMacOS }.sorted { $0.frame.midX > $1.frame.midX }
    }

    /// The left edge of the immovable right-side cluster. Falls back to the
    /// right of the rightmost movable item when no pinned item was scanned.
    static func rightAnchorMinX(_ items: [MenuBarItemSnapshot]) -> CGFloat? {
        let pinned = items.filter(\.isPinnedByMacOS)
        if let edge = pinned.map(\.frame.minX).min() {
            return edge
        }
        return items.filter { !$0.isPinnedByMacOS }.map(\.frame.maxX).max()
    }

    /// Returns where the item must be dropped for the given rank, or nil when
    /// it already occupies that rank counting from the right.
    static func moveTarget(
        itemID: String,
        rank: Int,
        movableRightToLeft movable: [MenuBarItemSnapshot],
        rightAnchorMinX: CGFloat
    ) -> CGPoint? {
        guard rank < movable.count else { return nil }
        if movable[rank].id == itemID { return nil }
        let anchorX = rank == 0 ? rightAnchorMinX : movable[rank - 1].frame.minX
        let y = movable[rank].frame.midY
        return CGPoint(x: anchorX - 6, y: y)
    }

    /// True when the item sits at its rank position in this scan.
    static func isInPlace(
        itemID: String,
        rank: Int,
        movableRightToLeft movable: [MenuBarItemSnapshot]
    ) -> Bool {
        rank < movable.count && movable[rank].id == itemID
    }
}
