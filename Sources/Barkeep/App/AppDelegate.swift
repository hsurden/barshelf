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
        if ProcessInfo.processInfo.arguments.contains("--show-hidden-items") {
            DispatchQueue.main.async { [weak self] in
                self?.coordinator.revealHiddenItemsForLaunchTest()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
