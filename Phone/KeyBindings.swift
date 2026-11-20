import Foundation
import SwiftUI

enum PadKey: String, CaseIterable, Codable, Identifiable {
    case function, control, option, command, shift
    case escape, enter, tab, space, backspace
    case up, down, left, right
    case one, two, three, four, five, six, seven, eight, nine, zero
    case a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z
    var id: Self { self }

    var code: UInt16 {
        switch self {
        case .a: 0; case .s: 1; case .d: 2; case .f: 3; case .h: 4; case .g: 5
        case .z: 6; case .x: 7; case .c: 8; case .v: 9; case .b: 11; case .q: 12
        case .w: 13; case .e: 14; case .r: 15; case .y: 16; case .t: 17; case .one: 18
        case .two: 19; case .three: 20; case .four: 21; case .six: 22; case .five: 23
        case .nine: 25; case .seven: 26; case .eight: 28; case .zero: 29; case .o: 31
        case .u: 32; case .i: 34; case .p: 35; case .enter: 36; case .l: 37; case .j: 38
        case .k: 40; case .n: 45; case .m: 46; case .tab: 48; case .space: 49
        case .backspace: 51; case .escape: 53; case .command: 55; case .shift: 56
        case .option: 58; case .control: 59; case .function: 63; case .left: 123
        case .right: 124; case .down: 125; case .up: 126
        }
    }

    var glyph: String {
        switch self {
        case .function: "fn"; case .control: "⌃"; case .option: "⌥"; case .shift: "⇧"
        case .command: "⌘"; case .escape: "esc"; case .enter: "↵"; case .space: "␣"
        case .tab: "⇥"; case .backspace: "⌫"; case .up: "↑"; case .down: "↓"
        case .left: "←"; case .right: "→"
        case .one: "1"; case .two: "2"; case .three: "3"; case .four: "4"; case .five: "5"
        case .six: "6"; case .seven: "7"; case .eight: "8"; case .nine: "9"; case .zero: "0"
        default: rawValue.uppercased()
        }
    }

    var name: String {
        switch self {
        case .one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .zero: glyph
        default: rawValue.capitalized
        }
    }
    static let modifiers: [Self] = [.function, .control, .option, .shift, .command]
}

struct KeyBinding: Equatable, Codable {
    var key: PadKey
    var modifiers: [PadKey] = []
    var title: String = ""
    var keys: [PadKey] { PadKey.modifiers.filter { $0 != key && modifiers.contains($0) } + [key] }
    var glyph: String { keys == [.space] ? "Space" : keys.map(\.glyph).joined() }
    var name: String { title.isEmpty ? (keys.count > 1 ? keys.map(\.name).joined(separator: " + ") : key.name) : title }
    var subtitle: String { name == glyph || name.uppercased() == glyph ? "" : name }
    static let defaults: [Self] = [PadKey.function, .control, .option, .one, .two, .three, .space].map { Self(key: $0) }
    static let presets: [(String, [Self])] = [
        ("Wispr Flow", [
            Self(key: .space, modifiers: [.function], title: "Hands-free"),
            Self(key: .space, modifiers: [.control, .option], title: "Alt. hands-free")
        ]),
        ("Codex", [
            Self(key: .n, modifiers: [.command], title: "New chat"),
            Self(key: .k, modifiers: [.command], title: "Command menu"),
            Self(key: .v, modifiers: [.control, .shift], title: "Voice input")
        ]),
        ("Claude Code", [
            Self(key: .c, modifiers: [.control], title: "Interrupt"),
            Self(key: .tab, modifiers: [.shift], title: "Permission mode")
        ])
    ]
}

@MainActor
final class RemoteControls: ObservableObject {
    @Published private(set) var bindings: [KeyBinding]
    @Published var sensitivity: Double { didSet { preferences.set(sensitivity, forKey: "pointer.sensitivity") } }
    @Published var haptics: Bool { didSet { preferences.set(haptics, forKey: "controls.haptics") } }
    let link: PhoneLink
    private let preferences: UserDefaults
    private var pressed: [Int: [PadKey]] = [:]
    private var keyHolds: [PadKey: Int] = [:]

    init(link: PhoneLink, preferences: UserDefaults) {
        self.link = link
        self.preferences = preferences
        let saved = preferences.data(forKey: "keys.v1").flatMap { try? JSONDecoder().decode([KeyBinding].self, from: $0) }
        switch saved?.count {
        case 6, KeyBinding.defaults.count:
            let existing = saved ?? []
            bindings = existing + KeyBinding.defaults.dropFirst(existing.count)
        default:
            bindings = KeyBinding.defaults
        }
        sensitivity = preferences.object(forKey: "pointer.sensitivity") as? Double ?? 1.4
        haptics = preferences.object(forKey: "controls.haptics") as? Bool ?? true
        if saved?.count == 6 { persist() }
    }

    func save(_ binding: KeyBinding, at index: Int) {
        bindings[index] = binding
        persist()
    }

    func restoreKeys() {
        bindings = KeyBinding.defaults
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(bindings) {
            preferences.set(data, forKey: "keys.v1")
        }
    }

    func press(_ index: Int) {
        guard link.isConnected, link.canControl, pressed[index] == nil else { return }
        let keys = bindings[index].keys
        pressed[index] = keys
        for key in keys {
            let previous = keyHolds[key, default: 0]
            keyHolds[key] = previous + 1
            if previous == 0 { link.send(.key(code: key.code, down: true)) }
        }
    }

    func release(_ index: Int) {
        guard let keys = pressed.removeValue(forKey: index) else { return }
        for key in keys.reversed() {
            let remaining = keyHolds[key, default: 1] - 1
            if remaining <= 0 {
                keyHolds.removeValue(forKey: key)
                link.send(.key(code: key.code, down: false))
            } else {
                keyHolds[key] = remaining
            }
        }
    }

    func reset() {
        pressed.removeAll()
        keyHolds.removeAll()
        if link.isConnected { link.send(.releaseAll) }
    }
}
