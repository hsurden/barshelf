import Foundation
import CoreGraphics

enum VisibilityZone: String, Codable, CaseIterable, Identifiable, Sendable {
    case alwaysVisible
    case hidden
    case alwaysHidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alwaysVisible: "Always visible"
        case .hidden: "Hidden"
        case .alwaysHidden: "Always hidden"
        }
    }

    var help: String {
        switch self {
        case .alwaysVisible: "Barkeep never hides these items."
        case .hidden: "Available in the picker and with the show/hide shortcut."
        case .alwaysHidden: "Available in the picker without taking menu bar space."
        }
    }
}

enum MenuBarMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case overflowShelf
    case classic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overflowShelf: "Overflow shelf"
        case .classic: "Classic hide and reveal"
        }
    }

    var help: String {
        switch self {
        case .overflowShelf:
            "Every icon stays in the menu bar until it overflows. The shelf lists overflowed and Always hidden items."
        case .classic:
            "Barkeep hides the items you put in the Hidden and Always hidden sections, with the reveal shortcut and boundaries."
        }
    }
}

enum BarkeepIconStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case dot
    case ring
    case ellipsis
    case diamond
    case chevrons
    case line
    case sparkle
    case grid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dot: "Dot"
        case .ring: "Ring"
        case .ellipsis: "Ellipsis"
        case .diamond: "Diamond"
        case .chevrons: "Chevrons"
        case .line: "Line"
        case .sparkle: "Sparkle"
        case .grid: "Grid"
        }
    }
}

struct BarkeepSettings: Codable, Equatable, Sendable {
    var launchAtLogin = false
    var showDockIcon = false
    var iconStyle: BarkeepIconStyle = .ellipsis
    var autoRehide = true
    var rehideDelay: TimeInterval = 5
    var hideOnAppChange = false
    var showOnHover = false
    var hoverDelay: TimeInterval = 1
    var showOnScroll = false
    var showOnMenuBarClick = true

    var requireAuthentication = false
    var showOnLowBattery = false
    var lowBatteryLevel = 20
    var alwaysShowOnExternalDisplay = false

    var useCustomAppearance = false
    var appearanceOpacity = 0.16
    var appearanceCornerRadius = 8.0
    var appearanceBorder = false
    var reduceItemSpacing = false
    var itemSpacing = 4
    var itemPadding = 4

    // Optional so documents saved before this field existed keep decoding.
    var menuBarMode: MenuBarMode?

    var mode: MenuBarMode { menuBarMode ?? .overflowShelf }
}

struct ItemRule: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var displayName: String
    var ownerName: String
    var bundleIdentifier: String?
    var zone: VisibilityZone
    var group: String?
}

struct BarkeepProfile: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var rules: [String: ItemRule]
    var settings: BarkeepSettings
    let createdAt: Date

    init(name: String, rules: [String: ItemRule], settings: BarkeepSettings) {
        id = UUID()
        self.name = name
        self.rules = rules
        self.settings = settings
        createdAt = Date()
    }
}

/// One ranked entry in the overflow-shelf priority order. Rank 1 is the
/// rightmost menu bar position, which macOS occludes last on a notched display.
struct PriorityEntry: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var displayName: String
    var ownerName: String
    var bundleIdentifier: String?
}

struct BarkeepDocument: Codable, Sendable {
    var version = 1
    var settings = BarkeepSettings()
    var rules: [String: ItemRule] = [:]
    var groups: [String] = []
    var profiles: [BarkeepProfile] = []
    // Optional so documents saved before this field existed keep decoding.
    var priorityOrder: [PriorityEntry]?
    // The current identity scheme uses machine-shaped Accessibility identifiers
    // or per-owner slots instead of
    // mutable status text as an item's persistent identity. Migration needs a
    // live scan, so this is separate from the document format version.
    var identityVersion: Int?
}

struct MenuBarItemSnapshot: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let ownerName: String
    let bundleIdentifier: String?
    let frame: CGRect
    let isEnabled: Bool
    let ownerPID: pid_t
    let sourceIdentifier: String?
    let ownerSlot: Int

    init(
        id: String,
        displayName: String,
        ownerName: String,
        bundleIdentifier: String?,
        frame: CGRect,
        isEnabled: Bool,
        ownerPID: pid_t = 0,
        sourceIdentifier: String? = nil,
        ownerSlot: Int = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.ownerName = ownerName
        self.bundleIdentifier = bundleIdentifier
        self.frame = frame
        self.isEnabled = isEnabled
        self.ownerPID = ownerPID
        self.sourceIdentifier = sourceIdentifier
        self.ownerSlot = ownerSlot
    }
}

enum MenuBarItemIdentity {
    static let currentVersion = 3

    static func stableAccessibilityIdentifier(
        bundleIdentifier: String?,
        identifier: String?
    ) -> String? {
        guard let value = identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        if bundleIdentifier == "com.apple.controlcenter", value.hasPrefix("com.apple.") {
            return value
        }
        let machineCharacters = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "._:-")
        )
        guard value.rangeOfCharacter(from: machineCharacters.inverted) == nil,
              value.contains(where: { "._-:".contains($0) }) else {
            return nil
        }
        return value
    }

    /// Accessibility identifiers are stable across launches. Apps that do not
    /// expose one are usually single-item owners; for them, persist the item's
    /// slot within that owner's extras menu bar. Mutable titles are display
    /// state and must never be part of the identifier.
    static func id(bundleIdentifier: String?, pid: pid_t, identifier: String?, slot: Int) -> String {
        let owner = bundleIdentifier ?? "pid:\(pid)"
        if let identifier = stableAccessibilityIdentifier(
            bundleIdentifier: bundleIdentifier,
            identifier: identifier
        ) {
            return "\(owner)|ax:\(identifier)"
        }
        return "\(owner)|slot:\(slot)"
    }
}

