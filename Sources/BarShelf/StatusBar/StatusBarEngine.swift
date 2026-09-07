import AppKit

@MainActor
final class StatusBarEngine: NSObject {
    /// The Always hidden section is closed at rest, which keeps every other
    /// item inline until macOS overflows it. It opens only for a confirmed
    /// move sequence or a debug launch flag; nothing else changes it.
    enum State: String, Sendable {
        case resting
        case open
    }

    var onPrimaryAction: ((NSEvent) -> Void)?
    var menuProvider: (() -> NSMenu)?
    private(set) var state: State = .resting

    private let statusBar = NSStatusBar.system
    private let controlItem: NSStatusItem
    private var alwaysHiddenBoundary: NSStatusItem
    private var iconStyle: BarShelfIconStyle = .dot

    private static let openBoundaryLength: CGFloat = 14
    private static let closedBoundaryLength: CGFloat = 10_000
    private static let controlAutosaveName = "BarShelf.Control.v3"
    private static let alwaysHiddenBoundaryAutosaveName = "BarShelf.AlwaysHiddenBoundary.v3"

    override init() {
        Self.seedInitialPositions()

        controlItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        alwaysHiddenBoundary = statusBar.statusItem(withLength: Self.openBoundaryLength)
        super.init()

        configure(controlItem, name: Self.controlAutosaveName, label: "Open overflow shelf")
        configure(
            alwaysHiddenBoundary,
            name: Self.alwaysHiddenBoundaryAutosaveName,
            label: "Always hidden items boundary"
        )

        controlItem.button?.target = self
        controlItem.button?.action = #selector(handleControlClick(_:))
        controlItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        controlItem.button?.toolTip = "Open overflow shelf"

        alwaysHiddenBoundary.button?.alphaValue = 0.5
        setState(.resting)
    }

    private static func seedInitialPositions() {
        let defaults = UserDefaults.standard
        // The autosave names changed with the rename from Barkeep. macOS keys
        // each item's menu bar position on that name, so copy the old values
        // once rather than making the user drag both items into place again.
        let renamed = [
            (controlAutosaveName, "Barkeep.Control.v3"),
            (alwaysHiddenBoundaryAutosaveName, "Barkeep.AlwaysHiddenBoundary.v3"),
        ]
        for (name, legacy) in renamed {
            let key = "NSStatusItem Preferred Position \(name)"
            let legacyKey = "NSStatusItem Preferred Position \(legacy)"
            if defaults.object(forKey: key) == nil, let old = defaults.object(forKey: legacyKey) {
                defaults.set(old, forKey: key)
            }
        }
        let key = "NSStatusItem Preferred Position \(controlAutosaveName)"
        if defaults.object(forKey: key) == nil {
            defaults.set(0, forKey: key)
        }
    }

    func setIconStyle(_ style: BarShelfIconStyle) {
        iconStyle = style
        updateControlImage()
    }

    /// The control item's window frame in AppKit screen coordinates, used to
    /// anchor the overflow shelf under the menu bar.
    func controlScreenFrame() -> CGRect? {
        controlItem.button?.window?.frame
    }

    /// The Always hidden boundary's window frame in AppKit screen
    /// coordinates. Hidden items reveal immediately left of this spot, and
    /// their real menus drop from there, so the shelf anchors below it.
    func alwaysHiddenBoundaryScreenFrame() -> CGRect? {
        alwaysHiddenBoundary.button?.window?.frame
    }

    /// Temporarily shrinks the control to free drawable menu bar space during
    /// a full-bar hide. Pass nil to restore the normal width.
    func setControlLength(_ length: CGFloat?) {
        controlItem.length = length ?? NSStatusItem.squareLength
    }

    /// Moves the Always hidden boundary by recreating it at a saved preferred
    /// position. The boundary is BarShelf's own item, so this needs no drag and
    /// works even while the boundary sits behind the notch. The offset is
    /// measured in points from the right edge of the screen.
    func repositionAlwaysHiddenBoundary(preferredRightOffset: CGFloat) {
        UserDefaults.standard.set(
            Double(preferredRightOffset),
            forKey: "NSStatusItem Preferred Position \(Self.alwaysHiddenBoundaryAutosaveName)"
        )
        statusBar.removeStatusItem(alwaysHiddenBoundary)
        alwaysHiddenBoundary = statusBar.statusItem(withLength: Self.openBoundaryLength)
        configure(
            alwaysHiddenBoundary,
            name: Self.alwaysHiddenBoundaryAutosaveName,
            label: "Always hidden items boundary"
        )
        alwaysHiddenBoundary.button?.alphaValue = 0.5
        setState(state)
    }

    func setState(_ newState: State) {
        state = newState
        switch newState {
        case .resting:
            alwaysHiddenBoundary.length = Self.closedBoundaryLength
        case .open:
            alwaysHiddenBoundary.length = Self.openBoundaryLength
        }
        // The boundary never draws a divider glyph, even while open.
        alwaysHiddenBoundary.button?.image = nil
        updateControlImage()
    }

    func boundaryFrames() -> BoundaryFrames? {
        guard let control = controlItem.button?.window?.frame,
              let alwaysHidden = alwaysHiddenBoundary.button?.window?.frame,
              control.width > 0,
              alwaysHidden.width > 0 else {
            return nil
        }
        // The closed boundary is thousands of points wide, so its LEFT edge
        // is the meaningful divider; a midpoint would misclassify items.
        let edge = CGRect(
            x: alwaysHidden.minX,
            y: alwaysHidden.minY,
            width: min(alwaysHidden.width, 30),
            height: alwaysHidden.height
        )
        return BoundaryFrames(control: control, alwaysHidden: edge)
    }

    func targetPoint(for zone: VisibilityZone) -> CGPoint? {
        boundaryFrames()?.targetPoint(for: zone)
    }

    private func configure(_ item: NSStatusItem, name: String, label: String) {
        item.autosaveName = name
        item.isVisible = true
        item.button?.setAccessibilityLabel(label)
    }

    private func updateControlImage() {
        controlItem.button?.image = BarShelfIconFactory.image(for: iconStyle, expanded: state == .open)
        controlItem.button?.setAccessibilityValue(state == .open ? "Open" : "Closed")
    }

    @objc private func handleControlClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            defer {
                sender.highlight(false)
                sender.state = .off
            }
            if let menu = menuProvider?() {
                NSMenu.popUpContextMenu(menu, with: event, for: sender)
            }
        } else {
            onPrimaryAction?(event)
        }
    }
}
