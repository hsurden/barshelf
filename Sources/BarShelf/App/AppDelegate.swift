import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
        if ProcessInfo.processInfo.arguments.contains("--show-settings") {
            DispatchQueue.main.async { [weak self] in
                self?.coordinator.showSettings()
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--show-picker") {
            DispatchQueue.main.async { [weak self] in
                self?.coordinator.showSearch()
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--show-permission-guide") {
            DispatchQueue.main.async {
                PermissionAssistant.shared.presentAccessibilityGuide(keepVisibleForTesting: true)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--request-accessibility") {
            DispatchQueue.main.async {
                AccessibilityPermission.request()
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--show-shelf") {
            DispatchQueue.main.async { [weak self] in
                self?.coordinator.showShelf()
            }
        }
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--test-window-move"), arguments.count > index + 1 {
            let bundleID = arguments[index + 1]
            Task { [weak self] in await self?.coordinator.testWindowMove(bundleIdentifier: bundleID) }
        }
        if let flagIndex = arguments.firstIndex(of: "--debug-hide"), arguments.count > flagIndex + 1 {
            let bundleID = arguments[flagIndex + 1]
            Task { [weak self] in
                await self?.coordinator.debugMove(bundleIdentifier: bundleID, to: .alwaysHidden)
            }
        }
        if let flagIndex = arguments.firstIndex(of: "--debug-unhide"), arguments.count > flagIndex + 1 {
            let bundleID = arguments[flagIndex + 1]
            Task { [weak self] in
                await self?.coordinator.debugMove(bundleIdentifier: bundleID, to: .alwaysVisible)
            }
        }
        if let flagIndex = arguments.firstIndex(of: "--debug-activate"), arguments.count > flagIndex + 1 {
            let bundleID = arguments[flagIndex + 1]
            Task { [weak self] in
                await self?.coordinator.debugActivate(bundleIdentifier: bundleID)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--debug-scan") {
            Task { [weak self] in
                await self?.coordinator.printDebugScan()
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        coordinator.prepareForTermination() ? .terminateNow : .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // An explicit reopen (for example, opening the running app in Finder)
        // must provide a window even when the menu bar control is unreachable.
        // Reuse this instance's coordinator; launch and login remain quiet.
        coordinator.showSettings()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
