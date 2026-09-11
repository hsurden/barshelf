import CoreGraphics
import Foundation

/// Ephemeral WindowServer evidence. Never stored in settings or item identity.
struct MenuBarWindow: Equatable, Sendable {
    let id: CGWindowID
    let ownerPID: pid_t
    let frame: CGRect

    static func readAll() -> [MenuBarWindow] {
        let rows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let layer = row[kCGWindowLayer as String] as? Int,
                  layer == Int(CGWindowLevelForKey(.statusWindow)),
                  let id = row[kCGWindowNumber as String] as? CGWindowID,
                  let pid = row[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = row[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.width > 0, frame.height > 0 else { return nil }
            return MenuBarWindow(id: id, ownerPID: pid, frame: frame)
        }
    }

    /// AX describes the button, whereas WindowServer describes its surrounding
    /// status window. Tahoe hosts third-party buttons in Control Center; accept
    /// that specific host only, and reject every ambiguous geometric match.
    static func match(frame: CGRect, ownerPID: pid_t, hostPID: pid_t?,
                      windows: [MenuBarWindow]) -> MenuBarWindow? {
        guard frame.width > 0, frame.height > 0,
              frame.minX.isFinite, frame.minY.isFinite,
              frame.width.isFinite, frame.height.isFinite else { return nil }
        let matches = windows.filter {
            ($0.ownerPID == ownerPID || $0.ownerPID == hostPID) &&
            abs($0.frame.midX - frame.midX) <= 2 &&
            abs($0.frame.midY - frame.midY) <= 2 &&
            abs($0.frame.width - frame.width) <= 20 &&
            abs($0.frame.height - frame.height) <= 20
        }
        return matches.count == 1 ? matches[0] : nil
    }
}

enum WindowMoveEdge: Sendable {
    case left, right

    /// The down is window-addressed at the destination edge, so no cursor drag
    /// path is needed. A rightward move releases one source width before the edge.
    ///
    /// A leftward move releases a quarter of the way into the destination, on
    /// the requested side. Live calibration on a tightly spaced Tahoe bar
    /// (19-point neighbor windows) showed macOS lifts the source with its left
    /// edge at the cursor, then inserts by comparing the release point with the
    /// neighbors' midpoints: releases up to half the neighbor width landed
    /// correctly; three-quarters and the full width landed one slot too far.
    /// The cap at the source width keeps the wide closed divider's release point
    /// where it was verified.
    func movePoints(source: CGRect, destination: CGRect) -> (start: CGPoint, end: CGPoint) {
        let boundary = self == .left ? destination.minX : destination.maxX
        let movingRight = self == .left ? source.maxX <= boundary : source.minX <= boundary
        let startX = movingRight ? boundary : boundary + (self == .left ? -1 : 1)
        let inset = min(source.width, destination.width / 4)
        let leftwardEnd = self == .left ? boundary + inset : boundary - inset
        return (CGPoint(x: startX, y: destination.minY),
                CGPoint(x: movingRight ? boundary - source.width : leftwardEnd, y: destination.minY))
    }

    func point(on frame: CGRect) -> CGPoint {
        CGPoint(x: self == .left ? frame.minX : frame.maxX, y: frame.midY)
    }
}

enum WindowMoveError: LocalizedError {
    case windowNotMatched
    case windowChanged
    case deliveryUnavailable
    case deliveryTimedOut
    case userIsInteracting

    var errorDescription: String? {
        switch self {
        case .windowNotMatched: "BarShelf could not uniquely match this icon to its live menu-bar window."
        case .windowChanged: "The menu-bar window changed before the move could start. Try again."
        case .deliveryUnavailable: "macOS did not allow BarShelf to deliver the targeted move."
        case .deliveryTimedOut: "The menu-bar host did not acknowledge the targeted move."
        case .userIsInteracting: "Release the mouse button and modifier keys, then try again."
        }
    }
}
