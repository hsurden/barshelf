import ApplicationServices
import Foundation

enum AccessibilityPermission {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    @MainActor
    static func request() {
        // The standard macOS dialog with "Open System Settings" is the whole
        // flow. Barkeep's own drag-tile guide panel confused more than it
        // helped and is only reachable through its explicit launch flag now.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}