struct MenuBarPickerContents {
    let overflow: [MenuBarItemSnapshot]
    let visible: [MenuBarItemSnapshot]

    init(
        items: [MenuBarItemSnapshot],
        query: String,
        zoneFor: (MenuBarItemSnapshot) -> VisibilityZone
    ) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = items.filter { item in
            guard !item.isPinnedByMacOS else { return false }
            guard !trimmed.isEmpty else { return true }
            return item.displayName.localizedCaseInsensitiveContains(trimmed) ||
                item.ownerName.localizedCaseInsensitiveContains(trimmed)
        }
        let sorted = candidates.sorted { lhs, rhs in
            let nameOrder = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return lhs.ownerName.localizedCaseInsensitiveCompare(rhs.ownerName) == .orderedAscending
        }
        overflow = sorted.filter { zoneFor($0) != .alwaysVisible }
        visible = sorted.filter { zoneFor($0) == .alwaysVisible }
    }

    var isEmpty: Bool { overflow.isEmpty && visible.isEmpty }
}

extension MenuBarItemSnapshot {
    /// macOS pins the Clock and Control Center on the far right of the menu bar
    /// and rejects every Command-drag on them, so Barkeep never offers to move them.
    var isPinnedByMacOS: Bool {
        guard bundleIdentifier == "com.apple.controlcenter" else { return false }
        let identifier = sourceIdentifier ?? id.split(separator: "|", maxSplits: 1)
            .dropFirst().first.map(String.init)?.replacingOccurrences(of: "ax:", with: "")
        return identifier == "com.apple.menuextra.clock" ||
            identifier == "com.apple.menuextra.controlcenter"
    }
}

struct BoundaryFrames: Sendable {
    let control: CGRect
    let hidden: CGRect
    let alwaysHidden: CGRect

    func zone(for itemFrame: CGRect) -> VisibilityZone {
        if itemFrame.midX > control.midX || itemFrame.midX > hidden.midX {
            return .alwaysVisible
        }
        if itemFrame.midX > alwaysHidden.midX {
            return .hidden
        }
        return .alwaysHidden
    }

    func targetPoint(for zone: VisibilityZone) -> CGPoint? {
        // The two boundary frames coincide in overflow-shelf mode, where the
        // Always hidden boundary doubles as the hidden boundary.
        guard alwaysHidden.midX <= hidden.midX,
              hidden.midX < control.midX else {
            return nil
        }

        let y = control.midY
        switch zone {
        case .alwaysVisible:
            guard hidden.maxX <= control.minX else { return nil }
            let x = hidden.maxX == control.minX
                ? hidden.maxX + 1
                : (hidden.maxX + control.minX) / 2
            return CGPoint(x: x, y: y)
        case .hidden:
            guard alwaysHidden.maxX <= hidden.minX else { return nil }
            let x = alwaysHidden.maxX == hidden.minX
                ? alwaysHidden.maxX + 1
                : (alwaysHidden.maxX + hidden.minX) / 2
            return CGPoint(x: x, y: y)
        case .alwaysHidden:
            return CGPoint(x: alwaysHidden.minX - 18, y: y)
        }
    }
}

struct ScreenCoordinateSpace: Sendable {
    let appKitFrame: CGRect
    let quartzFrame: CGRect

    func quartzPoint(fromAppKit point: CGPoint) -> CGPoint? {
        guard appKitFrame.insetBy(dx: -2, dy: -2).contains(point) else {
            return nil
        }
        return CGPoint(
            x: quartzFrame.minX + point.x - appKitFrame.minX,
            y: quartzFrame.minY + appKitFrame.maxY - point.y
        )
    }

    func quartzPoint(fromAccessibility point: CGPoint, menuBarAnchorY: CGFloat) -> CGPoint? {
        var candidates: [CGPoint] = []
        if quartzFrame.insetBy(dx: -2, dy: -2).contains(point) {
            candidates.append(point)
        }
        if let converted = quartzPoint(fromAppKit: point),
           quartzFrame.insetBy(dx: -2, dy: -2).contains(converted),
           !candidates.contains(converted) {
            candidates.append(converted)
        }
        return candidates.min {
            abs($0.y - menuBarAnchorY) < abs($1.y - menuBarAnchorY)
        }
    }
}

enum BarkeepError: LocalizedError {
    case accessibilityRequired
    case itemNotFound
    case itemNotRevealed
    case itemPinnedByMacOS
    case itemOccluded
    case menuBarFull
    case boundariesUnavailable
    case invalidGeometry
    case moveNotConfirmed
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityRequired: "Give Barkeep Accessibility access to list and move menu bar items."
        case .itemNotFound: "Barkeep could not find this item in the current menu bar."
        case .itemNotRevealed: "This item did not appear on the screen. Barkeep kept the old section."
        case .itemPinnedByMacOS: "macOS keeps this item on the right side. Barkeep cannot move it."
        case .itemOccluded: "macOS hides this item behind the notch, so Barkeep cannot grab it to move it. Quit or rearrange other menu bar apps to free space, then apply the order again."
        case .menuBarFull: "The menu bar is full, and macOS hides this spot behind the notch. Close some menu bar apps or turn on tighter spacing, then try again."
        case .boundariesUnavailable: "Barkeep could not find its section boundaries."
        case .invalidGeometry: "The current menu bar layout is not safe for this move."
        case .moveNotConfirmed: "macOS did not complete the move. Barkeep kept the old section."
        case .authenticationFailed: "Barkeep did not reveal the hidden items."
        }
    }
}
