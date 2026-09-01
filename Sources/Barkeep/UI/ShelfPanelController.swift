import AppKit
import Combine
import SwiftUI

/// Borderless non-activating panel that hugs the underside of the menu bar and
/// shows the overflowed items as a second row of icons. Clicking an icon
/// presses the real menu bar item; typing or the chevron expands into the
/// searchable list.
final class ShelfPanel: NSPanel {
    var onTypeToSearch: ((String) -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func keyDown(with event: NSEvent) {
        if let characters = event.characters,
           !characters.isEmpty,
           !event.modifierFlags.contains(.command),
           characters.rangeOfCharacter(from: .alphanumerics) != nil {
            onTypeToSearch?(characters)
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor
final class ShelfPanelController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    private weak var coordinator: AppCoordinator?
    private var hostingView: NSHostingView<ShelfView>?
    private var outsideClickMonitor: Any?
    private var itemsSubscription: AnyCancellable?
    private var lastControlFrame: CGRect?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        let rootView = ShelfView(coordinator: coordinator)
        let hosting = NSHostingView(rootView: rootView)
        let panel = ShelfPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        hostingView = hosting
        super.init(window: panel)
        panel.delegate = self
        panel.onTypeToSearch = { [weak coordinator] seed in
            coordinator?.expandShelfToList(seedQuery: seed)
        }
        itemsSubscription = coordinator.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.window?.isVisible == true else { return }
                // Let SwiftUI lay out the new content before re-fitting.
                DispatchQueue.main.async {
                    self.layoutToFit()
                    if let window = self.window {
                        self.position(window, below: self.lastControlFrame)
                    }
                }
            }
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show(below controlFrame: CGRect?) {
        guard let window else { return }
        lastControlFrame = controlFrame
        layoutToFit()
        position(window, below: controlFrame)
        window.makeKeyAndOrderFront(nil)
        installOutsideClickMonitor()
    }

    /// The item list changes after every scan, so the panel re-fits and
    /// re-anchors whenever SwiftUI lays out new content.
    func layoutToFit() {
        guard let window, let hostingView else { return }
        var size = hostingView.fittingSize
        size.width = min(max(size.width, 120), 720)
        size.height = max(size.height, 40)
        window.setContentSize(size)
    }

    private func position(_ window: NSWindow, below anchorFrame: CGRect?) {
        let anchorPoint = anchorFrame.map { CGPoint(x: $0.midX, y: $0.midY) }
        let screen = anchorPoint.flatMap { point in
            NSScreen.screens.first { $0.frame.insetBy(dx: -2, dy: -2).contains(point) }
        } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let top = visible.maxY - 4
        // Centered under the Barkeep control, on the control's own screen.
        var x = visible.maxX - window.frame.width - 8
        if let anchorFrame {
            x = min(anchorFrame.midX - window.frame.width / 2, x)
            x = max(x, visible.minX + 8)
        }
        window.setFrameOrigin(NSPoint(x: x, y: top - window.frame.height))
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    func windowWillClose(_ notification: Notification) {
        removeOutsideClickMonitor()
        onClose?()
    }
}

struct ShelfView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var hoveredName: String?

    var body: some View {
        iconRow
            // Reserved caption strip: the hovered item's name appears
            // instantly, without resizing the panel.
            .padding(.bottom, 15)
            .overlay(alignment: .bottom) {
                Text(hoveredName ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 5)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11))
            .fixedSize()
    }

    private var iconRow: some View {
        HStack(spacing: 4) {
            if !AccessibilityPermission.isGranted {
                Text("Allow Accessibility to list menu bar items")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Set Up") { AccessibilityPermission.request() }
            } else if coordinator.shelfSessionItems.isEmpty {
                if coordinator.isPreparingShelf {
                    ProgressView().controlSize(.small)
                    Text("Scanning…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Every icon fits in the menu bar")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(coordinator.shelfSessionItems) { item in
                    ShelfIconButton(item: item, coordinator: coordinator) { name in
                        hoveredName = name
                    }
                }
            }

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 3)

            Button {
                coordinator.showSettingsFromShelf()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 22, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveredName = $0 ? "Barkeep settings" : nil }
            .help("Open Barkeep settings (type to search items instead)")
        }
        .padding(.horizontal, 10)
        .padding(.top, 7)
    }
}

private struct ShelfIconButton: View {
    let item: MenuBarItemSnapshot
    @ObservedObject var coordinator: AppCoordinator
    let onHoverName: (String?) -> Void
    @State private var hovering = false

    private var label: String {
        item.displayName == item.ownerName
            ? item.displayName
            : "\(item.displayName) — \(item.ownerName)"
    }

    var body: some View {
        Button {
            Task { await coordinator.activate(item) }
        } label: {
            ShelfAppIcon(bundleIdentifier: item.bundleIdentifier)
                .padding(4)
                .background(
                    hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .onHover {
            hovering = $0
            onHoverName($0 ? label : nil)
        }
        .help(label)
    }
}

private struct ShelfAppIcon: View {
    let bundleIdentifier: String?

    var body: some View {
        if let bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: "app.dashed")
                .frame(width: 20, height: 20)
        }
    }
}
