import AppKit
import Carbon.HIToolbox
import CoreGraphics
import IOKit.hidsystem

/// Maintains the state of the remote keyboard and pointer for one connection.
/// The receiver calls this on the main thread, in wire order.
final class InputInjector {
    private let source = CGEventSource(stateID: .privateState)
    private let post: (CGEvent) -> Void
    private var heldKeys: [CGKeyCode] = []
    private var heldButtons: [RemoteButton] = []
    private var pointer: CGPoint?
    private var lastMove = -Double.infinity
    private var lastClick: (button: RemoteButton, point: CGPoint, time: TimeInterval, count: Int64)?
    private var scrollRemainder = CGPoint.zero

    init(post: @escaping (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }) {
        self.post = post
        source?.localEventsSuppressionInterval = 0
    }

    func handle(_ event: RemoteEvent) {
        guard event.isValid else { return }
        switch event {
        case let .key(code, down):
            setKey(code, down: down)
        case let .move(dx, dy):
            move(dx: dx, dy: dy)
        case let .scroll(dx, dy):
            scroll(dx: dx, dy: dy)
        case let .button(button, down):
            setButton(button, down: down)
        case let .click(button, count):
            guard !heldButtons.contains(button) else { return }
            let location = currentPoint()
            for index in 1...count {
                let clickCount = recordClick(button, at: location, restart: count > 1 && index == 1)
                mouse(button.downType, button: button, at: location, count: clickCount)
                mouse(button.upType, button: button, at: location, count: clickCount)
            }
        case let .text(value):
            insertText(value)
        case .releaseAll:
            releaseAll()
        }
    }

    func releaseAll() {
        for button in heldButtons.reversed() { setButton(button, down: false) }
        for code in heldKeys.reversed() { setKey(code, down: false) }
        pointer = nil
        lastClick = nil
        lastMove = -.infinity
        scrollRemainder = .zero
    }

    private static let modifiers: [CGKeyCode: CGEventFlags] = [
        CGKeyCode(kVK_Command): sided(.maskCommand, NX_DEVICELCMDKEYMASK),
        CGKeyCode(kVK_RightCommand): sided(.maskCommand, NX_DEVICERCMDKEYMASK),
        CGKeyCode(kVK_Shift): sided(.maskShift, NX_DEVICELSHIFTKEYMASK),
        CGKeyCode(kVK_RightShift): sided(.maskShift, NX_DEVICERSHIFTKEYMASK),
        CGKeyCode(kVK_Option): sided(.maskAlternate, NX_DEVICELALTKEYMASK),
        CGKeyCode(kVK_RightOption): sided(.maskAlternate, NX_DEVICERALTKEYMASK),
        CGKeyCode(kVK_Control): sided(.maskControl, NX_DEVICELCTLKEYMASK),
        CGKeyCode(kVK_RightControl): sided(.maskControl, NX_DEVICERCTLKEYMASK),
        CGKeyCode(kVK_Function): .maskSecondaryFn,
    ]

    private static func sided(_ modifier: CGEventFlags, _ deviceBit: Int32) -> CGEventFlags {
        CGEventFlags(rawValue: modifier.rawValue | UInt64(deviceBit))
    }

    private var flags: CGEventFlags {
        // This connection is one virtual keyboard. A host flag sampled between its
        // down and up edges must never turn a release back into another press.
        var flags: CGEventFlags = []
        for code in heldKeys {
            if let modifier = Self.modifiers[code] { flags.formUnion(modifier) }
        }
        return flags
    }

    private func setKey(_ code: CGKeyCode, down: Bool) {
        guard heldKeys.contains(code) != down,
              let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        else { return }
        if down {
            heldKeys.append(code)
        } else {
            heldKeys.removeAll { $0 == code }
        }
        if Self.modifiers[code] != nil { event.type = .flagsChanged }
        event.flags = flags
        post(event)
    }

    private func currentPoint() -> CGPoint {
        // Several packets can arrive before WindowServer applies the first move.
        if let pointer, ProcessInfo.processInfo.systemUptime - lastMove < 0.12 { return pointer }
        return CGEvent(source: nil)?.location ?? .zero
    }

