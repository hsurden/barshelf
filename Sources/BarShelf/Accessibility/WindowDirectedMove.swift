import AppKit
import CoreGraphics
import Foundation
import OSLog

/// Executed only on ItemMoveService's serial queue. Each call creates short-lived
/// event taps, runs their private run loop, then invalidates both taps. No polling
/// or event monitoring survives the requested operation.
enum WindowDirectedMove {
    private static let log = Logger(subsystem: "com.hsurden.barshelf", category: "move")
    static func perform(source: MenuBarWindow, destination: MenuBarWindow,
                        recipientPID: pid_t, edge: WindowMoveEdge, screens: [ScreenGeometry]) throws {
        guard !CGEventSource.buttonState(.combinedSessionState, button: .left),
              CGEventSource.flagsState(.combinedSessionState)
                .intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty else {
            throw WindowMoveError.userIsInteracting
        }
        let current = MenuBarWindow.readAll()
        guard current.contains(source), current.contains(destination), source.id != destination.id,
              source.frame.width < 300,
              screens.contains(where: {
                  abs($0.frame.minY + source.frame.height / 2 - source.frame.midY) <= 20 &&
                  abs($0.frame.minY + destination.frame.height / 2 - destination.frame.midY) <= 20
              }) else { throw WindowMoveError.windowChanged }
        guard let eventSource = CGEventSource(stateID: .hidSystemState),
              let pointer = CGEvent(source: nil)?.location else { throw WindowMoveError.deliveryUnavailable }

        eventSource.localEventsSuppressionInterval = 0
        eventSource.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateRemoteMouseDrag)
        let points = edge.movePoints(source: source.frame, destination: destination.frame)
        let down = try makeEvent(type: .leftMouseDown, window: source,
                                 at: points.start, source: eventSource, command: true)
        let up = try makeEvent(type: .leftMouseUp, window: destination,
                               at: points.end, source: eventSource, command: false)
        var completed = false
        var attemptedDown = false
        CGDisplayHideCursor(CGMainDisplayID())
        defer {
            if attemptedDown && !completed {
                // Always release a possibly delivered down, including timeout.
                release(up, recipientPID: recipientPID)
            }
            CGWarpMouseCursorPosition(pointer)
            CGDisplayShowCursor(CGMainDisplayID())
        }
        attemptedDown = true
        try Delivery(event: down, pid: recipientPID).send()
        log.notice("Directed down delivered")
        try waitForResponse(window: source)
        log.notice("Directed down changed source origin")
        // Tahoe needs a second release to finish its hosted-item move state.
        release(up, recipientPID: recipientPID)
        log.notice("Directed releases posted; awaiting geometry verification")
        completed = true
    }

    private static func release(_ event: CGEvent, recipientPID: pid_t) {
        // During a native move WindowServer may consume mouse-up before a
        // listen-only tap receives it. Send releases to both participants;
        // AppCoordinator verifies the resulting live layout before proceeding.
        for _ in 0..<2 {
            event.post(tap: .cgSessionEventTap)
            event.postToPid(recipientPID)
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    private static func makeEvent(type: CGEventType, window: MenuBarWindow,
                                  at point: CGPoint, source: CGEventSource, command: Bool) throws -> CGEvent {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: .left),
              let windowField = CGEventField(rawValue: 0x33) else { throw WindowMoveError.deliveryUnavailable }
        event.flags = command ? .maskCommand : []
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.id))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window.id))
        // Window routing field used by AppKit's menu-bar event path. It is
        // undocumented: matching and post-move verification are mandatory.
        event.setIntegerValueField(windowField, value: Int64(window.id))
        return event
    }

    private static func waitForResponse(window: MenuBarWindow) throws {
        let deadline = CFAbsoluteTimeGetCurrent() + 0.6
        repeat {
            if let fresh = MenuBarWindow.readAll().first(where: { $0.id == window.id }),
               fresh.frame.origin != window.frame.origin { return }
            Thread.sleep(forTimeInterval: 0.01)
        } while CFAbsoluteTimeGetCurrent() < deadline
        log.error("Source window did not change origin after down")
        throw WindowMoveError.deliveryTimedOut
    }

    /// A transaction-local queue handshake. The final marker acknowledges that
    /// the original app received our event, even when Control Center owns its window.
    private final class Delivery {
        let event: CGEvent
        let pid: pid_t
        let marker = Int64.random(in: 1...Int64.max)
        let entryMarker = Int64.random(in: 1...Int64.max)
        let exitMarker = Int64.random(in: 1...Int64.max)
        var processTap: CFMachPort?
        var sessionTap: CFMachPort?
        var delivered = false
        var forwarded = false
        var received = false
        var entered = false

        init(event: CGEvent, pid: pid_t) { self.event = event; self.pid = pid }

        func matches(_ incoming: CGEvent) -> Bool {
            incoming.type == event.type &&
            incoming.getIntegerValueField(.eventSourceUserData) == marker &&
            incoming.getIntegerValueField(.mouseEventWindowUnderMousePointer) ==
                event.getIntegerValueField(.mouseEventWindowUnderMousePointer) &&
            incoming.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent) ==
                event.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent)
        }

        func send() throws {
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            guard let entry = CGEvent(source: nil), let exit = CGEvent(source: nil) else {
                throw WindowMoveError.deliveryUnavailable
            }
            entry.setIntegerValueField(.eventSourceUserData, value: entryMarker)
            exit.setIntegerValueField(.eventSourceUserData, value: exitMarker)
            let context = Unmanaged.passUnretained(self).toOpaque()
            processTap = CGEvent.tapCreateForPid(pid: pid, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: (1 << CGEventType.null.rawValue) | (1 << event.type.rawValue),
                callback: { _, _, incoming, context in
                    guard let context else { return Unmanaged.passUnretained(incoming) }
                    let delivery = Unmanaged<Delivery>.fromOpaque(context).takeUnretainedValue()
                    let token = incoming.getIntegerValueField(.eventSourceUserData)
                    if incoming.type == .null && token == delivery.entryMarker {
                        delivery.entered = true
                        delivery.event.post(tap: .cgSessionEventTap)
                        return nil
                    }
                    if incoming.type == .null && token == delivery.exitMarker {
                        delivery.delivered = true
                        return nil
                    }
                    if delivery.matches(incoming) { delivery.received = true }
                    return Unmanaged.passUnretained(incoming)
                }, userInfo: context)
            sessionTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                options: .listenOnly, eventsOfInterest: 1 << event.type.rawValue,
                callback: { _, _, incoming, context in
                    guard let context else { return Unmanaged.passUnretained(incoming) }
                    let delivery = Unmanaged<Delivery>.fromOpaque(context).takeUnretainedValue()
                    if incoming.getIntegerValueField(.eventSourceUserData) == delivery.marker && !delivery.matches(incoming) {
                        WindowDirectedMove.log.error("Tagged event window mismatch: \(incoming.getIntegerValueField(.mouseEventWindowUnderMousePointer)) expected \(delivery.event.getIntegerValueField(.mouseEventWindowUnderMousePointer))")
                    }
                    if !delivery.forwarded && delivery.matches(incoming) {
                        delivery.forwarded = true
                        delivery.event.postToPid(delivery.pid)
                    }
                    return Unmanaged.passUnretained(incoming)
                }, userInfo: context)
            defer {
                if let processTap { CFMachPortInvalidate(processTap) }
                if let sessionTap { CFMachPortInvalidate(sessionTap) }
            }
            guard let processTap, let sessionTap,
                  let processSource = CFMachPortCreateRunLoopSource(nil, processTap, 0),
                  let sessionSource = CFMachPortCreateRunLoopSource(nil, sessionTap, 0) else {
                throw WindowMoveError.deliveryUnavailable
            }
            let runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(runLoop, processSource, .defaultMode)
            CFRunLoopAddSource(runLoop, sessionSource, .defaultMode)
            defer {
                CFRunLoopRemoveSource(runLoop, processSource, .defaultMode)
                CFRunLoopRemoveSource(runLoop, sessionSource, .defaultMode)
            }
            CGEvent.tapEnable(tap: processTap, enable: true)
            CGEvent.tapEnable(tap: sessionTap, enable: true)
            entry.postToPid(pid)
            let started = CFAbsoluteTimeGetCurrent()
            let deadline = started + 0.6
            var exitPosted = false
            while !delivered && CFAbsoluteTimeGetCurrent() < deadline {
                _ = CFRunLoopRunInMode(.defaultMode, 0.01, true)
                if received && !exitPosted {
                    exitPosted = true
                    exit.postToPid(pid)
                }
            }
            guard delivered else {
                WindowDirectedMove.log.error("Delivery timeout type=\(self.event.type.rawValue) pid=\(self.pid) entered=\(self.entered) forwarded=\(self.forwarded) received=\(self.received)")
                throw WindowMoveError.deliveryTimedOut
            }
        }
    }
}
