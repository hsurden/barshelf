import AppKit
import ApplicationServices
import Foundation
import os

struct RunningAppDescriptor: Sendable {
    let pid: pid_t
    let name: String
    let bundleIdentifier: String?
}

private let scanLog = Logger(subsystem: "is.ian.barkeep", category: "scan")

final class AccessibilityScanner: @unchecked Sendable {
    /// One busy application must not stall the whole scan. Accessibility's
    /// default messaging timeout is measured in seconds, so a hung app can
    /// hold the scan far past any interactive budget. Every probe below runs
    /// against a per-application element carrying this timeout instead.
    private static let messagingTimeout: Float = 0.25

    /// Probes are blocked on IPC rather than on the CPU, so the useful width
    /// is higher than the core count, but still bounded so a large session
    /// cannot explode the thread pool.
    private static let maxConcurrentProbes = 16

    private let queue = DispatchQueue(label: "is.ian.barkeep.accessibility", qos: .userInitiated)
    private let probeQueue = DispatchQueue(
        label: "is.ian.barkeep.accessibility.probe",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private var elementsByID: [String: AXUIElement] = [:]

    func scan(apps: [RunningAppDescriptor]) async -> [MenuBarItemSnapshot] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: scanNow(apps: apps))
            }
        }
    }

    func press(itemID: String) async -> MenuBarPressResult {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let element = elementsByID[itemID] else {
                    continuation.resume(returning: .unavailable)
                    return
                }
                let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
                scanLog.notice("AXPress response=\(error.rawValue, privacy: .public)")
                continuation.resume(returning: MenuBarPressResult(error: error))
            }
        }
    }

    private func scanNow(apps: [RunningAppDescriptor]) -> [MenuBarItemSnapshot] {
        let started = DispatchTime.now()
        let probed = probeAll(apps: apps)

        var snapshots: [MenuBarItemSnapshot] = []
        var newElements: [String: AXUIElement] = [:]

        // Merge in the caller's application order so a concurrent probe still
        // produces the same result as the earlier serial scan.
        for found in probed {
            for (snapshot, element) in found {
                if snapshots.contains(where: { existing in
                    existing.bundleIdentifier == snapshot.bundleIdentifier &&
                    abs(existing.frame.midX - snapshot.frame.midX) < 1 &&
                    abs(existing.frame.midY - snapshot.frame.midY) < 1
                }) {
                    continue
                }
                snapshots.append(snapshot)
                newElements[snapshot.id] = element
            }
        }

        elementsByID = newElements
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds)
            / 1_000_000
        scanLog.notice("""
        scan apps=\(apps.count, privacy: .public) \
        items=\(snapshots.count, privacy: .public) \
        ms=\(elapsed, format: .fixed(precision: 1), privacy: .public)
        """)
        return snapshots.sorted { lhs, rhs in
            if abs(lhs.frame.midY - rhs.frame.midY) > 2 {
                return lhs.frame.midY > rhs.frame.midY
            }
            return lhs.frame.midX > rhs.frame.midX
        }
    }

    /// Asks every application for its status items concurrently. Each probe is
    /// an independent synchronous round trip into another process, so the scan
    /// is dominated by waiting rather than by work.
    private func probeAll(apps: [RunningAppDescriptor]) -> [[(MenuBarItemSnapshot, AXUIElement)]] {
        guard !apps.isEmpty else { return [] }
        var results = [[(MenuBarItemSnapshot, AXUIElement)]](repeating: [], count: apps.count)
        let lock = NSLock()
        let group = DispatchGroup()
        let slots = DispatchSemaphore(value: Self.maxConcurrentProbes)

        for (index, app) in apps.enumerated() {
            slots.wait()
            probeQueue.async(group: group) { [self] in
                defer { slots.signal() }
                let found = probe(app: app)
                guard !found.isEmpty else { return }
                lock.lock()
                results[index] = found
                lock.unlock()
            }
        }
        group.wait()
        return results
    }

    private func probe(app: RunningAppDescriptor) -> [(MenuBarItemSnapshot, AXUIElement)] {
        let application = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        // AXMenuBar is the app's File/Edit/View menu. AXExtrasMenuBar contains
        // the status items that appear on the right side of the macOS menu bar.
        guard let menuBar: AXUIElement = copyAttribute(
            application,
            kAXExtrasMenuBarAttribute as CFString
        ) else {
            return []
        }

        let children: [AXUIElement] = copyArrayAttribute(
            menuBar,
            kAXChildrenAttribute as CFString,
            limit: 256
        )
        return children.enumerated().compactMap { index, element in
            guard let snapshot = makeSnapshot(element: element, app: app, ordinal: index) else {
                return nil
            }
            return (snapshot, element)
        }
    }

    private func makeSnapshot(
        element: AXUIElement,
        app: RunningAppDescriptor,
        ordinal: Int
    ) -> MenuBarItemSnapshot? {
        let role: String? = copyAttribute(element, kAXRoleAttribute as CFString)
        guard role == (kAXMenuBarItemRole as String) else {
            return nil
        }

        guard let frame = frame(of: element), frame.width > 0, frame.height > 0 else {
            return nil
        }

        let title: String? = copyAttribute(element, kAXTitleAttribute as CFString)
        let description: String? = copyAttribute(element, kAXDescriptionAttribute as CFString)
        let identifier: String? = copyAttribute(element, "AXIdentifier" as CFString)
        let cleanTitle = [title, description, identifier, app.name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Menu bar item"

        let stableIdentifier = MenuBarItemIdentity.stableAccessibilityIdentifier(
            bundleIdentifier: app.bundleIdentifier,
            identifier: identifier
        )
        let id = MenuBarItemIdentity.id(
            bundleIdentifier: app.bundleIdentifier,
            pid: app.pid,
            identifier: stableIdentifier,
            slot: ordinal
        )
        let enabled: Bool = copyAttribute(element, kAXEnabledAttribute as CFString) ?? true

        return MenuBarItemSnapshot(
            id: id,
            displayName: cleanTitle,
            ownerName: app.name,
            bundleIdentifier: app.bundleIdentifier,
            frame: frame,
            isEnabled: enabled,
            ownerPID: app.pid,
            sourceIdentifier: stableIdentifier,
            ownerSlot: ordinal
        )
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue: AXValue = copyAttribute(element, kAXPositionAttribute as CFString),
              let sizeValue: AXValue = copyAttribute(element, kAXSizeAttribute as CFString) else {
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func copyAttribute<T>(_ element: AXUIElement, _ name: CFString) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else {
            return nil
        }
        return value as? T
    }

    private func copyArrayAttribute(
        _ element: AXUIElement,
        _ name: CFString,
        limit: Int
    ) -> [AXUIElement] {
        var count: CFIndex = 0
        guard AXUIElementGetAttributeValueCount(element, name, &count) == .success,
              count > 0 else {
            return []
        }
        var value: CFArray?
        let result = AXUIElementCopyAttributeValues(
            element,
            name,
            0,
            min(count, limit),
            &value
        )
        guard result == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
}
