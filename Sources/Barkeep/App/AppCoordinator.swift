import AppKit
import Combine
import LocalAuthentication
import UniformTypeIdentifiers
import os

private let moveLog = Logger(subsystem: "is.ian.barkeep", category: "move")

private struct MoveConfirmation {
    let items: [MenuBarItemSnapshot]
    let item: MenuBarItemSnapshot
    let boundaries: BoundaryFrames
}

private enum ActivationPhase: Equatable {
    case resting
    case shelfOpen
    case revealing(String)
    case menuOpen(String)
    case restoring
}

@MainActor
final class AppCoordinator: NSObject, ObservableObject {
    let store: StateStore
    let updater = UpdateService.shared

    @Published private(set) var items: [MenuBarItemSnapshot] = []
    @Published private(set) var itemZones: [String: VisibilityZone] = [:]
    @Published private(set) var overflowIDs: Set<String> = []
    @Published private(set) var shelfSessionItems: [MenuBarItemSnapshot] = []
    @Published private(set) var isPreparingShelf = false
    @Published private(set) var isScanning = false
    @Published private(set) var isApplyingOrder = false
    @Published private(set) var movingItemID: String?
    @Published var message: String?
    var pendingSearchQuery = ""

    private let statusBar = StatusBarEngine()
    private let scanner = AccessibilityScanner()
    private let mover = ItemMoveService()
    private let triggers = TriggerCenter()
    private let hotKeys = HotKeyCenter()
    private var settingsWindow: SettingsWindowController?
    private var searchPanel: SearchPanelController?
    private var shelfPanel: ShelfPanelController?
    private var shelfClosedAt: Date?
    private var activationPhase: ActivationPhase = .resting
    private var shelfInventory = ShelfInventory()
    private var rehideTask: Task<Void, Never>?
    private var interactionEscapeMonitor: Any?
    private var interactionEndContinuation: CheckedContinuation<Void, Never>?
    private var interactionDidEnd = false
    private var authenticationContext: LAContext?
    private var permissionObserver: NSObjectProtocol?

    init(store: StateStore? = nil) {
        self.store = store ?? StateStore()
        super.init()
    }