    private func move(dx: Double, dy: Double) {
        let start = currentPoint()
        let point = Self.displayPoint(CGPoint(x: start.x + dx, y: start.y + dy))
        let button = heldButtons.last
        guard let event = CGEvent(
            mouseEventSource: source, mouseType: button?.dragType ?? .mouseMoved,
            mouseCursorPosition: point, mouseButton: button?.cgButton ?? .left
        ) else { return }
        event.flags = flags
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64((point.x - start.x).rounded()))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64((point.y - start.y).rounded()))
        if button != nil { event.setIntegerValueField(.mouseEventClickState, value: lastClick?.count ?? 1) }
        pointer = point
        lastMove = ProcessInfo.processInfo.systemUptime
        post(event)
    }

    private static func displayPoint(_ point: CGPoint) -> CGPoint {
        let displays = NSScreen.screens.compactMap { screen -> CGRect? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
            else { return nil }
            return CGDisplayBounds(id)
        }
        if displays.contains(where: { $0.contains(point) }) { return point }
        var nearest = CGPoint.zero
        var distance = Double.infinity
        for bounds in displays {
            let candidate = CGPoint(
                x: min(max(point.x, bounds.minX), bounds.maxX - 1),
                y: min(max(point.y, bounds.minY), bounds.maxY - 1)
            )
            let gap = hypot(point.x - candidate.x, point.y - candidate.y)
            if gap < distance { nearest = candidate; distance = gap }
        }
        return displays.isEmpty ? point : nearest
    }

    private func setButton(_ button: RemoteButton, down: Bool) {
        guard heldButtons.contains(button) != down else { return }
        let location = currentPoint()
        if down {
            heldButtons.append(button)
            let count = recordClick(button, at: location)
            mouse(button.downType, button: button, at: location, count: count)
        } else {
            heldButtons.removeAll { $0 == button }
            mouse(button.upType, button: button, at: location, count: lastClick?.count ?? 1)
        }
    }

    private func recordClick(_ button: RemoteButton, at point: CGPoint, restart: Bool = false) -> Int64 {
        let now = ProcessInfo.processInfo.systemUptime
        var count: Int64 = 1
        if !restart, let lastClick, lastClick.button == button,
           now - lastClick.time <= NSEvent.doubleClickInterval,
           hypot(point.x - lastClick.point.x, point.y - lastClick.point.y) <= 4 {
            count = min(lastClick.count + 1, 3)
        }
        lastClick = (button, point, now, count)
        return count
    }

    private func mouse(_ type: CGEventType, button: RemoteButton, at point: CGPoint, count: Int64) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: button.cgButton) else { return }
        event.flags = flags
        event.setIntegerValueField(.mouseEventClickState, value: count)
        post(event)
    }

    private func scroll(dx: Double, dy: Double) {
        let x = dx + scrollRemainder.x
        let y = dy + scrollRemainder.y
        let wholeX = Int32(x)
        let wholeY = Int32(y)
        scrollRemainder = CGPoint(x: x - Double(wholeX), y: y - Double(wholeY))
        guard wholeX != 0 || wholeY != 0,
              let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                  wheel1: wholeY, wheel2: wholeX, wheel3: 0) else { return }
        event.flags = flags
        post(event)
    }

    private func insertText(_ text: String) {
        // Small UTF-16 runs are accepted by text clients without touching the clipboard.
        // Keep each surrogate pair together when a run crosses the limit.
        var run: [UInt16] = []
        func emitRun() {
            guard !run.isEmpty else { return }
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                else { continue }
                event.flags = []
                run.withUnsafeBufferPointer {
                    event.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress)
                }
                post(event)
            }
            run.removeAll(keepingCapacity: true)
        }
        for scalar in text.unicodeScalars {
            let units = scalar.utf16
            if run.count + units.count > 20 { emitRun() }
            run.append(contentsOf: units)
        }
        emitRun()
    }
}

private extension RemoteButton {
    var cgButton: CGMouseButton {
        switch self { case .left: return .left; case .right: return .right; case .middle: return .center }
    }

    var downType: CGEventType {
        switch self { case .left: return .leftMouseDown; case .right: return .rightMouseDown; case .middle: return .otherMouseDown }
    }

    var upType: CGEventType {
        switch self { case .left: return .leftMouseUp; case .right: return .rightMouseUp; case .middle: return .otherMouseUp }
    }

    var dragType: CGEventType {
        switch self { case .left: return .leftMouseDragged; case .right: return .rightMouseDragged; case .middle: return .otherMouseDragged }
    }
}
