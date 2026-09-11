import Foundation

/// A return address made from live item identities, never saved coordinates.
/// BarShelf's own control and divider participate so empty sections work too.
struct TemporaryItemPlacement {
    struct Anchor: Equatable {
        let id: String
        let frame: CGRect
    }

    static let controlID = "barshelf.temporary.control"
    static let boundaryID = "barshelf.temporary.boundary"

    let itemID: String
    let leftID: String?
    let rightID: String?
    let wasLeftOfBoundary: Bool?

    init?(itemID: String, anchors: [Anchor]) {
        let ordered = anchors.sorted { $0.frame.midX < $1.frame.midX }
        guard let index = ordered.firstIndex(where: { $0.id == itemID }) else { return nil }
        self.itemID = itemID
        leftID = index > 0 ? ordered[index - 1].id : nil
        rightID = index + 1 < ordered.count ? ordered[index + 1].id : nil
        wasLeftOfBoundary = ordered.firstIndex(where: { $0.id == Self.boundaryID }).map { index < $0 }
    }

    /// Prefer the original right neighbor, then the left if that app exited.
    /// If both exited, use the original side of the section divider. Never
    /// guess an old pixel position.
    func returnAnchor(in anchors: [Anchor]) -> (anchor: Anchor, edge: WindowMoveEdge)? {
        if let right = anchors.first(where: { $0.id == rightID }) { return (right, .left) }
        if let left = anchors.first(where: { $0.id == leftID }) { return (left, .right) }
        if let wasLeftOfBoundary,
           let boundary = anchors.first(where: { $0.id == Self.boundaryID }) {
            return (boundary, wasLeftOfBoundary ? .left : .right)
        }
        return nil
    }

    func returnTarget(in anchors: [Anchor]) -> CGPoint? {
        guard let destination = returnAnchor(in: anchors) else { return nil }
        let point = destination.edge.point(on: destination.anchor.frame)
        return CGPoint(x: point.x + (destination.edge == .left ? -2 : 2), y: point.y)
    }

    func isRestored(in anchors: [Anchor]) -> Bool {
        let ordered = anchors.sorted { $0.frame.midX < $1.frame.midX }
        guard let index = ordered.firstIndex(where: { $0.id == itemID }) else { return false }
        let hasLeft = ordered.contains { $0.id == leftID }
        let hasRight = ordered.contains { $0.id == rightID }
        guard hasLeft || hasRight else {
            guard let wasLeftOfBoundary,
                  let boundaryIndex = ordered.firstIndex(where: { $0.id == Self.boundaryID }) else { return false }
            return wasLeftOfBoundary ? index + 1 == boundaryIndex : index == boundaryIndex + 1
        }
        return (!hasLeft || (index > 0 && ordered[index - 1].id == leftID)) &&
            (!hasRight || (index + 1 < ordered.count && ordered[index + 1].id == rightID))
    }

    static func leadingVisibleAnchor(in anchors: [Anchor], excluding itemID: String,
                                     screens: [ScreenGeometry]) -> Anchor? {
        anchors.filter {
            $0.id != itemID && $0.id != boundaryID && isDrawable($0.frame, screens: screens)
        }.min { $0.frame.minX < $1.frame.minX }
    }

    static func accessAnchor(for item: Anchor, in anchors: [Anchor],
                             screens: [ScreenGeometry]) -> Anchor? {
        let leading = leadingVisibleAnchor(in: anchors, excluding: item.id, screens: screens)
        let control = anchors.first { $0.id == controlID }
        return [leading, control].compactMap { $0 }.first { anchor in
            let points = WindowMoveEdge.left.movePoints(source: item.frame, destination: anchor.frame)
            return isDrawable(CGRect(origin: points.end, size: item.frame.size), screens: screens)
        }
    }

    static func isImmediatelyBefore(item: CGRect, neighbor: CGRect, otherItems: [CGRect]) -> Bool {
        item.width > 0 && item.maxX <= neighbor.minX + 2 &&
        neighbor.minX - item.maxX <= 12 &&
        !otherItems.contains { $0.midX > item.midX && $0.midX < neighbor.midX }
    }

    static func isInOverflow(_ frame: CGRect, reference: CGRect, screens: [ScreenGeometry]) -> Bool {
        frame.width > 0 && frame.height > 0 &&
        isOnMenuBarRow(frame, reference: reference) && !isDrawable(frame, screens: screens)
    }

    static func isAvailableForAccess(_ frame: CGRect, reference: CGRect) -> Bool {
        frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite && frame.height.isFinite &&
        frame.width > 0 && frame.height > 0 && isOnMenuBarRow(frame, reference: reference)
    }

    static func isOnMenuBarRow(_ frame: CGRect, reference: CGRect) -> Bool {
        abs(frame.midY - reference.midY) < 3
    }

    /// Require the whole icon to clear the notch, not just its center.
    static func isDrawable(_ frame: CGRect, screens: [ScreenGeometry]) -> Bool {
        screens.contains {
            frame.width > 0 && frame.height > 0 &&
            frame.minX >= ($0.statusAreaMinX ?? $0.frame.minX) &&
            frame.maxX <= $0.frame.maxX &&
            frame.midY >= $0.frame.minY && frame.midY <= $0.frame.minY + 40
        }
    }
}