    func start() {
        statusBar.onPrimaryAction = { [weak self] event in
            self?.handlePrimaryClick(event)
        }
        statusBar.menuProvider = { [weak self] in
            self?.makeMenu() ?? NSMenu()
        }
        triggers.onReveal = { [weak self] in self?.requestReveal(all: false) }
        triggers.onHide = { [weak self] in self?.hide() }
        hotKeys.onToggle = { [weak self] in
            guard let self else { return }
            if menuBarMode == .overflowShelf {
                toggleShelf()
            } else {
                statusBar.state == .hidden ? requestReveal(all: false) : hide()
            }
        }
        hotKeys.onSearch = { [weak self] in self?.showSearch() }
        hotKeys.start()
        updater.onWillShowWindow = { [weak self] in
            self?.settingsWindow?.close()
            self?.searchPanel?.close()
        }
        permissionObserver = NotificationCenter.default.addObserver(
            forName: PermissionAssistant.accessibilityChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.objectWillChange.send()
                Task { await self?.refreshItems(promptForPermission: false) }
            }
        }
        settingsDidChange()
        if menuBarMode == .classic {
            statusBar.hide()
        }
    }

    var menuBarMode: MenuBarMode { store.settings.mode }

    func settingsDidChange() {
        let settings = store.settings
        statusBar.setMode(settings.mode)
        if settings.mode == .classic {
            shelfPanel?.close()
        }
        statusBar.setIconStyle(settings.iconStyle)
        // Classic reveal triggers (hover, scroll, menu bar click, battery,
        // display) would pop the Always hidden section open unexpectedly in
        // shelf mode, so they are disarmed there.
        var triggerSettings = settings
        if settings.mode == .overflowShelf {
            triggerSettings.showOnHover = false
            triggerSettings.showOnScroll = false
            triggerSettings.showOnMenuBarClick = false
            triggerSettings.hideOnAppChange = false
            triggerSettings.showOnLowBattery = false
            triggerSettings.alwaysShowOnExternalDisplay = false
        }
        triggers.update(settings: triggerSettings)
        MenuBarSpacingService.apply(settings: settings)
        applyActivationPolicy()
        do {
            try LoginItemService.setEnabled(settings.launchAtLogin)
        } catch {
            message = "Barkeep could not change Launch at Login: \(error.localizedDescription)"
        }
    }

    func iconStyleDidChange() {
        statusBar.setIconStyle(store.settings.iconStyle)
    }

    func showSettings() {
        if settingsWindow == nil {
            let controller = SettingsWindowController(coordinator: self)
            controller.onClose = { [weak self] in
                guard let self else { return }
                self.settingsWindow = nil
                self.applyActivationPolicy()
            }
            settingsWindow = controller
        }
        applyActivationPolicy()
        settingsWindow?.show()
        Task { await refreshItems(promptForPermission: false) }
    }

    func showSettingsFromPicker() {
        searchPanel?.close()
        showSettings()
    }

    func showSettingsFromShelf() {
        shelfPanel?.close()
        showSettings()
    }

    func quitApp() {
        NSApp.terminate(nil)
    }

    private func applyActivationPolicy() {
        let keepRegular = settingsWindow != nil || store.settings.showDockIcon
        NSApp.setActivationPolicy(keepRegular ? .regular : .accessory)
    }

    func showSearch() {
        guard canRevealWithoutPrompt || !store.settings.requireAuthentication else {
            authenticate { [weak self] in self?.showSearch() }
            return
        }
        if searchPanel == nil {
            let controller = SearchPanelController(coordinator: self)
            controller.onClose = { [weak self] in self?.searchPanel = nil }
            searchPanel = controller
        }
        searchPanel?.show()
        Task { await refreshItems(promptForPermission: true) }
    }

    func toggleShelf() {
        if shelfPanel?.window?.isVisible == true {
            shelfPanel?.close()
        } else if let closedAt = shelfClosedAt, Date().timeIntervalSince(closedAt) < 0.35 {
            // The click on the control just closed the shelf by taking key
            // status away from it; do not immediately reopen it.
            shelfClosedAt = nil
        } else {
            showShelf()
        }
    }

    func showShelf() {
        guard menuBarMode == .overflowShelf,
              movingItemID == nil,
              activationPhase == .resting else { return }
        guard canRevealWithoutPrompt || !store.settings.requireAuthentication else {
            authenticate { [weak self] in self?.showShelf() }
            return
        }
        // Opening the shelf tucks back any item left revealed by a previous
        // shelf activation, so the scan below sees the resting bar.
        rehideTask?.cancel()
        rehideTask = nil
        let wasRevealed = statusBar.state == .revealedAll
        statusBar.setState(.revealed)
        activationPhase = .shelfOpen
        shelfSessionItems = []
        isPreparingShelf = true
        if shelfPanel == nil {
            let controller = ShelfPanelController(coordinator: self)
            controller.onClose = { [weak self] in
                guard let self else { return }
                self.shelfPanel = nil
                self.shelfClosedAt = Date()
                self.shelfSessionItems = []
                self.isPreparingShelf = false
                if self.activationPhase == .shelfOpen {
                    self.activationPhase = .resting
                }
            }
            shelfPanel = controller
        }
        shelfPanel?.show(below: statusBar.controlScreenFrame())
        Task {
            if wasRevealed {
                // Give the tucked-back items time to slide out of the bar, so
                // this scan classifies them as overflowed and the shelf
                // lists them again.
                try? await Task.sleep(for: .milliseconds(400))
            }
            await refreshItems(promptForPermission: true)
            guard activationPhase == .shelfOpen else { return }
            let hiddenIDs = Set(shelfInventory.items.compactMap {
                intentZone(for: $0) == .alwaysHidden ? $0.id : nil
            })
            shelfSessionItems = ShelfSessionModel.items(
                from: shelfInventory.items,
                overflowIDs: shelfInventory.overflowIDs,
                intentionallyHiddenIDs: hiddenIDs
            )
            isPreparingShelf = false
        }
    }

    /// The shelf's chevron, or typing while the shelf is open, expands into the
    /// searchable list. The seed becomes the list's initial query.
    func expandShelfToList(seedQuery: String = "") {
        shelfPanel?.close()
        pendingSearchQuery = seedQuery
        showSearch()
    }

    func refreshItems(promptForPermission: Bool) async {
        guard !isScanning, movingItemID == nil else { return }
        guard AccessibilityPermission.isGranted else {
            if promptForPermission { AccessibilityPermission.request() }
            message = BarkeepError.accessibilityRequired.localizedDescription
            return
        }

        isScanning = true
        defer { isScanning = false }
        let result: [MenuBarItemSnapshot]
        if menuBarMode == .overflowShelf {
            // Only the Always hidden section exists in shelf mode, and its
            // items stay scannable while off screen, so scan in place without
            // opening any section.
            result = await scanner.scan(apps: runningApps())
            itemZones = zones(for: result, boundaries: statusBar.boundaryFrames())
        } else {
            let previousState = statusBar.state
            statusBar.revealAll()
            try? await Task.sleep(for: .milliseconds(140))
            result = await scanner.scan(apps: runningApps())
            let boundaries = statusBar.boundaryFrames()
            itemZones = zones(for: result, boundaries: boundaries)
            statusBar.setState(previousState)
        }
        applyScanResult(result)
        message = result.isEmpty ? "Barkeep did not find any menu bar items." : nil
    }

    func isOverflowed(_ item: MenuBarItemSnapshot) -> Bool {
        overflowIDs.contains(item.id) || shelfInventory.overflowIDs.contains(item.id)
    }

    func currentZone(for item: MenuBarItemSnapshot) -> VisibilityZone {
        itemZones[item.id] ?? store.rules[item.id]?.zone ?? .alwaysVisible
    }

    func items(in zone: VisibilityZone) -> [MenuBarItemSnapshot] {
        items.filter { !$0.isPinnedByMacOS && currentZone(for: $0) == zone }
    }

    /// Shelf mode's saved intent for an item: hidden only when a rule says so.
    func intentZone(for item: MenuBarItemSnapshot) -> VisibilityZone {
        store.rules[item.id]?.zone ?? .alwaysVisible
    }

    /// The Items tab groups by saved intent in shelf mode. Live geometry is
    /// unreliable across displays and macOS reflows, so physical disagreement
    /// is surfaced per row instead of silently reshuffling the columns.
    func itemsForSettings(in zone: VisibilityZone) -> [MenuBarItemSnapshot] {
        guard menuBarMode == .overflowShelf else { return items(in: zone) }
        return items.filter { item in
            guard !item.isPinnedByMacOS else { return false }
            let isHidden = intentZone(for: item) == .alwaysHidden
            return zone == .alwaysHidden ? isHidden : !isHidden
        }
        // Rightmost first, so the list's top row is the safest bar position.
        .sorted { $0.frame.midX > $1.frame.midX }
    }

    /// True when the user asked for this item to be hidden but macOS still
    /// shows it in the bar.
    func isPendingHide(_ item: MenuBarItemSnapshot) -> Bool {
        menuBarMode == .overflowShelf &&
        intentZone(for: item) == .alwaysHidden &&
        !isOverflowed(item)
    }

    var pendingHideCount: Int {
        items.filter { !$0.isPinnedByMacOS && isPendingHide($0) }.count
    }

    /// Explicit retry for items macOS bounced back into the bar after a hide.
    /// Runs one confirmed move at a time and reports what is still visible.
    func reapplyHiddenItems() async {
        guard movingItemID == nil, !isScanning, !isApplyingOrder else { return }
        await refreshItems(promptForPermission: true)
        let pending = items.filter { !$0.isPinnedByMacOS && isPendingHide($0) }
        guard !pending.isEmpty else {
            message = "Every hidden item is already out of the bar."
            return
        }
        for item in pending {
            await moveItem(item, to: .alwaysHidden)
        }
        await refreshItems(promptForPermission: false)
        let remaining = items.filter { !$0.isPinnedByMacOS && isPendingHide($0) }
        message = remaining.isEmpty
            ? "Barkeep moved every hidden item out of the bar."
            : "\(remaining.count) hidden item\(remaining.count == 1 ? " is" : "s are") still in the bar. Free some menu bar space and try again."
    }

    func moveItem(_ item: MenuBarItemSnapshot, to zone: VisibilityZone) async {
        guard movingItemID == nil, !isScanning else { return }
        guard !item.isPinnedByMacOS else {
            message = BarkeepError.itemPinnedByMacOS.localizedDescription
            return
        }
        guard AccessibilityPermission.isGranted else {
            AccessibilityPermission.request()
            message = BarkeepError.accessibilityRequired.localizedDescription
            return
        }

        movingItemID = item.id
        let previousState = statusBar.state
        rehideTask?.cancel()
        rehideTask = nil
        statusBar.revealAll()
        defer {
            statusBar.setControlLength(nil)
            statusBar.setState(previousState)
            movingItemID = nil
            if previousState != .hidden {
                scheduleRehide()
            }
        }

        do {
            let screens = screenGeometries()
            guard let originalPointer = screens.lazy.compactMap({
                $0.coordinates.quartzPoint(fromAppKit: NSEvent.mouseLocation)
            }).first else {
                throw BarkeepError.invalidGeometry
            }
            let reveal = try await waitForRevealedItem(matching: item, screens: screens)
            let freshItems = reveal.items
            let freshItem = reveal.item
            moveLog.notice("""
            move \(item.id, privacy: .public) -> \(zone.title, privacy: .public) \
            source=\(String(describing: freshItem.frame), privacy: .public)
            """)
            guard let target = statusBar.targetPoint(for: zone) else {
                throw BarkeepError.boundariesUnavailable
            }
            if let boundaries = statusBar.boundaryFrames() {
                moveLog.notice("""
                boundaries control=\(String(describing: boundaries.control), privacy: .public) \
                hidden=\(String(describing: boundaries.hidden), privacy: .public) \
                alwaysHidden=\(String(describing: boundaries.alwaysHidden), privacy: .public) \
                target=\(String(describing: target), privacy: .public)
                """)
            }
            guard let quartzTarget = screens.lazy.compactMap({
                $0.coordinates.quartzPoint(fromAppKit: target)
            }).first else {
                throw BarkeepError.invalidGeometry
            }
            let rawSourcePoint = CGPoint(x: freshItem.frame.midX, y: freshItem.frame.midY)
            guard let quartzSource = screens.compactMap({
                $0.coordinates.quartzPoint(
                    fromAccessibility: rawSourcePoint,
                    menuBarAnchorY: quartzTarget.y
                )
            }).min(by: {
                abs($0.y - quartzTarget.y) < abs($1.y - quartzTarget.y)
            }) else {
                throw BarkeepError.invalidGeometry
            }
            // Every display's menu bar mirrors the same items packed from its
            // right edge, so a point the notch occludes on the built-in
            // display has a drawable twin on a notch-free display. Grabs from
            // behind the notch fail (verified live), so occluded drags are
            // remapped to the roomiest display and performed there.
            var dragSource = quartzSource
            var dragTarget = quartzTarget
            var sourceOccluded = screens.contains(where: { $0.hidesMenuBarPoint(dragSource) })
            var targetOccluded = screens.contains(where: { $0.hidesMenuBarPoint(dragTarget) })
            if sourceOccluded || targetOccluded,
               let notched = screens.first(where: { $0.statusAreaMinX != nil }),
               let roomy = screens.first(where: { $0.statusAreaMinX == nil }) {
                if sourceOccluded {
                    dragSource = notched.remapMenuBarPoint(dragSource, to: roomy)
                }
                if targetOccluded {
                    dragTarget = notched.remapMenuBarPoint(dragTarget, to: roomy)
                }
                moveLog.notice("""
                remapped drag to notch-free display \
                source=\(String(describing: dragSource), privacy: .public) \
                target=\(String(describing: dragTarget), privacy: .public)
                """)
                sourceOccluded = false
                targetOccluded = false
            } else if sourceOccluded || targetOccluded {
                // No notch-free display attached. Freeing Barkeep's own
                // pixels shifts everything right and is often just enough
                // for the occluded point to clear the notch.
                statusBar.setControlLength(8)
                try? await Task.sleep(for: .milliseconds(300))
                let rescan = await scanner.scan(apps: runningApps())
                if let shifted = rescan.first(where: { matches($0, item) }),
                   let shiftedSource = screens.lazy.compactMap({
                       $0.coordinates.quartzPoint(
                           fromAccessibility: CGPoint(x: shifted.frame.midX, y: shifted.frame.midY),
                           menuBarAnchorY: dragTarget.y
                       )
                   }).first,
                   let newTarget = statusBar.targetPoint(for: zone),
                   let shiftedTarget = screens.lazy.compactMap({
                       $0.coordinates.quartzPoint(fromAppKit: newTarget)
                   }).first {
                    dragSource = shiftedSource
                    dragTarget = shiftedTarget
                    sourceOccluded = screens.contains { $0.hidesMenuBarPoint(dragSource) }
                    targetOccluded = screens.contains { $0.hidesMenuBarPoint(dragTarget) }
                    moveLog.notice("""
                    shrunk control for occluded drag \
                    source=\(String(describing: dragSource), privacy: .public) \
                    target=\(String(describing: dragTarget), privacy: .public)
                    """)
                }
            }
            let quartzSourceFrame = CGRect(
                x: dragSource.x - freshItem.frame.width / 2,
                y: dragSource.y - freshItem.frame.height / 2,
                width: freshItem.frame.width,
                height: freshItem.frame.height
            )

            if targetOccluded {
                // The hidden zone's drop point sits behind the notch. macOS
                // can still land this drop (verified live: the drag can route
                // through another display's menu bar), so shelf mode tries the
                // direct drag and lets the confirmation scan decide, then
                // falls back to the full-bar sequence. Classic mode keeps the
                // honest upstream failure.
                guard menuBarMode == .overflowShelf, zone == .alwaysHidden else {
                    throw BarkeepError.menuBarFull
                }
                try await mover.move(
                    from: quartzSourceFrame,
                    to: dragTarget,
                    originalPointer: originalPointer,
                    screens: screens
                )
                if let confirmation = await confirmMove(item, to: zone) {
                    applyConfirmedMove(confirmation, to: zone)
                    return
                }
                try await hideOnFullBar(item, screens: screens, originalPointer: originalPointer)
            } else {
                if let boundaries = statusBar.boundaryFrames(),
                   boundaries.zone(for: freshItem.frame) == zone {
                    applyConfirmedMove(
                        MoveConfirmation(items: freshItems, item: freshItem, boundaries: boundaries),
                        to: zone
                    )
                    return
                }
                try await mover.move(
                    from: quartzSourceFrame,
                    to: dragTarget,
                    originalPointer: originalPointer,
                    screens: screens
                )
            }
            guard let confirmation = await confirmMove(item, to: zone) else {
                throw sourceOccluded ? BarkeepError.itemOccluded : BarkeepError.moveNotConfirmed
            }
            applyConfirmedMove(confirmation, to: zone)
        } catch {
            message = error.localizedDescription
        }
    }

    /// Hides an item on a completely full menu bar, where the hidden zone's
    /// drop point is behind the notch. Sequence: shrink Barkeep's control to
    /// free a sliver of drawable space, drag the item into the freed leftmost
    /// slot, then recreate the Always hidden boundary immediately to the
    /// item's right (the boundary is Barkeep's own status item, so it needs
    /// no drag). Every drop lands on drawable pixels, and the caller's
    /// confirmation scan still decides whether the rule is saved.
    private func hideOnFullBar(
        _ item: MenuBarItemSnapshot,
        screens: [ScreenGeometry],
        originalPointer: CGPoint
    ) async throws {
        statusBar.setControlLength(8)
        defer { statusBar.setControlLength(nil) }
        try? await Task.sleep(for: .milliseconds(300))

        let snapshots = await scanner.scan(apps: runningApps())
        guard let fresh = snapshots.first(where: { matches($0, item) }) else {
            throw BarkeepError.itemNotFound
        }
        guard let screen = screens.first(where: { $0.statusAreaMinX != nil }) ?? screens.first else {
            throw BarkeepError.invalidGeometry
        }
        let stripLeft = (screen.statusAreaMinX ?? screen.frame.minX) + 4
        let visibleMovables = snapshots.filter {
            !$0.isPinnedByMacOS &&
            !OverflowClassifier.isOverflowed(frame: $0.frame, screens: screens)
        }
        guard let leftmost = visibleMovables.min(by: { $0.frame.midX < $1.frame.midX }) else {
            throw BarkeepError.invalidGeometry
        }
        guard leftmost.frame.minX - stripLeft > 10 else {
            throw BarkeepError.menuBarFull
        }

        let rawSource = CGPoint(x: fresh.frame.midX, y: fresh.frame.midY)
        guard let quartzSource = screens.lazy.compactMap({
            $0.coordinates.quartzPoint(fromAccessibility: rawSource, menuBarAnchorY: rawSource.y)
        }).first else {
            throw BarkeepError.invalidGeometry
        }
        if screens.contains(where: { $0.hidesMenuBarPoint(quartzSource) }) {
            throw BarkeepError.itemOccluded
        }
        let sourceFrame = CGRect(
            x: quartzSource.x - fresh.frame.width / 2,
            y: quartzSource.y - fresh.frame.height / 2,
            width: fresh.frame.width,
            height: fresh.frame.height
        )
        let dropPoint = CGPoint(x: (stripLeft + leftmost.frame.minX - 2) / 2, y: quartzSource.y)
        moveLog.notice("""
        full-bar hide \(item.id, privacy: .public) \
        drop=\(String(describing: dropPoint), privacy: .public) \
        stripLeft=\(stripLeft, privacy: .public)
        """)
        try await mover.move(
            from: sourceFrame,
            to: dropPoint,
            originalPointer: originalPointer,
            screens: screens
        )

        // The boundary may close over this item only when the item is the
        // leftmost visible movable; otherwise neighbors would be hidden too.
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(120))
            let rescan = await scanner.scan(apps: runningApps())
            guard let moved = rescan.first(where: { matches($0, item) }) else { continue }
            let visible = rescan.filter {
                !$0.isPinnedByMacOS &&
                !OverflowClassifier.isOverflowed(frame: $0.frame, screens: screens)
            }
            guard let neighbor = visible
                .filter({ $0.id != moved.id })
                .min(by: { $0.frame.midX < $1.frame.midX }),
                moved.frame.midX < neighbor.frame.midX else {
                continue
            }
            let desiredMidX = (moved.frame.maxX + neighbor.frame.minX) / 2
            statusBar.repositionAlwaysHiddenBoundary(
                preferredRightOffset: screen.frame.maxX - desiredMidX
            )
            try? await Task.sleep(for: .milliseconds(300))
            return
        }
        throw BarkeepError.moveNotConfirmed
    }

    func activate(_ item: MenuBarItemSnapshot) async {
        guard movingItemID == nil else { return }
        guard activationPhase == .resting || activationPhase == .shelfOpen else { return }

        let previousState = statusBar.state
        activationPhase = .revealing(item.id)
        rehideTask?.cancel()
        rehideTask = nil
        closePickers()

        var target = item
        let needsReveal = isOverflowed(item) || intentZone(for: item) == .alwaysHidden
        if needsReveal {
            statusBar.revealAll()
            try? await Task.sleep(for: .milliseconds(180))
            let rescanned = await scanner.scan(apps: runningApps())
            applyScanResult(rescanned)
            guard let refreshed = rescanned.first(where: { matches($0, item) }) else {
                message = BarkeepError.itemNotFound.localizedDescription
                await restoreAfterActivation(previousState: previousState)
                return
            }
            target = refreshed
        }

        beginInteractionSession(itemID: target.id)
        _ = await scanner.press(itemID: target.id)
        // The selected item now remains physically available even after its
        // menu closes. A Barkeep click or Escape explicitly ends the session.
        await waitForInteractionSessionToEnd()
        await restoreAfterActivation(previousState: previousState)
    }

    private func beginInteractionSession(itemID: String) {
        stopInteractionMonitoring()
        interactionDidEnd = false
        activationPhase = .menuOpen(itemID)
        interactionEscapeMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            Task { @MainActor in
                if event.type == .keyDown && event.keyCode == 53 {
                    self?.finishInteractionSession()
                }
            }
        }
    }

    private func waitForInteractionSessionToEnd() async {
        if interactionDidEnd { return }
        await withCheckedContinuation { continuation in
            if interactionDidEnd {
                continuation.resume()
            } else {
                interactionEndContinuation = continuation
            }
        }
    }

    private func finishInteractionSession() {
        guard !interactionDidEnd else { return }
        interactionDidEnd = true
        interactionEndContinuation?.resume()
        interactionEndContinuation = nil
    }

    private func stopInteractionMonitoring() {
        if let interactionEscapeMonitor {
            NSEvent.removeMonitor(interactionEscapeMonitor)
            self.interactionEscapeMonitor = nil
        }
    }

    private func restoreAfterActivation(previousState: StatusBarEngine.State) async {
        activationPhase = .restoring
        stopInteractionMonitoring()
        if menuBarMode == .overflowShelf {
            statusBar.setState(.revealed)
        } else {
            statusBar.setState(previousState)
        }
        try? await Task.sleep(for: .milliseconds(350))
        let rescanned = await scanner.scan(apps: runningApps())
        applyScanResult(rescanned)
        activationPhase = .resting
    }

    private func applyScanResult(_ result: [MenuBarItemSnapshot]) {
        store.reconcileItemIdentities(with: result)
        let scannedOverflow = OverflowClassifier.overflowedIDs(
            items: result,
            screens: screenGeometries()
        )
        let runningPIDs = Set(runningApps().map(\.pid))
        shelfInventory.update(
            scannedItems: result,
            scannedOverflowIDs: scannedOverflow,
            runningPIDs: runningPIDs
        )
        overflowIDs = scannedOverflow
        items = result
    }

    private func closePickers() {
        searchPanel?.close()
        shelfPanel?.close()
    }

    /// Direct drag-to-reorder from the Items tab: one confirmed move that
    /// places the item at the given position counting from the right.
    func reorderItem(_ item: MenuBarItemSnapshot, toRank rank: Int) async {
        guard movingItemID == nil, !isScanning, !isApplyingOrder else { return }
        guard AccessibilityPermission.isGranted else {
            AccessibilityPermission.request()
            message = BarkeepError.accessibilityRequired.localizedDescription
            return
        }
        isApplyingOrder = true
        defer { isApplyingOrder = false }
        let entry = PriorityEntry(
            id: item.id,
            displayName: item.displayName,
            ownerName: item.ownerName,
            bundleIdentifier: item.bundleIdentifier
        )
        do {
            if try await placePriorityItem(entry, rank: max(0, rank)) {
                message = "\(item.displayName) moved."
            }
        } catch {
            message = "\(item.displayName): \(error.localizedDescription)"
        }
        await refreshItems(promptForPermission: false)
    }

    /// Applies the saved priority order with real, confirmed Command-drags:
    /// rank 1 lands rightmost, each later rank immediately left of the one
    /// before it. Runs only from the explicit "Apply Order Now" action, moves
    /// one item at a time, rescans between moves, and stops on the first
    /// failure with the earlier arrangement untouched from that point on.
    func applyPriorityOrder() async {
        guard movingItemID == nil, !isScanning, !isApplyingOrder else { return }
        guard AccessibilityPermission.isGranted else {
            AccessibilityPermission.request()
            message = BarkeepError.accessibilityRequired.localizedDescription
            return
        }
        let priority = store.priorityOrder
        guard !priority.isEmpty else {
            message = "Add items to the priority list first."
            return
        }

        isApplyingOrder = true
        defer { isApplyingOrder = false }
        var movedCount = 0
        for (rank, entry) in priority.enumerated() {
            do {
                if try await placePriorityItem(entry, rank: rank) {
                    movedCount += 1
                }
            } catch {
                message = "\(entry.displayName): \(error.localizedDescription)"
                await refreshItems(promptForPermission: false)
                return
            }
        }
        await refreshItems(promptForPermission: false)
        message = movedCount == 0
            ? "The menu bar already matches the priority order."
            : "Barkeep applied the priority order with \(movedCount) move\(movedCount == 1 ? "" : "s")."
    }

    private func placePriorityItem(_ entry: PriorityEntry, rank: Int) async throws -> Bool {
        let screens = screenGeometries()
        var snapshots = await scanner.scan(apps: runningApps())
        var movable = OrderPlanner.movableRightToLeft(snapshots)
        guard let match = movable.first(where: { matchesPriority($0, entry) }) else {
            throw BarkeepError.itemNotFound
        }
        if OrderPlanner.isInPlace(itemID: match.id, rank: rank, movableRightToLeft: movable) {
            return false
        }
        guard let anchor = OrderPlanner.rightAnchorMinX(snapshots),
              let target = OrderPlanner.moveTarget(
                itemID: match.id,
                rank: rank,
                movableRightToLeft: movable,
                rightAnchorMinX: anchor
              ) else {
            throw BarkeepError.invalidGeometry
        }
        guard let originalPointer = screens.lazy.compactMap({
            $0.coordinates.quartzPoint(fromAppKit: NSEvent.mouseLocation)
        }).first else {
            throw BarkeepError.invalidGeometry
        }
        let rawSource = CGPoint(x: match.frame.midX, y: match.frame.midY)
        guard let quartzSource = screens.lazy.compactMap({
            $0.coordinates.quartzPoint(fromAccessibility: rawSource, menuBarAnchorY: rawSource.y)
        }).first, let quartzTarget = screens.lazy.compactMap({
            $0.coordinates.quartzPoint(fromAccessibility: target, menuBarAnchorY: rawSource.y)
        }).first else {
            throw BarkeepError.invalidGeometry
        }
        if screens.contains(where: { $0.hidesMenuBarPoint(quartzSource) }) {
            throw BarkeepError.itemOccluded
        }
        if screens.contains(where: { $0.hidesMenuBarPoint(quartzTarget) }) {
            throw BarkeepError.menuBarFull
        }

        movingItemID = match.id
        defer { movingItemID = nil }
        moveLog.notice("""
        order move \(match.id, privacy: .public) rank=\(rank, privacy: .public) \
        source=\(String(describing: quartzSource), privacy: .public) \
        target=\(String(describing: quartzTarget), privacy: .public)
        """)
        let sourceFrame = CGRect(
            x: quartzSource.x - match.frame.width / 2,
            y: quartzSource.y - match.frame.height / 2,
            width: match.frame.width,
            height: match.frame.height
        )
        try await mover.move(
            from: sourceFrame,
            to: quartzTarget,
            originalPointer: originalPointer,
            screens: screens
        )
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(120))
            snapshots = await scanner.scan(apps: runningApps())
            movable = OrderPlanner.movableRightToLeft(snapshots)
            if let fresh = movable.first(where: { matchesPriority($0, entry) }),
               OrderPlanner.isInPlace(itemID: fresh.id, rank: rank, movableRightToLeft: movable) {
                items = snapshots
                overflowIDs = OverflowClassifier.overflowedIDs(items: snapshots, screens: screens)
                return true
            }
        }
        throw BarkeepError.moveNotConfirmed
    }

    /// Launch-flag helper: activates an item the way a shelf click does and
    /// reports whether a menu actually opened on screen.
    func debugActivate(bundleIdentifier: String) async {
        try? await Task.sleep(for: .milliseconds(600))
        await refreshItems(promptForPermission: true)
        guard let item = items.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            print("debug-activate: no item for \(bundleIdentifier)")
            fflush(stdout)
            return
        }
        print("debug-activate: \(item.displayName) frame=\(item.frame) overflowed=\(isOverflowed(item))")
        fflush(stdout)
        await activate(item)
        try? await Task.sleep(for: .milliseconds(800))
        print("debug-activate: menuIsOpen=\(Self.menuIsOpen()) message=\(message ?? "none")")
        let rescan = await scanner.scan(apps: runningApps())
        if let fresh = rescan.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            print("debug-activate: item now at \(fresh.frame)")
        }
        fflush(stdout)
    }

    /// Launch-flag helper: exercises the full move pipeline headlessly so a
    /// terminal launch can verify hide and unhide without the Settings UI.
    func debugMove(bundleIdentifier: String, to zone: VisibilityZone) async {
        try? await Task.sleep(for: .milliseconds(600))
        await refreshItems(promptForPermission: true)
        guard let item = items.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            print("debug-move: no item for \(bundleIdentifier)")
            fflush(stdout)
            return
        }
        print("debug-move: \(item.displayName) frame=\(item.frame) -> \(zone.rawValue)")
        statusBar.revealAll()
        try? await Task.sleep(for: .milliseconds(200))
        if let boundaries = statusBar.boundaryFrames() {
            print("debug-move boundaries: control=\(boundaries.control) alwaysHidden=\(boundaries.alwaysHidden) target(\(zone.rawValue))=\(String(describing: boundaries.targetPoint(for: zone)))")
        } else {
            print("debug-move boundaries: unavailable")
        }
        for screen in screenGeometries() {
            print("debug-move screen: \(screen.frame) statusAreaMinX=\(String(describing: screen.statusAreaMinX))")
        }
        fflush(stdout)
        await moveItem(item, to: zone)
        let resultZone = itemZones[item.id].map(\.rawValue) ?? "unknown"
        print("debug-move result: zone=\(resultZone) message=\(message ?? "none")")
        let after = await scanner.scan(apps: runningApps())
        if let final = after.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            print("debug-move after: frame=\(final.frame)")
        } else {
            print("debug-move after: item not found in rescan")
        }
        if let boundaries = statusBar.boundaryFrames() {
            print("debug-move after boundaries: alwaysHidden=\(boundaries.alwaysHidden)")
        }
        fflush(stdout)
    }

    /// Launch-flag helper: prints every scanned item with its frame and
    /// overflow classification to stdout so a terminal launch can verify the
    /// notch hypothesis without any UI.
    func printDebugScan() async {
        await refreshItems(promptForPermission: true)
        let screens = screenGeometries()
        print("debug-scan: \(items.count) items, mode=\(menuBarMode.rawValue) state=\(statusBar.state.rawValue)")
        if let boundaries = statusBar.boundaryFrames() {
            print("boundaries: control=\(boundaries.control) alwaysHidden=\(boundaries.alwaysHidden)")
        } else {
            print("boundaries: unavailable")
        }
        let defaults = UserDefaults.standard
        for name in ["Barkeep.Control.v3", "Barkeep.AlwaysHiddenBoundary.v3", "Barkeep.HiddenBoundary.v3"] {
            print("preferred \(name): \(defaults.object(forKey: "NSStatusItem Preferred Position \(name)") ?? "unset")")
        }
        for screen in screens {
            print("screen quartz=\(screen.frame) statusAreaMinX=\(screen.statusAreaMinX.map(String.init(describing:)) ?? "none")")
        }
        for item in items.sorted(by: { $0.frame.midX < $1.frame.midX }) {
            let state = isOverflowed(item) ? "OVERFLOWED" : "visible"
            let pinned = item.isPinnedByMacOS ? " pinned" : ""
            print("\(state)\(pinned) x=\(Int(item.frame.minX))-\(Int(item.frame.maxX)) \(item.displayName) [\(item.bundleIdentifier ?? "?")]")
        }
        fflush(stdout)
    }

    private func matchesPriority(_ item: MenuBarItemSnapshot, _ entry: PriorityEntry) -> Bool {
        item.id == entry.id || (
            item.bundleIdentifier == entry.bundleIdentifier &&
            item.displayName == entry.displayName &&
            item.ownerName == entry.ownerName
        )
    }

    func requestReveal(all: Bool) {
        guard movingItemID == nil else { return }
        if store.settings.requireAuthentication && statusBar.state == .hidden {
            authenticate { [weak self] in self?.reveal(all: all) }
        } else {
            reveal(all: all)
        }
    }

    func revealHiddenItemsForLaunchTest() {
        rehideTask?.cancel()
        rehideTask = nil
        statusBar.revealHidden()
    }

    func hide() {
        guard movingItemID == nil,
              activationPhase == .resting || activationPhase == .shelfOpen else { return }
        rehideTask?.cancel()
        rehideTask = nil
        if menuBarMode == .overflowShelf {
            // Shelf mode's resting state keeps everything inline except the
            // Always hidden section.
            statusBar.setState(.revealed)
        } else {
            statusBar.hide()
        }
        authenticationContext = nil
    }

    func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Barkeep Settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportData().write(to: url, options: .atomic)
            message = "Barkeep exported the settings."
        } catch {
            message = "Barkeep could not export the settings: \(error.localizedDescription)"
        }
    }

    func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.importData(Data(contentsOf: url))
            settingsDidChange()
            message = "Barkeep imported the settings."
        } catch {
            message = "Barkeep could not import this file: \(error.localizedDescription)"
        }
    }

    private var canRevealWithoutPrompt: Bool {
        authenticationContext != nil
    }

    private func handlePrimaryClick(_ event: NSEvent) {
        guard movingItemID == nil else { return }
        if activationPhase != .resting && activationPhase != .shelfOpen {
            finishInteractionSession()
            return
        }
        if menuBarMode == .overflowShelf {
            if event.modifierFlags.contains(.option) {
                showSearch()
            } else {
                toggleShelf()
            }
        } else if event.modifierFlags.contains(.option) {
            if statusBar.state == .revealedAll { hide() } else { requestReveal(all: true) }
        } else {
            showSearch()
        }
    }

    private func reveal(all: Bool) {
        guard movingItemID == nil else { return }
        all ? statusBar.revealAll() : statusBar.revealHidden()
        scheduleRehide()
    }

    private func scheduleRehide() {
        rehideTask?.cancel()
        // Shelf mode always returns to its resting state; the auto-rehide
        // preference only governs classic mode.
        guard store.settings.autoRehide || menuBarMode == .overflowShelf else { return }
        // Shelf mode tucks revealed items back the moment the menu closes;
        // the classic delay only applies to classic mode.
        let delay = menuBarMode == .overflowShelf ? 0.6 : store.settings.rehideDelay
        rehideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            // Stay open while the pointer is in the menu bar area or a menu
            // is open, so the bar never hides mid-interaction.
            while !Task.isCancelled, Self.pointerIsBusyInMenuBar() {
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private static func pointerIsBusyInMenuBar() -> Bool {
        let location = NSEvent.mouseLocation
        if NSScreen.screens.contains(where: {
            Self.isInMenuBarStrip(location: location, screenFrame: $0.frame)
        }) {
            return true
        }
        return menuIsOpen()
    }

    static func isInMenuBarStrip(location: CGPoint, screenFrame: CGRect) -> Bool {
        location.x >= screenFrame.minX &&
        location.x <= screenFrame.maxX &&
        location.y >= screenFrame.maxY - 38 &&
        location.y <= screenFrame.maxY
    }

    private static func menuIsOpen() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            .optionOnScreenOnly,
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }
        let menuLayer = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return windows.contains { ($0[kCGWindowLayer as String] as? Int) == menuLayer }
    }

    private func authenticate(onSuccess: @escaping @MainActor () -> Void) {
        let context = LAContext()
        authenticationContext = context
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Open the menu bar item picker"
        ) { [weak self] success, _ in
            Task { @MainActor in
                if success {
                    onSuccess()
                } else {
                    self?.authenticationContext = nil
                    self?.message = BarkeepError.authenticationFailed.localizedDescription
                }
            }
        }
    }

    private func runningApps() -> [RunningAppDescriptor] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != ownPID
        }.map {
            RunningAppDescriptor(
                pid: $0.processIdentifier,
                name: $0.localizedName ?? $0.bundleIdentifier ?? "App",
                bundleIdentifier: $0.bundleIdentifier
            )
        }
    }

    private func screenGeometries() -> [ScreenGeometry] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            let quartzFrame = CGDisplayBounds(displayID)
            var statusAreaMinX: CGFloat?
            if screen.safeAreaInsets.top > 0, let statusArea = screen.auxiliaryTopRightArea {
                statusAreaMinX = quartzFrame.minX + statusArea.minX - screen.frame.minX
            }
            return ScreenGeometry(
                coordinates: ScreenCoordinateSpace(
                    appKitFrame: screen.frame,
                    quartzFrame: quartzFrame
                ),
                statusAreaMinX: statusAreaMinX
            )
        }
    }

    private func zones(
        for snapshots: [MenuBarItemSnapshot],
        boundaries: BoundaryFrames?
    ) -> [String: VisibilityZone] {
        var result: [String: VisibilityZone] = [:]
        for item in snapshots {
            result[item.id] = boundaries?.zone(for: item.frame)
                ?? itemZones[item.id]
                ?? store.rules[item.id]?.zone
                ?? .alwaysVisible
        }
        return result
    }

    private func confirmMove(
        _ requestedItem: MenuBarItemSnapshot,
        to zone: VisibilityZone
    ) async -> MoveConfirmation? {
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(100))
            let scannedItems = await scanner.scan(apps: runningApps())
            guard let verifiedItem = scannedItems.first(where: { matches($0, requestedItem) }),
                  let boundaries = statusBar.boundaryFrames() else {
                continue
            }
            moveLog.notice("""
            confirm scan frame=\(String(describing: verifiedItem.frame), privacy: .public) \
            zone=\(boundaries.zone(for: verifiedItem.frame).title, privacy: .public)
            """)
            if boundaries.zone(for: verifiedItem.frame) == zone {
                return MoveConfirmation(
                    items: scannedItems,
                    item: verifiedItem,
                    boundaries: boundaries
                )
            }
        }
        return nil
    }

    private func applyConfirmedMove(_ confirmation: MoveConfirmation, to zone: VisibilityZone) {
        itemZones = zones(for: confirmation.items, boundaries: confirmation.boundaries)
        items = confirmation.items
        store.setRule(for: confirmation.item, zone: zone)
        message = "\(confirmation.item.displayName) is now \(zone.title.lowercased())."
    }

    /// Always-hidden items slide in from off screen after revealAll, so a fixed delay
    /// can scan a frame that is still off screen or still animating. Poll until the
    /// item reports the same on-screen frame twice before using it as a drag source.
    private func waitForRevealedItem(
        matching item: MenuBarItemSnapshot,
        screens: [ScreenGeometry]
    ) async throws -> (items: [MenuBarItemSnapshot], item: MenuBarItemSnapshot) {
        var sawItem = false
        var previousFrame: CGRect?
        for _ in 0..<16 {
            try await Task.sleep(for: .milliseconds(140))
            let scannedItems = await scanner.scan(apps: runningApps())
            guard let match = scannedItems.first(where: { matches($0, item) }) else {
                previousFrame = nil
                continue
            }
            sawItem = true
            let source = CGPoint(x: match.frame.midX, y: match.frame.midY)
            let onScreen = screens.contains {
                $0.coordinates.quartzPoint(
                    fromAccessibility: source,
                    menuBarAnchorY: source.y
                ) != nil
            }
            guard onScreen else {
                moveLog.notice(
                    "reveal wait: off screen \(String(describing: match.frame), privacy: .public)"
                )
                previousFrame = nil
                continue
            }
            if let previous = previousFrame,
               abs(previous.midX - match.frame.midX) < 1,
               abs(previous.midY - match.frame.midY) < 1 {
                return (scannedItems, match)
            }
            previousFrame = match.frame
        }
        throw sawItem ? BarkeepError.itemNotRevealed : BarkeepError.itemNotFound
    }

    private func matches(_ lhs: MenuBarItemSnapshot, _ rhs: MenuBarItemSnapshot) -> Bool {
        lhs.id == rhs.id || (
            lhs.bundleIdentifier == rhs.bundleIdentifier &&
            lhs.displayName == rhs.displayName &&
            lhs.ownerName == rhs.ownerName
        )
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        if menuBarMode == .overflowShelf {
            menu.addItem(withTitle: "Open Overflow Shelf", action: #selector(menuShelf), keyEquivalent: "")
            menu.addItem(withTitle: "Open Item Picker…", action: #selector(menuSearch), keyEquivalent: "f")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Settings…", action: #selector(menuSettings), keyEquivalent: ",")
        } else {
            menu.addItem(withTitle: "Open Item Picker…", action: #selector(menuSearch), keyEquivalent: "f")
            menu.addItem(withTitle: "Arrange Visible Items…", action: #selector(menuSettings), keyEquivalent: ",")
            menu.addItem(.separator())
            let toggleTitle = statusBar.state == .hidden ? "Show Hidden Items" : "Hide Items"
            menu.addItem(withTitle: toggleTitle, action: #selector(menuToggle), keyEquivalent: "")
            menu.addItem(withTitle: "Show All Items", action: #selector(menuShowAll), keyEquivalent: "")
        }
        if updater.isConfigured {
            let updateTitle = updater.pendingVersion.map { "Update to \($0)…" } ?? "Check for Updates…"
            menu.addItem(withTitle: updateTitle, action: #selector(menuUpdate), keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Barkeep", action: #selector(menuQuit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        return menu
    }

    @objc private func menuToggle() {
        statusBar.state == .hidden ? requestReveal(all: false) : hide()
    }

    @objc private func menuShowAll() { requestReveal(all: true) }
    @objc private func menuShelf() { showShelf() }
    @objc private func menuSearch() { showSearch() }
    @objc private func menuSettings() { showSettings() }
    @objc private func menuUpdate() {
        settingsWindow?.close()
        searchPanel?.close()
        updater.checkForUpdates()
    }
    @objc private func menuQuit() { quitApp() }
}
