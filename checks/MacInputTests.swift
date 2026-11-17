// Run from the repository root:
// xcrun swiftc Shared/RemoteProtocol.swift Mac/InputInjector.swift checks/MacInputTests.swift -o /tmp/relaypad-input-tests
// /tmp/relaypad-input-tests
import AppKit
import CoreGraphics
import IOKit.hidsystem

@main
enum MacInputTests {
    static func main() {
        var events: [CGEvent] = []
        let input = InputInjector { events.append($0) }

        for _ in 0..<2 {
            input.handle(.key(code: 63, down: true))
            input.handle(.key(code: 63, down: false))
        }
        precondition(events.count == 4)
        precondition(events.allSatisfy { $0.type == .flagsChanged && key($0) == 63 })
        precondition(events.map { $0.flags.contains(.maskSecondaryFn) }
                     == [true, false, true, false])

        events.removeAll()
        input.handle(.key(code: 59, down: true))
        input.handle(.key(code: 58, down: true))
        input.handle(.key(code: 49, down: true))
        input.handle(.key(code: 49, down: true)) // duplicate transition
        input.handle(.releaseAll)
        precondition(events.map(key) == [59, 58, 49, 49, 58, 59])
        precondition(events.map(\.type) == [.flagsChanged, .flagsChanged, .keyDown, .keyUp, .flagsChanged, .flagsChanged])
        precondition(events[2].flags.contains([.maskControl, .maskAlternate]))
        precondition(events[3].flags.contains([.maskControl, .maskAlternate]))
        precondition(events[4].flags.contains(.maskControl))
        precondition(events[2].flags.rawValue & UInt64(NX_DEVICELCTLKEYMASK) != 0)
        precondition(events[2].flags.rawValue & UInt64(NX_DEVICELALTKEYMASK) != 0)
        precondition(!events[4].flags.contains(.maskAlternate))
        precondition(events[4].flags.rawValue & UInt64(NX_DEVICELALTKEYMASK) == 0)
        precondition(events[5].flags.isEmpty)
        input.releaseAll()
        precondition(events.count == 6)

        events.removeAll()
        input.handle(.click(button: .left, count: 1))
        input.handle(.click(button: .left, count: 1))
        precondition(events.map(\.type) == [.leftMouseDown, .leftMouseUp, .leftMouseDown, .leftMouseUp])
        precondition(events.map { $0.getIntegerValueField(.mouseEventClickState) } == [1, 1, 2, 2])
        input.handle(.releaseAll)

        events.removeAll()
        input.handle(.button(button: .left, down: true))
        input.handle(.move(dx: 5, dy: -5))
        input.releaseAll()
        input.handle(.move(dx: -5, dy: 5))
        precondition(events.map(\.type) == [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved])

        events.removeAll()
        input.handle(.scroll(dx: 0.5, dy: 0.5))
        input.handle(.scroll(dx: 0.5, dy: 0.5))
        precondition(events.map(\.type) == [.scrollWheel])
        let text = String(repeating: "q", count: 19) + "🪁e\u{301}🥳"
        events.removeAll()
        input.handle(.text(text))
        precondition(events.map(\.type) == [.keyDown, .keyUp, .keyDown, .keyUp])
        let decoded = events.filter { $0.type == .keyDown }.map(unicodeString).joined()
        precondition(decoded.utf16.elementsEqual(text.utf16))

        events.removeAll()
        input.handle(.move(dx: .nan, dy: 0))
        input.handle(.scroll(dx: .infinity, dy: 0))
        input.handle(.key(code: UInt16.max, down: true))
        input.handle(.click(button: .right, count: Int.max))
        precondition(events.isEmpty)
        checkPrimaryClickAndDigits()
        print("Passed AppKit text entry, primary and secondary clicks, Fn double-tap, chord release, click count, drag cleanup, scroll, Unicode, and input validation checks.")
    }

    /// Dispatches into an offscreen editable window. No event is posted to the desktop.
    private static func checkPrimaryClickAndDigits() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 40),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let editor = NSTextView(frame: window.contentLayoutRect)
        window.contentView = editor
        precondition(window.makeFirstResponder(editor))
        var clicks: [NSEvent] = []
        let input = InputInjector { event in
            guard let received = NSEvent(cgEvent: event) else { preconditionFailure("Invalid NSEvent") }
            switch received.type {
            case .keyDown, .keyUp:
                // WindowServer normally supplies the target window number at delivery.
                let addressed = NSEvent.keyEvent(with: received.type, location: .zero,
                                                 modifierFlags: received.modifierFlags, timestamp: received.timestamp,
                                                 windowNumber: window.windowNumber, context: nil,
                                                 characters: received.characters ?? "",
                                                 charactersIgnoringModifiers: received.charactersIgnoringModifiers ?? "",
                                                 isARepeat: false, keyCode: received.keyCode)!
                window.sendEvent(addressed)
            case .leftMouseDown, .rightMouseDown:
                clicks.append(received)
            default:
                break
            }
        }
        input.handle(.key(code: 59, down: true))
        input.handle(.click(button: .left, count: 1))
        input.handle(.key(code: 59, down: false))
        input.handle(.click(button: .left, count: 1))
        input.handle(.click(button: .right, count: 1))
        precondition(clicks.map(\.type) == [.leftMouseDown, .leftMouseDown, .rightMouseDown])
        precondition(clicks.map { $0.modifierFlags.contains(.control) } == [true, false, false])
        for code: CGKeyCode in [18, 19, 20] {
            input.handle(.key(code: code, down: true))
            input.handle(.key(code: code, down: false))
        }
        // Match this Mac's active layout when it differs from the US number row.
        let expected = [18, 19, 20].map { code in
            let reference = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: true)!
            reference.flags = []
            return NSEvent(cgEvent: reference)!.characters!
        }.joined()
        precondition(!expected.isEmpty && editor.string == expected, "Editor received \(editor.string.debugDescription), expected \(expected.debugDescription)")
        print("Offscreen text view received \(editor.string.debugDescription).")
    }

    private static func key(_ event: CGEvent) -> Int64 {
        event.getIntegerValueField(.keyboardEventKeycode)
    }

    private static func unicodeString(_ event: CGEvent) -> String {
        var units = [UniChar](repeating: 0, count: 32)
        var count = 0
        event.keyboardGetUnicodeString(maxStringLength: units.count, actualStringLength: &count, unicodeString: &units)
        return String(decoding: units.prefix(count), as: UTF16.self)
    }
}
